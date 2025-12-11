#!/usr/bin/env bash
# 一键安装 rclone + 配置 OneDrive + 设置每天定时备份
# 用法：
#   sudo bash rclone_onedrive_backup.sh '<TOKEN_JSON>' '<DRIVE_ID>' 'HH:MM'
# 例：
#   sudo bash rclone_onedrive_backup.sh '{"access_token":"xxx","expiry":"2025-01-01T00:00:00Z"}' '{"access_token":"xxx","expiry":"2025-01-01T00:00:00Z"}' '03:03'

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "❌ 请使用 root（sudo）运行本脚本"
  exit 1
fi

if [[ $# -ne 3 ]]; then
  echo "用法：sudo bash $0 '<TOKEN_JSON>' '<DRIVE_ID>' 'HH:MM'"
  exit 1
fi

TOKEN_JSON="$1"
DRIVE_ID="$2"
BACKUP_TIME="$3"

if [[ ! "$BACKUP_TIME" =~ ^([01][0-9]|2[0-3]):([0-5][0-9])$ ]]; then
  echo "❌ 时间格式错误，应为 HH:MM，例如 03:03"
  exit 1
fi

CRON_H="${BACKUP_TIME%:*}"
CRON_M="${BACKUP_TIME#*:}"

REMOTE_NAME="onedrive"
CONF_DIR="/root/.config/rclone"
CONF_FILE="${CONF_DIR}/rclone.conf"
BACKUP_SCRIPT="/usr/local/bin/vps_rclone_backup.sh"
LOG_FILE="/var/log/vps_rclone_backup.log"

mkdir -p "$CONF_DIR"

##############################
# 安装 rclone
##############################
if ! command -v rclone >/dev/null 2>&1; then
  echo "==> 安装 rclone..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y rclone
  else
    echo "❌ 当前系统没有 apt-get，请手动安装 rclone 后再运行。"
    exit 1
  fi
else
  echo "==> rclone 已安装，跳过。"
fi

##############################
# 写入 rclone 配置
##############################
echo "==> 写入 rclone 配置到 ${CONF_FILE}"

cat > "$CONF_FILE" <<EOF
[${REMOTE_NAME}]
type = onedrive
token = ${TOKEN_JSON}
drive_type = personal
drive_id = ${DRIVE_ID}
EOF

chmod 600 "$CONF_FILE"
export RCLONE_CONFIG="$CONF_FILE"

##############################
# 创建备份脚本（真正执行备份的那个）
##############################
echo "==> 创建备份脚本：${BACKUP_SCRIPT}"

cat > "$BACKUP_SCRIPT" <<"EOF"
#!/usr/bin/env bash
set -euo pipefail

REMOTE="onedrive"
HOST="$(hostname)"
REMOTE_DIR="${REMOTE}:/vps_backup目录/${HOST}/"

TS="$(date +%F_%H-%M-%S)"
TMP="/tmp/vps_backup_${TS}"
ARCHIVE="${HOST}_${TS}.tar.gz"

mkdir -p "$TMP"

# 备份内容：nginx、fail2ban、3x-ui 数据库与配置、SSL 证书
FILES=(
  "/etc/nginx"
  "/etc/fail2ban"
  "/etc/x-ui/x-ui.db"
  "/usr/local/x-ui/bin/config.json"
  "/root/cert/domain/fullchain.pem"
  "/root/cert/domain/privkey.pem"
  "/etc/cert/fullchain.pem"
  "/etc/cert/privkey.pem"
)

EXIST=()
for f in "${FILES[@]}"; do
  if [[ -e "$f" ]]; then
    EXIST+=("$f")
  else
    echo "⚠️ 路径不存在，跳过：$f"
  fi
done

if [[ ${#EXIST[@]} -eq 0 ]]; then
  echo "❌ 没有找到任何需要备份的文件/目录"
  exit 1
fi

echo "==> 打包以下内容："
printf '  - %s\n' "${EXIST[@]}"

tar -czf "${TMP}/${ARCHIVE}" "${EXIST[@]}"

echo "==> 上传到 OneDrive：${REMOTE_DIR}"
rclone copy "${TMP}/${ARCHIVE}" "$REMOTE_DIR" --create-empty-src-dirs

rm -rf "$TMP"
echo "✅ 备份完成：${ARCHIVE}"
EOF

chmod +x "$BACKUP_SCRIPT"

##############################
# 配置 cron 定时任务
##############################
echo "==> 写入每日定时任务到 /etc/crontab，每天 ${BACKUP_TIME} 执行备份"

touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

# 删除旧的备份任务
sed -i "/vps_rclone_backup.sh/d" /etc/crontab

echo "${CRON_M} ${CRON_H} * * * root ${BACKUP_SCRIPT} >> ${LOG_FILE} 2>&1" >> /etc/crontab

echo "🎉 部署完成！"
echo "手动测试一次备份："
echo "  sudo ${BACKUP_SCRIPT}"
