#!/usr/bin/env python3
"""Rebuild the dictionary data in ../dictionary/ from ../ASD-STE100_ISSUE9.pdf.

Part 2 of the standard is one 4-column Word table repeated over PDF pages
149-434.  `pdftotext -layout` looks clean on the first page and quietly
corrupts the rest, so the table is rebuilt from word-level geometry
(`pdftotext -bbox-layout`).  Facts verified against the file, which the parser
relies on:

  * column starts are 72 / 180 / 310 / 439 pt, all shifted -22 on verso pages
    (binding margin); some pages jitter by 1-2pt
  * pdftotext often merges cells that sit side by side into a single <line>,
    so both the column AND the row of every word are taken from the word's own
    box, never from the enclosing line
  * columns 2-4 are set in a larger font than column 1 on some pages but not
    others, so a cell's box top can sit up to ~4pt above its neighbour in the
    same row; rows are >=18pt apart, so cells are matched to the nearest row
    anchor rather than to a fixed offset
  * a line wrapped inside a cell sits 11.5-12.1pt below the line above it,
    while the next row starts at least 18pt lower
  * the standard mixes editorial notes into columns 2 and 3, set apart only by
    a deep indent, so a cell indented past its column start is kept separately

Usage: python3 scripts/extract_dictionary.py
"""
import json, re, subprocess, sys, tempfile
import xml.etree.ElementTree as ET
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PDF = ROOT / "ASD-STE100_ISSUE9.pdf"
OUT = ROOT / "dictionary"
DICT_FIRST, DICT_LAST = 149, 434      # pages holding dictionary entries
ERRATA_PAGES = (145, 146)             # "List of recurring errors", Part 2 intro
ISSUE, ISSUE_DATE = "Issue 9", "2025-01-15"

BASE = (72.0, 180.0, 310.0, 439.0)
TOL = 12.0         # how far left of its column start a cell's content may begin
SAMELINE = 2.5     # word boxes within this many pt are on the same line
WRAP = 14.0        # line gap up to which a line is a wrap of the cell above
ROWTOL = 6.0       # cell tops this close belong to the same row
NOTE_IN = 30.0     # a cell indented this far past its column is a note
POS = "n|v|adj|adv|prep|conj|pron|art|prefix|TN|TV"
CHROME = {"Word", "(part of speech)", "Approved meaning/", "ALTERNATIVES",
          "STE EXAMPLE", "Non-STE example", "Blank Page"}
NOFORMS = re.compile(r"No other (verb )?forms?( of this adjective)?\.?", re.I)


