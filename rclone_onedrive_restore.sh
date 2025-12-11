#!/usr/bin/env bash
# 一键从 OneDrive 恢复 nginx / fail2ban / 3x-ui / SSL 证书
# 用法：
#   sudo bash rclone_onedrive_restore.sh '<TOKEN_JSON>' '<DRIVE_ID>'

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "❌ 请使用 sudo 运行本脚本"
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

echo "==> 当前主机名：$HOST"
echo "==> 远程备份目录：$SRC"

#########################################
# 安装基础软件：nginx / fail2ban / curl / rclone
#########################################
echo "==> 安装 nginx / fail2ban / curl / rclone ..."
if command -v apt-get >/dev/null 2>&1; then
  apt-get update
  apt-get install -y nginx fail2ban curl rclone
else
  echo "❌ 未找到 apt-get，目前脚本只支持 Debian/Ubuntu 系列。"
  exit 1
fi

#########################################
# 写入 rclone 配置
#########################################
echo "==> 写入 rclone 配置：$CONF_FILE"

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
# 测试 OneDrive 远程是否可用
#########################################
echo "==> 测试 OneDrive 连接..."

if ! rclone lsd "$REMOTE:" >/dev/null 2>&1; then
  echo "❌ 无法连接到 OneDrive，请检查 TOKEN_JSON / DRIVE_ID 是否正确。"
  exit 1
fi

# 确认备份目录存在
if ! rclone lsd "$SRC" >/dev/null 2>&1; then
  echo "❌ 未找到备份目录：$SRC"
  echo "  请确认备份脚本使用的是同一主机名（hostname）上传的。"
  exit 1
fi

#########################################
# 安装 3x-ui（自动回复 n，避免交互）
#########################################
if ! command -v x-ui >/dev/null 2>&1 && [[ ! -d "/usr/local/x-ui" ]]; then
  echo "==> 未检测到 3x-ui，开始安装（自动回复 n）..."
  echo "n" | bash <(curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh)
else
  echo "==> 检测到 3x-ui 已存在，跳过安装。"
fi

#########################################
# 恢复 nginx 配置
#########################################
echo "==> 恢复 /etc/nginx 配置 ..."
mkdir -p /etc/nginx
rclone sync "${SRC}nginx" /etc/nginx --create-empty-src-dirs

#########################################
# 恢复 fail2ban 配置
#########################################
echo "==> 恢复 /etc/fail2ban 配置 ..."
mkdir -p /etc/fail2ban
rclone sync "${SRC}fail2ban" /etc/fail2ban --create-empty-src-dirs

#########################################
# 恢复 3x-ui 配置（数据库 + config.json）
#########################################
echo "==> 恢复 3x-ui 配置 ..."
mkdir -p /etc/x-ui
mkdir -p /usr/local/x-ui/bin

rclone copy "${SRC}xui/x-ui.db" /etc/x-ui/x-ui.db  --create-empty-src-dirs || echo "⚠️ 没有找到 x-ui.db 备份，跳过。"
rclone copy "${SRC}xui/config.json" /usr/local/x-ui/bin/config.json --create-empty-src-dirs || echo "⚠️ 没有找到 config.json 备份，跳过。"

#########################################
# 恢复 /root/cert 整个目录
#########################################
echo "==> 恢复 /root/cert 整个目录 ..."
mkdir -p /root/cert
if rclone lsd "${SRC}root_cert" >/dev/null 2>&1; then
  rclone sync "${SRC}root_cert" /root/cert --create-empty-src-dirs
else
  echo "⚠️ 远程未找到 root_cert 目录，跳过证书恢复。"
fi

#########################################
# 同步证书到 /etc/cert
#########################################
echo "==> 同步证书到 /etc/cert ..."
mkdir -p /etc/cert
# 直接把 /root/cert 下所有内容复制到 /etc/cert
cp -r /root/cert/* /etc/cert/ 2>/dev/null || true

#########################################
# 重启服务
#########################################
echo "==> 重启 nginx / fail2ban / x-ui ..."
systemctl restart nginx || echo "⚠️ 重启 nginx 失败，请手动检查。"
systemctl restart fail2ban || echo "⚠️ 重启 fail2ban 失败，请手动检查。"
systemctl restart x-ui || echo "⚠️ 重启 x-ui 失败（服务名可能不同，请手动检查）。"

echo
echo "🎉 恢复完成！"
echo "已从 ${SRC} 恢复 nginx / fail2ban / 3x-ui / 证书。"
