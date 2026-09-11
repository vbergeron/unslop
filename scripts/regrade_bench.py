#!/usr/bin/env python3
"""Re-grade another project's published eval outputs with this gate.

The In an agent loop section of ../README.md compares two graders over the same
generations: the regex counter of the `simple-english` skill, and this gate. It
is a claim about somebody else's published numbers, so the way it was computed
has to be inspectable. This script is that.

    python3 scripts/regrade_bench.py --raw /path/to/SimpleEnglish/evals/results/raw

Nothing from the other repository is copied into this one. The script reads its
raw output files where they already sit, on your machine.

Each raw file carries the generated `text`, the `condition` (baseline, skill or
judge), the `scenario`, the block `type`, and the `lint` field holding that
project's own counts. Judge files carry no text and are skipped.

Aggregation follows that project's own run_bench.py exactly, so that the two
columns of the table differ in the grader and in nothing else:

    a rate for each text  ->  the mean of those for each model
                          ->  the mean of the per-model reductions

The rate denominator is its `lint.words`, again its own, so a different way of
counting words cannot show up as a difference between graders. The pooled
figures divide summed violations by summed words instead, and are printed
because averaging ratios and pooling counts do not agree.
"""

import argparse
import collections
import glob
import json
import os
import subprocess
import sys
import tempfile


def grade(binary, text, kind):
    """Errors and warnings this gate reports on one generated text."""
    # The block kind decides which rules apply and which sentence limit holds,
    # and the other project records it per scenario, so it is passed through
    # rather than guessed from the markdown.
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as f:
        f.write(f"<!-- ste: {kind} -->\n\n{text}\n")
        path = f.name
    try:
        run = subprocess.run(
            [binary, "--format", "json", "--warnings", path],
            capture_output=True, text=True)
        # Exit 1 is errors found, which is the normal case here. Exit 2 is the
        # run failing, and must not be read as a clean text.
        if run.returncode not in (0, 1):
            raise SystemExit(f"unslop failed on {path}: {run.stderr.strip()}")
        out = run.stdout.strip()
        diags = json.loads(out) if out.startswith("[") else []
    finally:
        os.unlink(path)
    return (sum(1 for d in diags if d["severity"] == "error"),
            sum(1 for d in diags if d["severity"] == "warning"))


def collect(raw_dir, binary):
    rows = []
    files = sorted(glob.glob(os.path.join(raw_dir, "*.json")))
    if not files:
        raise SystemExit(f"no raw eval files under {raw_dir}")
    for i, path in enumerate(files, 1):
        d = json.load(open(path))
        if "text" not in d or "lint" not in d:
            continue                      # a judge pass, which grades no text
        errors, warnings = grade(binary, d["text"], d.get("type", "descriptive"))
        words = d["lint"]["words"]
        rows.append(dict(
            model=d["model"], cond=d["condition"], scenario=d["scenario"],
            words=words, errors=errors, warnings=warnings,
            theirs_total=d["lint"]["violations_total"],
            theirs_per100=d["lint"]["violations_per_100w"],
            ours_per100=100 * errors / max(1, words)))
        print(f"\r  graded {i}/{len(files)}", end="", file=sys.stderr)
    print(file=sys.stderr)
    return rows


def mean(values):
    values = list(values)
    return sum(values) / len(values)