def parse_entries(bbox_xml):
    root = ET.fromstring(bbox_xml[bbox_xml.index("<doc>"):bbox_xml.index("</doc>") + 6])
    entries, anomalies, orphans = [], [], []
    cur = None

    for pno, page in enumerate(root.iter("page"), start=DICT_FIRST):
        words = []
        for ln in page.iter("line"):
            ws = sorted((float(w.get("xMin")), float(w.get("yMin")), w.text or "")
                        for w in ln.findall("word") if 58 < float(w.get("yMin")) < 695)
            if ws: words.append(ws)
        if not words: continue

        xs = [x for ws in words for x, _, _ in ws]
        off = max((0.0, -22.0),
                  key=lambda o: sum(1 for x in xs
                                    if any(abs(x - (b + o)) < 5.0 for b in BASE)))
        S = [b + off for b in BASE]

        # walk each line left to right, so a line merged out of two cells splits
        percol = defaultdict(list)
        for ws in words:
            c = max((i for i in range(4) if ws[0][0] >= S[i] - TOL), default=0)
            for x, y, t in ws:
                while c < 3 and x >= S[c + 1] - TOL:
                    c += 1
                percol[c + 1].append((y, x, t))

        # words -> lines -> cells (a step of ~12pt is a wrap of the cell above)
        cells = defaultdict(list)
        for c, ws in percol.items():
            lines = []
            for y, x, t in sorted(ws):
                if lines and y - lines[-1][0] <= SAMELINE:
                    lines[-1][1].append((x, t))
                else:
                    lines.append([y, [(x, t)]])
            for y, items in lines:
                items = sorted(items)
                t = " ".join(t for _, t in items).strip()
                if not t or t in CHROME: continue
                note = items[0][0] > S[c - 1] + NOTE_IN
                if cells[c] and y - cells[c][-1][2] <= WRAP and note == cells[c][-1][3]:
                    cells[c][-1][1] += " " + t
                    cells[c][-1][2] = y
                else:
                    cells[c].append([y, t, y, note])

        # a column-1 cell that is only the "no other forms" note carries no data
        cells[1] = [c for c in cells[1] if not NOFORMS.fullmatch(c[1].strip())]

        # rows: cluster cell tops, then match every cell to the nearest anchor
        tops = sorted(y for c in (1, 2, 3, 4) for y, _, _, _ in cells[c])
        rows = []
        for y in tops:
            if not rows or y - rows[-1] > ROWTOL: rows.append(y)
        if not rows: continue
        byrow = defaultdict(lambda: defaultdict(list))
        for c in (1, 2, 3, 4):
            for y, t, _, note in cells[c]:
                i = min(range(len(rows)), key=lambda k: abs(rows[k] - y))
                byrow[i][5 if note else c].append(t)

        for i in range(len(rows)):
            at = lambda c: " ".join(byrow[i][c])
            head = re.sub(r"(\w)- (\w)", r"\1\2", at(1))       # rejoin hyphen wraps
            row = {"alt": at(2), "ste": at(3), "non_ste": at(4), "note": at(5)}
            if head:
                m = re.match(r"^(.+?)\s*\((" + POS + r")\)\s*(.*)$", head)
                if m:
                    word, pos, rest = m.group(1).strip(), m.group(2), m.group(3).strip()
                else:
                    word, pos, rest = head.strip(), "", ""
                    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9 \-'.()]*", head):
                        anomalies.append((pno, head))
                rest = NOFORMS.sub("", rest).strip()
                # BE prints its forms as "IS, WAS, (also ARE, WERE)"
                forms = [re.sub(r"^(also|or)\s+", "", f.strip(" ()."), flags=re.I)
                         for f in rest.lstrip(",").split(",") if f.strip(" ().")]
                # OCCUR and PROTRUDE print their forms with no comma between
                # them, so a comma split glues them into one. A form holding a
                # space, in an entry whose headword holds none, is several
                # forms. The guard keeps "MAKES SURE" whole.
                if " " not in word:
                    forms = [f for form in forms for f in form.split()]
                cur = {"word": word, "pos": pos, "forms": forms,
                       "approved": word == word.upper(), "page": pno, "rows": [row]}
                entries.append(cur)
            elif any(row.values()):
                (cur["rows"].append(row) if cur else orphans.append((pno, row)))

    return entries, anomalies, orphans


# The PDF breaks nine words across lines at a hyphen. Seven are real compounds
# that keep the hyphen; these two were split inside a single word.
SYLLABIC = {"TRICHLORO-ETHYLENE": "TRICHLOROETHYLENE",
            "ELECTROMAG-NETICALLY": "ELECTROMAGNETICALLY"}


def cl(s):
    s = re.sub(r"\s+", " ", (s or "").replace("\t", " ")).strip()
    s = re.sub(r"(?<=[A-Za-z])- (?=[A-Za-z])", "-", s)
    for a, b in SYLLABIC.items():
        s = s.replace(a, b)
    return s




def recurring_errors(layout_text):
    pages = layout_text.split("\f")
    out = []
    for i in ERRATA_PAGES:
        for line in pages[i - 1].split("\n"):
            m = re.match(r"^\s{1,4}([a-z][^()]*\((?:n|v|adj|adv|prep|conj|pron|art)\)"
                         r"|[a-z][a-z ]+?)\s{2,}(\S.*?)\s*$", line)
            if m and "Non-STE" not in line:
                out.append((m.group(1), m.group(2)))
    return out


# --- Prolog emission ---------------------------------------------------------

# Atoms that are Prolog operators or directives must be quoted even though they
# look like plain lowercase words. "is" and "not" really do occur in the STE
# vocabulary (forms of BE, and NOT (adv)).
RESERVED = {"is", "not", "mod", "rem", "div", "rdiv", "xor", "as", "in",
            "dynamic", "discontiguous", "initialization", "module", "table",
            "meta_predicate", "public", "mode", "op"}


def atom(s):
    """Render s as a Prolog atom, bare when that is unambiguous."""
    s = cl(s)
    if re.fullmatch(r"[a-z][a-z0-9_]*", s) and s not in RESERVED:
        return s
    return "'" + s.replace("\\", "\\\\").replace("'", "''") + "'"


def usage_of(word):
    """Split a printed headword into (bare word, parenthetical) or (word, None)."""
    m = re.match(r"^(.+?)\s*\((.+)\)$", re.sub(r"\s+\)", ")", cl(word)))
    return (m.group(1).strip(), m.group(2).strip()) if m else (cl(word), None)


def spelling_of(qual):
    """'or MATTE' -> 'MATTE'; anything else -> None (it is a construction)."""
    if qual and re.match(r"^or\s+", qual, flags=re.I):
        return re.sub(r"^or\s+", "", qual, flags=re.I)
    return None


