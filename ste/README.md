# The engine

The ASD-STE100 checker itself, in ISO Prolog. It emits structured terms, and
the host owns the CLI and the wording. The host is
`../src` in Rust; see `../README.md` for the binary.

## Interface

```prolog
set_glossary(+Words)                % once, at startup: a list of atoms
check(+Codes, -Answer)              % the pure entry, used by the tests
check(+Codes, +Syntax, -Answer)     % ... told how to divide the document
check_file(+Path, -Answer)          % reads the file itself, through ISO open/3
check_file(+Path, +Syntax, -Answer) % ... overriding what the extension says
```

`Syntax` is `markdown` or `text`. Anything else is a `type_error`: a syntax the
engine did not recognise would yield no blocks, and a gate that reports nothing
is one that passes everything. `check/2` is `text`, and `check_file/2` reads the
syntax off the extension — only `.md` and `.markdown` are markdown.

Every entry is nondeterministic and yields, in document order:

```prolog
diag(diag(Rule, Severity, span(Line, Byte, Len), Finding, Suggestions))
done(ok)      % ALWAYS the last answer
```

`Line` is 1-based, `Byte` a 0-based byte offset within the line and `Len` a
byte length. Bytes rather than character columns because the host slices the
line, and the corpus contains multi-byte characters — typographic quotes, a
degree sign — on which the two differ. The host converts for display.

In Prolog a query with no solutions is indistinguishable from one that failed
for a bad reason. For a gate, "no errors" is the verdict that lets a document
through, so it must not be reachable by accident. The second branch of
`check/2` succeeds whatever happens to the first. The host's contract: the last
answer is always `done(_)`, and answers running out without it means the engine
failed, not that the document is clean. A clean document yields one answer.

Nothing is materialised across the document: blocks and sentences come from
generators, and only two bounded things are collected — one block's sentence
list, for the rules that count sentences, and one sentence's diagnostics, to
sort them. Global order still holds because the generators run in document
order.

## Shape

Modelled on the Attempto Parsing Engine: a tokenizer front end hands the rules
a clean token list, and source positions ride on every token.

| File | Role |
| --- | --- |
| `markdown.pl` | Lines to blocks, to GitHub Flavored Markdown 0.29-gfm. |
| `text.pl` | Lines to blocks for a file with no markup. Blank lines divide paragraphs and nothing else is structure. |
| `tokenize.pl` | Characters to tokens to sentences, plus the section 8 word counter. |
| `lexicon.pl` | Lookup over `../dictionary/ste_dictionary.pl`, and the verb classes the rules need. |
| `grammar.pl` | The DCG that resolves a part of speech in context. |
| `rules.pl` | The checks. Each one names the rule it enforces, and emits structured findings only. |
| `engine.pl` | `check/2` and `check/3`, the syntax of a document, the generators, the per-sentence sort. Carries no load directives. |
| `load.pl` | The load order, for SWI and for the tests. |

`engine.pl` carries no `ensure_loaded/1`. A host consults these files from
strings compiled into its binary, and has no filesystem to resolve a directive
against. The load order lives in `load.pl` and in `../src/engine.rs`. The tests
use `load.pl`, so a change to one order shows up in the other.

## Portability

Plain ISO Prolog, no module declaration, running under both SWI and the
embedded Scryer. Four rules keep it that way.

- Directives go in functional form, `:- dynamic(foo/1).`, never as a prefix
  operator. SWI declares `dynamic` and `discontiguous` as operators; Scryer
  does not, and the file becomes a syntax error there.
- No `library(...)` imports in these files. Scryer autoloads nothing and needs
  `library(lists)` and `library(dcgs)`; SWI has both built in and has no
  `library(dcgs)` at all. The loader carries the imports, not the engine.
- Nothing outside ISO plus `library(lists)`. `forall/2` was the one slip and
  is inlined as `\+ (Cond, \+ Action)`.
- No `format/3` with an atom sink. That is what carried every message before
  the findings became structured, and it was the single biggest reason the
  engine was not portable.

Block kind decides which rules apply and which sentence limit holds, so the
structure is parsed and not guessed. `markdown.pl` implements the block level
of GitHub Flavored Markdown 0.29-gfm, which is a strict superset of CommonMark:
an ordered list item is `procedural` (rules 5.x, 20 words), a bullet item is an
`item` (25 words, but not a paragraph, so rule 6.6 does not count its
sentences), a paragraph is `descriptive` (rules 6.x, 25 words), a block quote
is a `note` (rule 5.5) at any depth, a paragraph opening with the word WARNING
or CAUTION is `safety`, a heading counts as one word by rule 8.6, a table row
holds labels, and a code block — fenced with backticks or tildes, or indented
four columns — is skipped. An HTML comment `<!-- ste: procedural -->`
overrides the kind of the block that follows it.

