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
use engine::Engine;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

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
            Input::File(p) => engine.check_file(p, cli.max_errors),
            Input::Inline { text, .. } => engine.check_text(text, cli.max_errors),
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
        } else if let Err(e) = read_lines(f) {
            return Err(format!("{}: {e}", f.display()));
        } else {
            inputs.push(Input::File(f.clone()));
        }
    }
    Ok(inputs)
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
