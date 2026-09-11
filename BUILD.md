# How to make the unslop binary

This manual tells you how to make the `unslop` binary on your machine. Every
step occurs on your machine. No step sends your data to a different machine.

This repository does not contain ASD-STE100. It also does not contain the data
that the scripts make from it. Thus you must get your copy of the standard
before you start. `README.md` gives the reason.

## Before you start

Make sure that you have these tools:

- Rust 1.88 or later, with `cargo`.
- Python 3.
- `pdftotext`, from the poppler package.
- Git.

To make sure that a tool is on your machine, do this command:

```
cargo --version && python3 --version && pdftotext -v
```

## 1. Get the standard

Go to <https://www.asd-ste100.org/STE_downloads.html>. Complete the form.
ASD sends you Issue 9 of ASD-STE100 at no cost.

The form is how ASD knows who holds a copy. Do not go around it.

Put the PDF in the root of the repository. Give it the name
`ASD-STE100_ISSUE9.pdf`.

Then make sure that you have the correct file:

```
pdfinfo ASD-STE100_ISSUE9.pdf
```

The report must show 434 pages. It must show the title "ASD-STE100 Simplified
Technical English". It must show the author "ASD STEMG". If one of these
values is different, you have a different issue of the standard. Get Issue 9.

## 2. Make the lexicon

Do this command:

```
python3 scripts/extract_dictionary.py
```

The script reads pages 149 thru 434 of the PDF. It makes 2 files in
`dictionary/`:

- `ste_dictionary.pl` — 8,679 facts. The engine reads these.
- `ste_examples.pl` — 4,964 example sentences. Only the tests read these.

The script shows a count for each type of fact. If the script shows a warning
about an unparsed headword, stop and read `dictionary/README.md`.

To also make the 53 rules in a form that you can read, do this command:

```
python3 scripts/extract_rules.py
```

Git ignores all 3 files, because ASD holds the rights to their content.

## 3. Make the binary

Do this command:

```
cargo build --release --locked
```

The `--locked` flag is necessary. One dependency, `ordered-float`, has a
version that is for a later Rust than 1.88. `Cargo.lock` holds the correct
version. Without `--locked`, cargo selects the later version and the build
stops.

The build takes approximately 90 seconds. The result is
`target/release/unslop`, a binary of 7.3 MB.

If the lexicon is absent, `build.rs` stops the build. It then shows these same
steps. A gate without a lexicon lets all documents through, and that result is
worse than no binary.

## 4. Make sure that the binary operates

Do this command:

```
./target/release/unslop --version
./target/release/unslop --quiet test/clean.md
```

This command must show `0 error(s), 0 warning(s)`. It must give the exit
status 0.

Then do this command:

```
./target/release/unslop --quiet test/expected.md
```

This command must show 5 errors. It must give the exit status 1. The 2 results
together show that the gate accepts correct text and stops incorrect text.

## 5. Do the tests

```
test/run.sh
```

The tests use the standard, thus they operate only on your machine. The suite
does 2 Prolog suites and the tests of the host.

The most important test is the guard against false positives. It gives the
2,886 STE examples of the standard to the engine. All of them are correct STE,
thus the engine must find no error in them.

## If a step stops with an error

If cargo shows `ordered-float ... requires rustc`, you did not use `--locked`.
Do the command again with the flag.

If the build stops and shows `ste_dictionary.pl is missing`, do step 2 again.

If the binary shows `existence_error` for a predicate, a Prolog file has a
syntax error that Scryer does not accept. Do this command to see the cause:

```
cargo run --example loadcheck
```

If a test shows `FAIL`, read `ste/README.md`. It records the purpose of each test.