Every content line carries the byte offset at which its content begins, worked
out where the containers are known, so a diagnostic inside a nested list still
points into the source line that the host slices.

The structure used to be guessed from each line on its own, and every way that
guess can be wrong appeared as a diagnostic: a bulleted list read as one
paragraph of seven sentences, a step wrapped at a column that lost its second
line, a decimal number opening a line that read as a step and had three of its
characters eaten, a paragraph opening "Warnings" that took the safety limit,
and a tilde fence or an indented code block checked as prose.

## Severity policy

**An error fires only where the standard is closed and the evidence is
positive.** Rule 3.2 enumerates exactly six permitted verb forms, so a
construction outside them is a finding, not a guess. A semicolon is forbidden
outright. A word count is arithmetic.

**A part of speech is resolved by parsing, not by guessing.** The grammar
offers every reading the lexicon allows and the parse decides. A word is
committed only when every parse agrees on it; where they disagree it stays
unresolved and the dependent rules keep quiet.

## What it checks

**16 of the 53 rules** emit a diagnostic.

Errors: 1.2 (a word used in a reading the standard forbids, and words it never
approves), 1.7 (a dictionary noun used as a verb), 3.2 (progressive, perfect —
which is also where rule 3.4 on auxiliary chains lands, though no diagnostic
names 3.4), 3.6 (passive in a procedure), 4.2 (contractions), 5.1 and 6.3
(sentence length, counted by rules 8.4 thru 8.7), 5.4 (condition divided from
the command), 6.6 (six sentences to a paragraph), 8.1 (semicolon).

Warnings: 1.1 (word not in the dictionary — most often a technical noun that
belongs in the glossary), 1.2 where the reading is undecidable, 1.4 and 3.5
(inflections outside the permitted forms), 3.6 (passive in descriptive
text, which rule 3.6 permits when the agent is unknown), 2.1 (a multi-word noun
of more than three words — the rule is closed at three but the constituent
boundary is not: "MOBILE GROUND POWER UNIT" may be a four-word noun or an
adjective before a three-word one), 5.3 (a step that opens with no verb), 5.5
(a note that gives an instruction).

Implemented but never reported, because they are not violations to find:
**8.4 thru 8.7** are the specification of the word counter, on which the 5.1
and 6.3 limits depend. **1.6** governs the severity policy through the
technical-noun escape, and emits nothing of its own.

Out of scope: 1.13, 3.7, 4.5, all of section 7 (safety instructions, though the
block kind is already detected so 7.1 and 7.2 are within reach), all of section
9, and everything editorial (1.3, 1.5, 1.9 thru 1.12, 2.2, 4.1, 4.3, 4.4, 6.1,
6.2, 6.4, 6.5, 8.2, 8.3).

## The grammar

`grammar.pl` resolves a part of speech by parsing rather than by tagging. The
lexicon offers every reading a word has, and the parse settles which survives:

```
Test the system for leaks.        1 parse    Test/v the/art system/n for/prep leaks/n
Do the leak test of the system.   1 parse    Do/v the/art leak/n test/n of/prep the/art system/n
```

So rule 1.2 now applies as written — `"Test" is used as a verb, which is not
approved -> use TEST (n)` on the first, nothing on the second. A newswire-trained
tagger gets this backwards, because it labels a sentence-initial imperative as a
noun, and STE procedures are nothing but sentence-initial imperatives.

Two constraints bound what it claims:

- A position is committed only if every parse assigns it the same part of
  speech. Disagreement produces no claim.
- Failure to parse is not a violation. STE is 53 editorial rules laid over
  ordinary English, not a language a grammar defines, so real text contains
  shapes the grammar does not cover. No parse means the lexicon-only warnings
  still apply and nothing is convicted.

Ambiguity is held down structurally rather than by cutting: a clause takes at
most one bare noun phrase, so noun-phrase boundaries cannot chain; only a
coordinator joins two clauses, subordination going through `condition//1`; and
a bare pronoun noun phrase is restricted to words that really are pronouns,
since `each` and `both` carry a pronoun reading but behave as quantifiers.

Measured over the standard's own examples: 75% of sentences parse and 79% of
word positions resolve, in 1.5 seconds for 2886 sentences. An unresolved
position produces no diagnostic.

The grammar also reports the multi-word noun spans it built, which is where
rule 2.1 comes from. Reconstructing those spans afterwards from runs of nouns
was wrong — it crossed phrase boundaries and called "DO STEP 2 THREE TIMES" a
four-word noun.

