# Issues

Every entry carries a reproduction, because a defect report that cannot be
re-run is an opinion. The figures come from:

```
swipl -q -g measure_main -t halt test/measure.pl
scripts/bench_throughput.sh
```

Open entries are in the order worth fixing. A false positive in the error
channel comes first, whatever its size: a gate that fails a build for a reason
the writer cannot see is a gate that gets switched off, and then nothing else
on this list matters.

---

# Open

## 1. The grammar is run over a table row, which is labels and not a sentence

Rule 8.6 counts a table cell as one word, because a cell is a label. The
length rules respect that. The grammar does not: it parses the row as a
sentence, and a label then draws a part of speech it never had.

```
$ unslop test/blocks.md
test/blocks.md:31:3: error rule 1.2: "Head" is used as a verb, which is not approved
    -> use POINT (v)
```

`| Head | Cell |` is a header row naming columns. No reading of it as a
sentence is meaningful.

**Fix.** Do not resolve a part of speech in a `table` block: hand
`sentence_diag/4` the empty resolution, so the lexicon-only warnings still
apply and nothing is convicted on a reading the row does not have. Consider
the same for `heading`.

## 2. An inline markdown link convicts its own syntax

```
$ unslop -c '[BUILD.md](BUILD.md) covers it: obtaining the standard.'
2 error(s)          # rule 1.2, "BUILD" is used as a verb

$ unslop -c 'See BUILD.md for the steps.'      0 errors
$ unslop -c 'See `BUILD.md` for the steps.'    0 errors, 0 warnings
```

A bare filename is fine and a code span is fine. The link form is not: the
brackets and parentheses fragment the line, the period of `.md` ends a
sentence, and the fragments that remain give `BUILD` a verb reading. It fires
three times on this repository's own `README.md`.

`markdown.pl` owns the block level and none of the inline level, so link and
emphasis syntax reaches the tokenizer as text. A code span is already a token
of its own; nothing else is.

**Fix.** Recognise `[text](target)` in the tokenizer, emitting the text as
words and the target as one opaque token, the way a code span works. The byte
offsets have to survive it, which is why this belongs in the tokenizer and not
in `markdown.pl`. Then reconsider `markup_word/1`, which drops single-character
words to cope with what emphasis leaves behind and is a symptom of the same
gap.

## 3. A unanimous wrong parse on a noun phrase with a relative clause

```
$ unslop -c 'A quoted note that continues lazily.'
error rule 1.2: "note" is used as a verb, which is not approved -> use RECORD (v)
```

`note` is the head noun of the subject. The sentence has no main verb, so no
parse reads it as a declarative, and the parse that survives makes `note` the
verb. Unanimity cannot decline what it never saw a competitor for.

This is the failure mode `ste/README.md` records under Known limits. It is
worth an entry because F3 made it an error where it was a warning, and a noun
phrase with a relative clause and no main verb is an ordinary caption.

**Fix.** Widen, as F2 did: a bare noun phrase with a modifier should parse
without a verb, which adds the competing parse that unanimity then declines to
convict.

## 4. An inflected forbidden verb gets the wrong rule and the wrong advice

628 of the 629 not-approved single-word verbs carry no inflected form in the
dictionary. That is reasonable, since the standard has no cause to print the
forms of a word you must not write, but `form_of/3` cannot find them, so the
inflection lands on rule 1.1 instead of 1.2:

```
$ unslop --warnings -c 'The pump verified the value.'
warning rule 1.1: "verified" is not in the dictionary
    -> replace it, or add it to the glossary if it is a technical noun
```

```prolog
?- findall(W, ( ste_word(W, v, not_approved, _), \+ sub_atom(W,_,_,_,' '),
                findall(F, (ste_form(F,W,v), F \== W), []) ), Ws), length(Ws, N).
N = 628.
```

Same shape as F5, and the advice again tells the writer to whitelist a word
the standard replaces. It adds almost nothing to sensitivity once F3 is in
place, 612 against 613, so the value is the rule and the replacement.

**Fix.** A clause on `form_of/3` mapping a regular inflection onto a
not-approved verb base, beside the `noun_plural/2` clause at
`ste/lexicon.pl:24`. **Not `-ing`**: rule 3.5 permits an `-ing` word as a
modifier, and including it reported `ROTATING` in the standard's own compliant
example of a rotating tube — one new false positive, measured.

