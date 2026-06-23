#!/usr/bin/env bash
# Test suite for lsix's processlabel() — the pure label-sanitizing function.
#
# processlabel() does the trickiest string work in lsix (recursive awk halving
# to wrap long names + sed escaping of % \ @ + control-char scrubbing). It had
# no test coverage, yet a regression there silently corrupts the caption shown
# under every thumbnail. These tests pin its current behavior.
#
# Run:  tests/test_processlabel.sh        (or  bash tests/test_processlabel.sh)
# Exit: 0 if all pass (or prerequisites are missing -> SKIP), 1 on any failure.

set -u

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- Prerequisites -----------------------------------------------------------
# lsix refuses to run on Apple's ancient bash 3 and exits if ImageMagick is
# absent; both checks fire at *source* time. Skip (rather than fail) when a
# prerequisite is missing so constrained machines/CI don't report false errors.
if (( BASH_VERSINFO[0] < 4 )); then
    echo "SKIP: bash ${BASH_VERSINFO[0]}.x is too old to source lsix (needs >= 4)." >&2
    exit 0
fi
if ! command -v montage >/dev/null 2>&1 && ! command -v magick >/dev/null 2>&1; then
    echo "SKIP: ImageMagick (montage/magick) not installed; lsix won't source." >&2
    exit 0
fi

# Source lsix to import its functions, then drop the trap it installs: its
# cleanup() calls 'exit 0', which would otherwise mask this script's exit code.
# shellcheck source=/dev/null
source "$repo_root/lsix"
trap - SIGINT SIGHUP SIGABRT EXIT

# --- Assertions --------------------------------------------------------------
pass=0
fail=0

check() {
    local name="$1" input="$2" expected="$3" got
    got="$(processlabel "$input")"
    if [[ "$got" == "$expected" ]]; then
        printf 'ok   - %s\n' "$name"
        pass=$((pass + 1))
    else
        printf 'FAIL - %s\n      input:    %q\n      expected: %q\n      got:      %q\n' \
            "$name" "$input" "$expected" "$got"
        fail=$((fail + 1))
    fi
}

check "plain short name is unchanged"         'cat.png'      'cat.png'
check "leading colon is stripped"             ':cat.png'     'cat.png'
check "trailing [0] frame suffix is stripped" 'cat.png[0]'   'cat.png'
check "percent is doubled for ImageMagick"    '50%off.png'   '50%%off.png'
check "backslash is doubled"                  'a\b'          'a\\b'
check "at-sign is escaped"                    'me@host.png'  'me\@host.png'
check "control chars become question marks"   $'a\tb'        'a?b'
check "long name: extension dropped, then split" \
      'abcdefghijklmnopqrst.jpg'  $'abcdefghij\nklmnopqrst'

# --- Summary -----------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
