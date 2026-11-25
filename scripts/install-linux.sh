
#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

APP_SOURCE="$ROOT_DIR/target/release/bongocat-app"
HELPER_SOURCE="$ROOT_DIR/target/release/bongocat-input-helper"
DESKTOP_SOURCE="$ROOT_DIR/resources/linux/com.ayangweb.bongo-cat.desktop"

APP_PATH="/usr/bin/bongocat-app"
DESKTOP_PATH="/usr/share/applications/com.ayangweb.bongo-cat.desktop"

POLICY_PATH="/usr/share/polkit-1/actions/com.bongocat.input-helper.policy"
RULE_PATH="/etc/polkit-1/rules.d/49-bongocat-input-helper.rules"
HELPER_PATH="/usr/libexec/bongocat-input-helper"

BACKUP_ROOT="/var/backups/bongocat-input-helper"

USER_NAME="$(id -un)"

POLICY_TMP=""
RULE_TMP=""
BACKUP_DIR=""
BACKUP_CREATED=0
INSTALL_STARTED=0

FILES=(
    "$APP_PATH"
    "$DESKTOP_PATH"
    "$HELPER_PATH"
    "$POLICY_PATH"
    "$RULE_PATH"
)

die() {
    echo "ERROR: $*" >&2
    exit 1
}

cleanup() {
    [[ -z "$POLICY_TMP" ]] || rm -f -- "$POLICY_TMP"
    [[ -z "$RULE_TMP" ]] || rm -f -- "$RULE_TMP"
}

rollback() {
    local file
    local backup_file

    echo
    echo "========================================"
    echo "Installation failed. Rolling back..."
    echo "========================================"

    for file in "${FILES[@]}"; do
        backup_file="$BACKUP_DIR/$(basename "$file")"

        if [[ "$BACKUP_CREATED" -eq 1 ]] &&
           sudo test -f "$backup_file"; then

            sudo rm -f -- "$file"
            sudo cp -a -- "$backup_file" "$file"
            echo "[RESTORED] $file"
        else
            sudo rm -f -- "$file"
            echo "[REMOVED] $file"
        fi
    done

    echo
    echo "Rollback completed."
}

on_error() {
    local status="$1"
    local line="$2"

    trap - ERR
    set +e

    echo
    echo "ERROR: Installation failed at line $line (exit code $status)."

    if [[ "$INSTALL_STARTED" -eq 1 ]]; then
        rollback
    else
        echo "Installation had not started. Existing files were not modified."
    fi

    exit "$status"
}

trap cleanup EXIT
trap 'on_error "$?" "$LINENO"' ERR

echo "=== BongoCat CachyOS Installer ==="
echo "Install user: $USER_NAME"

# 不允許以 root 執行
[[ "$EUID" -ne 0 ]] ||
    die "請使用一般使用者執行，不要在前面加 sudo。"

[[ "$USER_NAME" =~ ^[a-zA-Z0-9_.-]+$ ]] ||
    die "無法安全處理使用者名稱：$USER_NAME"

# 確認 CachyOS
[[ -f /etc/os-release ]] ||
    die "找不到 /etc/os-release。"

source /etc/os-release

[[ "${ID:-}" == "cachyos" ]] ||
    die "此安裝程式僅支援 CachyOS，目前系統 ID：${ID:-unknown}"

# 檢查必要指令
for cmd in cargo sudo pacman install mktemp flock; do
    command -v "$cmd" >/dev/null 2>&1 ||
        die "缺少必要指令：$cmd"
done

# 檢查必要套件
for package in polkit libinput; do
    pacman -Q "$package" >/dev/null 2>&1 ||
        die "尚未安裝套件：$package。請先執行 sudo pacman -S $package"
done

command -v pkexec >/dev/null 2>&1 ||
    die "找不到 pkexec，請確認 polkit 已正確安裝。"

# 檢查來源檔案
[[ -f "$DESKTOP_SOURCE" ]] ||
    die "找不到桌面啟動器：$DESKTOP_SOURCE"

[[ -f "$ROOT_DIR/scripts/check-linux.sh" ]] ||
    die "找不到 scripts/check-linux.sh"

# 安裝鎖定
if [[ -n "${XDG_RUNTIME_DIR:-}" ]] &&
   [[ -d "$XDG_RUNTIME_DIR" ]] &&
   [[ -O "$XDG_RUNTIME_DIR" ]]; then
    LOCK_FILE="$XDG_RUNTIME_DIR/bongocat-install.lock"
else
    mkdir -p "$HOME/.cache"
    LOCK_FILE="$HOME/.cache/bongocat-install.lock"
fi

exec 9>"$LOCK_FILE"

