#!/usr/bin/env bash
# 用法：
#   sudo bash rclone_onedrive_restore.sh '<TOKEN_JSON>' '<DRIVE_ID>'

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "❌ 请使用 sudo"
  exit 1
fi

if [[ $# -ne 2 ]]; then
  echo "用法：sudo bash $0 '<TOKEN_JSON>' '<DRIVE_ID>'"
  exit 1
fi

TOKEN_JSON="$1"
DRIVE_ID="$2"

REMOTE="onedrive"
CONF_DIR="/root/.config/rclone"
CONF_FILE="${CONF_DIR}/rclone.conf"

HOST="$(hostname)"
SRC="${REMOTE}:/vps_backup目录/${HOST}/"

#########################################
# 安装依赖 nginx / fail2ban / curl / rclone
#########################################
echo "==> 安装依赖..."

apt update
apt install -y nginx fail2ban curl rclone

#########################################
# 写入 rclone 配置
#########################################
mkdir -p "$CONF_DIR"

cat > "$CONF_FILE" <<EOF
[$REMOTE]
type = onedrive
token = ${TOKEN_JSON}
drive_type = personal
drive_id = ${DRIVE_ID}
EOF

chmod 600 "$CONF_FILE"
export RCLONE_CONFIG="$CONF_FILE"


#########################################
# 安装 3x-ui 面板（自动回复 n，避免交互）
#########################################
if ! command -v x-ui >/dev/null 2>&1 && [[ ! -d "/usr/local/x-ui" ]]; then
  echo "==> 未安装 3x-ui，自动安装（自动回复 n）..."
  echo "n" | bash <(curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh)
else
  echo "==> 检测到 3x-ui 已安装，跳过安装。"
fi


#########################################
# 恢复 nginx
#########################################
echo "==> 恢复 /etc/nginx"
rclone sync "${SRC}nginx" /etc/nginx --create-empty-src-dirs


#########################################
# 恢复 fail2ban
#########################################
echo "==> 恢复 /etc/fail2ban"
rclone sync "${SRC}fail2ban" /etc/fail2ban --create-empty-src-dirs


#########################################
# 恢复 3x-ui
#########################################
echo "==> 恢复 3x-ui 配置"

mkdir -p /etc/x-ui
mkdir -p /usr/local/x-ui/bin

rclone copy "${SRC}xui/x-ui.db" /etc/x-ui/x-ui.db
rclone copy "${SRC}xui/config.json" /usr/local/x-ui/bin/config.json


#########################################
# 恢复 /root/cert（整目录）
#########################################
echo "==> 恢复 /root/cert 整个目录"

mkdir -p /root/cert
rclone sync "${SRC}root_cert" /root/cert --create-empty-src-dirs


#########################################
# 将证书复制到 /etc/cert
#########################################
echo "==> 同步证书到 /etc/cert"

mkdir -p /etc/cert
cp -r /root/cert/* /etc/cert/ 2>/dev/null || true


#########################################
# 重启服务
#########################################
echo "==> 重启 nginx / fail2ban / x-ui"
sy
