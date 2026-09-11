//! All the wording, and the one place a byte offset becomes a column.
//!
//! The engine emits structured findings precisely so that this file can be
//! replaced without touching it: text here, JSON next door, and an editor
//! could match on the same types.

use crate::diag::{Diagnostic, Finding, Span, Suggestion};

pub fn message(finding: &Finding) -> String {
    use Finding::*;
    match finding {
        SentenceTooLong { words, limit, kind } => {
            format!("sentence of {words} words, the limit for {kind} text is {limit}")
        }
        ParagraphTooLong { sentences, limit } => {
            format!("paragraph of {sentences} sentences, the limit is {limit}")
        }
        Semicolon => "a semicolon is not permitted".into(),
        Contraction { word } => format!("\"{word}\" is a contraction"),
        NotApprovedAs { word, pos } => {
            format!("\"{word}\" is used as {}, which is not approved", pos_name(pos))
        }
        NeverApproved { word } => format!("\"{word}\" is never approved in STE"),
        UndecidableReading { word, pos } => format!(
            "\"{word}\" reads as {} here, which is not approved; keep it only as a technical noun",
            pos_name(pos)
        ),
        TechnicalNounReading { word } => format!(
            "\"{word}\" is used as a noun the dictionary does not approve; keep it only as a technical noun"
        ),
        TechnicalNounOnly { word, pos } => format!(
            "\"{word}\" is used as {}; the dictionary approves it only as a technical noun",
            pos_name(pos)
        ),
        NotInDictionary { word } => format!("\"{word}\" is not in the dictionary"),
        UnlistedTechnicalNoun { word } => {
            format!("\"{word}\" is a technical noun that the glossary does not list")
        }
        ForbiddenForm { word, base } => {
            format!("\"{word}\" is not a permitted form of {base}")
        }
        VerbConstruction { what, first, second } => format!(
            "\"{first} {second}\" is the {what}, which rule 3.2 does not permit"
        ),
        PassiveVoice { first, second } => {
            format!("\"{first} {second}\" is the passive voice")
        }
        MultiWordNoun { length, limit, head } => format!(
            "multi-word noun of {length} words starting at \"{head}\", the limit is {limit}"
        ),
        NounUsedAsVerb { word } => {
            format!("\"{word}\" is a noun in the dictionary and is used here as a verb")
        }
        ConditionNotDivided { word } => format!(
            "the condition that starts with \"{word}\" is not divided from the command"
        ),
        StepWithoutVerb { word } => {
            format!("the step starts with \"{word}\", which is not a verb")
        }
        NoteGivesInstruction { word } => {
            format!("the note starts with the command \"{word}\"")
        }
    }
}

pub fn advice(suggestion: &Suggestion) -> String {
    use Suggestion::*;
    match suggestion {
        // The standard's own words, passed through unchanged.
        Replace(alts) => format!("use {}", alts.join(", ")),
        Advice(note) => note.clone(),
        Expand(e) => format!("write \"{e}\""),
        UseForm { base, forms } if forms.is_empty() => format!("use {base}"),
        UseForm { base, forms } => {
            format!("permitted forms are {base}, {}", forms.join(", "))
        }
        KeepAsModifier(base) => {
            format!("keep it only as a technical noun or a modifier, otherwise use {base}")
        }
        SplitSentence => "split it into shorter sentences".into(),
        SplitParagraph => "divide the paragraph".into(),
        TwoSentences => "write two sentences".into(),
        AddComma => "put a comma before the command".into(),
        ActiveVoice => "name the agent and use the active voice".into(),
        SimpleTense => "use the simple present, past or future, or the imperative".into(),
        ShortenNoun => "write it in full, then shorten it or use prepositions".into(),
        AddToGlossary => "replace it, or add it to the glossary if it is a technical noun".into(),
        StartWithImperative => "start with an approved verb in the imperative form".into(),
        MoveToStep => "move the instruction into a step, or rewrite as information".into(),
        UseApprovedVerb => "use an approved verb and keep the word as the noun".into(),
    }
}

fn pos_name(pos: &str) -> &str {
    match pos {
        "n" => "a noun",
        "v" => "a verb",
        "adj" => "an adjective",
        "adv" => "an adverb",
        other => other,
    }
}

/// The 1-based character column a person expects, from the byte offset the
/// engine emits. This is the whole reason the engine carries bytes: on a line
/// with typographic quotes or a degree sign the two differ, and only the side
/// holding the text can convert.
pub fn display_column(line: Option<&str>, span: Span) -> usize {
    match line {
        Some(text) if span.byte <= text.len() => text[..span.byte].chars().count() + 1,
        _ => span.byte + 1,
    }
}

pub fn text(path: &str, lines: &[String], d: &Diagnostic) -> String {
    let line = lines.get(d.span.line.saturating_sub(1)).map(String::as_str);
    let col = display_column(line, d.span);
    let mut out = format!(
        "{path}:{}:{col}: {} rule {}: {}\n",
        d.span.line,
        d.severity,
        d.rule,
        message(&d.finding)
    );
    for s in &d.suggestions {
        out.push_str(&format!("    -> {}\n", advice(s)));
    }
    out
}

pub fn json(path: &str, lines: &[String], d: &Diagnostic) -> String {
    let line = lines.get(d.span.line.saturating_sub(1)).map(String::as_str);
    let advices: Vec<String> = d.suggestions.iter().map(|s| escape(&advice(s))).collect();
    format!(
        concat!(
            "{{\"file\":\"{}\",\"line\":{},\"column\":{},\"byte\":{},\"length\":{},",
            "\"severity\":\"{}\",\"rule\":\"{}\",\"message\":\"{}\",\"suggestions\":[{}]}}"
        ),
        escape(path),
        d.span.line,
        display_column(line, d.span),
        d.span.byte,
        d.span.len,
        d.severity,
        escape(&d.rule),
        escape(&message(&d.finding)),
        advices
            .iter()
            .map(|a| format!("\"{a}\""))
            .collect::<Vec<_>>()
            .join(",")
    )
}

fn escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn column_counts_characters_not_bytes() {
        // "THE \u{201c}AUTO\u{201d} LIGHT": the opening quote is three bytes,
        // so a byte offset of 6 is character column 5.
        let line = "THE \u{201c}AUTO\u{201d} LIGHT";
        let span = Span {
            line: 1,
            byte: 4,
            len: 3,
        };
        assert_eq!(display_column(Some(line), span), 5);
        let after = Span {
            line: 1,
            byte: 7,
            len: 4,
        };
        assert_eq!(display_column(Some(line), after), 6);
    }

    #[test]
    fn column_falls_back_when_the_line_is_missing() {
        let span = Span {
            line: 9,
            byte: 3,
            len: 1,
        };
        assert_eq!(display_column(None, span), 4);
    }

    #[test]
    fn json_escapes_quotes() {
        assert_eq!(escape("a \"b\" c"), "a \\\"b\\\" c");
    }
}
