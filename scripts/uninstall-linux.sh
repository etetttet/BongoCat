
#!/usr/bin/env bash
set -Eeuo pipefail

APP_PATH="/usr/bin/bongocat-app"
DESKTOP_PATH="/usr/share/applications/com.ayangweb.bongo-cat.desktop"
HELPER_PATH="/usr/libexec/bongocat-input-helper"

POLICY_PATH="/usr/share/polkit-1/actions/com.bongocat.input-helper.policy"
RULE_PATH="/etc/polkit-1/rules.d/49-bongocat-input-helper.rules"

BACKUP_ROOT="/var/backups/bongocat-input-helper"
BACKUP_DIR=""

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

if [[ "$EUID" -eq 0 ]]; then
    die "請使用一般使用者執行，不要在前面加 sudo。"
fi

command -v sudo >/dev/null 2>&1 ||
    die "找不到 sudo。"

echo "=== BongoCat Linux Uninstaller ==="
echo
echo "The following files will be removed or restored:"
printf '  %s\n' "${FILES[@]}"
echo

# 尋找最新備份
if sudo test -d "$BACKUP_ROOT"; then
    BACKUP_NAME="$(
        sudo find "$BACKUP_ROOT" \
            -mindepth 1 -maxdepth 1 -type d \
            -printf '%f\n' |
            LC_ALL=C sort |
            tail -n 1
    )"

    if [[ -n "$BACKUP_NAME" ]]; then
        CANDIDATE="$BACKUP_ROOT/$BACKUP_NAME"

        # 確認備份至少包含一個目標檔案
        for file in "${FILES[@]}"; do
            if sudo test -f "$CANDIDATE/$(basename "$file")"; then
                BACKUP_DIR="$CANDIDATE"
                break
            fi
        done
    fi
fi

if [[ -n "$BACKUP_DIR" ]]; then
    echo "Latest valid backup found:"
    echo "  $BACKUP_DIR"
    echo
    echo "Available backup files:"

    for file in "${FILES[@]}"; do
        if sudo test -f "$BACKUP_DIR/$(basename "$file")"; then
            echo "  [FOUND] $(basename "$file")"
        else
            echo "  [MISSING] $(basename "$file")"
        fi
    done
else
    echo "No valid backup found."
fi

echo
read -r -p "Continue uninstalling? [y/N] " answer

[[ "$answer" =~ ^[Yy]$ ]] || {
    echo "Cancelled."
    exit 0
}

RESTORE=0

if [[ -n "$BACKUP_DIR" ]]; then
    echo
    read -r -p "Restore files from the latest backup? [y/N] " answer

    if [[ "$answer" =~ ^[Yy]$ ]]; then
        RESTORE=1
    fi
fi

echo
sudo -v

echo "Removing / restoring files..."

for file in "${FILES[@]}"; do
    filename="$(basename "$file")"
    backup_file="$BACKUP_DIR/$filename"

    if [[ "$RESTORE" -eq 1 ]] &&
       sudo test -f "$backup_file"; then

        sudo install -d -o root -g root "$(dirname "$file")"
        sudo cp -a -- "$backup_file" "$file"

        echo "[RESTORED] $file"

    else
        if sudo test -e "$file"; then
            sudo rm -f -- "$file"
            echo "[REMOVED]  $file"
        else
            echo "[SKIPPED]  $file (not found)"
        fi
    fi
done

echo
echo "========================================"
echo "BongoCat uninstallation completed!"
echo "========================================"

if [[ "$RESTORE" -eq 1 ]]; then
    echo
    echo "Restored available files from:"
    echo "$BACKUP_DIR"
fi

echo
echo "Backups were preserved in:"
echo "$BACKUP_ROOT"

echo
echo "User configuration and personal data were not removed."
