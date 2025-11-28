#!/usr/bin/env bash
#
# 一键检查 Debian 系统信息脚本
# 适用：Debian / Ubuntu 及其衍生发行版

set -e

OUT_DIR="/tmp"
PKG_LIST_FILE="${OUT_DIR}/installed_packages_$(date +%F_%H%M%S).txt"

echo "======================================"
echo "  系统基础信息检查"
echo "  运行时间：$(date)"
echo "======================================"
echo

#################### CPU 信息 ####################
echo "========== CPU 信息 =========="
if command -v lscpu >/dev/null 2>&1; then
    lscpu | egrep 'Model name|Socket\(s\)|Core\(s\) per socket|Thread|CPU\(s\)' || lscpu
else
    echo "未找到 lscpu 命令，尝试从 /proc/cpuinfo 获取："
    grep -m1 "model name" /proc/cpuinfo || cat /proc/cpuinfo
fi
echo

#################### 内存 信息 ####################
echo "========== 内存 信息 =========="
if command -v free >/dev/null 2>&1; then
    free -h
else
    echo "未找到 free 命令，尝试从 /proc/meminfo 获取："
    head -n 10 /proc/meminfo
fi
echo

#################### 磁盘 / 分区 信息 ####################
echo "========== 磁盘与分区概览 (lsblk) =========="
if command -v lsblk >/dev/null 2>&1; then
    lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT
else
    echo "未找到 lsblk 命令。"
fi
echo

echo "========== 磁盘使用情况 (df) =========="
df -hT | sed '1,1s/^/文件系统信息：\n/'
echo

#################### 网络 / IP 信息 ####################
echo "========== 网络 / IP 信息 =========="
echo "主机名：$(hostname)"
echo

# 简单 IP 信息
if command -v hostname >/dev/null 2>&1; then
    echo "IP 地址（hostname -I）："
    hostname -I 2>/dev/null || echo "获取失败"
    echo
fi

# 详细网卡信息
if command -v ip >/dev/null 2>&1; then
    echo "详细网卡信息（ip addr）："
    ip addr show
elif command -v ifconfig >/dev/null 2>&1; then
    echo "详细网卡信息（ifconfig）："
    ifconfig
else
    echo "未找到 ip / ifconfig 命令，无法显示详细网卡信息。"
fi
echo

#################### 系统版本 信息 ####################
echo "========== 系统版本 信息 =========="
if command -v lsb_release >/dev/null 2>&1; then
    lsb_release -a
elif [ -f /etc/os-release ]; then
    cat /etc/os-release
elif [ -f /etc/debian_version ]; then
    echo "Debian 版本：$(cat /etc/debian_version)"
else
    echo "无法确定系统版本信息。"
fi
echo
