//! The embedded ASD-STE100 engine.
//!
//! The Prolog sources are compiled into the binary with `include_str!`, in the
//! order `ste/load.pl` documents. `markdown.pl` comes first: it owns the block
//! structure, to GitHub Flavored Markdown 0.29-gfm, and the tokenizer consumes
//! the content lines it produces. They cannot carry load directives of their
//! own: a consulted string has no filesystem to resolve them against, so the
//! order lives here and in `ste/load.pl`, which the Prolog tests use.
//!
//! The engine yields one answer at a time and `done(ok)` last. Running out of
//! answers without that terminator means the engine is broken, which is not
//! the same as a clean document, so it is reported as such.

use crate::diag::{diagnostic, Diagnostic, Severity};
use scryer_prolog::{LeafAnswer, Machine, MachineBuilder, Term};
use std::fmt;
use std::path::Path;

/// In dependency order. The dictionary is the bulk of it: 14,634 facts.
///
/// All of it goes into ONE module. The engine is deliberately module-free ISO
/// Prolog, so its files call each other directly; consulting them under
/// separate module names hides those predicates from one another and the first
/// cross-file call raises existence_error.
const MODULE: &str = "user";

/// Scryer autoloads nothing: `reverse/2` and friends come from
/// `library(lists)`, and `phrase/2` from `library(dcgs)`. These cannot live in
/// the engine files, because SWI has them built in and has no `library(dcgs)`
/// at all. The loader is the right place for them, and `ste/load.pl` is its
/// SWI counterpart.
const PRELUDE: &str = "\
:- use_module(library(lists)).
:- use_module(library(dcgs)).
";

const SOURCES: &[&str] = &[
    include_str!("../ste/markdown.pl"),
    include_str!("../ste/tokenize.pl"),
    include_str!("../dictionary/ste_dictionary.pl"),
    include_str!("../ste/lexicon.pl"),
    include_str!("../ste/grammar.pl"),
    include_str!("../ste/rules.pl"),
    include_str!("../ste/engine.pl"),
];

#[derive(Debug)]
pub enum Error {
    /// The engine threw.
    Prolog(String),
    /// The answers ran out without `done(ok)`.
    NoTerminator,
    /// A term this build does not understand.
    Unknown(String),
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::Prolog(e) => write!(f, "the engine raised: {e}"),
            Error::NoTerminator => {
                f.write_str("the engine stopped without finishing; this is not a clean document")
            }
            Error::Unknown(e) => f.write_str(e),
        }
    }
}

impl std::error::Error for Error {}

pub struct Engine {
    machine: Machine,
}

impl Engine {
    pub fn new(glossary: &[String]) -> Result<Self, Error> {
        let mut machine = MachineBuilder::default().build();
        // One consult of one program, not six. Consulting the files
        // separately left only the last one's predicates visible, so the first
        // cross-file call raised existence_error(read_file_codes/2).
        let mut program = String::from(PRELUDE);
        for source in SOURCES {
            program.push('\n');
            program.push_str(source);
        }
        machine.consult_module_string(MODULE, program);
        let mut engine = Engine { machine };
        if !glossary.is_empty() {
            let words: Vec<String> = glossary.iter().map(|w| quote(w)).collect();
            // Once, at startup: the one assertz/1 stays out of the hot path.
            engine.expect_success(&format!("set_glossary([{}]).", words.join(",")))?;
        }
        Ok(engine)
    }

    /// Every diagnostic for one file, in document order.
    ///
    /// `max_errors` stops the walk early, which is the point of the engine
    /// streaming: the answers it has not been asked for are never computed.
    /// The limit counts ERRORS, not diagnostics -- counting diagnostics let a
    /// run stop on two warnings, report zero errors and exit 0 on a file that
    /// had six.
    ///
    /// Returns the diagnostics and whether the walk was cut short, so the
    /// caller can say so rather than present a truncated count as a total.
    pub fn check_file(
        &mut self,
        path: &Path,
        max_errors: Option<usize>,
    ) -> Result<(Vec<Diagnostic>, bool), Error> {
        self.run(
            format!("check_file({}, A).", quote(&path.display().to_string())),
            max_errors,
        )
    }

    /// The same, on text the caller already holds.
    ///
    /// This goes through the engine's pure entry, `check/2`, with the text
    /// encoded as a list of character codes in the query. That is why a whole
    /// document goes by path instead: a query is a string, and encoding a
    /// 100KB file this way costs some 600KB of query. A snippet is a few
    /// hundred bytes, so the same objection does not apply.
    pub fn check_text(
        &mut self,
        text: &str,
        max_errors: Option<usize>,
    ) -> Result<(Vec<Diagnostic>, bool), Error> {
        self.run(format!("check({}, A).", codes(text)), max_errors)
    }

