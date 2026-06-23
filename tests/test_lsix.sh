#!/usr/bin/env bash
#
# Regression tests for lsix. No external test framework required.
#
#   Run:  tests/test_lsix.sh
#     or:  bash tests/test_lsix.sh
#
# lsix requires bash >= 4; if started under an older bash (e.g. Apple's
# stock /bin/bash 3.2) we transparently re-exec under a newer one.

if [ "${BASH_VERSINFO:-0}" -lt 4 ]; then
    for cand in /opt/homebrew/bin/bash /usr/local/bin/bash; do
        # shellcheck disable=SC2016  # ${BASH_VERSINFO[0]} must expand in $cand, not here
        if [ -x "$cand" ] && [ "$("$cand" -c 'echo ${BASH_VERSINFO[0]}' 2>/dev/null)" -ge 4 ]; then
            exec "$cand" "$0" "$@"
        fi
    done
    echo "ERROR: these tests need bash >= 4 (found ${BASH_VERSION:-unknown})." >&2
    exit 2
fi

set -u

BASH_BIN="${BASH}"                                  # the bash we are running under
SELFDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SELFDIR/.." && pwd)"
LSIX="$ROOT/lsix"
[ -f "$LSIX" ] || { echo "ERROR: lsix not found at $LSIX" >&2; exit 2; }

# --------------------------------------------------------------------------
# Sandbox with a fake ImageMagick so tests are hermetic and never render.
# --------------------------------------------------------------------------
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAKEBIN="$WORK/bin"
mkdir -p "$FAKEBIN"

# Fake `magick`: when asked to montage, record every argument (one per line)
# to $MAGICK_MONTAGE_ARGS and emit a placeholder stream; otherwise (e.g.
# `magick - -colors N sixel:-`) just consume stdin and succeed.
cat > "$FAKEBIN/magick" <<'FAKE'
#!/usr/bin/env bash
if [ "${1:-}" = montage ]; then
    shift
    if [ -n "${MAGICK_MONTAGE_ARGS:-}" ]; then
        for a in "$@"; do printf '%s\n' "$a" >> "$MAGICK_MONTAGE_ARGS"; done
    fi
    printf 'FAKEGIF\n'
else
    cat >/dev/null 2>&1 || true
fi
exit 0
FAKE
chmod +x "$FAKEBIN/magick"

# `montage` only needs to exist so `command -v magick montage` succeeds; lsix
# rewrites montage -> `magick montage` via alias when magick is present.
cat > "$FAKEBIN/montage" <<'FAKE'
#!/usr/bin/env bash
exit 0
FAKE
chmod +x "$FAKEBIN/montage"

# --------------------------------------------------------------------------
# Minimal harness.
# --------------------------------------------------------------------------
pass=0
fail=0
check() { # check NAME EXPECTED ACTUAL
    if [ "$2" = "$3" ]; then
        printf 'ok   - %s\n' "$1"
        pass=$((pass + 1))
    else
        printf 'FAIL - %s\n' "$1"
        printf '        expected: %q\n' "$2"
        printf '        actual:   %q\n' "$3"
        fail=$((fail + 1))
    fi
}

# ==========================================================================
# 1. processlabel(): the label-munging pipeline (the trickiest part of lsix).
#    The BASH_SOURCE guard lets us source lsix and exercise it directly.
# ==========================================================================
pl() { # pl INPUT  ->  prints processlabel output
    # shellcheck disable=SC2016  # the -c body is evaluated by the child bash
    LSIX="$LSIX" PATH="$FAKEBIN:$PATH" "$BASH_BIN" -c '
        source "$LSIX" >/dev/null 2>&1
        cleanup() { :; }            # neutralise EXIT trap (no escape output)
        processlabel "$1"
    ' _ "$1"
}

check "processlabel keeps short names unchanged" \
      "foo.png" "$(pl 'foo.png')"
check "processlabel strips ImageMagick [0] frame suffix" \
      "nyancat.gif" "$(pl 'nyancat.gif[0]')"
check "processlabel strips leading colon (coder prefix)" \
      "foo.png" "$(pl ':foo.png')"
check "processlabel escapes @ (ImageMagick metacharacter)" \
      '\@foo.png' "$(pl '@foo.png')"
check "processlabel wraps overly long names onto two lines" \
      "$(printf 'verylong\nfilename')" "$(pl 'verylongfilename.jpeg')"

# ==========================================================================
# 2. Regression: an empty-string filename must be dropped before reaching
#    ImageMagick. Passing "" to montage hangs it (see README "Bugs").
# ==========================================================================
run_lsix() { # run_lsix ARGS... ; fills $ARGS_FILE and $ERR_FILE
    ARGS_FILE="$WORK/montage_args"; : > "$ARGS_FILE"
    ERR_FILE="$WORK/stderr";        : > "$ERR_FILE"
    MAGICK_MONTAGE_ARGS="$ARGS_FILE" LSIX_FORCE_SIXEL_SUPPORT=1 \
        PATH="$FAKEBIN:$PATH" \
        "$BASH_BIN" "$LSIX" "$@" </dev/null >/dev/null 2>"$ERR_FILE"
}

# 2a. Only an empty arg: nothing valid remains, so montage must never run.
run_lsix ""
check "empty-only invocation never calls montage" \
      "0" "$(wc -l < "$ARGS_FILE" | tr -d ' ')"
check "empty filename produces a warning on stderr" \
      "1" "$(grep -a -c 'ignoring empty filename' "$ERR_FILE")"

# 2b. Mixed: the empty arg is dropped, real names still flow through.
run_lsix "" "img1.png" "img2.png"
check "real filename img1 is passed to montage" \
      "1" "$(grep -a -cxF 'file://img1.png' "$ARGS_FILE")"
check "real filename img2 is passed to montage" \
      "1" "$(grep -a -cxF 'file://img2.png' "$ARGS_FILE")"
check "no empty/blank argument reaches montage" \
      "0" "$(grep -a -c '^$' "$ARGS_FILE")"
check "no bare 'file://' (empty path) reaches montage" \
      "0" "$(grep -a -cxF 'file://' "$ARGS_FILE")"

# ==========================================================================
# 3. Static: the script must stay syntactically valid bash.
# ==========================================================================
if "$BASH_BIN" -n "$LSIX" 2>"$WORK/synerr"; then
    check "lsix passes 'bash -n' syntax check" "ok" "ok"
else
    check "lsix passes 'bash -n' syntax check" "ok" "FAIL: $(cat "$WORK/synerr")"
fi

# --------------------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
