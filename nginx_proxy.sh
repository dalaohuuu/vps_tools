#!/usr/bin/env bash
set -e

############################################################
# 一键部署：acme.sh + Nginx + Cloudreve + 3x-ui 反代
#
# 用法：
#   ./deploy.sh <DOMAIN> <CF_Token>
#
# 示例：
#   ./deploy.sh cc1.5165188.xyz your_cloudflare_api_token
############################################################

# ====== 0. 参数与基础变量 ======
if [ $# -lt 2 ]; then
  echo "用法: $0 <DOMAIN> <CF_Token>"
  echo "示例: $0 cc1.5165188.xyz your_cloudflare_api_token"
  exit 1
fi

DOMAIN="$1"
CF_Token="$2"

CERT_ROOT="/root/cert"
CERT_DIR="$CERT_ROOT/$DOMAIN"
CERT_ETC_DIR="/etc/cert"
CLOUDREVE_DIR="/opt/cloudreve"
HTPASS_FILE="/etc/nginx/.htpasswd_3xui"

ADMIN_USER="myadmin"
ADMIN_PASS="$(openssl rand -base64 12)"

echo "========== 一键部署：acme.sh + Nginx + Cloudreve + 3x-ui =========="
echo "域名：       $DOMAIN"
echo "证书目录：   $CERT_DIR"
echo "Nginx 证书： $CERT_ETC_DIR"
echo "Cloudreve：  $CLOUDREVE_DIR"
echo

# ====== 1. 必须是 root ======
if [ "$(id -u)" -ne 0 ]; then
  echo "请用 root 运行：先执行 sudo -i，再运行这个脚本。"
  exit 1
fi

# ====== 2. 安装基础依赖 ======
echo "[1/7] 安装依赖 (nginx, apache2-utils, wget, curl, tar, socat, cron, openssl)..."
apt update -y
apt install -y nginx apache2-utils wget curl tar socat cron openssl

# ====== 3. 用 acme.sh 检测/申请/安装证书 ======
echo "[2/7] 检测 / 申请 SSL 证书（acme.sh）..."

# 确保 acme.sh 安装
if [ ! -d "/root/.acme.sh" ]; then
  echo "[2/7] 未检测到 acme.sh，开始安装..."
  curl https://get.acme.sh | sh
fi

ACME="/root/.acme.sh/acme.sh"
if [ ! -x "$ACME" ]; then
  echo "acme.sh 未正确安装在 $ACME"
  exit 1
fi

# Cloudflare Token 环境变量
export CF_Token="$CF_Token"

# 使用 Let's Encrypt
"$ACME" --set-default-ca --server letsencrypt

# 使用 acme.sh 自身的证书列表判断是否已有该域名记录
HAS_CERT=0
if "$ACME" --list >/tmp/acme_list.out 2>/dev/null; then
  # 跳过表头，从第二行开始取第 1 列（域名），去空格后精确匹配
  if awk -F'|' 'NR>1 {gsub(/ /,"",$1); print $1}' /tmp/acme_list.out | grep -qx "$DOMAIN"; then
    HAS_CERT=1
  fi
fi
rm -f /tmp/acme_list.out || true

if [ "$HAS_CERT" -eq 1 ]; then
  echo "[2/7] acme.sh 中已存在 $DOMAIN 的证书记录，跳过重新签发，直接安装 / 同步证书..."
else
  echo "[2/7] acme.sh 中未找到 $DOMAIN 证书记录，开始首次签发..."
  # 这里不加 --force，交由 acme.sh 自己判断是否需要签发
  "$ACME" --issue -d "$DOMAIN" --dns dns_cf
fi

mkdir -p "$CERT_DIR" "$CERT_ETC_DIR"

echo "[2/7] 安装 / 同步证书到本地目录..."
# 安装到 /root/cert/$DOMAIN
"$ACME" --install-cert -d "$DOMAIN" \
  --key-file       "$CERT_DIR/privkey.pem" \
  --fullchain-file "$CERT_DIR/fullchain.pem"

# 安装到 /etc/cert 供 Nginx 使用
"$ACME" --install-cert -d "$DOMAIN" \
  --key-file       "$CERT_ETC_DIR/privkey.pem" \
  --fullchain-file "$CERT_ETC_DIR/fullchain.pem" \
  --reloadcmd "systemctl reload nginx || true"

echo "证书已安装："
echo "  $CERT_DIR/fullchain.pem"
echo "  $CERT_DIR/privkey.pem"
echo "  $CERT_ETC_DIR/fullchain.pem"
echo "  $CERT_ETC_DIR/privkey.pem"
echo

# ====== 4. 创建 Nginx BasicAuth 文件 ======
echo "[3/7] 创建 Nginx 面板 BasicAuth 用户：$ADMIN_USER"
rm -f "$HTPASS_FILE"
echo "$ADMIN_PASS" | htpasswd -ci "$HTPASS_FILE" "$ADMIN_USER"

# ====== 5. 安装 Cloudreve ======
echo "[4/7] 安装 Cloudreve 到 $CLOUDREVE_DIR ..."
mkdir -p "$CLOUDREVE_DIR"
cd "$CLOUDREVE_DIR"

LATEST_URL=$(wget -qO- https://api.github.com/repos/cloudreve/Cloudreve/releases/latest \
  | grep browser_download_url | grep linux_amd64 | cut -d '"' -f 4 | head -n1)

if [ -z "$LATEST_URL" ]; then
  echo "获取 Cloudreve 最新版本失败，请检查网络或 GitHub 访问。"
  exit 1
fi
echo "下载 Cloudreve：$LATEST_URL"
wget -O cloudreve.tar.gz "$LATEST_URL"
tar -zxvf cloudreve.tar.gz
chmod +x cloudreve

# ====== 6. 写 Cloudreve systemd 服务 ======
echo "[5/7] 创建 Cloudreve systemd 服务..."

cat >/etc/systemd/system/cloudreve.service <<EOF
[Unit]
Description=Cloudreve Service
After=network.target

[Service]
Type=simple
WorkingDirectory=$CLOUDREVE_DIR
ExecStart=$CLOUDREVE_DIR/cloudreve
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now cloudreve

# ====== 7. 写 Nginx 站点配置 ======
echo "[6/7] 创建 Nginx 站点配置 /etc/nginx/conf.d/$DOMAIN.conf ..."

cat >/etc/nginx/conf.d/"$DOMAIN".conf <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    return 301 https://\$server_name:8443\$request_uri;
}

