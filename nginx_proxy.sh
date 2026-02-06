#!/usr/bin/env bash

############################################################
# 一键部署：acme.sh + Nginx + Cloudreve（无 3x-ui 反代）
#
# 用法：
#   bash deploy.sh <DOMAIN> <CF_Token>
#
# 示例：
#   bash deploy.sh cc1.5165188.xyz YOUR_CF_TOKEN
#
# 部署后访问：
#   https://<DOMAIN>:8443/
############################################################

echo "========== 一键部署启动 =========="

### 0. 参数检查 ###
if [ $# -lt 2 ]; then
  echo "用法: $0 <DOMAIN> <CF_Token>"
  echo "示例: $0 cc1.5165188.xyz YOUR_CF_TOKEN"
  exit 1
fi

DOMAIN="$1"
CF_Token="$2"

HTTPS_PORT=8443
CERT_ROOT="/root/cert"
CERT_DIR="$CERT_ROOT/$DOMAIN"
CERT_ETC_DIR="/etc/cloudreve/cert"
CLOUDREVE_DIR="/opt/cloudreve"

echo "域名：        $DOMAIN"
echo "证书目录：    $CERT_DIR"
echo "Nginx 证书：  $CERT_ETC_DIR"
echo "Cloudreve：   $CLOUDREVE_DIR"
echo

### 1. 必须 root ###
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ 请用 root 运行（sudo -i）"
  exit 1
fi

### 2. 安装依赖 ###
echo "[1/6] 安装依赖..."
apt update -y
apt install -y nginx wget curl tar socat cron openssl

rm -f /etc/nginx/sites-enabled/* 2>/dev/null || true

### 3. 安装 acme.sh + 签证书 ###
echo "[2/6] 安装 / 检测 acme.sh，并申请证书..."

if [ ! -d "/root/.acme.sh" ]; then
  curl -fsSL https://get.acme.sh | sh || echo "⚠ acme.sh 安装失败"
fi

ACME="/root/.acme.sh/acme.sh"

if [ -x "$ACME" ]; then
  export CF_Token="$CF_Token"

  "$ACME" --set-default-ca --server letsencrypt || true

  echo "[2/6] 为 $DOMAIN 签证书 (--force)..."
  "$ACME" --issue -d "$DOMAIN" --dns dns_cf --force || \
    echo "⚠ 证书签发失败，请检查 Cloudflare Token 和域名解析"

  mkdir -p "$CERT_DIR" "$CERT_ETC_DIR"

  "$ACME" --install-cert -d "$DOMAIN" \
      --key-file "$CERT_DIR/privkey.pem" \
      --fullchain-file "$CERT_DIR/fullchain.pem"

  "$ACME" --install-cert -d "$DOMAIN" \
      --key-file "$CERT_ETC_DIR/privkey.pem" \
      --fullchain-file "$CERT_ETC_DIR/fullchain.pem" \
      --reloadcmd "chmod 644 $CERT_ETC_DIR/privkey.pem && systemctl reload nginx || true"
else
  echo "⚠ acme.sh 未正确安装，跳过证书流程"
fi

### 权限处理：仅 /etc/cert/privkey.pem 设为 644 ###
if [ -f "$CERT_ETC_DIR/privkey.pem" ]; then
    chmod 644 "$CERT_ETC_DIR/privkey.pem"
    echo "[权限] 已将 $CERT_ETC_DIR/privkey.pem 设置为 644"
else
    echo "⚠ 未找到 $CERT_ETC_DIR/privkey.pem（acme.sh 可能失败）"
fi

### 4. 安装 Cloudreve ###
echo "[3/6] 安装 Cloudreve..."

mkdir -p "$CLOUDREVE_DIR"
cd "$CLOUDREVE_DIR" || exit 1

URL=$(wget -qO- https://api.github.com/repos/cloudreve/Cloudreve/releases/latest \
  | grep browser_download_url | grep linux_amd64 | cut -d '"' -f 4 | head -n1)

if [ -n "$URL" ]; then
  wget -O cloudreve.tar.gz "$URL"
  tar -zxvf cloudreve.tar.gz
  chmod +x cloudreve
else
  echo "❌ 获取 Cloudreve 最新版本失败"
fi

### 5. systemd 服务 ###
echo "[4/6] 写入 Cloudreve systemd 服务..."

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

### 6. 写 Nginx 配置（仅 Cloudreve） ###
echo "[5/6] 写入 Nginx 配置..."

cat >/etc/nginx/conf.d/$DOMAIN.conf <<EOF
server {
    listen 80 default_server;
    server_name $DOMAIN;
    return 301 https://\$host:$HTTPS_PORT\$request_uri;
}

server {
    listen $HTTPS_PORT ssl http2 default_server;
    server_name $DOMAIN;

    # 解除上传大小限制（server 级别）
    client_max_body_size 0;

    ssl_certificate     $CERT_DIR/fullchain.pem;
    ssl_certificate_key $CERT_DIR/privkey.pem;

    # Cloudreve 网盘
    location / {
        proxy_pass http://127.0.0.1:5212;
        proxy_http_version 1.1;

        # 解除上传大小限制（location 级别）
        client_max_body_size 0;
        # 大文件 / 分片上传推荐关闭缓冲
        proxy_request_buffering off;

        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # 上传可能比较久，给长一点超时时间
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
EOF

nginx -t || echo "⚠ Nginx 配置有错误"
systemctl reload nginx || echo "⚠ Nginx reload 失败"

### 7. 完成 ###
echo "========== 部署完成 🎉 =========="
echo "Cloudreve 网盘："
echo "  https://$DOMAIN:$HTTPS_PORT/"
echo
echo "证书位置："
echo "  /root/cert/$DOMAIN/"
echo "  /etc/cert/"
echo "私钥权限："
echo "  $CERT_ETC_DIR/privkey.pem -> 644"
echo
echo "脚本可用于 GitHub 或自动化部署环境。"