if ! flock -n 9; then
    die "另一個 BongoCat 安裝程序正在執行，請稍後再試。"
fi

echo "[OK] Installation lock acquired"

# 確認 sudo
sudo -v

# 判斷安裝模式
EXISTING_COUNT=0

for file in "${FILES[@]}"; do
    if sudo test -e "$file"; then
        ((EXISTING_COUNT += 1))
    fi
done

echo

if (( EXISTING_COUNT == 0 )); then
    INSTALL_MODE="First installation"
elif (( EXISTING_COUNT == ${#FILES[@]} )); then
    INSTALL_MODE="Update existing installation"
else
    INSTALL_MODE="Repair / incomplete installation"
fi

echo "Installation mode: $INSTALL_MODE"
echo "Existing files: $EXISTING_COUNT / ${#FILES[@]}"

cd "$ROOT_DIR"

echo
echo "[1/5] Building BongoCat main application..."

cargo build --release -p bongocat-app

[[ -x "$APP_SOURCE" ]] ||
    die "主程式不存在或不可執行：$APP_SOURCE"

echo
echo "[2/5] Building Linux Input Helper..."

cargo build --release -p bongocat-input-helper

[[ -x "$HELPER_SOURCE" ]] ||
    die "Input Helper 不存在或不可執行：$HELPER_SOURCE"

echo
echo "[3/5] Preparing Polkit configuration..."

POLICY_TMP="$(mktemp)"
RULE_TMP="$(mktemp)"

cat > "$POLICY_TMP" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE policyconfig PUBLIC
 "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd">
<policyconfig>
  <action id="com.bongocat.input-helper">
    <description>Run BongoCat input helper</description>
    <message>Authentication is required to run the BongoCat input helper</message>
    <defaults>
      <allow_any>no</allow_any>
      <allow_inactive>no</allow_inactive>
      <allow_active>auth_admin</allow_active>
    </defaults>
    <annotate key="org.freedesktop.policykit.exec.path">/usr/libexec/bongocat-input-helper</annotate>
    <annotate key="org.freedesktop.policykit.exec.argv1">--input-helper</annotate>
  </action>
</policyconfig>
XML

cat > "$RULE_TMP" <<EOF
polkit.addRule(function(action, subject) {
    if (
        action.id === "com.bongocat.input-helper" &&
        subject.user === "$USER_NAME" &&
        subject.local &&
        subject.active
    ) {
        return polkit.Result.YES;
    }
});
EOF

echo
echo "[4/5] Backing up existing installation..."

BACKUP_DIR="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)-$$"

for file in "${FILES[@]}"; do
    if sudo test -e "$file"; then
        if [[ "$BACKUP_CREATED" -eq 0 ]]; then
            sudo install -d -o root -g root -m 0700 "$BACKUP_DIR"
            BACKUP_CREATED=1
        fi

        sudo cp -a -- "$file" "$BACKUP_DIR/"
        echo "[BACKUP] $file"
    fi
done

echo
echo "[5/5] Installing BongoCat..."

INSTALL_STARTED=1

sudo install -D -o root -g root -m 0755 \
    "$APP_SOURCE" "$APP_PATH"

sudo install -D -o root -g root -m 0644 \
    "$DESKTOP_SOURCE" "$DESKTOP_PATH"

sudo install -D -o root -g root -m 0755 \
    "$HELPER_SOURCE" "$HELPER_PATH"

sudo install -D -o root -g root -m 0644 \
    "$POLICY_TMP" "$POLICY_PATH"

sudo install -D -o root -g root -m 0644 \
    "$RULE_TMP" "$RULE_PATH"

INSTALL_STARTED=0

echo
echo "========================================"
echo "BongoCat installation completed!"
echo "========================================"
echo
echo "Installation mode: $INSTALL_MODE"
echo "Main application: $APP_PATH"
echo "Desktop entry: $DESKTOP_PATH"
echo "Input Helper: $HELPER_PATH"
echo "Polkit Policy: $POLICY_PATH"
echo "Polkit Rules: $RULE_PATH"
echo "Authorized user: $USER_NAME"

if [[ "$BACKUP_CREATED" -eq 1 ]]; then
    echo
    echo "Backup directory: $BACKUP_DIR"
else
    echo
    echo "No previous installation files needed backup."
fi

echo
echo "Running installation verification..."

if bash "$ROOT_DIR/scripts/check-linux.sh"; then
    echo
    echo "========================================"
    echo "Installation and verification passed!"
    echo "========================================"
else
    echo
    echo "WARNING: Installation completed, but verification reported errors."
    echo "Please inspect the check-linux.sh output."
    exit 1
fi
