# unslop

[![CI](https://github.com/vbergeron/unslop/actions/workflows/ci.yml/badge.svg)](https://github.com/vbergeron/unslop/actions/workflows/ci.yml)
[![Licence: MIT OR Apache-2.0](https://img.shields.io/badge/licence-MIT%20OR%20Apache--2.0-blue.svg)](#licence)

A mechanical ASD-STE100 gate for documentation. Checks prose against
Simplified Technical English and reports each rule the text breaks, at a line
and column, with the replacement the standard gives. It runs offline, against
a lexicon extracted from the standard: no network call, no second model
grading the first.

```
$ unslop docs/guide.md
docs/guide.md:5:1: error rule 1.2: "should" is never approved in STE
    -> use MUST (v), IF (conj)
docs/guide.md:8:4: error rule 1.2: "Check" is used as a verb, which is not approved
    -> use MAKE SURE (v), MEASURE (v), EXAMINE (v), CHECK (n)
6 error(s), 26 warning(s)
```

## Quick start

There is no `cargo install unslop`. The binary embeds a lexicon extracted
from a copyrighted standard, so you build it yourself once you hold a copy —
three commands, once you have the PDF:

```
# get the standard free of charge, save it as ASD-STE100_ISSUE9.pdf in the
# repository root: https://www.asd-ste100.org/STE_downloads.html
python3 scripts/extract_dictionary.py
cargo build --release --locked
```

[BUILD.md](BUILD.md) walks through each step and what to do if one fails.
The *Licensing* section right below explains why this can't be a one-liner.
Once you have a binary, [USAGE.md](USAGE.md) or *Usage* below covers running
it.

## Contents

[Licensing](#licensing) · [Build](#build) · [Usage](#usage) ·
[Design](#design) · [Coverage](#coverage) · [Measured](#measured) ·
[In an agent loop](#in-an-agent-loop) · [Layout](#layout) ·
[Copyright](#copyright) · [Licence](#licence)

## Licensing

ASD-STE100 is copyright ASD, Brussels. "ASD-STE100" and "Simplified Technical
English" are EU trade marks, No. 017966390.

The front matter of the standard states: *no reproduction or publication of it,
in whole or in part, shall be made without the written authority of an officer
of ASD.*

It then grants usage rights, free of charge, to eight categories of
organisation:

1. National associations that are ASD members, and their member companies.
2. Members of AIA (US) and AIAC (Canada).
3. Members of ICCAIA not covered by 1 and 2.
4. Customers of companies in categories 1 to 3.
5. Ministries of Defence of ASD, AIA and AIAC member countries.
6. Airlines for America (A4A).
7. Airworthiness authorities.
8. Universities and research institutes, for educational purposes.

The grant is by organisation, not by purpose. Whether you may hold and
redistribute a copy depends on which category you fall into.

Two clauses are commonly misread:

- The *disclaimer of liability* states that the document creates no legal
  obligations. It applies to the writing rules. It is not a copyright waiver.
- In the EU the lexicon carries two rights: copyright in the definitions and
  examples, and the sui generis database right (Directive 96/9/EC), which
  covers the investment in assembling it regardless of originality.

### Consequences for this repository

| | |
| --- | --- |
| In the repository | The extractors, the engine, the host, the tests, the manuals |
| Not in the repository | The PDF, the lexicon, the extracted rule text |
| Not published | Release binaries. A binary embeds the lexicon |

You obtain the standard yourself, through ASD's
[request form](https://www.asd-ste100.org/STE_downloads.html). The scripts turn
your copy into a lexicon on your machine. This is not automated: the form
records who holds a copy, and the usage grant depends on that record.

`scripts/check_no_standard.py` holds the line where `.gitignore` cannot.
`.gitignore` covers the files the scripts generate; it cannot cover a sentence
quoted by hand into a document, which is how ASD's text actually gets in. The
check reads every example out of your copy and refuses any that appears in a
file git would carry. It runs with the tests.

The extraction keeps only what a rule reads. ASD's definitions and its 4964
example sentences are 58% of the extracted volume and no rule reads either;
the definitions are dropped, and the examples go to a separate file that only
the test suite loads. `dictionary/README.md` covers the extraction.

For anything beyond this, ASD grants written authority on request:
`stemg@asd-ste100.org`.

## Build

[BUILD.md](BUILD.md) covers it: obtaining the standard, making the lexicon,
compiling, and verifying the result.

```
python3 scripts/extract_dictionary.py
cargo build --release --locked
```

`--locked` is required: `Cargo.lock` pins `ordered-float` to a version that
builds on Rust 1.88. `build.rs` fails the build when the lexicon is absent.

The release binary is 7.3MB. Its dynamic dependencies are libc, libm and
libgcc_s. Build time is about 90 seconds.

## Usage

[USAGE.md](USAGE.md) covers the exit contract, errors against warnings, the
glossary, block types, and the limits.

```
unslop docs/guide.md
cat docs/guide.md | unslop
unslop --glossary glossary.txt docs/*.md || exit 1
```

Exit status: 0 no error, 1 errors found, 2 the run failed. Warnings do not
change the status.

BUILD.md and USAGE.md are written in Simplified Technical English and report
zero errors under this tool. Both read `glossary.txt`, so one concept keeps one
word across both (rules 1.11 and 9.4).

## Design

**Engine: Prolog.** Rule 1.2 forbids `test (v)` and approves `TEST (n)`, so the
checker must resolve a part of speech in context. A statistical tagger labels a
sentence-initial imperative as a noun, which is the shape of every STE
procedure. A DCG over the closed lexicon resolves it by parsing, and commits a
word only when every parse agrees. `ste/README.md` covers the grammar.

**Structure: parsed, not guessed.** Block kind decides which rules apply and
which sentence limit holds, so `ste/markdown.pl` implements the block level of
[GitHub Flavored Markdown 0.29-gfm](https://github.github.com/gfm/), a strict
superset of CommonMark. Only a file that claims to be markdown gets it: `.md`
and `.markdown` are parsed as markdown, and everything else — `.txt`, no
extension at all, standard input — goes through `ste/text.pl`, where a blank
line divides paragraphs and nothing else is structure. Reading `#` as a heading
in a file that never said it was markdown drops that line's words from the
check, and dropping words is how a gate goes quiet. `--syntax md|text`
overrides the choice. Every way a line-by-line guess can be wrong used to
appear as a diagnostic: a bulleted list read as a paragraph of seven sentences,
a step wrapped at a column that lost its second line and its word count, a
tilde fence checked as prose. `test/markdown_test.pl` holds the block stream
against a fixture, which is the level the corpus cannot reach.

**Host: Rust.** The engine emits structured terms —
`diag(Rule, Severity, span(Line, Byte, Len), Finding, Suggestions)` — one
solution at a time, and carries no wording. The host owns the text, the output
formats and the exit codes. `include_str!` compiles the Prolog sources into the
binary, so there is no runtime to install.

The engine is ISO Prolog with no module declaration. It runs under SWI, for
development and the tests, and under the embedded Scryer.

## Coverage

16 of the 53 rules emit a diagnostic. Rules 8.4 to 8.7 are implemented as the
word counter rather than as checks. Rule 1.6 governs the severity policy and
emits nothing. Sections 7 and 9 are not covered.

An error is reported only where the standard is closed and the evidence is
positive. A reading the grammar cannot settle produces a warning.
`ste/README.md` lists which rule falls where.

## Measured

Every figure below comes from the standard's own example sentences, which the
extraction puts in `dictionary/ste_examples.pl`. 3007 of them are marked `ste`
and are compliant by construction. 1957 are marked `non_ste`: the sentences
the standard itself prints as wrong. Deduplicated, that is 2886 and 1891. Both
sides are run with the two-word glossary the guard uses, `insert` and `main`,
which the standard puts inside technical nouns under rule 1.6.

A figure nobody can re-derive is worth nothing, so each one here has a script
that prints it:

```
swipl -q -g measure_main -t halt test/measure.pl   # precision, sensitivity
scripts/bench_throughput.sh                        # throughput
scripts/regrade_bench.py --raw DIR                 # the comparison below
```

### Precision

On the 2886 compliant sentences the engine reports **0 errors**. An earlier
version reported 812, a 28% false-positive rate. `ste/README.md` records what
each correction was. `test/engine_test.pl` holds this as its primary guard.

Warnings are a different matter. The same 2886 sentences draw 4027 of them,
1.40 to a sentence, and 625 sentences — 21.7% — come back without one.
3608 of the 4027 are rule 1.1, a word the dictionary does not carry, which
is what a glossary is for. The rest are 288 of rule 1.2, 80 of 3.6, 42 of 3.5 and 9 of
2.1. So the warning channel is legible only behind a glossary of the subject
field. This repository needs some 200 entries for three files.

### Sensitivity

The 1891 non-compliant sentences are the other half of the same corpus, and
they are the true-positive side that nothing used to guard:

| | |
| --- | --- |
| Draw an error | **613 of 1891, 32.4%** |
| Draw a diagnostic of any severity | 1860, 98.4% |

Per (headword, sentence) pair, where the standard names the word it objects
to: of 1893 pairs, 480 draw an error, 1065 draw a warning, and 348 draw
nothing on that word.

Warnings are hidden by default and never change the exit status, so the error
figure is what the gate stops. It stood at 202 of 1891, 10.7%, until the
severity policy stopped excusing a word in a position the grammar had
committed to a verb. `test/engine_test.pl` now holds it as a floor, beside the
false-positive guard, so a change cannot quietly halve it.

What the corpus cannot reach is the block level. It supplies one sentence at a
time, so no multi-line block is ever built and a bare imperative is guessed
descriptive, which leaves rules 5.1, 5.3, 5.4 and 5.5 unexercised by it.
`test/blocks.md` and `test/markdown_test.pl` are the answer: a fixture of
blocks rather than sentences, holding the structure the gate reads. The false
positive that hid there had to be found by running the gate over this README.

### What the severity policy cost

Rule 1.6 lets a word the dictionary does not approve stand when it is a
technical noun, so a word no reading of which is approved anywhere could only
draw a warning: a wrong parse cannot be ruled out. The clause did not look at
the part of speech the grammar had committed to. Where that position is a
**verb** the technical-noun escape cannot apply, and the technical-verb escape
is tested one branch earlier, through `technical_advice/2`.

| | False positives of 2886 | Non-compliant caught of 1891 |
| --- | --- | --- |
| Before | 0 | 202, 10.7% |
| Verb positions convicted | 2, 0.07% | 613, 32.4% |
| …and the two parse gaps closed | **0** | **613, 32.4%** |

The two false positives were the two shapes already under Known limits in
`ste/README.md`: a unanimous wrong parse reading a technical noun as a verb in
a conditional whose subject is two coordinated nouns, and a `No. ` identifier
after a heading noun. Neither was intrinsic to the severity choice. Closing
them — a coordinated subject in the grammar, and a period that a numeral
follows no longer ending a sentence — gives three times the sensitivity at no
cost in precision.

### Throughput

The embedded machine sets the speed, not the algorithm. The same engine over
the same document, best of three from `scripts/bench_throughput.sh`:

| | |
| --- | --- |
| Startup, consulting 8679 facts | 0.35 s, on every invocation |
| `USAGE.md`, 750 words, through the binary | 0.67 s, so 0.32 s of engine |
| `USAGE.md`, the same engine under SWI | 0.03 s |
| 59,600 words of prose | 24 s, about 2460 words a second |

One binary with no runtime to install costs an order of magnitude of speed. At
2460 words a second, an agent that rewrites a 2000-word document pays about a
second a turn. A gate across 500,000 words of `docs/` takes three minutes.

## In an agent loop

Code has compilers, tests and linters: oracles that a plausible answer does
not satisfy. Prose has none, which is why documentation is where the output of
an agent degrades with nothing to say no to it.

ASD-STE100 fits that gap for a reason that is not elegance. Its reference is
closed: some 900 approved words, one part of speech to each, and the
replacement printed beside the word. A closed reference makes decidable what
otherwise needs judgement. Judgement inside an agent loop degrades into asking
a second model, which correlates the grader with the generator.

Two things are wanted, and they are not the same thing. A skill steers the
model while it writes. A gate says no afterwards, on evidence the model does
not own.

### Grading the generator side

[`simple-english`](https://github.com/AminBlg/SimpleEnglish) (MIT) is the
skill side of the same standard: it loads STE into the model before it writes.
It reports 74.6% fewer STE violations, measured by its `evals/ste_lint.py` —
132 lines, ten regular expressions, no lexicon and no part of speech. That
file says as much itself: a regex pass, not a compliance verdict. Its README
carries the same warning.

Because it publishes its raw eval outputs, the claim can be checked against
the lexicon instead. 112 texts, 56 baseline and skill pairs over 7 Claude
models, re-graded here. Its own aggregation is kept: a rate for each text, the
mean of those for each model, then the mean of the seven model reductions.

| Model | Its counter | This gate, word-weighted |
| --- | --- | --- |
| claude-opus-5 | 85.2% | 65.6% |
| claude-opus-4-6 | 82.3% | 39.7% |
| claude-opus-4-7 | 81.7% | 15.5% |
| claude-sonnet-5 | 80.0% | 37.8% |
| claude-opus-4-5 | 77.6% | 57.4% |
| claude-sonnet-4-6 | 74.9% | 19.5% |
| claude-opus-4-8 | 41.3% | 39.6% |
| **Mean** | **74.7%** | **39.3%** |

Its own aggregation reproduces its published 74.6% to a rounding step, which
is what shows the two graders are reading the same data. That aggregation is
the mean of a rate computed for each text, and it cannot carry the right
column: 17 of the 112 generations are under 20 words, two of them one word, so
a single error in a 5-word text reads as 40 per 100 words and moves a model by
a hundred points. The right column is therefore weighted by words. Pooled over
every text: 2.29 to 0.68 violations per 100 words by its counter, 2.88 to 1.67
errors per 100 words by this gate, so −70.2% against −42.0%. Paired by model
and scenario, the skill is better on 45 of 56 and worse on 11.

Three results, and all three matter:

- The claim holds under an independent grader, about half the size.
- A weak grader flattens the models. Its counter spreads them over 44 points
  and puts `claude-opus-4-8` last; the lexicon spreads them over 50 and puts
  `claude-opus-4-7` last, at 15.5%. The ranking a benchmark produces is a
  property of its grader before it is a property of the models.
- 1.67 errors per 100 words remain with the skill on, and 11 pairs of 56 get
  worse. A skill does not reach compliance by itself, which is the argument
  for a gate that does not share its evidence.

The gap widened when the gate got stricter: it measured the same runs at
−58.9% before the severity policy stopped excusing a verb reading. What that
change added to the gate's sight is vocabulary in a verb position, and
vocabulary is what a prompt fixes least — so the stricter the grader, the
smaller the prompt's measured effect.

`scripts/regrade_bench.py` is the whole of it, against a checkout of that
project:

```
scripts/regrade_bench.py --raw ../SimpleEnglish/evals/results/raw
```

It reads that project's raw files where they sit and copies nothing. It keeps
its `lint.words` as the denominator, so a different way of counting words
cannot appear as a difference between graders. It prints both aggregations.

### What this gate does not do

The name promises more than the standard gives. `robust`, `comprehensive`,
`leverages`, `seamlessly` and `simply` come out as rule 1.1 warnings, which is
where `pump` and `technician` come out too. ASD-STE100 is a controlled
language, not a detector of promotional register.

Where the two overlap, the error channel is accurate. On a paragraph of
ordinary machine prose it fires on `should` twice, `however`, `may`, `need`,
`now`, two contractions, one progressive and a 28-word sentence. Those are the
entries the standard's own list of frequent errors was built from. A model
that writes fast fails where a writer in a hurry does.

## Layout

| Path | Contents |
| --- | --- |
| `BUILD.md`, `USAGE.md` | The manuals. STE, sharing `glossary.txt` |
| `scripts/` | The extractors: PDF to lexicon, PDF to rule text. The benches behind the figures above |
| `ste/` | The engine, in ISO Prolog. `markdown.pl` is the block structure |
| `src/` | The host, in Rust. Produces the `unslop` binary |
| `test/` | Prolog suites, `blocks.md` and `measure.pl`. They need the standard, so they run locally |
| `examples/loadcheck.rs` | Reports what Scryer rejects while loading |

Open defects are tracked as [GitHub Issues](https://github.com/vbergeron/unslop/issues),
not in this tree. Issues and pull requests are welcome. A change to `ste/` or
`src/` needs `test/run.sh` to pass, which needs your own copy of the
standard, per Licensing above.

## Copyright

ASD-STE100 is copyright and an EU trademark of ASD, Brussels (EU Trade Mark
No. 017966390). The code in `ste/`, `src/` and `scripts/` is ours. The output of
those scripts is ASD's. `.gitignore` excludes it, and releases carry
instructions instead.

## Licence

The source in this repository is under either [MIT](LICENSE-MIT) or
[Apache-2.0](LICENSE-APACHE), at your option. Both are the standard texts,
unmodified.

The grant reaches the source and stops there. It does not reach ASD-STE100, the
lexicon or rule text a script extracts from it, or a binary built from them: the
binary embeds the lexicon, which is why no release carries one. Neither licence
grants any right in the trade marks "ASD-STE100" and "Simplified Technical
English" — Apache-2.0 excludes them at section 6, and MIT says nothing, which
is not a grant.

The dependencies impose nothing further. All 303 crates in the build graph are
permissive: Scryer is BSD-3-Clause, and four MPL-2.0 crates arrive under
`scraper`. MPL-2.0 is per-file copyleft that leaves this code alone and asks
only that the source of those files reach whoever gets a binary, which no one
does.