## 5. The output does not identify the ruler it measured with

```
$ unslop --version
unslop 0.1.0                    # the crate, which says nothing about the lexicon
```

Nothing in the JSON either. The lexicon is extracted locally, so two binaries
of the same version can embed different ones: another issue of the standard, or
a corrected extractor. `build.rs` checks that the file exists, not what is in
it.

This blocks the use that needs a stable ruler. Tracked over a corpus, the error
rate separates a drifted agent from a compliant one 97.8% of the time over 8
documents, against 67.8% over one. A team following that figure for six months
cannot tell "the documents got worse" from "we rebuilt the lexicon".

**Fix.** Hash `dictionary/ste_dictionary.pl` in `build.rs`, expose it through
`--version`, and carry it in a header object in the JSON.

## 6. JSON output does not say when the run was cut short

```
$ unslop --format json --max-errors 2 doc.md | jq length
2                    # complete, or truncated? nothing in the output says
```

The text format appends `, stopped early`. `USAGE.md` states the principle —
you cannot read a short count as a correct document — and JSON is what an
agent reads. The exit status still says 1 whenever errors were found, so a gate
is safe; a consumer that decides from the output is not.

**Fix.** Emit a final object carrying `truncated` and the counts, and document
the shape in `USAGE.md` beside the exit status. While there: `--quiet --format
json` prints the count line rather than JSON, which is defensible and
undocumented.

## 7. A length limit is cited to a rule that does not set it

```
$ unslop safety.md
safety.md:1:10: error rule 6.3: sentence of 23 words, the limit for safety text is 20
```

Rule 6.3 sets 25. `too_long/3` at `ste/rules.pl:57` maps `procedural` to rule
5.1 and every other kind to 6.3, while `limit/2` gives safety 20. Section 7 is
out of scope, so a safety block has no implemented rule to cite.

**Fix.** Either cite section 7 and bring 7.1 and 7.2 into scope, which
`ste/README.md` says is within reach now that the block kind is parsed, or drop
`limit(safety, 20)` and let a safety block take the limit rule 6.3 does set.

## 8. Five approved verbs carry no inflected form, and one is in the corpus

`activate`, `deactivate`, `must`, `will` and `cannot` list only the base form
in `ste_form/3`. For the modals that is correct. For `activate` it means the
third-person form draws a warning:

```
$ unslop --warnings -c 'The autopilot activates the mode.'
warning rule 1.1: "activates" is not in the dictionary
```

The standard prints a compliant example using that very form, so this is a
false positive on compliant text, invisible to the guard because the guard
counts errors only.

**Fix.** Examine the printed page. If the forms are there, the gap is in
`scripts/extract_dictionary.py`. If they are not, the engine must derive the
regular forms of an approved verb instead of requiring them listed.

## 9. A control character in a path panics the process

```
$ unslop "$(printf 'we\nird.md')"
thread 'main' panicked at ... InvalidSingleQuotedCharacter('\n')
exit=101
```

