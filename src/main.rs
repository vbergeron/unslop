//! unslop -- a mechanical ASD-STE100 gate for documentation.
//!
//! Every diagnostic derives from the standard's own text, or from the lexicon
//! extracted out of it. The engine is Prolog, embedded, so the tool ships as
//! one binary that runs offline.
//!
//! Exit status is the gate contract:
//!   0  nothing reported as an error
//!   1  errors found
//!   2  the run itself failed
//! Warnings never fail the gate.

mod diag;
mod engine;
mod render;

use clap::{Parser, ValueEnum};
use diag::Severity;
use engine::{Engine, Syntax};
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use walkdir::{DirEntry, WalkDir};

#[derive(Parser)]
#[command(
    name = "unslop",
    version,
    about = "Check documentation against ASD-STE100 Simplified Technical English",
    long_about = None
)]
struct Cli {
    /// Files to check, or - for standard input
    ///
    /// With no FILE, reads standard input, so it works in a pipeline like any
    /// other filter.
    #[arg(value_name = "FILE")]
    files: Vec<PathBuf>,

    /// Walk a directory named on the command line, instead of erroring on it
    ///
    /// Only files named *.md or *.markdown are checked, in sorted order.
    /// Everything else under a repository -- source, lockfiles, a .git --
    /// is not documentation, so a hidden entry (dot-prefixed, .git included)
    /// is skipped, the way rg and fd skip one by default.
    #[arg(short, long)]
    recursive: bool,

    /// Check this text instead, like python -c
    ///
    /// Sugar over standard input, for a one-liner without a heredoc.
    #[arg(short = 'c', long, value_name = "TEXT", conflicts_with = "files")]
    text: Option<String>,

    /// Project technical nouns and verbs, one per line, # for a comment
    ///
    /// Rules 1.1, 1.5, 1.6, 1.8 and 1.12 rest on technical nouns, an open set
    /// specific to each project. Without a glossary every identifier, product
    /// name and domain term is reported.
    #[arg(short, long, value_name = "FILE")]
    glossary: Option<PathBuf>,

    /// Show warnings as well as errors
    #[arg(short, long)]
    warnings: bool,

    /// Print only the summary line
    #[arg(short, long)]
    quiet: bool,

    /// Output format
    #[arg(short, long, value_enum, default_value_t = Format::Text)]
    format: Format,

    /// Stop after this many errors, per file
    ///
    /// The engine yields one finding at a time, so what is not asked for is
    /// never parsed.
    #[arg(long, value_name = "N")]
    max_errors: Option<usize>,

    /// How to read the input: auto, md or text
    ///
    /// `auto` takes it from the extension: .md and .markdown get the markdown
    /// block grammar, anything else is plain text. Standard input and -c have
    /// no extension, so they are plain text unless this says otherwise, which
    /// is what makes markdown on a pipeline reachable at all.
    #[arg(long, value_enum, default_value_t = SyntaxArg::Auto)]
    syntax: SyntaxArg,
}

#[derive(Copy, Clone, PartialEq, Eq, ValueEnum)]
enum SyntaxArg {
    Auto,
    Md,
    Text,
}

impl From<SyntaxArg> for Syntax {
    fn from(a: SyntaxArg) -> Self {
        match a {
            SyntaxArg::Auto => Syntax::Auto,
            SyntaxArg::Md => Syntax::Markdown,
            SyntaxArg::Text => Syntax::Text,
        }
    }
}

#[derive(Copy, Clone, PartialEq, Eq, ValueEnum)]
enum Format {
    Text,
    Json,
}

