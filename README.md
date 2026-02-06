# 1.acme_cf_install.sh
```
curl -fsSL https://raw.githubusercontent.com/dalaohuuu/vps_tools/main/acme_cf_install.sh -o acme_cf_install.sh \
&& chmod +x acme_cf_install.sh \
&& bash acme_cf_install.sh -d 'domain' -t 'cf_token'
```
Usages
Instead domain and cf_token
|参数|值|
|:---|:---:|
|-d|domain|
|-t|cf_token|

# 2.一键检查 Debian 系统信息
```
curl -fsSL https://raw.githubusercontent.com/dalaohuuu/vps_tools/refs/heads/main/debianinfo.sh -o debianinfo.sh \
&& chmod +x debianinfo.sh \
&& bash debianinfo.sh
```
# 3.linux系统ddclient CloudFlare托管域名动态域名解析
```
sudo apt update && sudo apt install -y curl && \
curl -fsSL https://raw.githubusercontent.com/dalaohuuu/vps_tools/main/cloudflare-ddns.sh -o cloudflare-ddns.sh && \
chmod +x cloudflare-ddns.sh && \
sudo ./cloudflare-ddns.sh install YOUR_Domain YOUR_CF_TOKEN renewtime
```
## 3.1 example：
### 3.1.1 参数说明：
|项目|值|说明|
|:---|:-------------------------|:-------------------------|
|Zone|domain.com|根域名（自动识别，不必输入）|
|Domain|example.domain.com|完整域名|
|CF_token|1234567890abcdef|具有编辑 Cloudflare 域名权限的 API Token|
|renewtime|300| 脚本检查 IP 更新周期（秒）|

### 3.1.2 运行脚本：
sudo apt update && sudo apt install -y curl && \
curl -fsSL https://raw.githubusercontent.com/dalaohuuu/vps_tools/main/cloudflare-ddns.sh -o cloudflare-ddns.sh && \
chmod +x cloudflare-ddns.sh && \
sudo ./cloudflare-ddns.sh install example.domain.com 1234567890abcdef 300

# 4.Cloudreve + Nginx + SSL 一键部署脚本

本项目提供一个简洁的自动化脚本，用于在 **纯净 Ubuntu 服务器上部署：**

- **Cloudreve 网盘**
- **Nginx HTTPS 反代（启用自定义端口 8443）**
- **acme.sh 自动申请并安装 Let's Encrypt SSL 证书（Cloudflare DNS）**

---

## 4.1🚀 功能特点

- 自动安装 Cloudreve（获取 GitHub 最新 release）
- 自动安装 Nginx 并配置反向代理
- 自动使用 acme.sh + Cloudflare DNS 申请证书
- 自动安装证书至：
  - `/root/cert/<domain>/`
  - `/etc/cert/`
- 自动创建 systemd 服务，Cloudreve 开机启动
- 自动配置 HTTPS 访问（端口：`8443`）
- 无 `set -e`，脚本容错性更强

---

## 4.2📦 适用系统

- Ubuntu 20.04 / 22.04 / 24.04 以及其他 Debian 系发行版

---

## 4.3📘 使用方法

```bash
curl -fsSL curl -fsSL https://raw.githubusercontent.com/dalaohuuu/vps_tools/refs/heads/main/nginx_proxy.sh -o nginx_proxy.sh \
  && chmod +x nginx_proxy.sh \
  && ./nginx_proxy.sh Domain CF_Token
```
# 5. force-static-ip.sh
Set **static IPv4 + IPv6** and **disable automatic IP changes**
(cloud-init / DHCP / IPv6 RA) on **Ubuntu 20.04 / 24.04**.

> ⚠️ May disconnect SSH. Use console / out-of-band access.

## 5.1Run

```bash
curl -fsSL https://raw.githubusercontent.com/dalaohuuu/vps_tools/refs/heads/main/force-static-ip.sh | sudo bash -s -- \
  --iface ens3 \
  --ipv4 ip/netmask --gw4 gateway \
  --ipv6 ip/Prefix Length --gw6 gateway \
  --dns "dns1,ipv4 dns,ipv6 dns,......" \
  --yes

```
## 5.2Does
   - Disable cloud-init network config
      禁用 cloud-init 的网络配置功能
      防止云镜像/云平台在重启或初始化时自动修改 IP、网关或 DNS。
   - Disable DHCP / IPv6 RA / SLAAC
      关闭 DHCP / IPv6 RA / SLAAC 自动配置
      防止系统通过 DHCP 或 IPv6 路由通告自动获取或变更 IP 地址。
   - Write netplan static IPv4 + IPv6
      写入 netplan 静态 IPv4 + IPv6 配置
      使用 netplan 明确指定 IPv4 / IPv6 地址、网关和 DNS。
   - Backup existing configs
      自动备份现有网络配置
      在修改前对原有配置文件进行备份，便于回滚恢复。
## 5.3Options

    --keep-networkmanager
      保留并继续使用 NetworkManager（默认会禁用它以减少自动改 IP 的可能）。
    --no-cloud-init
      不修改 cloud-init 的网络配置（默认会禁用 cloud-init 的网络接管）。
    --dry-run
      仅展示将要生成的配置内容，不对系统做任何实际修改。
