
#!/usr/bin/env bash
set -Eeuo pipefail

APP="/usr/bin/bongocat-app"
DESKTOP="/usr/share/applications/com.ayangweb.bongo-cat.desktop"

HELPER="/usr/libexec/bongocat-input-helper"
POLICY="/usr/share/polkit-1/actions/com.bongocat.input-helper.policy"
RULE="/etc/polkit-1/rules.d/49-bongocat-input-helper.rules"

failed=0

pass() {
    echo "[OK] $*"
}

fail() {
    echo "[FAIL] $*"
    failed=1
}

check_file() {
    local file="$1"
    local description="$2"
    local privileged="${3:-no}"

    if [[ "$privileged" == "yes" ]]; then
        if sudo test -f "$file"; then
            pass "$description found: $file"
        else
            fail "$description missing: $file"
        fi
    else
        if [[ -f "$file" ]]; then
            pass "$description found: $file"
        else
            fail "$description missing: $file"
        fi
    fi
}

echo "=== BongoCat Linux Installation Check ==="

# 確認 sudo
if ! sudo -v; then
    fail "sudo authentication failed"
    exit 1
fi

echo
echo "[1/5] Main application"

check_file "$APP" "BongoCat application"

if [[ -f "$APP" ]]; then
    [[ -x "$APP" ]] &&
        pass "Main application is executable" ||
        fail "Main application is not executable"

    if [[ "$(stat -c '%U:%G:%a' "$APP")" == "root:root:755" ]]; then
        pass "Main application permissions: root:root 755"
    else
        fail "Main application permissions incorrect"
        stat -c 'Actual: %U:%G:%a' "$APP"
    fi
fi

echo
echo "[2/5] Desktop entry"

check_file "$DESKTOP" "Desktop entry"

if [[ -f "$DESKTOP" ]]; then
    grep -Fxq 'Exec=/usr/bin/bongocat-app' "$DESKTOP" &&
        pass "Desktop Exec path correct" ||
        fail "Desktop Exec path incorrect"

    grep -Fxq 'Type=Application' "$DESKTOP" &&
        pass "Desktop entry type correct" ||
        fail "Desktop entry type incorrect"
fi

echo
echo "[3/5] Linux Input Helper"

check_file "$HELPER" "Input Helper" yes

if sudo test -f "$HELPER"; then
    sudo stat -c 'Helper owner: %U:%G | Permission: %a' "$HELPER"

    [[ "$(sudo stat -c '%U:%G:%a' "$HELPER")" == "root:root:755" ]] &&
        pass "Helper permissions correct" ||
        fail "Helper permissions incorrect"
fi

echo
echo "[4/5] Polkit configuration"

check_file "$POLICY" "Polkit Policy" yes
check_file "$RULE" "Polkit Rule" yes

if sudo test -f "$POLICY"; then
    sudo grep -q 'action id="com.bongocat.input-helper"' "$POLICY" &&
        pass "Policy action ID correct" ||
        fail "Policy action ID missing"

    sudo grep -Fq '<annotate key="org.freedesktop.policykit.exec.path">/usr/libexec/bongocat-input-helper</annotate>' "$POLICY" &&
        pass "Policy helper path correct" ||
        fail "Policy helper path incorrect"

    sudo grep -Fq '<annotate key="org.freedesktop.policykit.exec.argv1">--input-helper</annotate>' "$POLICY" &&
        pass "Policy argument restriction correct" ||
        fail "Policy argument restriction missing"

    sudo grep -Fq '<allow_any>no</allow_any>' "$POLICY" &&
        pass "Policy denies inactive/remote authorization by default" ||
        fail "Policy allow_any setting incorrect"
fi

if sudo test -f "$RULE"; then
    sudo grep -q 'com.bongocat.input-helper' "$RULE" &&
        pass "Polkit action rule found" ||
        fail "Polkit action rule missing"

    sudo grep -q 'subject.user' "$RULE" &&
        pass "Polkit user restriction found" ||
        fail "Polkit user restriction missing"

    sudo grep -q 'subject.local' "$RULE" &&
        pass "Polkit local session restriction found" ||
        fail "Polkit local session restriction missing"

    sudo grep -q 'subject.active' "$RULE" &&
        pass "Polkit active session restriction found" ||
        fail "Polkit active session restriction missing"

    sudo grep -q 'polkit.Result.YES' "$RULE" &&
        pass "Polkit authorization rule found" ||
        fail "Polkit authorization result missing"
fi

echo
echo "[5/5] System dependencies"

if command -v pkexec >/dev/null 2>&1; then
    pass "pkexec available"
else
    fail "pkexec unavailable"
fi

if pacman -Q polkit >/dev/null 2>&1; then
    pass "polkit package installed"
else
    fail "polkit package missing"
fi

if pacman -Q libinput >/dev/null 2>&1; then
    pass "libinput package installed"
else
    fail "libinput package missing"
fi

echo
echo "========================================"

if (( failed == 0 )); then
    echo "All installation checks passed."
    exit 0
else
    echo "Some installation checks failed."
    exit 1
fi