    fn run(
        &mut self,
        query: String,
        max_errors: Option<usize>,
    ) -> Result<(Vec<Diagnostic>, bool), Error> {
        let mut found = Vec::new();
        let mut errors = 0usize;
        let mut terminated = false;

        // QueryState yields Result<LeafAnswer, Term>: an Err is the machine
        // failing, an Exception is the program throwing. Both stop the run and
        // are reported as a failure, not as a clean document.
        for answer in self.machine.run_query(query) {
            match answer {
                Err(t) => return Err(Error::Prolog(format!("{t:?}"))),
                Ok(LeafAnswer::True) | Ok(LeafAnswer::False) => {}
                Ok(LeafAnswer::Exception(t)) => return Err(Error::Prolog(format!("{t:?}"))),
                Ok(LeafAnswer::LeafAnswer { bindings, .. }) => {
                    let Some(term) = bindings.get("A") else {
                        continue;
                    };
                    match answer_kind(term) {
                        Answer::Done => {
                            terminated = true;
                            break;
                        }
                        Answer::Diag(d) => {
                            let d = diagnostic(d).map_err(|e| Error::Unknown(e.to_string()))?;
                            if d.severity == Severity::Error {
                                errors += 1;
                            }
                            found.push(d);
                            if max_errors.is_some_and(|m| errors >= m) {
                                // Dropping the iterator here is deliberate: the
                                // rest of the document is never parsed.
                                return Ok((found, true));
                            }
                        }
                        Answer::Other => {
                            return Err(Error::Unknown(format!(
                                "the engine emitted an answer this build does not know: {term:?}"
                            )))
                        }
                    }
                }
            }
        }

        if terminated {
            Ok((found, false))
        } else {
            Err(Error::NoTerminator)
        }
    }

    /// Only the first answer matters here, so take it rather than looping: a
    /// for-loop whose every arm returns is a loop that never loops.
    fn expect_success(&mut self, query: &str) -> Result<(), Error> {
        match self.machine.run_query(query.to_string()).next() {
            Some(Err(t)) => Err(Error::Prolog(format!("{t:?}"))),
            Some(Ok(LeafAnswer::Exception(t))) => Err(Error::Prolog(format!("{t:?}"))),
            Some(Ok(LeafAnswer::False)) => Err(Error::Prolog(format!("{query} failed"))),
            Some(Ok(_)) => Ok(()),
            None => Err(Error::Prolog(format!("{query} produced no answer"))),
        }
    }
}

enum Answer<'a> {
    Diag(&'a Term),
    Done,
    Other,
}

fn answer_kind(t: &Term) -> Answer<'_> {
    match t {
        Term::Compound(name, args) if name == "diag" && args.len() == 1 => Answer::Diag(&args[0]),
        Term::Compound(name, args) if name == "done" && args.len() == 1 => Answer::Done,
        _ => Answer::Other,
    }
}

/// Text as a Prolog list of character codes, which `check/2` consumes. Codes
/// rather than a double-quoted literal: `"..."` reads as chars in Scryer, a
/// string in SWI and codes in ISO, so a literal would mean the engine behaved
/// differently depending on where it ran.
fn codes(s: &str) -> String {
    let mut out = String::with_capacity(s.len() * 4 + 2);
    out.push('[');
    for (i, c) in s.chars().enumerate() {
        if i > 0 {
            out.push(',');
        }
        out.push_str(&(c as u32).to_string());
    }
    out.push(']');
    out
}

/// A quoted Prolog atom. Paths and glossary words are short, so this is the
/// only escaping the boundary needs.
fn quote(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('\'');
    for c in s.chars() {
        match c {
            '\'' => out.push_str("''"),
            '\\' => out.push_str("\\\\"),
            _ => out.push(c),
        }
    }
    out.push('\'');
    out
}

#[cfg(test)]
mod tests {
    use super::{codes, quote};

    #[test]
    fn encodes_text_as_codes() {
        assert_eq!(codes(""), "[]");
        assert_eq!(codes("Hi."), "[72,105,46]");
        // A multi-byte character is one code point, not its bytes.
        assert_eq!(codes("\u{b5}m"), "[181,109]");
    }

    #[test]
    fn quotes_awkward_paths() {
        assert_eq!(quote("plain.md"), "'plain.md'");
        assert_eq!(quote("it's.md"), "'it''s.md'");
        assert_eq!(quote("a\\b.md"), "'a\\\\b.md'");
    }
}
