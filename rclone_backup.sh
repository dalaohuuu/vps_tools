#!/bin/bash
set -e

# Telegram bot 配置（保留你原来的）
TG_BOT_TOKEN="7882038759:AAEI39f0_GstuET8AZVa4jW-ZjiB66r8bAw"
TG_CHAT_ID="6591145769"
notify() {
    local MESSAGE="$1"
    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TG_CHAT_ID}" \
        -d text="$(hostname) - $MESSAGE" >/dev/null
}

REMOTE_NAME="onedrive"
HOST_ID="${HOSTNAME:-$(hostname)}"
HOST_ID_CLEAN=$(echo "$HOST_ID" | tr ' /' '__')

backup_3xui() {
    # ✅ 新目录：onedrive/vpsbackup/3xui/主机名字/
    local REMOTE_DIR="${REMOTE_NAME}:vpsbackup/3xui/${HOST_ID_CLEAN}"
    local TMP_DIR="/tmp/3xui_backup_${HOST_ID_CLEAN}"

    local DB_FILE="/etc/x-ui/x-ui.db"
    local CONF_FILE="/usr/local/x-ui/bin/config.json"
    local CERT_DIR="/root/cert"

    rm -rf "$TMP_DIR"
    mkdir -p "$TMP_DIR/cert"

    cp "$DB_FILE" "$TMP_DIR"/
    cp "$CONF_FILE" "$TMP_DIR"/
    if [ -d "$CERT_DIR" ]; then
        cp -a "${CERT_DIR}/." "$TMP_DIR/cert/"
    fi

    rclone sync "$TMP_DIR" "$REMOTE_DIR" --create-empty-src-dirs
    rm -rf "$TMP_DIR"

    notify "✅ OneDrive 备份完成：vpsbackup/3xui/${HOST_ID_CLEAN}/"
}

backup_compose_app() {
    # 用法：backup_compose_app <应用名> <compose目录>
    local APP_NAME="$1"
    local COMPOSE_DIR="$2"

    if [ -z "$APP_NAME" ] || [ -z "$COMPOSE_DIR" ]; then
        echo "用法：backup_compose_app <app_name> <compose_dir>"
        echo "示例：backup_compose_app sublinkpro /opt/sublinkpro"
        return 1
    fi
    if [ ! -d "$COMPOSE_DIR" ]; then
        echo "compose_dir 不存在：$COMPOSE_DIR"
        return 1
    fi

    # ✅ 新目录：onedrive/vpsbackup/docker/容器应用的名称/
    local REMOTE_DIR="${REMOTE_NAME}:vpsbackup/docker/${APP_NAME}"

    # 你的 sublinkpro 数据都在 /opt/sublinkpro/db template logs（bind mount），
    # 所以把整个 compose 目录打包上传就能完整迁移/恢复。
    local TMP_TAR="/tmp/${APP_NAME}_${HOST_ID_CLEAN}_compose_backup.tar.gz"

    tar -czf "$TMP_TAR" -C "$COMPOSE_DIR" .

    # 上传到 OneDrive
    rclone copy "$TMP_TAR" "$REMOTE_DIR" --create-empty-src-dirs

    rm -f "$TMP_TAR"
    notify "✅ Docker Compose 应用备份完成：vpsbackup/docker/${APP_NAME}/"
}

# ========= 主流程 =========
trap 'notify "⚠️ 备份失败，请检查 VPS。"' ERR

backup_3xui

# ✅ 这里增加 sublinkpro 备份（你这台机子路径就是 /opt/sublinkpro）
backup_compose_app "sublinkpro" "/opt/sublinkpro"
