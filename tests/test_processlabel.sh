#!/usr/bin/env bash
#
# Unit tests for the processlabel() function in ../lsix.
#
# processlabel() massages a filename before it is handed to ImageMagick's
# `montage` as -label text. It is the only pure function in lsix (no terminal
# I/O, no sixel, no ImageMagick), which makes it the natural place to pin down
# behavior with regression tests.
#
# These tests do NOT modify or run lsix as a whole. They extract just the
# processlabel() definition from the script and eval it, so the function is
# exercised exactly as shipped. lsix stays byte-for-byte unchanged.
#
# Usage:   bash tests/test_processlabel.sh
# Exit:    0 if every assertion passes, 1 if any fails, 2 on setup error.

set -u

here=$(cd "$(dirname "$0")" && pwd)
lsix="$here/../lsix"

if [[ ! -f "$lsix" ]]; then
    echo "setup error: cannot find lsix at $lsix" >&2
    exit 2
fi

# Pull out the processlabel() function (from its definition line up to and
# including the first closing brace at column 0) and load it into this shell.
fn=$(awk '/^processlabel\(\)/{f=1} f{print} f&&/^}/{exit}' "$lsix")
eval "$fn"

if ! declare -f processlabel >/dev/null 2>&1; then
    echo "setup error: could not load processlabel() from lsix" >&2
    exit 2
fi

pass=0
fail=0

check() {
    # check <description> <input> <expected>
    local desc=$1 input=$2 expected=$3 actual
    actual=$(processlabel "$input")
    if [[ "$actual" == "$expected" ]]; then
        pass=$((pass + 1))
        printf 'ok   - %s\n' "$desc"
    else
        fail=$((fail + 1))
        printf 'FAIL - %s\n' "$desc"
        printf '        input:    %q\n' "$input"
        printf '        expected: %q\n' "$expected"
        printf '        actual:   %q\n' "$actual"
    fi
}

# Short names are passed through untouched (extension is kept).
check "plain short name is unchanged"             "cat.jpg"        "cat.jpg"

# ImageMagick frame/coder syntax is stripped so the label reads cleanly.
check "trailing [0] frame suffix is removed"      "frame.gif[0]"   "frame.gif"
check "leading colon is removed"                  ":photo.png"     "photo.png"
check "leading colon and [0] both removed"        ":movie.gif[0]"  "movie.gif"

# Characters that are special to ImageMagick's label parser are escaped.
check "percent sign is doubled for ImageMagick"   "50%.png"        "50%%.png"
check "at sign is backslash-escaped"              "@home.png"      "\\@home.png"
check "backslash is doubled"                      'a\b.png'        'a\\b.png'

# Control characters in a filename are replaced with question marks.
check "control characters become question marks"  $'a\tb.jpg'      "a?b.jpg"

# Long names (> 15 chars): the extension is dropped and the remaining text is
# recursively halved onto separate lines so montage does not overlap it.
check "long name: extension stripped and wrapped" "abcdefghijklmnop.jpg" $'abcdefgh\nijklmnop'

echo
echo "passed: $pass, failed: $fail"
[[ $fail -eq 0 ]]
