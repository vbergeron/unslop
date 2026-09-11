//! The diagnostic vocabulary, and how it is read back out of a Prolog term.
//!
//! The engine emits structured findings and carries no wording. This module
//! mirrors those functors as Rust types; `render` turns them into text.
//!
//! An unknown functor is a hard error, never a silently dropped diagnostic.
//! That is the same principle as the engine's `done(ok)` terminator: a gate
//! must not be able to report a clean document by accident, and adding a rule
//! on the Prolog side must not make it quietly vanish here.

use scryer_prolog::Term;
use std::fmt;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Severity {
    Error,
    Warning,
}

impl fmt::Display for Severity {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Severity::Error => f.write_str("error"),
            Severity::Warning => f.write_str("warning"),
        }
    }
}

/// `span(Line, Byte, Len)`: line is 1-based, byte is a 0-based byte offset
/// within that line, len is a byte length. Byte offsets rather than character
/// columns because the caller slices the line; see `render::display_column`.
#[derive(Debug, Clone, Copy)]
pub struct Span {
    pub line: usize,
    pub byte: usize,
    pub len: usize,
}

#[derive(Debug, Clone)]
pub enum Finding {
    SentenceTooLong {
        words: usize,
        limit: usize,
        kind: String,
    },
    ParagraphTooLong {
        sentences: usize,
        limit: usize,
    },
    Semicolon,
    Contraction {
        word: String,
    },
    NotApprovedAs {
        word: String,
        pos: String,
    },
    NeverApproved {
        word: String,
    },
    UndecidableReading {
        word: String,
        pos: String,
    },
    TechnicalNounReading {
        word: String,
    },
    TechnicalNounOnly {
        word: String,
        pos: String,
    },
    NotInDictionary {
        word: String,
    },
    UnlistedTechnicalNoun {
        word: String,
    },
    ForbiddenForm {
        word: String,
        base: String,
    },
    VerbConstruction {
        what: String,
        first: String,
        second: String,
    },
    PassiveVoice {
        first: String,
        second: String,
    },
    MultiWordNoun {
        length: usize,
        limit: usize,
        head: String,
    },
    NounUsedAsVerb {
        word: String,
    },
    ConditionNotDivided {
        word: String,
    },
    StepWithoutVerb {
        word: String,
    },
    NoteGivesInstruction {
        word: String,
    },
}

/// `Replace` and `Advice` carry text quoted verbatim out of ASD-STE100. Pass
/// it through unchanged: it is the standard's wording, not ours, and it is
/// what makes a diagnostic actionable.
#[derive(Debug, Clone)]
pub enum Suggestion {
    Replace(Vec<String>),
    Advice(String),
    Expand(String),
    UseForm { base: String, forms: Vec<String> },
    KeepAsModifier(String),
    SplitSentence,
    SplitParagraph,
    TwoSentences,
    AddComma,
    ActiveVoice,
    SimpleTense,
    ShortenNoun,
    AddToGlossary,
    StartWithImperative,
    MoveToStep,
    UseApprovedVerb,
}

#[derive(Debug, Clone)]
pub struct Diagnostic {
    pub rule: String,
    pub severity: Severity,
    pub span: Span,
    pub finding: Finding,
    pub suggestions: Vec<Suggestion>,
}

/// The engine produced a term this build does not understand.
#[derive(Debug)]
pub struct Unknown(pub String);

impl fmt::Display for Unknown {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "the engine emitted a term this build does not know: {}",
            self.0
        )
    }
}

impl std::error::Error for Unknown {}

type Result<T> = std::result::Result<T, Unknown>;

fn unknown<T>(what: &str, t: &Term) -> Result<T> {
    Err(Unknown(format!("{what}: {t:?}")))
}

fn atom(t: &Term) -> Result<String> {
    match t {
        Term::Atom(a) => Ok(a.clone()),
        Term::String(s) => Ok(s.clone()),
        _ => unknown("expected an atom", t),
    }
}

fn count(t: &Term) -> Result<usize> {
    match t {
        Term::Integer(i) => i
            .to_string()
            .parse()
            .map_err(|_| Unknown(format!("{i} is not a count"))),
        _ => unknown("expected an integer", t),
    }
}

fn atoms(t: &Term) -> Result<Vec<String>> {
    match t {
        Term::List(items) => items.iter().map(atom).collect(),
        _ => unknown("expected a list", t),
    }
}

/// Match `functor(args...)`, or a bare atom as a zero-argument compound.
fn functor(t: &Term) -> Result<(&str, &[Term])> {
    match t {
        Term::Compound(name, args) => Ok((name.as_str(), args.as_slice())),
        Term::Atom(name) => Ok((name.as_str(), &[])),
        _ => unknown("expected a compound term", t),
    }
}

