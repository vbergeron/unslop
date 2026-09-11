# ASD-STE100 dictionary, extracted

Part 2 (Dictionary) of ASD-STE100 Simplified Technical English, Issue 9,
2025-01-15, extracted from `../ASD-STE100_ISSUE9.pdf` (PDF pages 149-434).

## Files

| File | Size | What it holds |
| --- | --- | --- |
| `ste_dictionary.pl` | 8679 facts | The lexicon as ISO Prolog facts. What the checker reads, and what the binary embeds. |
| `ste_examples.pl` | 4964 facts | The standard's example sentences. Loaded by `test/engine_test.pl` alone, for the false-positive guard. |

Both files are derived from a copyrighted document, so `.gitignore` excludes
them. Rebuild them with `python3 scripts/extract_dictionary.py` once you have
your copy of the standard. See the Licensing section of `../README.md`.

## Excluded from the extraction

Three predicates the extraction used to emit are excluded. No rule reads any
of them, and together they were most of the volume:

- **`ste_meaning`** — 977 of ASD's own definitions. Rule 1.3 is about approved
  meanings and no lexicon lookup can enforce it, so nothing consulted them.
- **`ste_usage`** and **`ste_variant`** — 14 facts indexing the parenthetical
  constructions and the one alternate spelling. The distinction they protected
  lives in the `ste_word` key itself, which keeps the parenthetical, so the
  index was redundant.
- **`ste_example`** — 4964 sentences, half the volume, moved to its own file.
  The guard needs them; the binary does not.

Together that took the embedded lexicon from 838,616 characters to 352,294 —
58% less of ASD's content in anything that ships, and 7.8MB to 7.3MB of binary.

Four TSV views went too. They were generated for reading and loaded by
nothing.

`../scripts/extract_dictionary.py` rebuilds both files from the PDF alone.

## The Prolog fact base

```prolog
ste_word(Word, POS, Status, Page)         % Status: approved | not_approved
ste_ambiguous(Word, POS)                  % same Word+POS, conflicting status
ste_tokens(Tokens, Word, POS)             % multi-word entries, for matching
ste_form(Form, Word, POS)                 % permitted forms (rules 1.4, 3.1)
ste_alternative(Word, POS, Alt, AltPOS)   % structured replacement
ste_alternative_text(Word, POS, Text)     % as printed, incl. plain guidance
ste_note(Word, POS, Note)                 % the standard's editorial note
ste_recurring_error(Word, POS, Better)    % Part 2 intro, frequent mistakes
```

Counts: `ste_form` 2683, `ste_word` 2198, `ste_alternative_text` 1878,
`ste_alternative` 1708, `ste_note` 111, `ste_tokens` 61,
`ste_recurring_error` 39, `ste_ambiguous` 1. In `ste_examples.pl`,
`ste_example` 4964.

`ste_form/3` is keyed on the form, not the lemma, because that is the query the
gate makes. `ste_form(assembling, _, _)` fails, so "assembling" breaks rule 1.4.
`ste_form(assembles, W, P)` gives `assemble-v`.

Plain ISO facts — no module declaration, only the ISO `discontiguous/1`
directive — developed against SWI-Prolog 9.x and meant to load under Scryer
later, which it now does. One item is open: a few atoms carry non-ASCII
characters inherited from the PDF (curly quotes, an ellipsis, a degree and a
micro sign, and one private-use glyph). Most of them were in the example
sentences, so they no longer reach the binary.

### Two traps the schema is shaped around

Both occur in the printed standard, and both corrupt a lexicon lookup without
raising an error:

**A parenthetical in a headword marks a construction, not a spelling.**
`PREVENT (v)` is approved; `prevent (from) (v)` is not. Stripping the
parenthetical merges an approved word with a forbidden construction into
contradictory facts, so the parenthetical stays in the key: the entry is
`'prevent (from)'`, not `prevent`. There are 13 such entries, and they are
inert: no lookup of a bare word reaches them. The exception is
`MATT (or MATTE)`, where the parenthetical is a spelling, so both spellings
become forms of one entry.

**Some senses are separated by the case of the printed headword alone.**
`GET (v)` is approved ("To obtain, to come into the state of having") while
`get (v)` is not (use `BECOME (v)`) — same word, same part of speech, opposite
status, nothing else to tell them apart. So `(Word, POS)` is not a unique key
and status is not a function of it. Such words are listed in `ste_ambiguous/2`
and cannot be decided mechanically: that is rule 1.3 (approved meanings), which
no lexicon lookup can settle. A gate must treat them as needing judgement, never
as a hard failure. Exactly one word is affected today (`get`), but the checker
should consult `ste_ambiguous/2` rather than assume it stays that way.

## How it was extracted

`pdftotext -layout` looks clean on the first page and quietly corrupts the rest,
so the table is rebuilt from word-level geometry (`pdftotext -bbox-layout`).
What matters when re-running against a later issue:

- Columns start at 72 / 180 / 310 / 439 pt, all shifted 22pt left on verso
  pages, with 1-2pt of per-page jitter. The layout is picked per page.
- pdftotext frequently merges two side-by-side cells into one `<line>`, so both
  the column and the row of every word come from the word's own box. Using line
  boxes corrupts about 3% of entries, without raising an error.
- Columns 2-4 are set in a larger font than column 1 on some pages, so a cell's
  box top can sit up to 4pt above its neighbour in the same row. Rows are at
  least 18pt apart, so cells are matched to the nearest row anchor.
- A wrapped line inside a cell sits 11.5-12.1pt below the line above it.
- Editorial notes are mixed into columns 2 and 3, set apart only by a deep
  indent; they are split into their own field.

## What was checked

Against the extraction:

- 0 unparsed headwords and 0 rows that could not be attached to an entry.
- Every entry has a part of speech, except the two phrase entries
  (`FOR EXAMPLE`, `such as`).
- 2197 of 2198 entries start with the letter of the page they sit on. The
  exception is `zero` on a page whose footer still reads `Y`.

Against the fact base, loaded in SWI:

- Every duplicated `Word+POS` key is flagged in `ste_ambiguous/2`, and status is
  a function of `Word+POS` for every key that is not flagged.
- No `ste_form/3` or `ste_tokens/3` key carries a parenthesis.
- Every approved plain word has at least one form; every not-approved entry has
  either an alternative or a guidance note.
- Every alternative that is not tagged `tn`/`tv` resolves to an entry or a form.
  The 111 tagged `tn`/`tv` are technical nouns and verbs, which the standard's
  own introduction excludes from the dictionary while citing them as
  alternatives.

One discrepancy is unresolved: the Part 2 introduction claims 875 approved and
1274 not-approved words, against 878 and 1320 here. The approved side is within
3. On the not-approved side the extra 46 are not parse failures — every one of
them reads correctly against the rendered page — so the counts are probably
measuring something narrower (the 13 parenthetical constructions and the 42
multi-word entries such as `carry out` are the likely candidates). Treat the
totals as approximate, not the entries.

## Copyright

ASD-STE100 is a copyright and an EU trademark of ASD, Brussels (EU Trade Mark
No. 017966390). ASD gives the specification free of charge but forbids
reproduction in whole or in part without written authority, except for the
organizations listed under "Special usage rights" in the PDF front matter.
These files are a local working reference, not redistributable content.
