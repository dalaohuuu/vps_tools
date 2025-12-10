#!/usr/bin/env bash

############################################################
# 一键部署：acme.sh + Nginx + Cloudreve + 面板反代
# 适合放在 GitHub 上公开使用，无敏感信息，无 set -e
#
# 用法：
#   bash deploy.sh <DOMAIN> <CF_Token> <PanelPath> <SubPath>
#
# 示例：
#   bash deploy.sh cc1.5165188.xyz YOUR_CF_TOKEN O6hm1nsvmUDuiotGF3 sub
############################################################

echo "========== 一键部署启动 =========="

### 0. 参数检查 ###
if [ $# -lt 4 ]; then
  echo "用法: $0 <DOMAIN> <CF_Token> <PanelPath> <SubPath>"
  exit 1
fi

DOMAIN="$1"
CF_Token="$2"
PanelRaw="$3"
SubRaw="$4"

# 去掉前后 '/'
Panel="${PanelRaw#/}"
Panel="${Panel%/}"
Sub="${SubRaw#/}"
Sub="${SubRaw%/}"

if [ -z "$Panel" ] || [ -z "$Sub" ]; then
  echo "❌ PanelPath / SubPath 不能为空"
  exit 1
fi

HTTPS_PORT=8443
CERT_ROOT="/root/cert"
CERT_DIR="$CERT_ROOT/$DOMAIN"
CERT_ETC_DIR="/etc/cert"
CLOUDREVE_DIR="/opt/cloudreve"
HTPASS_FILE="/etc/nginx/.htpasswd_3xui"

ADMIN_USER="myadmin"
ADMIN_PASS="$(openssl rand -base64 12)"

### 1. 必须 root ###
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ 请用 root 运行（sudo -i）"
  exit 1
fi

### 2. 安装依赖 ###
echo "[1/7] 安装依赖..."
apt update -y
apt install -y nginx apache2-utils wget curl tar socat cron openssl

rm -f /etc/nginx/sites-enabled/* 2>/dev/null || true

### 3. 安装 acme.sh 和证书 ###
echo "[2/7] 安装 acme.sh / 申请证书..."

if [ ! -d "/root/.acme.sh" ]; then
  curl -fsSL https://get.acme.sh | sh || echo "⚠ acme.sh 安装失败"
fi

ACME="/root/.acme.sh/acme.sh"

if [ -x "$ACME" ]; then
  export CF_Token="$CF_Token"
  "$ACME" --set-default-ca --server letsencrypt || true

  "$ACME" --issue -d "$DOMAIN" --dns dns_cf --force || \
    echo "⚠ 证书签发失败，请检查 Cloudflare Token 和域名解析"

  mkdir -p "$CERT_DIR" "$CERT_ETC_DIR"

  "$ACME" --install-cert -d "$DOMAIN" \
      --key-file "$CERT_DIR/privkey.pem" \
      --fullchain-file "$CERT_DIR/fullchain.pem"

  "$ACME" --install-cert -d "$DOMAIN" \
      --key-file "$CERT_ETC_DIR/privkey.pem" \
      --fullchain-file "$CERT_ETC_DIR/fullchain.pem" \
      --reloadcmd "systemctl reload nginx || true"
else
  echo "⚠ acme.sh 未安装成功，请手工检查"
fi

### 4. BasicAuth ###
echo "[3/7] 创建 BasicAuth..."
rm -f "$HTPASS_FILE"
echo "$ADMIN_PASS" | htpasswd -ci "$HTPASS_FILE" "$ADMIN_USER"

### 5. 安装 Cloudreve ###
echo "[4/7] 安装 Cloudreve..."

mkdir -p "$CLOUDREVE_DIR"
cd "$CLOUDREVE_DIR"

URL=$(wget -qO- https://api.github.com/repos/cloudreve/Cloudreve/releases/latest \
  | grep browser_download_url | grep linux_amd64 | cut -d '"' -f 4 | head -n1)

if [ -z "$URL" ]; then
  echo "❌ 无法从 GitHub 获取 Cloudreve 发布版本"
else
  wget -O cloudreve.tar.gz "$URL" || echo "❌ 下载失败"
  tar -zxvf cloudreve.tar.gz
  chmod +x cloudreve
fi

### 6. systemd 服务 ###
echo "[5/7] 写入 Cloudreve systemd 服务..."

cat >/etc/systemd/system/cloudreve.service <<EOF
[Unit]
Description=Cloudreve
After=network.target

[Service]
WorkingDirectory=$CLOUDREVE_DIR
ExecStart=$CLOUDREVE_DIR/cloudreve
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now cloudreve || echo "⚠ Cloudreve 启动失败"

### 7. 写 Nginx 配置 ###
echo "[6/7] 写入 Nginx 配置..."

cat >/etc/nginx/conf.d/$DOMAIN.conf <<EOF
server {
    listen 80 default_server;
    server_name $DOMAIN;
    return 301 https://\$host:$HTTPS_PORT\$request_uri;
}

server {
    listen $HTTPS_PORT ssl http2 default_server;
    server_name $DOMAIN;

    ssl_certificate     $CERT_DIR/fullchain.pem;
    ssl_certificate_key $CERT_DIR/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:5212;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    location ^~ /$Sub/ {
        proxy_pass http://127.0.0.1:2096;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    location ^~ /$Panel/ {
        proxy_pass http://127.0.0.1:1234;
        proxy_http_version 1.1;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        auth_basic "3x-ui admin";
        auth_basic_user_file $HTPASS_FILE;
    }
}
EOF

nginx -t || echo "⚠ Nginx 配置可能有错误"
systemctl reload nginx || echo "⚠ Nginx reload 失败"

### 8. 总结 ###
echo "========== 部署完成 🎉 =========="
echo "访问信息："
echo "  网盘：     https://$DOMAIN:$HTTPS_PORT/"
echo "  面板：     https://$DOMAIN:$HTTPS_PORT/$Panel/"
echo "  订阅：     https://$DOMAIN:$HTTPS_PORT/$Sub/"
echo
echo "BasicAuth："
echo "  用户名： $ADMIN_USER"
echo "  密码：   $ADMIN_PASS"
echo
echo "脚本来自 GitHub 公共仓库，可安全分发。"
