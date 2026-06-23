#!/usr/bin/env bash
#
# Unit tests for lsix.
#
# These tests source the lsix script and exercise individual functions
# WITHOUT requiring ImageMagick or a SIXEL-capable terminal: the
# magick/montage/convert commands are stubbed so the tests run anywhere.
#
# Run:  bash tests/run_tests.sh        (a bash >= 4 is located automatically)

# --- Ensure we run under bash >= 4 -----------------------------------------
# lsix (and these tests) use bash 4+ features. macOS still ships bash 3.2,
# so re-exec under a newer bash if one can be found.
if [[ -z "${BASH_VERSINFO[0]:-}" || ${BASH_VERSINFO[0]} -lt 4 ]]; then
    for newbash in bash /opt/homebrew/bin/bash /usr/local/bin/bash /opt/local/bin/bash; do
        v=$("$newbash" -c 'echo ${BASH_VERSINFO[0]}' 2>/dev/null) || continue
        if [[ -n "$v" && "$v" -ge 4 ]]; then
            exec "$newbash" "$0" "$@"
        fi
    done
    echo "ERROR: bash >= 4 is required to run these tests (found ${BASH_VERSION:-unknown})." >&2
    echo "       On macOS install one with: brew install bash" >&2
    exit 2
fi

# --- Locate the lsix script relative to this test file ----------------------
TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LSIX="$TEST_DIR/../lsix"
if [[ ! -f "$LSIX" ]]; then
    echo "ERROR: cannot find lsix at $LSIX" >&2
    exit 2
fi

# --- Tiny assertion helper --------------------------------------------------
tests_run=0
tests_failed=0

assert_eq() {  # assert_eq <description> <expected> <actual>
    local desc=$1 expected=$2 actual=$3
    tests_run=$((tests_run + 1))
    if [[ "$expected" == "$actual" ]]; then
        printf 'ok   - %s\n' "$desc"
    else
        tests_failed=$((tests_failed + 1))
        printf 'FAIL - %s\n' "$desc"
        printf '       expected: %q\n' "$expected"
        printf '       actual:   %q\n' "$actual"
    fi
}

# --- Stub ImageMagick BEFORE sourcing lsix ---------------------------------
# lsix exits at load time if it can't find magick/montage, and (when magick
# exists) routes convert/montage through magick via aliases. Every invocation
# is logged to a file so the parent shell can count calls even though main()
# is exercised inside a subshell.
MAGICK_CALL_LOG=$(mktemp)
magick()  { printf 'call\n' >> "$MAGICK_CALL_LOG"; }
montage() { printf 'call\n' >> "$MAGICK_CALL_LOG"; }
convert() { printf 'call\n' >> "$MAGICK_CALL_LOG"; }

# --- Source the script under test (its guarded main() does not run) ---------
# shellcheck disable=SC1090
source "$LSIX"

# lsix installs a cleanup trap at load time; remove it so it doesn't fire on
# this test process's EXIT (it emits terminal escapes and forces `exit 0`,
# which would otherwise mask test failures).
trap - SIGINT SIGHUP SIGABRT EXIT

# ---------------------------------------------------------------------------
# processlabel(): pure label-sanitizing helper. Lock in documented behavior.
# ---------------------------------------------------------------------------
assert_eq "processlabel: plain short name is unchanged" \
    "foo.png" "$(processlabel "foo.png")"

assert_eq "processlabel: strips leading ':' and trailing '[0]'" \
    "foo.gif" "$(processlabel ":foo.gif[0]")"

assert_eq "processlabel: escapes % and @ for ImageMagick" \
    'a\@b%%c' "$(processlabel "a@b%c")"

assert_eq "processlabel: long name drops extension and wraps with a newline" \
    $'abcdefgh\nijklmnop' "$(processlabel "abcdefghijklmnop.jpg")"

# ---------------------------------------------------------------------------
# main(): empty-string arguments must be skipped (they hang ImageMagick),
# while ordinary filenames must still be processed.
# ---------------------------------------------------------------------------
# Replace the terminal-querying autodetect with a no-op that sets the few
# globals main() needs to assemble a montage command. Stub realpath too so the
# directory-recursion path stays quiet.
autodetect() { numtiles=6; tilexspace=3; tileyspace=1; }
realpath()   { printf '%s\n' "$1"; }

count_calls() { local n; n=$(wc -l < "$MAGICK_CALL_LOG"); printf '%s' "${n//[[:space:]]/}"; }

: > "$MAGICK_CALL_LOG"
( main "" )                      # subshell isolates positional/array state
assert_eq "main: a lone empty-string arg invokes no ImageMagick command" \
    "0" "$(count_calls)"

: > "$MAGICK_CALL_LOG"
( main "somefile.png" )
ran=no; [[ "$(count_calls)" -gt 0 ]] && ran=yes
assert_eq "main: an ordinary filename still invokes ImageMagick" \
    "yes" "$ran"

: > "$MAGICK_CALL_LOG"
( main "" "somefile.png" "" )    # mixed: only the real file should be processed
ran=no; [[ "$(count_calls)" -gt 0 ]] && ran=yes
assert_eq "main: a mix of empty and real args still processes the real one" \
    "yes" "$ran"

# --- Summary ----------------------------------------------------------------
rm -f "$MAGICK_CALL_LOG"
printf '\n%d test(s), %d failure(s)\n' "$tests_run" "$tests_failed"
[[ "$tests_failed" -eq 0 ]]