fn main() -> ExitCode {
    let cli = Cli::parse();

    let glossary = match cli.glossary.as_deref().map(read_glossary) {
        Some(Ok(words)) => words,
        Some(Err(e)) => return fail(&format!("{}: {e}", cli.glossary.unwrap().display())),
        None => Vec::new(),
    };

    let mut engine = match Engine::new(&glossary) {
        Ok(e) => e,
        Err(e) => return fail(&e.to_string()),
    };

    let mut errors = 0usize;
    let mut warnings = 0usize;
    let mut truncated = false;
    let mut first_json = true;
    if cli.format == Format::Json && !cli.quiet {
        print!("[");
    }

    let inputs = match gather(&cli) {
        Ok(i) => i,
        Err(e) => return fail(&e),
    };

    for input in &inputs {
        let (label, lines) = (input.label(), input.lines());
        let found = match input {
            // A path goes to the engine as a path: it reads the file through
            // ISO open/3, which keeps a whole document out of the query.
            Input::File(p) => engine.check_file(p, cli.max_errors, cli.syntax.into()),
            Input::Inline { text, .. } => {
                engine.check_text(text, cli.max_errors, cli.syntax.into())
            }
        };
        let found = match found {
            Ok((d, cut)) => {
                truncated |= cut;
                d
            }
            Err(e) => return fail(&format!("{label}: {e}")),
        };
        let path = &label;
        let lines = &lines;

        for d in &found {
            match d.severity {
                Severity::Error => errors += 1,
                Severity::Warning => warnings += 1,
            }
            if cli.quiet || (d.severity == Severity::Warning && !cli.warnings) {
                continue;
            }
            match cli.format {
                Format::Text => print!("{}", render::text(path, lines, d)),
                Format::Json => {
                    if !first_json {
                        print!(",");
                    }
                    first_json = false;
                    print!("{}", render::json(path, lines, d));
                }
            }
        }
    }

    // Say so when the count is a floor rather than a total: a truncated run
    // that printed "0 error(s)" would read as a clean file.
    let note = if truncated { ", stopped early" } else { "" };
    match cli.format {
        Format::Json if !cli.quiet => println!("]"),
        _ => println!("{errors} error(s), {warnings} warning(s){note}"),
    }

    if errors > 0 {
        ExitCode::from(1)
    } else {
        ExitCode::SUCCESS
    }
}

/// Where the text to check comes from.
enum Input {
    File(PathBuf),
    Inline { label: String, text: String },
}

impl Input {
    fn label(&self) -> String {
        match self {
            Input::File(p) => p.display().to_string(),
            Input::Inline { label, .. } => label.clone(),
        }
    }

    /// The host needs the lines whatever the source: converting a byte offset
    /// to a character column is only possible on the side that holds the text.
    fn lines(&self) -> Vec<String> {
        match self {
            Input::File(p) => read_lines(p).unwrap_or_default(),
            Input::Inline { text, .. } => text.lines().map(str::to_owned).collect(),
        }
    }
}

/// Read standard input when the caller names no source, and for a FILE of
/// `-`. This is the plain filter convention, and --text is sugar over it.
fn gather(cli: &Cli) -> Result<Vec<Input>, String> {
    if let Some(text) = &cli.text {
        return Ok(vec![Input::Inline {
            label: "<text>".into(),
            text: text.clone(),
        }]);
    }
    if cli.files.is_empty() {
        return Ok(vec![Input::Inline {
            label: "<stdin>".into(),
            text: read_stdin()?,
        }]);
    }
    let mut inputs = Vec::with_capacity(cli.files.len());
    for f in &cli.files {
        if f.as_os_str() == "-" {
            inputs.push(Input::Inline {
                label: "<stdin>".into(),
                text: read_stdin()?,
            });
            continue;
        }
        if f.is_dir() {
            if !cli.recursive {
                return Err(format!(
                    "{}: is a directory; pass --recursive to check the files under it",
                    f.display()
                ));
            }
            for p in walk_markdown(f)? {
                if let Err(e) = read_lines(&p) {
                    return Err(format!("{}: {e}", p.display()));
                }
                inputs.push(Input::File(p));
            }
            continue;
        }
        if let Err(e) = read_lines(f) {
            return Err(format!("{}: {e}", f.display()));
        }
        inputs.push(Input::File(f.clone()));
    }
    Ok(inputs)
}

/// Every `*.md`/`*.markdown` file under `dir`, sorted for output that does
/// not depend on the order the filesystem happens to hand entries back in.
///
/// `walkdir` does not follow symlinks unless told to, so a link cycle under
/// `dir` cannot turn this into an infinite walk.
fn walk_markdown(dir: &Path) -> Result<Vec<PathBuf>, String> {
    let mut found = Vec::new();
    let walker = WalkDir::new(dir)
        .into_iter()
        .filter_entry(|e| e.depth() == 0 || !hidden(e));
    for entry in walker {
        let entry = entry.map_err(|e| format!("{dir}: {e}", dir = dir.display()))?;
        if entry.file_type().is_file() && is_markdown(entry.path()) {
            found.push(entry.into_path());
        }
    }
    found.sort();
    Ok(found)
}

/// A dot-prefixed entry: `.git`, `.github`, an editor's `.foo` directory.
/// None of it is documentation, so `walk_markdown` never descends into it.
fn hidden(entry: &DirEntry) -> bool {
    entry
        .file_name()
        .to_str()
        .is_some_and(|s| s.starts_with('.'))
}

