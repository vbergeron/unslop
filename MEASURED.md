# How unslop is measured

This is the derivation behind the headline figures in `README.md`: the
corpus, the scripts that reproduce each number, the severity-policy history,
and the full benchmark against a prompt-only STE skill.

A figure nobody can re-derive is worth nothing, so each one here has a script
that prints it:

```
swipl -q -g measure_main -t halt test/measure.pl   # precision, sensitivity
scripts/bench_throughput.sh                        # throughput
scripts/regrade_bench.py --raw DIR                 # the benchmark below
```

## The corpus

Every figure below comes from the standard's own example sentences, which the
extraction puts in `dictionary/ste_examples.pl`. 3007 of them are marked `ste`
and are compliant by construction. 1957 are marked `non_ste`: the sentences
the standard itself prints as wrong. Deduplicated, that is 2886 and 1891. Both
sides are run with the two-word glossary the guard uses, `insert` and `main`,
which the standard puts inside technical nouns under rule 1.6.

## Precision

On the 2886 compliant sentences the engine reports **0 errors**. An earlier
version reported 812, a 28% false-positive rate. `ste/README.md` records what
each correction was. `test/engine_test.pl` holds this as its primary guard.

Warnings are a different matter. The same 2886 sentences draw 4027 of them,
1.40 to a sentence, and 625 sentences — 21.7% — come back without one.
3608 of the 4027 are rule 1.1, a word the dictionary does not carry, which
is what a glossary is for. The rest are 288 of rule 1.2, 80 of 3.6, 42 of 3.5 and 9 of
2.1. So the warning channel is legible only behind a glossary of the subject
field. This repository needs some 200 entries for three files.

## Sensitivity

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
positive that hid there had to be found by running the gate over the README.

## What the severity policy cost

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

## Throughput

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

## Benchmark against a prompt-only skill

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