## Rule 1.2 and the technical-noun escape

Rule 1.2 says an approved word may be used only as its listed part of speech,
so `test (v)` is forbidden while `TEST (n)` is approved. It is the rule the
dictionary was built for, and it is the one the gate can least enforce.

Rule 1.6 is the reason: a word that is not approved may still appear when it is
a technical noun or part of one, and technical nouns are absent from the
dictionary by design. So `FUEL` in "the fuel pump" is legal even though
`fuel (v)` is forbidden. Measured against the standard's own STE examples,
treating every forbidden reading as an error produced **812 errors on 2886
compliant sentences**, a 28% false-positive rate. Nearly all of it was
technical nouns: fuel, pump, oil,
switch, power, filter, cover, bolt. With the grammar and the severity split
below it is down to **2**.

With the reading resolved, the line falls where the standard puts it:

- The word **is** approved, just not in this reading (`test` as a verb, `check`
  as a verb): rule 1.2 as written, and an **error**.
- **No** reading of the word is approved anywhere (`fuel`, `service`, `part`):
  rule 1.6 leaves the technical-noun escape open and a wrong parse cannot be
  ruled out, so a **warning**.
- The reading is a **noun** and not approved (`failure`, `danger`,
  `attachment`): rule 1.6 again — a technical noun is a noun — so a
  **warning**. "THE DANGER AREA" and "A FAILURE OF THE PUMP" are the standard's
  own STE.
- The advice points at a technical noun or verb (`cover (v) -> COVER (TN)`):
  **warning**.

Independently of the grammar, the standard's own list of the most frequent
errors — minus the entries whose replacement is the same word in another part
of speech — is unconditional: ensure, verify, perform, should, shall, may,
however, therefore, since, utilize. Those are errors whether or not the
sentence parses, and they are exactly where machine-written prose fails.

## The glossary is not optional

Rules 1.1, 1.5, 1.6, 1.8 and 1.12 rest on technical nouns and verbs, an open
set specific to each project. Without a glossary every identifier, product name
and domain term is reported. One word per line, `#` for a comment:

```
bin/ste-check --glossary test/glossary.txt README.md
```

On `test/sample.md` a seven-word glossary drops the warnings from 28 to 20 and
leaves every error in place.

## Tests

```
test/run.sh
```

`test/contract.pl` checks the shape of the answers and the streaming contract;
`test/engine_test.pl` checks what the engine finds and what it must not. Both
load `load.pl` and nothing else, so they exercise exactly what a host loads.

The false-positive guard is the primary test. The standard's own STE examples
are compliant by construction, so an error reported on one of them is a defect
in the engine. The suite reads all 2886 out of the fact base, runs the engine
over them, and requires **zero errors**. It supplies a two-word glossary for
`insert` and `main`, which the standard uses inside technical nouns under rule
1.6. The corpus is generated at run time and not kept in the tree: it is 2886
verbatim examples from a copyrighted document.

## Known limits

- A wrong parse can be unanimous, which produces a false positive with no
  signal that anything went wrong. The corpus has none left. Widening the
  grammar removes them, either by adding a competing parse, which unanimity
  then declines to convict, or by removing the wrong parse.
- The grammar has no coverage for tables, lists inside sentences, or the
  `No. 105` shape of an identifier.
- The glossary matches single words. `main landing gear` needs three entries.
- The syntax of a document comes from its extension, and only `.md` and
  `.markdown` get `markdown.pl`. Everything else, `.txt` included, goes through
  `text.pl`, and so does a string handed to `check/2` with no syntax named: a
  file that never claimed to be markdown should not have a line dropped from
  the check because it opens with a `#`. `check/3` overrides this, and the host
  exposes that as `--syntax`.
- `markdown.pl` implements the block level of the spec and none of the inline
  level. Emphasis and link syntax reach the tokenizer as text, and an inline
  link still convicts its own syntax; see `../ISSUES.md`. The seven HTML block
  conditions are not each implemented, and tight and loose lists are not
  distinguished, which changes the rendering and not the text.
- Predicates live in one flat namespace, so a name can collide across files as
  `run/4` already did once, and `main/0` a second time. Keeping it ISO means no
  modules; prefixing is the fix if it happens again.
- A Scryer syntax error is invisible until it is not: `consult_module_string`
  returns nothing, so the failure appears later as an `existence_error` for
  whatever predicate never got defined. `cargo run --example loadcheck` asks
  the machine what it actually rejected.
- `test/expected.md` and `test/sample.md` contain bad prose by design. They are
  fixtures, not examples to copy.