`quote/1` at `src/engine.rs:230` escapes `'` and `\` and nothing else, and
Scryer's reader rejects a raw newline inside a quoted atom. The documented
contract is 0, 1 or 2.

**Fix.** Escape control characters in `quote/1`, or reject such a path in the
host with exit 2 and a message.

## 10. Startup is paid on every invocation

0.35 s to consult the engine and 8679 facts before a byte of input is read,
then 0.32 s of engine for a 750-word document, against 0.03 s for the same
engine under SWI. Acceptable for one agent turn. Three minutes for 500,000
words of `docs/`. F6 took the throughput from 1650 to 2460 words a second; the
startup is what is left.

**Fix**, in increasing order of work. Accept many files in one invocation,
which the host already does, so the startup cost amortises. Then a long-lived
mode that reads paths on standard input. Then find where Scryer spends the
engine time, because the algorithm is evidently not the cost.

## 11. Each file is read twice

`Input::lines` at `src/main.rs:175` reads the file in Rust to convert a byte
offset into a character column, and `check_file/2` reads it again in Prolog.
Deliberate as far as it goes, since the host holds the text and the engine
holds the parse, but the second read is only wanted for the lines a diagnostic
points at. Minor.

## 12. `ste/README.md` names two words as unconditional that are not

Its Rule 1.2 section lists the decidable subset as `ensure, verify, perform,
should, shall, may, however, therefore, since, utilize`, but `verify` and
`utilize` are not among the 39 `ste_recurring_error/3` facts the extraction
produces, so they never reach `unconditional/2`. F3 made this moot in the
output — both are errors now, through the resolved verb reading — but the
document still describes a mechanism that does not hold. Settle against the
printed page whether the extraction drops rows.

---

# Rejected

## R1. Rule 5.4 does not forbid a trailing condition

Ranked third to implement once, on the strength of the one category that gets
worse when the `simple-english` skill is loaded: trailing conditions, 16 to 24
by that project's own counter. The ranking and the evidence were both wrong.

Rule 5.4 asks that a condition *the reader must know about first* opens the
instruction and is divided from the command with a comma. That is a judgement
about which conditions must be known before acting, not a test on the position
of `if`. The compliant half of the corpus carries **49 examples with a
non-initial `if` or `when`**, compliant by construction. Their shapes, since
the sentences themselves stay out of this repository:

- an instruction whose object is qualified by a trailing `if` clause, where
  the condition selects among things rather than gating the act;
- an instruction to test *whether* something holds, where `if` introduces a
  complement and is not a condition at all;
- a safety instruction that opens with an imperative and attaches a `when`
  clause. **34 of the 49 are this one idiom**, which the standard uses
  throughout its own safety examples.

Reproduce the count by scanning the compliant corpus for a non-initial `if` or
`when`, as `test/measure.pl` scans it for everything else.

A position test would convict the standard's own STE, including its canonical
safety idiom. The order half of rule 5.4 belongs with rule 1.3: out of scope,
because it needs a person to read for sense.

The same evidence disqualifies the measurement that motivated it. That
project's `trailing_condition` regex flags all three instructions above, so its
count is not evidence about rule 5.4.

---

# Fixed

The reasoning lives in the code that carries it and in the Measured section of
`README.md`. Kept here as one line each, because the measured effect of a
change is the part that does not survive in a diff.

| | What it was | Effect, measured |
| --- | --- | --- |
| **F1** | `take_block/4` ended a block when the *guessed* kind of the next line differed, and a continuation line is guessed `descriptive` whatever it continues | A bulleted list read as a paragraph of seven sentences: an error on ordinary markdown, gone. A step wrapped at a column lost its second line and its word count: rule 5.1 fires again. Also fixed with it: `1.54` opening a line read as a step **and had three characters eaten by the marker measurer**, and a paragraph opening "Warnings" took the safety limit |
| **F2** | Two parse gaps, both under Known limits in `ste/README.md`: no production for a coordinated subject, and the period of `No.` ending a sentence | The two false positives F3 would otherwise have produced. Parse coverage unchanged, 76.2% to 76.3% |
| **F3** | The severity policy excused a word in a position the grammar had committed to a **verb**, where the rule 1.6 technical-noun escape cannot apply | Sensitivity **202 to 613 of 1891, 10.7% to 32.4%**, at **0** false positives, because F2 went first. It also found a real violation in this project's own `USAGE.md` |
| **F4** | The suite held the false-positive count at zero and nothing held the true-positive count | `sensitivity_floor/1`, a floor and not an equality. Verified to fail when raised past the figure |
| **F5** | `resolved_vocab/5` looked words up with `ste_form/3` while the unresolved path used `form_of/3`, which knows regular plurals | `portions` drew a rule 1.1 warning advising the glossary where `portion` drew the error with `PART (n)`. Some 200 nouns. Warning noise also fell 9%, 4450 to 4027 |
| **F6** | The block structure was guessed line by line | Replaced by `ste/markdown.pl`, the block level of [GFM 0.29-gfm](https://github.github.com/gfm/). An indented code block and a tilde fence were not representable, so their content was checked as prose: 12 errors to 6 on a document holding one of each. Throughput 1650 to **2460 words a second** |
| **F7** | The block level had no suite, and the corpus cannot be one: every example is one sentence on one line | `test/markdown_test.pl` over `test/blocks.md`, 21 cases. It found a defect in itself: `table` is a prefix operator in SWI, so `table-31` read as `table(-31)` |
