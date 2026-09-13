#!/bin/sh
# Tests for the STE gate.
#
# The engine is tested through Prolog, without going near the Rust host: what
# a host loads is ste/load.pl and nothing else, so that is what is exercised.
# The host's own tests are `cargo test`.
#
# Four Prolog suites:
# Then scripts/check_no_standard.py, which holds ASD's own text out of the
# files git would carry. .gitignore covers what the scripts generate; it cannot
# cover a sentence quoted by hand into a document.
#
#   markdown_test.pl  the block structure, against test/blocks.md
#   tokenize_test.pl  toks/4 and sentence_in/2, independent of the lexicon
#   contract.pl       the shape of the answers and the streaming contract
#   engine_test.pl    what the engine finds, and what it must not

set -u
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root" || exit 2

fail=0

suite() {
    label=$1
    goal=$2
    file=$3
    printf -- '-- %s --\n' "$label"
    out=$(swipl -q -g "$goal" -t halt "$file" </dev/null 2>&1)
    printf '%s\n' "$out"
    if printf '%s' "$out" | grep -q '^FAIL'; then
        fail=$((fail + 1))
    fi
    # A suite that dies before printing anything is a failure, not a pass.
    if ! printf '%s' "$out" | grep -q '^ok'; then
        printf 'FAIL  %s produced no results\n' "$label"
        fail=$((fail + 1))
    fi
    printf '\n'
}

suite 'block structure'    markdown_main test/markdown_test.pl
suite 'tokenizer'          tokenize_main test/tokenize_test.pl
suite 'embedding contract' contract_main test/contract.pl
suite 'engine findings'    engine_main   test/engine_test.pl

printf -- '-- no quotation of the standard --\n'
if ! command -v python3 >/dev/null 2>&1; then
    printf 'skip  python3 is not installed\n'
else
    if python3 scripts/check_no_standard.py; then
        printf 'ok    no example sentence of the standard is quoted\n'
    else
        printf 'FAIL  ASD text is quoted in a file git would carry\n'
        fail=$((fail + 1))
    fi
fi

printf '\n'
printf -- '-- rust host --\n'
if ! command -v cargo >/dev/null 2>&1; then
    printf 'skip  cargo is not installed\n'
else
    # Not `cargo test | tail`: the pipeline's status is tail's, so a failing
    # build would come back as a pass. Capture, then print.
    out=$(cargo test --quiet 2>&1)
    status=$?
    printf '%s\n' "$out" | tail -20
    if [ "$status" -eq 0 ]; then
        printf 'ok    cargo test\n'
    else
        printf 'FAIL  cargo test (exit %s)\n' "$status"
        fail=$((fail + 1))
    fi
fi

printf '\n'
if [ "$fail" -eq 0 ]; then
    printf 'all tests passed\n'
else
    printf '%s failure(s)\n' "$fail"
fi
exit $((fail > 0))