/// The extension check `path_syntax/2` uses for the markdown grammar, made
/// here so recursion never sweeps up source files and lockfiles as prose.
fn is_markdown(path: &Path) -> bool {
    path.extension()
        .and_then(|e| e.to_str())
        .is_some_and(|e| e.eq_ignore_ascii_case("md") || e.eq_ignore_ascii_case("markdown"))
}

fn read_stdin() -> Result<String, String> {
    use std::io::Read;
    let mut text = String::new();
    std::io::stdin()
        .read_to_string(&mut text)
        .map_err(|e| format!("<stdin>: {e}"))?;
    Ok(text)
}

fn fail(message: &str) -> ExitCode {
    eprintln!("unslop: {message}");
    ExitCode::from(2)
}

fn read_lines(path: &Path) -> std::io::Result<Vec<String>> {
    Ok(std::fs::read_to_string(path)?
        .lines()
        .map(str::to_owned)
        .collect())
}

fn read_glossary(path: &Path) -> std::io::Result<Vec<String>> {
    Ok(std::fs::read_to_string(path)?
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
        .map(str::to_owned)
        .collect())
}

#[cfg(test)]
mod tests {
    use super::{is_markdown, walk_markdown};
    use std::path::{Path, PathBuf};
    use std::sync::atomic::{AtomicUsize, Ordering};

    /// A fresh, empty directory under the OS temp dir, removed by the caller.
    /// Parallel `cargo test` threads each get their own: a shared fixture on
    /// disk would make one test's cleanup another test's missing file.
    fn tempdir(label: &str) -> PathBuf {
        static NEXT: AtomicUsize = AtomicUsize::new(0);
        let n = NEXT.fetch_add(1, Ordering::Relaxed);
        let dir =
            std::env::temp_dir().join(format!("unslop-test-{}-{label}-{n}", std::process::id()));
        std::fs::create_dir_all(&dir).expect("must create temp dir");
        dir
    }

    fn touch(path: &Path) {
        std::fs::create_dir_all(path.parent().unwrap()).expect("must create parent");
        std::fs::write(path, "").expect("must write file");
    }

    #[test]
    fn is_markdown_matches_the_extension_case_insensitively() {
        assert!(is_markdown(Path::new("a.md")));
        assert!(is_markdown(Path::new("a.MD")));
        assert!(is_markdown(Path::new("a.markdown")));
        assert!(is_markdown(Path::new("a.MARKDOWN")));
        assert!(!is_markdown(Path::new("a.txt")));
        assert!(!is_markdown(Path::new("a.md.bak")));
        assert!(!is_markdown(Path::new("README")));
    }

    #[test]
    fn walk_markdown_finds_files_under_subdirectories_in_sorted_order() {
        let dir = tempdir("nested");
        touch(&dir.join("z.md"));
        touch(&dir.join("sub/a.md"));
        touch(&dir.join("sub/deeper/b.MARKDOWN"));
        touch(&dir.join("sub/skip.txt"));

        let found = walk_markdown(&dir).expect("must walk");

        assert_eq!(
            found,
            vec![
                dir.join("sub/a.md"),
                dir.join("sub/deeper/b.MARKDOWN"),
                dir.join("z.md"),
            ]
        );

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn walk_markdown_skips_hidden_files_and_directories() {
        let dir = tempdir("hidden");
        touch(&dir.join("visible.md"));
        // A hidden directory -- .git is the case this matters for, since it
        // holds binary content that is not even valid UTF-8 text.
        touch(&dir.join(".git/config.md"));
        // A hidden file directly, not just a hidden directory.
        touch(&dir.join(".env.md"));

        let found = walk_markdown(&dir).expect("must walk");

        assert_eq!(found, vec![dir.join("visible.md")]);

        std::fs::remove_dir_all(&dir).ok();
    }

    /// The root itself is never filtered as "hidden", even when its own name
    /// is dot-prefixed: only entries found while descending are skipped.
    #[test]
    fn walk_markdown_does_not_reject_a_dot_prefixed_root() {
        let parent = tempdir("dotroot-parent");
        let dir = parent.join(".config");
        touch(&dir.join("notes.md"));

        let found = walk_markdown(&dir).expect("must walk");

        assert_eq!(found, vec![dir.join("notes.md")]);

        std::fs::remove_dir_all(&parent).ok();
    }
}
