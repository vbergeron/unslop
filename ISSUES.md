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

## 2. A unanimous wrong parse on a noun phrase with a relative clause

```
$ unslop -c 'A quoted note that continues lazily.'
error rule 1.2: "note" is used as a verb, which is not approved -> use RECORD (v)
```

`note` is the head noun of the subject. The sentence has no main verb, so no
parse reads it as a declarative, and the parse that survives makes `note` the
verb. Unanimity cannot decline what it never saw a competitor for.

This is the failure mode `ste/README.md` records under Known limits. It is
worth an entry because a since-fixed defect made a resolved verb reading
convict as an error rather than a warning, and a noun phrase with a relative
clause and no main verb is an ordinary caption.

**Fix.** Widen the grammar, as before: a bare noun phrase with a modifier
should parse without a verb, which adds the competing parse that unanimity
then declines to convict.

## 3. An inflected forbidden verb gets the wrong rule and the wrong advice

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

Same shape as the regular-plural gap already fixed in the noun lookup path,
and the advice again tells the writer to whitelist a word the standard
replaces. It adds almost nothing to sensitivity now that a resolved verb
position convicts as an error, 612 against 613, so the value is the rule and
the replacement.

**Fix.** A clause on `form_of/3` mapping a regular inflection onto a
not-approved verb base, beside the `noun_plural/2` clause at
`ste/lexicon.pl:24`. **Not `-ing`**: rule 3.5 permits an `-ing` word as a
modifier, and including it reported `ROTATING` in the standard's own compliant
example of a rotating tube — one new false positive, measured.

## 4. The output does not identify the ruler it measured with

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

## 5. JSON output does not say when the run was cut short

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

## 6. A length limit is cited to a rule that does not set it

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

## 7. Five approved verbs carry no inflected form, and one is in the corpus

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

## 8. A control character in a path panics the process

```
$ unslop "$(printf 'we\nird.md')"
thread 'main' panicked at ... InvalidSingleQuotedCharacter('\n')
exit=101
```

`quote/1` at `src/engine.rs:308` escapes `'` and `\` and nothing else, and
Scryer's reader rejects a raw newline inside a quoted atom. The documented
contract is 0, 1 or 2.

**Fix.** Escape control characters in `quote/1`, or reject such a path in the
host with exit 2 and a message.

## 9. Startup is paid on every invocation

0.35 s to consult the engine and 8679 facts before a byte of input is read,
then 0.32 s of engine for a 750-word document, against 0.03 s for the same
engine under SWI. Acceptable for one agent turn. Three minutes for 500,000
words of `docs/`. The block-level rewrite took the throughput from 1650 to
2460 words a second; the startup is what is left.

**Fix**, in increasing order of work. Accept many files in one invocation,
which the host already does, so the startup cost amortises. Then a long-lived
mode that reads paths on standard input. Then find where Scryer spends the
engine time, because the algorithm is evidently not the cost.

## 10. Each file is read twice

`Input::lines` at `src/main.rs:213` reads the file in Rust to convert a byte
offset into a character column, and `check_file/2` reads it again in Prolog.
Deliberate as far as it goes, since the host holds the text and the engine
holds the parse, but the second read is only wanted for the lines a diagnostic
points at. Minor.

## 11. `ste/README.md` names two words as unconditional that are not

Its Rule 1.2 section lists the decidable subset as `ensure, verify, perform,
should, shall, may, however, therefore, since, utilize`, but `verify` and
`utilize` are not among the 39 `ste_recurring_error/3` facts the extraction
produces, so they never reach `unconditional/2`. The resolved-verb-position
fix made this moot in the output — both are errors now, through that reading
— but the document still describes a mechanism that does not hold. Settle
against the printed page whether the extraction drops rows.
