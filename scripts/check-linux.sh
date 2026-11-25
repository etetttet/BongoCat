
#!/usr/bin/env bash
set -u

HELPER="/usr/libexec/bongocat-input-helper"
POLICY="/usr/share/polkit-1/actions/com.bongocat.input-helper.policy"
RULE="/etc/polkit-1/rules.d/49-bongocat-input-helper.rules"

failed=0

check_file() {
    local file="$1"

    if sudo test -f "$file"; then
        echo "[OK] Found: $file"
    else
        echo "[FAIL] Missing: $file"
        failed=1
    fi
}

echo "=== BongoCat Linux Installation Check ==="

check_file "$HELPER"
check_file "$POLICY"
check_file "$RULE"

if sudo test -f "$HELPER"; then
    sudo stat -c 'Helper owner: %U:%G | Permission: %a' "$HELPER"

    [[ "$(sudo stat -c '%U:%G:%a' "$HELPER")" == "root:root:755" ]] ||
        { echo "[FAIL] Helper permissions incorrect"; failed=1; }
fi

if sudo test -f "$POLICY"; then
    sudo grep -q 'com.bongocat.input-helper' "$POLICY" &&
        echo "[OK] Policy action found" ||
        { echo "[FAIL] Policy action missing"; failed=1; }

    sudo grep -q '/usr/libexec/bongocat-input-helper' "$POLICY" &&
        echo "[OK] Helper path found in Policy" ||
        { echo "[FAIL] Helper path incorrect"; failed=1; }

    sudo grep -q 'argv1' "$POLICY" &&
        echo "[OK] Helper argument restriction found" ||
        { echo "[FAIL] Helper argument restriction missing"; failed=1; }
fi

if sudo test -f "$RULE"; then
    sudo grep -q 'polkit.Result.YES' "$RULE" &&
        echo "[OK] Polkit authorization rule found" ||
        { echo "[FAIL] Polkit authorization rule missing"; failed=1; }
fi

if command -v pkexec >/dev/null 2>&1; then
    echo "[OK] pkexec available"
else
    echo "[FAIL] pkexec unavailable"
    failed=1
fi

if (( failed == 0 )); then
    echo
    echo "All installation checks passed."
    exit 0
else
    echo
    echo "Some installation checks failed."
    exit 1
fi