## 5.4Rollback
      回滚方法（Rollback）

      如果网络异常或需要恢复：
      ```
      sudo netplan apply
      ```
      必要时可恢复 /etc/netplan/ 目录下的 .bak.* 备份文件后再执行上述命令。
# 6. install-shadowsocks-rust.sh

- 下载官方 release 的 `ssserver` 二进制
- 生成多个 `/etc/shadowsocks-rust/<NAME>.json`
- 为每个端口创建一个 systemd 服务：`ssserver-<NAME>.service`
- 自动开机自启并启动
- 不包含 UFW，不使用 jq/python，不自动安装依赖

## 6.1 一键使用（多端口多密码：推荐）

```bash
curl -fsSL https://raw.githubusercontent.com/dalaohuuu/vps_tools/main/install-shadowsocks-rust.sh \
  -o install-shadowsocks-rust.sh \
&& chmod +x install-shadowsocks-rust.sh \
&& sudo ./install-shadowsocks-rust.sh \
  --method chacha20-ietf-poly1305 \
  --mode tcp_only \
  --entry 'A1:12345:PASS_A1_12345678' \
  --entry 'A2:23456:PASS_A2_12345678' \
  --entry 'A3:34567:PASS_A3_12345678' \
&& systemctl list-units 'ssserver-*' --no-pager

```
## 6.2 参数总览
| 参数                         | 是否必需     | 默认值        | 说明                                               |
| -------------------------- | -------- | ---------- | ------------------------------------------------ |
| `--method <METHOD>`        | ✅ 必需（安装） | 无          | Shadowsocks 加密方式                                 |
| `--entry <NAME:PORT:PASS>` | ✅（多端口模式） | 无          | 多端口多密码，可重复                                       |
| `--port <PORT>`            | ✅（单端口模式） | 无          | 单端口监听                                            |
| `--password <PASS>`        | ✅（单端口模式） | 无          | 单端口密码                                            |
| `--mode <MODE>`            | ❌        | `tcp_only` | `tcp_only` / `tcp_and_udp`                       |
| `--timeout <SECONDS>`      | ❌        | `300`      | 连接超时（秒）                                          |
| `--tag <TAG>`              | ❌        | `latest`   | shadowsocks-rust 版本                              |
| `--log-level <LEVEL>`      | ❌        | unset      | 可选日志级别：`error/warn/info/debug/trace`（默认不写入配置，最稳） |
| `--force`                  | ❌        | 关闭         | 覆盖已有同名 `<NAME>` 的 config/unit                    |
| `--list`                   | ❌        | —          | 列出所有已安装实例（读取 `/etc/shadowsocks-rust/*.json`）     |
| `--remove <NAME>`          | ❌        | —          | 删除指定实例（disable + 删除 unit + 删除 json）              |
| `--dry-run`                | ❌        | 关闭         | 只打印不执行                                           |
| `-h, --help`               | ❌        | —          | 帮助                                               |


## 6.3 用户 / 认证相关参数（重点）
由于本脚本不使用 jq/python 来做 JSON 转义，因此对输入做了严格限制：
- NAME：[A-Za-z0-9_-]{1,32}
- PASS：[A-Za-z0-9._~+=-]{8,128}（注意：PASS 不能包含 :）
- METHOD：[A-Za-z0-9._+-]{3,64}
- 无空格、无引号、无特殊转义字符（建议始终给 --entry 加单引号）
如果不满足格式，脚本会直接报错退出。
### 6.3.1生成密码
- 标准方式 
  ```
  # 生成 16 字节 hex（只含 0-9a-f）
  openssl rand -hex 16
  ```
- 包含更多字符（base64）
  ```
  openssl rand -base64 12 | tr -d '\n'
  ```
## 6.4 依赖要求
脚本不会自动安装依赖，请自行确保存在：
- curl tar xz（用于解压 .tar.xz，没有可能会解压失败）
## 6.5 服务管理
多端口模式下，每个实例的服务名为：ssserver-<NAME>.service
常用命令：
```
systemctl list-units 'ssserver-*' --no-pager
sudo systemctl status ssserver-A1 --no-pager
sudo systemctl restart ssserver-A1
sudo journalctl -u ssserver-A1 -f
```
## 6.6 用法示例

- 列出全部实例
```bash
sudo ./install-shadowsocks-rust.sh --list
```
- 删除一个实例（删配置 + 删 unit + disable）
```bash
- sudo ./install-shadowsocks-rust.sh --remove NAME
```
- 覆盖重装（同名覆盖，需 --force）：
  ```
  sudo ./install-shadowsocks-rust.sh --force \
  --method chacha20-ietf-poly1305 \
  --mode tcp_only \
  --entry 'A1:12345:PASS_A1_12345678' \
  --entry 'A2:12345:PASS_A2_12345678'
  ```
- 单端口模式：
- ```
  sudo ./install-shadowsocks-rust.sh \
  --method chacha20-ietf-poly1305 \
  --port 12345 \
  --password 'PASS_A1_12345678'
  ```
- 安装两条 entry（覆盖重装加 --force）
```bash
sudo ./install-shadowsocks-rust.sh --force \
  --method chacha20-ietf-poly1305 \
  --entry 'name1:password1' \
  --entry 'name2:password2'
```

# License
## License
This project is licensed under the MIT License.
## 许可协议
本项目基于 MIT License 开源。
