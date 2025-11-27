#!/usr/bin/env bash
set -euo pipefail

echo "=============================="
echo "  acme.sh + Cloudflare 一键申请 SSL"
echo "=============================="
echo

# 1. 检查是否 root
if [[ "$EUID" -ne 0 ]]; then
  echo "请使用 root 身份运行本脚本（例如：sudo bash acme_cf_install.sh）"
  exit 1
fi

# 2. 读取域名
read -rp "请输入要申请证书的域名（例如：example.com）: " DOMAIN
if [[ -z "${DOMAIN}" ]]; then
  echo "域名不能为空！"
  exit 1
fi

# 3. 读取 Cloudflare API Token（不回显）
echo "请在 Cloudflare 后台创建一个 API Token（Zone DNS 权限即可）。"
read -rsp "请输入 Cloudflare API Token: " CF_TOKEN
echo
if [[ -z "${CF_TOKEN}" ]]; then
  echo "CF Token 不能为空！"
  exit 1
fi

# 4. 设置环境变量（acme.sh 会读取 CF_Token）
export CF_Token="${CF_TOKEN}"

ACME_ACCOUNT_EMAIL="admin@${DOMAIN}"

DIR_ROOT="/root/cert/${DOMAIN}"
DIR_ETC="/etc/cert"

echo
echo "域名: ${DOMAIN}"
echo "证书目录1: ${DIR_ROOT}"
echo "证书目录2: ${DIR_ETC}"
echo

# 5. 创建目录
mkdir -p "${DIR_ROOT}"
mkdir -p "${DIR_ETC}"

# 6. 安装 acme.sh（如果尚未安装）
if ! command -v acme.sh >/dev/null 2>&1; then
  echo ">>> 未检测到 acme.sh，正在安装..."
  curl https://get.acme.sh | sh -s email="${ACME_ACCOUNT_EMAIL}"

  # 加载环境变量
  if [[ -f "${HOME}/.bashrc" ]]; then
    # acme.sh 安装脚本会往 .bashrc 里写 PATH
    # shellcheck disable=SC1090
    . "${HOME}/.bashrc"
  fi
fi

# 7. 确保 acme.sh 在 PATH 中
if ! command -v acme.sh >/dev/null 2>&1; then
  if [[ -f "${HOME}/.acme.sh/acme.sh" ]]; then
    export PATH="${HOME}/.acme.sh:${PATH}"
  else
    echo "acme.sh 安装失败，找不到 ~/.acme.sh/acme.sh"
    exit 1
  fi
fi

echo ">>> 使用 Let's Encrypt 作为默认 CA..."
acme.sh --set-default-ca --server letsencrypt

# 8. 申请证书
echo ">>> 正在为 ${DOMAIN} 申请证书（DNS 验证，Cloudflare dns_cf）..."
acme.sh --issue \
  -d "${DOMAIN}" \
  --dns dns_cf \
  --server letsencrypt

echo ">>> 证书申请成功，开始安装证书..."

# 9. 安装证书到 /root/cert/<domain>/
acme.sh --install-cert -d "${DOMAIN}" \
  --key-file       "${DIR_ROOT}/privkey.pem" \
  --fullchain-file "${DIR_ROOT}/fullchain.pem"

# 10. 同步到 /etc/cert/
cp "${DIR_ROOT}/privkey.pem"   "${DIR_ETC}/privkey.pem"
cp "${DIR_ROOT}/fullchain.pem" "${DIR_ETC}/fullchain.pem"

# 11. 设置权限
chmod 600 "${DIR_ROOT}/privkey.pem" "${DIR_ETC}/privkey.pem"
chmod 644 "${DIR_ROOT}/fullchain.pem" "${DIR_ETC}/fullchain.pem"

# 12. 清理敏感环境变量
unset CF_Token CF_TOKEN

echo
echo "=============================="
echo "  完成！证书文件如下："
echo "  /root/cert/${DOMAIN}/fullchain.pem"
echo "  /root/cert/${DOMAIN}/privkey.pem"
echo "  /etc/cert/fullchain.pem"
echo "  /etc/cert/privkey.pem"
echo "=============================="
echo "如需配合 Nginx/Apache 使用，请在配置文件中指向以上路径。"
