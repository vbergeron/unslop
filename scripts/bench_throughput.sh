#!/bin/sh
# The throughput figures the README reports.
#
#   scripts/bench_throughput.sh
#
# Four numbers, because they answer different questions:
#
#   startup      what every invocation pays before it reads a byte: consulting
#                the engine and 8679 dictionary facts into the embedded machine
#   binary       one document through the binary, so startup included
#   swi          the same document through the same engine under SWI, which is
#                what isolates the cost of the embedded machine from the cost
#                of the algorithm
#   large        a document big enough that startup no longer dominates, which
#                is the words-a-second figure
#
# Each timing is the best of three, so a scheduler hiccup does not become a
# published number. The best case is the honest one to quote for a floor.

set -u
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root" || exit 2

binary=target/release/unslop
doc=USAGE.md
runs=3

[ -x "$binary" ] || { echo "$binary is not built; see BUILD.md" >&2; exit 2; }
command -v swipl >/dev/null 2>&1 || swi_missing=1

tmp=$(mktemp -d) || exit 2
trap 'rm -r "$tmp"' EXIT HUP INT TERM

# Milliseconds of wall clock for a command, best of $runs, output discarded.
best_ms() {
    best=""
    i=0
    while [ "$i" -lt "$runs" ]; do
        start=$(date +%s%N)
        "$@" >/dev/null 2>&1
        end=$(date +%s%N)
        ms=$(( (end - start) / 1000000 ))
        if [ -z "$best" ] || [ "$ms" -lt "$best" ]; then best=$ms; fi
        i=$((i + 1))
    done
    printf '%s' "$best"
}

: > "$tmp/empty.md"

# Large enough that the fixed cost is a few percent rather than half the run.
copies=40
i=0
while [ "$i" -lt "$copies" ]; do
    cat USAGE.md BUILD.md
    echo
    i=$((i + 1))
done > "$tmp/large.md"
words=$(wc -w < "$tmp/large.md" | tr -d ' ')

startup=$(best_ms "$binary" --quiet "$tmp/empty.md")
one=$(best_ms "$binary" --quiet --warnings "$doc")
large=$(best_ms "$binary" --quiet --warnings "$tmp/large.md")

printf 'best of %s runs\n\n' "$runs"
printf '  startup, an empty file        %6s ms   paid on every invocation\n' "$startup"
printf '  %-26s   %6s ms   of which %s ms is startup\n' "$doc, through the binary" "$one" "$startup"

if [ "${swi_missing:-0}" = 1 ]; then
    printf '  %-26s   %6s      swipl is not installed\n' "$doc, under SWI" "-"
else
    cat > "$tmp/swi_time.pl" <<'EOF'
:- ensure_loaded('ste/load.pl').
run :-
    read_file_codes('USAGE.md', Cs),
    best(3, Cs, Best),
    format("~w~n", [Best]).
% Best of three inside one process, so the figure excludes loading the engine:
% the comparison is against the binary's engine time, not its startup.
best(N, Cs, Best) :- best_(N, Cs, none, Best).
best_(0, _, B, B) :- !.
best_(N, Cs, B0, B) :-
    statistics(walltime, [T0|_]),
    findall(1, check(Cs, _), _),
    statistics(walltime, [T1|_]),
    DT is T1 - T0,
    ( B0 == none -> B1 = DT ; DT < B0 -> B1 = DT ; B1 = B0 ),
    N1 is N - 1,
    best_(N1, Cs, B1, B).
EOF
    swi=$(swipl -q -g run -t halt "$tmp/swi_time.pl" 2>/dev/null | tail -1)
    engine=$((one - startup))
    printf '  %-26s   %6s ms   against %s ms of engine in the binary\n' \
        "$doc, under SWI" "$swi" "$engine"
fi

rate=$(( words * 1000 / large ))
printf '  %-26s   %6s ms   %s words, about %s words a second\n' \
    "$words words of prose" "$large" "$words" "$rate"