pub fn diagnostic(t: &Term) -> Result<Diagnostic> {
    let (name, args) = functor(t)?;
    if name != "diag" || args.len() != 5 {
        return unknown("expected diag/5", t);
    }
    Ok(Diagnostic {
        rule: atom(&args[0])?,
        severity: severity(&args[1])?,
        span: span(&args[2])?,
        finding: finding(&args[3])?,
        suggestions: match &args[4] {
            Term::List(items) => items.iter().map(suggestion).collect::<Result<_>>()?,
            other => return unknown("expected a suggestion list", other),
        },
    })
}

fn severity(t: &Term) -> Result<Severity> {
    match atom(t)?.as_str() {
        "error" => Ok(Severity::Error),
        "warning" => Ok(Severity::Warning),
        _ => unknown("expected error or warning", t),
    }
}

fn span(t: &Term) -> Result<Span> {
    let (name, args) = functor(t)?;
    if name != "span" || args.len() != 3 {
        return unknown("expected span/3", t);
    }
    Ok(Span {
        line: count(&args[0])?,
        byte: count(&args[1])?,
        len: count(&args[2])?,
    })
}

fn finding(t: &Term) -> Result<Finding> {
    use Finding::*;
    let (name, a) = functor(t)?;
    Ok(match (name, a.len()) {
        ("sentence_too_long", 3) => SentenceTooLong {
            words: count(&a[0])?,
            limit: count(&a[1])?,
            kind: atom(&a[2])?,
        },
        ("paragraph_too_long", 2) => ParagraphTooLong {
            sentences: count(&a[0])?,
            limit: count(&a[1])?,
        },
        ("semicolon", 0) => Semicolon,
        ("contraction", 1) => Contraction { word: atom(&a[0])? },
        ("not_approved_as", 2) => NotApprovedAs {
            word: atom(&a[0])?,
            pos: atom(&a[1])?,
        },
        ("never_approved", 1) => NeverApproved { word: atom(&a[0])? },
        ("undecidable_reading", 2) => UndecidableReading {
            word: atom(&a[0])?,
            pos: atom(&a[1])?,
        },
        ("technical_noun_reading", 1) => TechnicalNounReading { word: atom(&a[0])? },
        ("technical_noun_only", 2) => TechnicalNounOnly {
            word: atom(&a[0])?,
            pos: atom(&a[1])?,
        },
        ("not_in_dictionary", 1) => NotInDictionary { word: atom(&a[0])? },
        ("unlisted_technical_noun", 1) => UnlistedTechnicalNoun { word: atom(&a[0])? },
        ("forbidden_form", 2) => ForbiddenForm {
            word: atom(&a[0])?,
            base: atom(&a[1])?,
        },
        ("verb_construction", 3) => VerbConstruction {
            what: atom(&a[0])?,
            first: atom(&a[1])?,
            second: atom(&a[2])?,
        },
        ("passive_voice", 2) => PassiveVoice {
            first: atom(&a[0])?,
            second: atom(&a[1])?,
        },
        ("multi_word_noun", 3) => MultiWordNoun {
            length: count(&a[0])?,
            limit: count(&a[1])?,
            head: atom(&a[2])?,
        },
        ("noun_used_as_verb", 1) => NounUsedAsVerb { word: atom(&a[0])? },
        ("condition_not_divided", 1) => ConditionNotDivided { word: atom(&a[0])? },
        ("step_without_verb", 1) => StepWithoutVerb { word: atom(&a[0])? },
        ("note_gives_instruction", 1) => NoteGivesInstruction { word: atom(&a[0])? },
        _ => return unknown("unknown finding", t),
    })
}

fn suggestion(t: &Term) -> Result<Suggestion> {
    use Suggestion::*;
    let (name, a) = functor(t)?;
    Ok(match (name, a.len()) {
        ("replace", 1) => Replace(atoms(&a[0])?),
        ("advice", 1) => Advice(atom(&a[0])?),
        ("expand", 1) => Expand(atom(&a[0])?),
        ("use_form", 2) => UseForm {
            base: atom(&a[0])?,
            forms: atoms(&a[1])?,
        },
        ("keep_as_modifier", 1) => KeepAsModifier(atom(&a[0])?),
        ("split_sentence", 0) => SplitSentence,
        ("split_paragraph", 0) => SplitParagraph,
        ("two_sentences", 0) => TwoSentences,
        ("add_comma", 0) => AddComma,
        ("active_voice", 0) => ActiveVoice,
        ("simple_tense", 0) => SimpleTense,
        ("shorten_noun", 0) => ShortenNoun,
        ("add_to_glossary", 0) => AddToGlossary,
        ("start_with_imperative", 0) => StartWithImperative,
        ("move_to_step", 0) => MoveToStep,
        ("use_approved_verb", 0) => UseApprovedVerb,
        _ => return unknown("unknown suggestion", t),
    })
}
