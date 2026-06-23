#!/usr/bin/env bash
#
# Unit tests for lsix's processlabel() function.
#
# These tests are intentionally dependency-free: they extract the real
# processlabel() definition from the lsix script and exercise it directly,
# so no SIXEL terminal and no image rendering are required. Only bash and
# the standard sed/awk/tr that processlabel itself uses are needed.
#
# Run with:
#     bash tests/test_processlabel.sh
#
# Exit status is 0 if all checks pass, non-zero otherwise.

set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lsix="$here/../lsix"

pass=0
fail=0

fatal() { echo "FATAL: $*" >&2; exit 1; }

[[ -f "$lsix" ]] || fatal "cannot find lsix script at: $lsix"

# 1. The script must at least be syntactically valid bash.
if bash -n "$lsix"; then
    echo "ok   - bash -n lsix (syntax check)"
    pass=$((pass + 1))
else
    echo "FAIL - bash -n lsix (syntax check)"
    fail=$((fail + 1))
fi

# 2. Pin the robustness fix: processlabel must use printf, not the fragile
#    `echo -n "$1"`, which silently eats filenames that look like echo
#    options (e.g. -n, -e, -ne).
if grep -qF "printf '%s' \"\$1\"" "$lsix" && ! grep -qF 'echo -n "$1"' "$lsix"; then
    echo "ok   - processlabel uses printf instead of echo -n"
    pass=$((pass + 1))
else
    echo "FAIL - processlabel still relies on 'echo -n \"\$1\"'"
    fail=$((fail + 1))
fi

# Extract and load the real processlabel() so we can call it directly.
func="$(sed -n '/^processlabel() {/,/^}/p' "$lsix")"
[[ "$func" == *"processlabel()"* ]] || fatal "could not extract processlabel() from $lsix"
eval "$func" || fatal "could not load processlabel() (eval failed)"

check() {
    # check <description> <input> <expected>
    local desc="$1" input="$2" expected="$3" got
    got="$(processlabel "$input")"
    if [[ "$got" == "$expected" ]]; then
        echo "ok   - $desc"
        pass=$((pass + 1))
    else
        echo "FAIL - $desc"
        printf '         input:    %q\n' "$input"
        printf '         expected: %q\n' "$expected"
        printf '         got:      %q\n' "$got"
        fail=$((fail + 1))
    fi
}

# --- Behavior that must stay compatible -------------------------------------
check "short filename passes through unchanged"    "cat.jpg"      "cat.jpg"
check "leading colon is stripped"                  ":foo.png"     "foo.png"
check "trailing [0] frame suffix is stripped"      "file.png[0]"  "file.png"
check "percent signs are doubled for montage"      "100%done.png" "100%%done.png"
check "at sign is escaped for montage"             "@foo.png"     '\@foo.png'
check "backslash is escaped for montage"           'a\b.png'      'a\\b.png'
check "control characters become question marks"   $'a\tb.png'    "a?b.png"
check "long names are wrapped (extension dropped)" \
      "verylongfilename1234.jpg" $'verylongfi\nlename1234'

# --- The actual bug fix -----------------------------------------------------
# Filenames that look like `echo` options used to vanish entirely because
# `echo -n "$1"` treated them as flags. printf '%s' prints them verbatim.
check "filename '-n' is preserved"  "-n"  "-n"
check "filename '-e' is preserved"  "-e"  "-e"
check "filename '-ne' is preserved" "-ne" "-ne"

echo
echo "passed: $pass, failed: $fail"
[[ $fail -eq 0 ]]