def report(rows):
    by = collections.defaultdict(lambda: collections.defaultdict(list))
    for r in rows:
        by[r["model"]][r["cond"]].append(r)

    models = [m for m in by if "baseline" in by[m] and "skill" in by[m]]
    models.sort(key=lambda m: -mean(r["theirs_per100"] for r in by[m]["baseline"]))

    print(f"{'model':28} {'their counter':>26} {'this gate':>26}")
    print(f"{'':28} {'base':>7} {'skill':>7} {'cut':>10} {'base':>7} {'skill':>7} {'cut':>10}")
    theirs_cuts, ours_cuts = [], []
    for m in models:
        base, skill = by[m]["baseline"], by[m]["skill"]
        tb = mean(r["theirs_per100"] for r in base)
        ts = mean(r["theirs_per100"] for r in skill)
        ob = mean(r["ours_per100"] for r in base)
        os_ = mean(r["ours_per100"] for r in skill)
        tc = 100 * (tb - ts) / tb if tb else 0.0
        oc = 100 * (ob - os_) / ob if ob else 0.0
        theirs_cuts.append(tc)
        ours_cuts.append(oc)
        print(f"{m:28} {tb:7.2f} {ts:7.2f} {tc:9.1f}% {ob:7.2f} {os_:7.2f} {oc:9.1f}%")

    print()
    print("Its own aggregation, the mean of the per-model reductions:")
    print(f"  its counter   {mean(theirs_cuts):.1f}%   <- compare against its published figure")
    print(f"  this gate     {mean(ours_cuts):.1f}%")

    print()
    print("Word-weighted per model, which a short text cannot swing:")
    wcuts = []
    for m in models:
        base, skill = by[m]["baseline"], by[m]["skill"]
        rb = 100 * sum(r["errors"] for r in base) / sum(r["words"] for r in base)
        rs = 100 * sum(r["errors"] for r in skill) / sum(r["words"] for r in skill)
        wc = 100 * (rb - rs) / rb if rb else 0.0
        wcuts.append(wc)
        print(f"  {m:28} {rb:5.2f} -> {rs:5.2f}   {wc:6.1f}%")
    print(f"  {'mean':28} {'':5}    {'':5}   {mean(wcuts):6.1f}%")
    tiny = [r for r in rows if r["words"] < 20]
    if tiny:
        print(f"\n  {len(tiny)} of {len(rows)} texts are under 20 words. Averaging a rate for")
        print("  each text gives those the same weight as a long one, so one of them")
        print("  carrying a single error moves a model's figure by tens of points. The")
        print("  word-weighted column above and the pooled figures below do not have")
        print("  that property; the per-text mean is kept only to reproduce the")
        print("  published number.")

    print()
    print("Pooled instead, summed violations over summed words:")
    for label, key in (("its counter", "theirs_total"), ("this gate", "errors")):
        wb = sum(r["words"] for r in rows if r["cond"] == "baseline")
        ws = sum(r["words"] for r in rows if r["cond"] == "skill")
        vb = sum(r[key] for r in rows if r["cond"] == "baseline")
        vs = sum(r[key] for r in rows if r["cond"] == "skill")
        rb, rs = 100 * vb / wb, 100 * vs / ws
        print(f"  {label:13} {rb:.2f} -> {rs:.2f} per 100 words   {100*(rs-rb)/rb:+.1f}%")

    pairs = collections.defaultdict(dict)
    for r in rows:
        pairs[(r["model"], r["scenario"])][r["cond"]] = r
    both = [p for p in pairs.values() if len(p) == 2]
    better = sum(1 for p in both if p["skill"]["ours_per100"] < p["baseline"]["ours_per100"])
    equal = sum(1 for p in both if p["skill"]["ours_per100"] == p["baseline"]["ours_per100"])
    print()
    print(f"Paired by model and scenario, on this gate: {len(both)} pairs, "
          f"better {better}, equal {equal}, worse {len(both) - better - equal}")

    words = sum(r["words"] for r in rows)
    print(f"\n{len(rows)} texts, {len(models)} models, {words} words graded")


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--raw", metavar="DIR",
                   help="the evals/results/raw directory of the other project")
    p.add_argument("--binary", default="target/release/unslop",
                   help="the unslop binary to grade with")
    p.add_argument("--json", metavar="FILE",
                   help="also write the per-text grades here")
    p.add_argument("--from-json", metavar="FILE",
                   help="report from grades saved earlier, without grading again")
    args = p.parse_args()

    if args.from_json:
        report(json.load(open(args.from_json)))
        return
    if not args.raw:
        raise SystemExit("give --raw DIR, or --from-json FILE")
    if not os.access(args.binary, os.X_OK):
        raise SystemExit(f"{args.binary} is not executable; see BUILD.md")

    rows = collect(args.raw, args.binary)
    if args.json:
        json.dump(rows, open(args.json, "w"), indent=1)
    report(rows)


if __name__ == "__main__":
    main()
