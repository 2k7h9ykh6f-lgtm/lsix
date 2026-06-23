#!/usr/bin/env bash
# Regression test for lsix: an empty-string filename argument must be ignored
# rather than handed to ImageMagick, which hangs on a bare "file://".
# (See the "Bugs" section of README.md.)
#
# ImageMagick is MOCKED here, so the only requirement is bash >= 4 -- the same
# bash that lsix itself requires. ImageMagick does NOT need to be installed.
#
# Usage:  bash tests/empty-arg.sh
# Exit:   0 on pass, non-zero on failure.

set -u

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
lsix="$here/../lsix"

if [[ ! -x "$lsix" ]]; then
    echo "FAIL: cannot find executable lsix at $lsix" >&2
    exit 1
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/lsix-test.XXXXXX")
trap 'rm -rf "$work"' EXIT

bin="$work/bin"
mkdir -p "$bin"
export LSIX_TEST_LOG="$work/montage.log"

# Mock the ImageMagick entry points lsix uses. lsix aliases convert/montage to
# `magick` when it is present, so `magick` does the real logging; `montage` and
# `convert` exist only to satisfy lsix's `command -v magick montage` check.
cat > "$bin/magick" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$LSIX_TEST_LOG"
exit 0
MOCK
cp "$bin/magick" "$bin/montage"
cp "$bin/magick" "$bin/convert"
chmod +x "$bin/magick" "$bin/montage" "$bin/convert"

# A real (non-empty) filename, to prove normal arguments still pass through.
real="$work/real.png"
: > "$real"

# Run lsix with an empty-string argument followed by a real filename.
# LSIX_FORCE_SIXEL_SUPPORT lets autodetect proceed without a sixel terminal.
PATH="$bin:$PATH" LSIX_FORCE_SIXEL_SUPPORT=1 \
    bash "$lsix" "" "$real" </dev/null >/dev/null 2>"$work/stderr" || true

fail() {
    echo "FAIL: $1" >&2
    echo "--- montage.log ---" >&2
    cat "$LSIX_TEST_LOG" >&2 2>/dev/null || echo "(no log produced)" >&2
    exit 1
}

# The real filename must reach montage...
grep -q "file://$real" "$LSIX_TEST_LOG" 2>/dev/null \
    || fail "real filename was not passed to montage"

# ...but a bare "file://" (from the empty argument) must NOT.
if grep -Eq '(^|[[:space:]])file://([[:space:]]|$)' "$LSIX_TEST_LOG" 2>/dev/null; then
    fail "empty filename leaked through as a bare file:// argument"
fi

echo "PASS: empty-string filename is ignored; real filename passes through"
exit 0
