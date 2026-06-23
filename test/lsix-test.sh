#!/usr/bin/env bash
#
# Tests for lsix.
#
# Run with:   test/lsix-test.sh        (or: bash test/lsix-test.sh)
#
# The tests source the lsix script -- which is why lsix only runs main()
# when executed directly, not when sourced -- and exercise two things:
#
#   1. processlabel(): the pure filename-to-montage-label transform.
#      These are characterization tests that lock the current output so a
#      future refactor cannot silently change how labels are rendered.
#
#   2. The empty-argument guard in main(): an empty filename ("") must be
#      skipped instead of being handed to ImageMagick, which hangs on it
#      (see the "Bugs" section of README.md).
#
# ImageMagick is NOT required: magick/montage/convert are replaced with
# stubs that merely record when they are invoked.
#
# Requires bash >= 4. (lsix itself refuses to run on the ancient bash 3
# that ships with macOS; install a newer one with `brew install bash`.)

# Re-exec under a newer bash if started with bash 3 (e.g. stock macOS).
if (( BASH_VERSINFO[0] < 4 )); then
    for newbash in /opt/homebrew/bin/bash /usr/local/bin/bash; do
        [[ -x "$newbash" ]] && exec "$newbash" "$0" "$@"
    done
    echo "SKIP: lsix tests need bash >= 4 (try: brew install bash)" >&2
    exit 0
fi

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
lsix="$here/../lsix"

if [[ ! -f "$lsix" ]]; then
    echo "FAIL: cannot find lsix at $lsix" >&2
    exit 1
fi

# --- Stub ImageMagick so the suite never needs it installed -----------------
stubdir=$(mktemp -d)
imlog="$stubdir/im.log"
trap 'rm -rf "$stubdir"' EXIT
for tool in magick montage convert; do
    cat > "$stubdir/$tool" <<EOF
#!/usr/bin/env bash
echo "\$0 \$*" >> "$imlog"
exit 0
EOF
    chmod +x "$stubdir/$tool"
done
PATH="$stubdir:$PATH"

# --- Load lsix's functions without running main() ---------------------------
# shellcheck source=/dev/null
source "$lsix"
# lsix installs an EXIT trap (cleanup) that calls `exit 0`, which would mask
# test failures; replace it so this script controls its own exit status.
trap 'rm -rf "$stubdir"' EXIT SIGINT SIGHUP SIGABRT

# --- Tiny assertion helper --------------------------------------------------
pass=0
fail=0

check_eq() { # check_eq <description> <expected> <actual>
    local desc=$1 expected=$2 actual=$3
    if [[ "$actual" == "$expected" ]]; then
        printf 'ok   - %s\n' "$desc"
        (( ++pass ))
    else
        printf 'FAIL - %s\n' "$desc"
        printf '         expected: %q\n' "$expected"
        printf '         actual:   %q\n' "$actual"
        (( ++fail ))
    fi
}

# --- processlabel(): pure label transform -----------------------------------
check_eq "short name is unchanged"             "photo.png"  "$(processlabel 'photo.png')"
check_eq "trailing [0] frame index removed"    "anim.gif"   "$(processlabel 'anim.gif[0]')"
check_eq "leading colon removed"               "weird"      "$(processlabel ':weird')"
check_eq "percent is doubled for ImageMagick"  "50%%.png"   "$(processlabel '50%.png')"
check_eq "at-sign is escaped for ImageMagick"  '\@home.png' "$(processlabel '@home.png')"
check_eq "backslash is doubled for ImageMagick" 'a\\b.png'  "$(processlabel 'a\b.png')"
check_eq "control chars become question marks" "a?b.png"    "$(processlabel "$(printf 'a\tb.png')")"
check_eq "long name: extension dropped, then wrapped" \
         "$(printf 'abcdefgh\nijklmnop')" "$(processlabel 'abcdefghijklmnop.png')"

# --- main(): empty-argument guard (the bug fix) -----------------------------
# Skip the "your terminal has no sixel support" early exit; we only care that
# an empty filename never reaches the montage pipeline.
export LSIX_FORCE_SIXEL_SUPPORT=1

: > "$imlog"
main "" </dev/null >/dev/null 2>&1
if [[ ! -s "$imlog" ]]; then
    printf 'ok   - empty filename "" is skipped (ImageMagick not invoked)\n'
    (( ++pass ))
else
    printf 'FAIL - empty filename "" reached ImageMagick:\n'
    while IFS= read -r line; do printf '         %s\n' "$line"; done < "$imlog"
    (( ++fail ))
fi

: > "$imlog"
main "regular.png" </dev/null >/dev/null 2>&1
if [[ -s "$imlog" ]]; then
    printf 'ok   - a regular filename still reaches ImageMagick\n'
    (( ++pass ))
else
    printf 'FAIL - regular filename did not reach ImageMagick (harness broken?)\n'
    (( ++fail ))
fi

# --- Summary ----------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
