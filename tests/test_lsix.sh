#!/usr/bin/env bash
#
# test_lsix.sh -- focused tests for lsix's command-line argument handling.
#
# What this verifies:
#   Regression test for the documented bug "specifying the empty string ''
#   as a filename makes ImageMagick hang" (see README.md "Bugs" section).
#   lsix must drop empty-string arguments before they ever reach ImageMagick,
#   while still forwarding real filenames unchanged.
#
# How it works (no real ImageMagick or sixel terminal needed):
#   * A stub `magick` is placed first on $PATH. It records every argument it
#     receives (one per line) to $LSIX_TEST_LOG and exits successfully, so we
#     can inspect exactly which "file://..." arguments lsix forwarded.
#   * LSIX_FORCE_SIXEL_SUPPORT=1 stops lsix from bailing out on a non-sixel TTY.
#   * stdin is /dev/null so lsix's terminal-query reads return immediately.
#
# lsix requires bash >= 4, so the script under test is run with the newest
# bash we can find. If none is available the tests are skipped (not failed).

set -u

here=$(cd "$(dirname "$0")" && pwd)
lsix="$here/../lsix"

if [ ! -f "$lsix" ]; then
    echo "FAIL: cannot find lsix at $lsix" >&2
    exit 1
fi

# --- Locate a bash >= 4 to run lsix with ---------------------------------
find_modern_bash() {
    local candidate version
    for candidate in bash /opt/homebrew/bin/bash /usr/local/bin/bash \
                     /opt/homebrew/Cellar/bash/*/bin/bash; do
        command -v "$candidate" >/dev/null 2>&1 || continue
        version=$("$candidate" -c 'echo "${BASH_VERSINFO[0]}"' 2>/dev/null)
        if [ -n "$version" ] && [ "$version" -ge 4 ] 2>/dev/null; then
            command -v "$candidate"
            return 0
        fi
    done
    return 1
}

newbash=$(find_modern_bash) || {
    echo "SKIP: no bash >= 4 found; lsix cannot run on this machine." >&2
    exit 0
}
echo "Using bash: $newbash ($("$newbash" -c 'echo $BASH_VERSION'))"

# --- Sandbox -------------------------------------------------------------
workdir=$(mktemp -d "${TMPDIR:-/tmp}/lsix_test.XXXXXX") || exit 1
cleanup() { rm -rf "$workdir"; }
trap cleanup EXIT

stubdir="$workdir/bin"
mkdir -p "$stubdir"
export LSIX_TEST_LOG="$workdir/magick_args.log"

# Stub that stands in for ImageMagick's `magick` (and thus `convert`/`montage`,
# which lsix aliases to it). Logs argv, drains stdin, succeeds.
cat > "$stubdir/magick" <<'STUB'
#!/usr/bin/env bash
for a in "$@"; do printf '%s\n' "$a"; done >> "$LSIX_TEST_LOG"
cat >/dev/null 2>&1 || true
exit 0
STUB
chmod +x "$stubdir/magick"

# Fixture: a regular (non-directory) file. Contents are irrelevant because
# magick is stubbed; lsix only checks that it is not a directory.
touch "$workdir/realfile.png"

run_lsix() {
    # Run lsix in the sandbox with the stub ahead on PATH.
    : > "$LSIX_TEST_LOG"
    ( cd "$workdir" \
        && LSIX_FORCE_SIXEL_SUPPORT=1 PATH="$stubdir:$PATH" \
           "$newbash" "$lsix" "$@" ) </dev/null >/dev/null 2>&1
}

pass=0
fail=0
check() { # check <description> <0-if-ok>
    if [ "$2" -eq 0 ]; then
        echo "  ok: $1"; pass=$((pass + 1))
    else
        echo "  FAIL: $1" >&2; fail=$((fail + 1))
    fi
}

# A "bare" file:// (empty filename) is exactly the argument that makes
# ImageMagick hang; it must never be forwarded.
has_bare_fileurl() { grep -qxF 'file://' "$LSIX_TEST_LOG" 2>/dev/null; }

# --- Test 1: real file alongside an empty-string arg ---------------------
echo "Test 1: lsix realfile.png \"\"  (empty arg must be dropped)"
run_lsix "realfile.png" ""
if grep -qxF 'file://realfile.png' "$LSIX_TEST_LOG" 2>/dev/null; then
    check "real filename is forwarded to ImageMagick" 0
else
    check "real filename is forwarded to ImageMagick" 1
fi
if has_bare_fileurl; then
    check "empty-string arg is NOT forwarded (no bare file://)" 1
else
    check "empty-string arg is NOT forwarded (no bare file://)" 0
fi

# --- Test 2: only an empty-string arg ------------------------------------
# Previously this forwarded a bare file:// and hung ImageMagick. Now it must
# be a clean no-op: ImageMagick is never invoked with a bare file://.
echo "Test 2: lsix \"\"  (must be a clean no-op)"
run_lsix ""
if has_bare_fileurl; then
    check "empty-only invocation forwards nothing problematic" 1
else
    check "empty-only invocation forwards nothing problematic" 0
fi

# --- Summary -------------------------------------------------------------
echo "-----------------------------------------"
echo "Passed: $pass  Failed: $fail"
[ "$fail" -eq 0 ]