def key_of(word):
    """Lookup key: the printed headword, lowercased.

    A construction's parenthetical is deliberately kept: "PREVENT (v)" is
    approved while "prevent (from) (v)" is not, so stripping it would merge an
    approved word with a forbidden construction into contradictory facts. An
    "(or SPELLING)" note is not a construction, so it is dropped from the key.
    """
    bare, qual = usage_of(word)
    if spelling_of(qual):
        return bare.lower()
    return re.sub(r"\s+\)", ")", cl(word)).lower()


def pos_of(pos):
    return pos.lower() if pos else "none"


EXAMPLES_HEADER = f"""% ASD-STE100 Simplified Technical English, {ISSUE}, {ISSUE_DATE}
% The example sentences from Part 2, as Prolog facts. Generated by
% scripts/extract_dictionary.py -- do not edit by hand.
%
% Kept apart from ste_dictionary.pl on purpose. No rule reads an example: they
% exist for the false-positive guard in test/engine_test.pl, which runs the
% checker over the standard's own compliant STE and requires zero errors. The
% binary embeds the lexicon, not this file.
%
%   ste_example(Word, POS, Kind, Text)        Kind: ste | non_ste
%
% Copyright: ASD-STE100 is a copyright and an EU trademark of ASD, Brussels.
% See ../dictionary/README.md before redistributing any of this.

:- discontiguous(ste_example/4).
"""


def write_prolog(name, examples_name, entries, errata):
    alt_re = re.compile(r"^(.+?)\s*\((" + POS + r")\)$")
    lines, examples, counts = [], [], defaultdict(int)

    def emit(fact):
        lines.append(fact)
        counts[fact[:fact.index("(")]] += 1

    # The standard's own example sentences: 50% of the volume, and the engine
    # never reads them. They go to their own file, which the test suite loads
    # for the false-positive guard and the binary does not embed.
    def emit_example(fact):
        examples.append(fact)
        counts["ste_example"] += 1

    status_of = defaultdict(set)
    for e in entries:
        status_of[(key_of(e["word"]), pos_of(e["pos"]))].add(e["approved"])

    for e in entries:
        key, p = key_of(e["word"]), pos_of(e["pos"])
        k = atom(key)
        status = "approved" if e["approved"] else "not_approved"
        emit(f"ste_word({k}, {p}, {status}, {e['page']}).")

        bare, qual = usage_of(e["word"])
        spelling = spelling_of(qual)
        extra_forms = [spelling.lower()] if spelling else []

        if not qual or spelling:           # a construction has no forms of its own
            toks = key.split()
            if len(toks) > 1:
                emit(f"ste_tokens([{', '.join(atom(t) for t in toks)}], {k}, {p}).")
            seen = set()
            for form in [key] + [f.lower() for f in e["forms"]] + extra_forms:
                form = cl(form)
                if form and form not in seen:
                    seen.add(form)
                    emit(f"ste_form({atom(form)}, {k}, {p}).")

        for r in e["rows"]:
            if r["alt"]:
                if e["approved"]:
                    pass          # the approved meaning: ASD's prose, read by nothing
                else:
                    m = alt_re.match(cl(r["alt"]))
                    if m:
                        emit(f"ste_alternative({k}, {p}, "
                             f"{atom(m.group(1).lower())}, {pos_of(m.group(2))}).")
                    emit(f"ste_alternative_text({k}, {p}, {atom(r['alt'])}).")
            if r["note"]:
                emit(f"ste_note({k}, {p}, {atom(r['note'])}).")
            for kind in ("ste", "non_ste"):
                if r[kind]:
                    emit_example(f"ste_example({k}, {p}, {kind}, {atom(r[kind])}).")

    # The standard separates some senses by the case of the printed headword
    # alone: "GET (v)" is approved, "get (v)" is not. Such a word cannot be
    # decided from its part of speech, so say so instead of guessing.
    for (key, p), statuses in sorted(status_of.items()):
        if len(statuses) > 1:
            emit(f"ste_ambiguous({atom(key)}, {p}).")

    for bad, good in errata:
        m = re.match(r"^(.+?)\s*\((" + POS + r")\)$", cl(bad))
        w, p = (m.group(1), pos_of(m.group(2))) if m else (cl(bad), "none")
        emit(f"ste_recurring_error({atom(w.lower())}, {p}, {atom(good)}).")

    header = f"""% ASD-STE100 Simplified Technical English, {ISSUE}, {ISSUE_DATE}
% Part 2 (Dictionary) as Prolog facts. Generated by scripts/extract_dictionary.py
% from ASD-STE100_ISSUE9.pdf -- do not edit by hand.
%
% Words and parts of speech are lowercase atoms. A multi-word entry keeps its
% spaces ('make sure'), so match token sequences through ste_tokens/3.
%
% Two traps the schema is shaped around, both real in the printed standard:
%
%   * A parenthetical in a headword marks a construction, not a spelling.
%     'PREVENT (v)' is approved while 'prevent (from) (v)' is not, so the
%     parenthetical stays in the key. Stripping it would merge an approved word
%     with a forbidden construction into contradictory facts.
%   * Some senses are separated by the CASE of the printed headword alone:
%     'GET (v)' is approved, 'get (v)' is not, same part of speech. Such a
%     word is listed in ste_ambiguous/2 and cannot be decided mechanically --
%     that is rule 1.3 (approved meanings), which no lexicon lookup can settle.
%     Treat those words as needing judgement, never as a hard failure.
%
% Plain ISO facts: no module declaration, no implementation-specific syntax.
% The discontiguous/1 directive is written in functional form, not as a prefix
% operator: SWI declares `discontiguous` as an operator and Scryer does not,
% so ":- discontiguous foo/1." is a syntax error there.
%
% Only what the checker reads is here. The standard's own prose -- its
% definitions and its example sentences -- was half the volume and no rule ever
% looked at it, so the definitions are dropped and the examples live in
% ste_examples.pl, which the test suite loads and the binary does not embed.
%
%   ste_word(Word, POS, Status, Page)         Status: approved | not_approved
%   ste_ambiguous(Word, POS)                  same Word+POS, conflicting status
%   ste_tokens(Tokens, Word, POS)             multi-word entries, for matching
%   ste_form(Form, Word, POS)                 permitted forms (rules 1.4, 3.1);
%                                             keyed on Form, includes Word
%   ste_alternative(Word, POS, Alt, AltPOS)   structured replacement
%   ste_alternative_text(Word, POS, Text)     as printed, incl. plain guidance
%   ste_note(Word, POS, Note)                 the standard's editorial note
%   ste_recurring_error(Word, POS, Better)    Part 2 intro, frequent mistakes
%
% Copyright: ASD-STE100 is a copyright and an EU trademark of ASD, Brussels.
% See ../dictionary/README.md before redistributing any of this.

:- discontiguous(ste_word/4).
:- discontiguous(ste_ambiguous/2).
:- discontiguous(ste_tokens/3).
:- discontiguous(ste_form/3).
:- discontiguous(ste_alternative/4).
:- discontiguous(ste_alternative_text/3).
:- discontiguous(ste_note/3).
:- discontiguous(ste_recurring_error/3).

ste_issue({atom(ISSUE)}, {atom(ISSUE_DATE)}).
"""
    for p in ("n", "v", "adj", "adv", "prep", "conj", "pron", "art", "prefix", "none"):
        header += f"ste_part_of_speech({p}).\n"

    with open(OUT / name, "w", encoding="utf-8") as f:
        f.write(header + "\n" + "\n".join(lines) + "\n")
    with open(OUT / examples_name, "w", encoding="utf-8") as f:
        f.write(EXAMPLES_HEADER + "\n" + "\n".join(examples) + "\n")
    print(f"  {name}: {len(lines)} facts")
    print(f"  {examples_name}: {len(examples)} facts (tests only, not embedded)")
    for pred in sorted(counts):
        print(f"      {pred}: {counts[pred]}")


