# How to operate unslop

This manual tells you how to examine documents with `unslop`. To make the
binary, read `BUILD.md`.

`unslop` reads a document. It compares the text against ASD-STE100 Simplified
Technical English. Then it reports each rule that the text does not obey.

## Examine one document

Do this command:

```
unslop docs/guide.md
```

Each report has this form:

```
docs/guide.md:5:1: error rule 1.2: "should" is never approved in STE
    -> use MUST (v), IF (conj)
```

The first line gives the position and the rule. The second line gives the
correction from the standard. The words after `use` are the words of ASD, not
ours.

## Examine a directory

`unslop` gives an error when a file in your list is a directory. Add
`--recursive` to read the files under it instead:

```
unslop --recursive docs
```

`unslop` reads each `.md` and `.markdown` file under the directory. It does
not read a file of another type, and it does not read `.git`.

## Examine text from a pipe

If you give no file name, `unslop` reads standard input:

```
cat docs/guide.md | unslop
```

A file name of `-` also means standard input:

```
unslop - < docs/guide.md
```

To examine one line of text, use the `-c` option:

```
unslop -c 'Test the system.'
```

## The exit status

The exit status is the contract of the gate:

- 0 — The gate found no error.
- 1 — The gate found errors.
- 2 — The command stopped before it could give a result.

A warning does not change the exit status. Thus a warning never stops your
build.

Status 2 is different from status 0. Status 2 shows that `unslop` did not
complete. Do not read it as a correct document.

## Errors and warnings

`unslop` shows only errors by default. To also show warnings, use the
`--warnings` option.

An error is a rule that the standard makes certain. A word that STE never
approves is an error. A sentence of 30 words in descriptive text is an error.

A warning is a rule that needs a decision from a person. Rule 1.6 lets a word
that is not approved stand when it is a technical noun, and no lookup can tell
the two apart. Thus such a word gives a warning.

## The glossary

Rules 1.1, 1.6 and 1.8 rest on technical nouns. A technical noun is part of
your subject field. ASD does not put technical nouns in the dictionary,
because each project has different ones.

Without a glossary, `unslop` reports each identifier and each product name.
Give it your own glossary:

```
unslop --glossary glossary.txt docs/*.md
```

Write one word for each line. A line that starts with `#` is a comment. This
project has its own glossary in `glossary.txt`. This manual and `BUILD.md` use
that same file, thus the two manuals keep one word for each concept.

## Other options

| Option | The result |
| --- | --- |
| `--recursive` | Reads the files under a directory |
| `--glossary FILE` | Reads your technical nouns from FILE |
| `--warnings` | Shows warnings and errors |
| `--quiet` | Shows only the count at the end |
| `--format json` | Gives one JSON object for each report |
| `--max-errors N` | Stops after N errors in a file |
| `--syntax auto\|md\|text` | Selects how to read the structure |

`--max-errors` counts errors and not reports of all types. If it stops the walk, the count
line also shows `stopped early`. Thus you cannot read a short count as a
correct document.

## Tell unslop the type of a block

The rules for a procedure are different from the rules for a description. A
step in a procedure has a limit of 20 words. A sentence in a description has a
limit of 25 words.

`unslop` reads the structure of the document to select the type:

| What you write | The rules that apply |
| --- | --- |
| A numbered list item | Procedural, rules 5.x, 20 words |
| A paragraph | Descriptive, rules 6.x, 25 words |
| A block quotation | A note, rule 5.5 |
| A line that starts with WARNING or CAUTION | Safety, rules 7.x |
| A heading | One word, by rule 8.6 |
| A row of a table | Labels, by rule 8.6 |
| A fenced code block | Not examined |

If the guess is not correct, write a marker before the block:

```
<!-- ste: procedural -->
```

## How unslop reads the structure

The name of the file selects the rules. A file with the name `.md` or
`.markdown` gets the markdown structure of the table above. Each other file is
plain text.

Plain text has no structure to read. Each line is text, thus `#` is not a
heading, and `unslop` examines the lines of a fenced code block. An empty line
divides one paragraph from the next, and nothing else divides the document.

Standard input and `-c` have no file name, thus they are plain text. To read
them as markdown, use the `--syntax` option:

```
cat docs/guide.md | unslop --syntax md
```

The option also gives the other result. It reads a markdown file as plain
text:

```
unslop --syntax text docs/guide.md
```

| What you give | How unslop reads it |
| --- | --- |
| `docs/guide.md` | Markdown |
| `notes.txt` | Plain text |
| `README` | Plain text |
| Standard input or `-c` | Plain text |
| `--syntax md` | Markdown |
| `--syntax text` | Plain text |

## Use unslop as a gate

Put `unslop` in front of the documents that an agent writes:

```
unslop --glossary glossary.txt docs/*.md || exit 1
```

The command gives status 1 when it finds an error, thus the build stops.

To let a document through while you correct it, remove it from the list. Do
not lower the rules for all documents, because a gate that reports no error
gives no protection.

## The limits of unslop

`unslop` examines 16 of the 53 rules. It cannot examine a rule that needs a
person to read for sense. Rule 1.3 is one example. It is about the approved
use of a word, and a lookup cannot make that decision.

A document that gives no error is a document with no mechanical error. It is
not a document that obeys ASD-STE100. No tool can give that result.
