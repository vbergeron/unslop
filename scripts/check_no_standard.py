#!/usr/bin/env python3
"""Refuse to let ASD's own text into the repository.

`.gitignore` keeps the PDF, the lexicon and the extracted rule text out, which
covers the files the scripts generate. It cannot cover a sentence quoted by
hand into a document, and that is the way ASD's text actually gets in: writing
about a rule, and reaching for the standard's own example to show what it
means. It happened while `ISSUES.md` was being written, four times.

    python3 scripts/check_no_standard.py

Every example sentence in `dictionary/ste_examples.pl` is checked against every
file git would track, and each sentence of a multi-sentence example separately,
since a quotation usually takes one of them. A match exits 1 and names the file.

Needs the extracted examples, so it runs where the standard is held. That is
also where a quotation gets written, which is the point.

What this does NOT check, deliberately: the standard's approved words. A
diagnostic carries them — `use MUST (v), IF (conj)` — because a replacement the
writer cannot see is no help, and the manuals print that output. Words are not
the reproduction the licence is about; sentences and tables are.
"""

import os
import re
import subprocess
import sys

EXAMPLES = "dictionary/ste_examples.pl"
MIN_WORDS = 4  # below this a match is a common phrase, not a quotation

FACT = re.compile(r"^ste_example\([^,]+,\s*[^,]+,\s*[a-z_]+,\s*'(.*)'\)\.$")


def fragments(path):
    """Every example, and every sentence of one, long enough to be a quotation."""
    out = []
    for line in open(path, encoding="utf-8"):
        m = FACT.match(line.strip())
        if not m:
            continue
        text = m.group(1).replace("''", "'")
        for piece in re.split(r"(?<=[.!?])\s+", text):
            if len(piece.split()) >= MIN_WORDS:
                out.append(piece)
    return out


def tracked_files():
    """What git would carry: the tracked files and the untracked ones it would
    add, which is what a first commit is made of."""
    seen = []
    for args in (["git", "ls-files"],
                 ["git", "ls-files", "-o", "--exclude-standard"]):
        run = subprocess.run(args, capture_output=True, text=True)
        seen += run.stdout.split("\n")
    return [f for f in seen if f and os.path.isfile(f)]


def main():
    if not os.path.exists(EXAMPLES):
        print(f"{EXAMPLES} is missing, so there is nothing to check against.",
              file=sys.stderr)
        print("Run scripts/extract_dictionary.py first; see BUILD.md.",
              file=sys.stderr)
        return 2

    texts = fragments(EXAMPLES)
    files = tracked_files()
    hits = []
    for path in files:
        try:
            body = open(path, encoding="utf-8").read().upper()
        except (UnicodeDecodeError, OSError):
            continue
        for text in texts:
            if text.upper() in body:
                hits.append((path, text))

    print(f"{len(texts)} example fragments against {len(files)} files")
    if not hits:
        print("clean: no example sentence of the standard is quoted")
        return 0

    print(f"\n{len(hits)} quotation(s) of ASD's own text:\n", file=sys.stderr)
    for path, text in hits:
        print(f"  {path}\n    {text}\n", file=sys.stderr)
    print("Describe the sentence instead of reproducing it. README.md gives "
          "the reason.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