server {
    listen 8443 ssl http2;
    listen [::]:8443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate     $CERT_DIR/fullchain.pem;
    ssl_certificate_key $CERT_DIR/privkey.pem;

    # ---- Cloudreve 主站 (5212) ----
    location / {
        proxy_pass http://127.0.0.1:5212;
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # ---- 3x-ui 订阅接口 (2096) ----
    location /sub/ {
        proxy_pass http://127.0.0.1:2096/;
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # ---- 3x-ui 面板 (1234) ----
    location /panel/ {
        proxy_pass http://127.0.0.1:1234/;

        auth_basic "3x-ui admin";
        auth_basic_user_file $HTPASS_FILE;

        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

nginx -t
systemctl reload nginx

# ====== 8. 总结信息 ======
echo "========== 部署完成 ✅ =========="
echo "证书目录："
echo "  /root/cert/$DOMAIN/"
echo "  /etc/cert/"
echo
echo "Cloudreve 网盘：  https://$DOMAIN/"
echo "3x-ui 面板：      https://$DOMAIN/panel/"
echo "3x-ui 订阅前缀：  https://$DOMAIN/sub/"
echo
echo "Nginx BasicAuth（访问 /panel/ 时先输入）："
echo "  用户名：$ADMIN_USER"
echo "  密码：  $ADMIN_PASS"
echo
echo "⚠ 请在 3x-ui 中确保："
echo "  面板监听： 127.0.0.1:1234"
echo "  订阅监听： 127.0.0.1:2096"
echo "  Reality 业务端口：0.0.0.0:8443（直接对公网，不走 Nginx）"
echo "================================="
