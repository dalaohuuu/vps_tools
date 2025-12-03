#!/bin/bash
set -e
trap 'notify "⚠️ 恢复失败，请检查 VPS。"' ERR

# Telegram bot 配置（从脚本参数传入）
TG_BOT_TOKEN="$1"
TG_CHAT_ID="$2"

if [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_ID" ]; then
    echo "用法: $0 <TG_BOT_TOKEN> <TG_CHAT_ID>"
    exit 1
fi

notify() {
    local MESSAGE="$1"
    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TG_CHAT_ID}" \
        -d text="$(hostname) - ${MESSAGE}"
}

REMOTE_NAME="onedrive"
REMOTE_BASE_DIR="xui_backup"

# 为了和备份脚本保持一致，这里同样用主机名来拼子目录
HOST_ID="$(hostname)"
HOST_ID_CLEAN=$(echo "$HOST_ID" | tr ' /' '__')
REMOTE_DIR="${REMOTE_NAME}:${REMOTE_BASE_DIR}/${HOST_ID_CLEAN}"

TMP_DIR="/tmp/xui_restore_${HOST_ID_CLEAN}"

DB_FILE="/etc/x-ui/x-ui.db"
CONF_FILE="/usr/local/x-ui/bin/config.json"
CERT_DIR="/root/cert"

# 本地当前配置做个简单备份（防止误操作）
LOCAL_BACKUP_DIR="/root/xui_local_backup_$(date +%F_%H-%M-%S)"
mkdir -p "$LOCAL_BACKUP_DIR"

if [ -f "$DB_FILE" ]; then
    mkdir -p "$LOCAL_BACKUP_DIR/etc-x-ui"
    cp "$DB_FILE" "$LOCAL_BACKUP_DIR/etc-x-ui/x-ui.db"
fi

if [ -f "$CONF_FILE" ]; then
    mkdir -p "$LOCAL_BACKUP_DIR/usr-local-x-ui-bin"
    cp "$CONF_FILE" "$LOCAL_BACKUP_DIR/usr-local-x-ui-bin/config.json"
fi

if [ -d "$CERT_DIR" ]; then
    mkdir -p "$LOCAL_BACKUP_DIR/cert"
    cp -a "${CERT_DIR}/." "$LOCAL_BACKUP_DIR/cert/"
fi

# 准备临时目录
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# 从 OneDrive 同步备份到临时目录（和备份脚本使用的目录规则一致）
rclone sync "$REMOTE_DIR" "$TMP_DIR" --create-empty-src-dirs

# 确保目标目录存在
mkdir -p "$(dirname "$DB_FILE")"
mkdir -p "$(dirname "$CONF_FILE")"
mkdir -p "$CERT_DIR"

# 恢复 x-ui.db
if [ -f "$TMP_DIR/x-ui.db" ]; then
    cp "$TMP_DIR/x-ui.db" "$DB_FILE"
else
    notify "⚠️ 恢复时未在远端备份中找到 x-ui.db 文件。"
fi

# 恢复 config.json
if [ -f "$TMP_DIR/config.json" ]; then
    cp "$TMP_DIR/config.json" "$CONF_FILE"
else
    notify "⚠️ 恢复时未在远端备份中找到 config.json 文件。"
fi

# 恢复证书目录
if [ -d "$TMP_DIR/cert" ]; then
    cp -a "$TMP_DIR/cert/." "$CERT_DIR/"
fi

# 清理临时目录
rm -rf "$TMP_DIR"

notify "✅ OneDrive 恢复完成，已从 /xui_backup/$HOST_ID/ 还原配置与证书。本地旧配置已备份到 $LOCAL_BACKUP_DIR。"