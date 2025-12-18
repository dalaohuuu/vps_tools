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

脚本默认只反代 Cloudreve，不包含任何 3x-ui 面板或订阅接口内容，适合用作独立网盘站点或为其他程序准备 SSL 环境。

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
一键使用：
```
curl -fsSL https://raw.githubusercontent.com/dalaohuuu/vps_tools/refs/heads/main/install-shadowsocks-rust.sh -o install-shadowsrocks-rust.sh \
  && chmod +x install-shadowsrocks-rust.sh \
  && sudo ./install-shadowsrocks-rust.sh \
    --port 使用的端口 \
    --method chacha20-ietf-poly1305 \
    --mode tcp_only \
    --user A1:PASS_A1 \
    --user A2:PASS_A2 \
    --user A3:PASS_A3 \
    --allow-ip A1_IP \
    --allow-ip A2_IP \
    --allow-ip A3_IP \
    --install-deps --install-jq \
  && sudo systemctl status ssserver --no-pager \
  && sudo ufw status numbered
```
## 6.1参数总览

|参数	|是否必需	|默认值	|说明	|备注 / 建议|
|---------|---------|----------|-----------|----------------|
|--port <PORT>|	✅ 必需|	无	|ssserver 监听端口|	你的场景用 62666|
|--method <METHOD>	|❌	|chacha20-ietf-poly1305	|Shadowsocks 加密方式|	同一端口只能一种 method|
|--mode <MODE>	|❌	|tcp_only	|传输模式：tcp_only 或 tcp_and_udp	|推荐 tcp_only（UDP 给 Hysteria2）|
|--timeout <SECONDS>|	❌	|300	|连接超时（秒）|	一般不用改|
## 6.2用户 / 认证相关参数（重点）
|参数|	是否必需|	默认值|	说明|	备注 / 建议|
|---------|---------|----------|-----------|----------------|
|--password <PASS>|	二选一	|无	|单用户密码	|适合只有 1 台入口 VPS|
|--user <NAME:PASS>|	二选一|	无|	多用户（可重复）|	推荐：每台 A 一个密码|
|（规则）|	—|	—|	--password 与 --user 不能同时使用	|脚本会强制校验|

📌 说明

  - 在 Shadowsocks 中：密码 = 用户身份

  - NAME 仅用于备注，不参与认证

  - 多入口（A1/A2/A3…）强烈推荐使用 --user

## 6.3防火墙（UFW）相关参数（非常实用）
|参数|	是否必需|	默认值|	说明|	备注 / 建议|
|---------|---------|----------|-----------|----------------|
|--allow-ip <IP/CIDR>|	❌|	无|	只允许指定 IP 访问 SS 端口|	强烈推荐，可多次使用|
|--open-public|	❌|	false|	对公网开放 SS 端口|	❌ 不推荐|
|--no-ufw-enable|	❌|	启用|	不自动 enable| / reload UFW|	适合你已有复杂规则时|

📌 UFW 行为说明

默认会：

确保 22/tcp 不被锁

为 SS 端口写 allow / deny 规则
## 6.4依赖管理（apt / yum / dnf）
|参数|	是否必需|	默认值|	说明|	备注 / 建议|
|---------|---------|----------|-----------|----------------|
|--install-deps|	❌|	关闭|	自动安装依赖|	新机器 推荐开启|
|--no-install-deps|	❌|	关闭|	禁止自动装依赖|	默认行为|
|--install-jq|	❌|	auto|	安装 jq	|推荐，保证 JSON 安全|
|--no-install-jq|	❌|	auto|	不安装 jq|	会自动降级到 python3|

📌 依赖说明

必需：curl、tar、xz

JSON 写入优先级：

jq（最佳）

python3

纯 shell（仅限简单密码）
## 6.5发布 / 版本控制相关
|参数|	是否必需|	默认值|	说明|	备注|
|---------|---------|----------|-----------|----------------|
|--tag <TAG>|	❌|	latest|	shadowsocks-rust 版本|	可指定如 v1.17.1|
## 6.6其他辅助参数
|参数|	是否必需|	默认值|	说明|	备注|
|---------|---------|----------|-----------|----------------|
|--dry-run|	❌|	关闭|	只打印不执行|	调试 / CI 很有用|
|-h, --help|	❌|	—|	显示帮助|	—|
## 6.7脚本内部关键变量
| 变量            | 默认值                                    | 说明             |
| ------------- | -------------------------------------- | -------------- |
| `BIN_PATH`    | `/usr/local/bin/ssserver`              | ssserver 二进制位置 |
| `CONF_PATH`   | `/etc/shadowsocks-rust/config.json`    | 配置文件           |
| `UNIT_PATH`   | `/etc/systemd/system/ssserver.service` | systemd 服务     |
| `SS_USER`     | `shadowsocks`                          | 运行服务的系统用户      |
| `LimitNOFILE` | `1048576`                              | 最大文件描述符        |
## 6.8 用法示例
、README 里可以加的「推荐用法示例」
## 6.9多入口 A → 单出口 B（推荐）
sudo ./install-shadowsrocks-rust.sh \
  --port 62666 \
  --method chacha20-ietf-poly1305 \
  --mode tcp_only \
  --user A1:PASS_A1 \
  --user A2:PASS_A2 \
  --allow-ip A1_IP \
  --allow-ip A2_IP \
  --install-deps --install-jq
# License
## License
This project is licensed under the MIT License.
## 许可协议
本项目基于 MIT License 开源。
