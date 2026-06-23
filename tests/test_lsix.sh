#!/usr/bin/env bash
#
# Tests for lsix.   Run:  bash tests/test_lsix.sh
#
# lsix itself refuses to run under bash 3.x, so these tests require bash >= 4.
# Under bash 3.x they SKIP (exit 0) rather than report a false failure.
#
# No real ImageMagick or sixel terminal is needed: we put `magick`/`montage`
# stubs on PATH, source lsix to exercise its functions directly, and run lsix
# as a subprocess to confirm which filenames actually reach `montage`.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lsix="$here/../lsix"

if (( BASH_VERSINFO[0] < 4 )); then
    echo "SKIP: bash ${BASH_VERSINFO[0]}.x detected; lsix requires bash >= 4." >&2
    exit 0
fi

fails=0
check() {  # check <description> <expected> <actual>
    if [[ "$2" == "$3" ]]; then
        printf 'ok   - %s\n' "$1"
    else
        printf 'FAIL - %s\n         expected: %q\n         actual:   %q\n' "$1" "$2" "$3"
        fails=$((fails + 1))
    fi
}
ok()       { printf 'ok   - %s\n' "$1"; }
notok()    { printf 'FAIL - %s\n' "$1"; fails=$((fails + 1)); }

# --- Stub ImageMagick (IM7 single-entrypoint style) -----------------------
stub="$(mktemp -d)"
cleanup() { rm -rf "$stub"; }
trap cleanup EXIT

montage_log="$stub/montage.args"
: > "$montage_log"

cat > "$stub/magick" <<EOF
#!/usr/bin/env bash
# Record the arguments of 'magick montage ...'; swallow the sixel pipe stage.
if [[ "\$1" == montage ]]; then
    shift
    printf '%s\n' "\$@" >> "$montage_log"
    printf 'FAKEGIF'          # stand-in for the gif stream piped onward
else
    cat >/dev/null 2>&1       # the '... | convert - sixel:-' stage
fi
exit 0
EOF
# lsix's dependency check is `command -v magick montage`; at runtime it aliases
# montage -> `magick montage`, so this copy only needs to exist on PATH.
cp "$stub/magick" "$stub/montage"
chmod +x "$stub/magick" "$stub/montage"
export PATH="$stub:$PATH"

# --- Unit tests: processlabel (regression safety for existing behaviour) ---
# Source lsix without running main, then drop its terminal-cleanup trap.
# shellcheck source=/dev/null
source "$lsix"
trap - SIGINT SIGHUP SIGABRT EXIT
trap cleanup EXIT

check "strips trailing [0]"       "foo.png"  "$(processlabel 'foo.png[0]')"
check "strips leading colon"      "foo.png"  "$(processlabel ':foo.png')"
check "escapes @ for ImageMagick" '\@a.png'  "$(processlabel '@a.png')"
check "control chars become ?"    "a?b.png"  "$(processlabel "$(printf 'a\tb.png')")"

# --- Integration test: the empty-string fix -------------------------------
# An empty filename used to be forwarded to montage and hang ImageMagick
# (see README "Bugs"). It must now be dropped before montage is invoked.
valid="$stub/valid.png"; : > "$valid"
: > "$montage_log"
LSIX_FORCE_SIXEL_SUPPORT=1 "$lsix" "" "$valid" </dev/null >/dev/null 2>&1

if grep -Fxq "file://$valid" "$montage_log"; then
    ok "valid filename is passed to montage"
else
    notok "valid filename is passed to montage"
fi
if grep -Fxq "file://" "$montage_log"; then
    notok "empty filename must NOT be passed to montage"
else
    ok "empty filename is skipped (no bare file://)"
fi

echo
if (( fails )); then
    echo "$fails test(s) FAILED"
    exit 1
fi
echo "All tests passed."
exit 0
