#!/usr/bin/env bash
#
# Tests for lsix.
#
# These tests are dependency-free: ImageMagick and a real sixel terminal are
# stubbed out, so the suite runs anywhere bash >= 4 is available.
#
#   Run:  bash tests/test-lsix.sh
#
# (If invoked under an old bash, e.g. macOS's default 3.2, the suite tries to
#  re-exec itself under a newer bash automatically.)

# --- Ensure a modern bash; lsix and these tests use bash 4+ features. --------
if [[ -z "${BASH_VERSINFO[0]:-}" || ${BASH_VERSINFO[0]} -lt 4 ]]; then
    for b in /opt/homebrew/bin/bash /usr/local/bin/bash "$(command -v bash)"; do
        if [[ -x "$b" ]]; then
            v=$("$b" -c 'echo ${BASH_VERSINFO[0]}' 2>/dev/null)
            if [[ ${v:-0} -ge 4 ]]; then exec "$b" "$0" "$@"; fi
        fi
    done
    echo "SKIP: need bash >= 4 to run these tests (found ${BASH_VERSINFO[0]:-unknown})." >&2
    exit 0
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LSIX="$HERE/../lsix"

fail=0
check() {  # check NAME EXPECTED ACTUAL
    if [[ "$2" == "$3" ]]; then
        printf 'ok   - %s\n' "$1"
    else
        fail=1
        printf 'FAIL - %s\n' "$1"
        printf '       expected: %q\n' "$2"
        printf '       actual:   %q\n' "$3"
    fi
}

# --- Stub ImageMagick so sourcing lsix passes its dependency check. -----------
# Defining magick() does two things: it satisfies lsix's "command -v magick
# montage" check, and it makes lsix alias `convert`->`magick` and
# `montage`->`magick montage`. That funnels ALL image work through this single
# function (regardless of the host's ImageMagick version), where we record the
# montage argv into ${CAP} and discard any piped sixel data.
CAP=/dev/null
magick() {
    if [[ "${1:-}" == "montage" ]]; then
        shift
        printf '%s\n' "$@" >>"$CAP"
    else
        cat >/dev/null
    fi
}

# Source lsix. main() is guarded behind a BASH_SOURCE check, so sourcing does
# NOT perform any terminal I/O or display anything.
# shellcheck source=/dev/null
source "$LSIX"

# Drop lsix's traps so cleanup()'s "exit 0" cannot mask our exit status.
trap - SIGINT SIGHUP SIGABRT EXIT

############################################################
# Group 1: processlabel() -- pure filename munging logic.
# (No terminal or ImageMagick needed; this is the core text processing.)
############################################################
check "short name unchanged"         "foo.png"    "$(processlabel 'foo.png')"
check "strip [0] frame suffix"       "bar.gif"    "$(processlabel 'bar.gif[0]')"
check "strip leading colon"          "baz.png"    "$(processlabel ':baz.png')"
check "escape percent for IM"        "50%%.png"   "$(processlabel '50%.png')"
check "escape at-sign for IM"        '\@foo.png'  "$(processlabel '@foo.png')"
check "escape backslash for IM"      'a\\b.png'   "$(processlabel 'a\b.png')"
check "control char becomes ?"       "a?b.png"    "$(processlabel "$(printf 'a\tb.png')")"

# Long filename (> 15 chars): extension is dropped, then wrapped with newlines.
check "long name: ext stripped + wrapped" \
      $'abcdefgh\nijklmnop' "$(processlabel 'abcdefghijklmnop.png')"

############################################################
# Group 2: empty-argument handling (regression test).
# Passing "" as a filename used to reach ImageMagick and hang it. lsix must
# now silently skip empty arguments and only forward the real files.
############################################################
autodetect() {   # replace terminal probing with fixed, harmless values
    numcolors=16; background=white; foreground=black; width=800
    tilewidth=120; tileheight=120; tilexspace=0; tileyspace=0; numtiles=21
}
CAP="$(mktemp)"   # magick() (defined above) appends the montage argv here

main "" "alpha.png" "" "beta.png"

got_alpha=$(grep -cxF 'file://alpha.png' "$CAP")
got_beta=$(grep -cxF  'file://beta.png'  "$CAP")
got_empty=$(grep -cxF 'file://'          "$CAP")
file_count=$(grep -c  '^file://'         "$CAP")
rm -f "$CAP"

check "real file alpha forwarded to montage"  "1" "$got_alpha"
check "real file beta forwarded to montage"   "1" "$got_beta"
check "empty filename NOT forwarded (no hang)" "0" "$got_empty"
check "exactly 2 files reach montage"          "2" "$file_count"

echo
if [[ $fail -eq 0 ]]; then
    echo "All tests passed."
else
    echo "Some tests FAILED."
fi
exit $fail