def main():
    if not PDF.exists():
        sys.exit(
            f"{PDF.name} is not here.\n"
            "The standard is not carried in this repository.\n"
            "Request your own copy from the form at\n"
            "    https://www.asd-ste100.org/STE_downloads.html\n"
            f"and save it as {PDF}\n"
            "See the Getting the standard section of README.md for why."
        )
    OUT.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        bbox, flat = Path(tmp) / "dict.html", Path(tmp) / "full.txt"
        subprocess.run(["pdftotext", "-bbox-layout", "-f", str(DICT_FIRST),
                        "-l", str(DICT_LAST), str(PDF), str(bbox)], check=True)
        subprocess.run(["pdftotext", "-layout", str(PDF), str(flat)], check=True)
        entries, anomalies, orphans = parse_entries(bbox.read_text(encoding="utf-8"))
        errata = recurring_errors(flat.read_text(encoding="utf-8"))

    app = sum(1 for e in entries if e["approved"])
    print(f"parsed {len(entries)} entries: {app} approved, {len(entries) - app} not approved")
    if anomalies or orphans:
        print(f"  WARNING {len(anomalies)} unparsed headwords, {len(orphans)} orphan rows")
        for a in (anomalies + orphans)[:10]: print("   ", a)

    write_prolog("ste_dictionary.pl", "ste_examples.pl", entries, errata)


if __name__ == "__main__":
    main()
