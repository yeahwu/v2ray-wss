#!/usr/bin/env bash
# 该脚本使用 nftables 实现端口转发功能，支持 TCP 和 UDP 协议
# Author: https://1024.day

# 遇到错误立即退出，未定义变量报错
set -euo pipefail

# 交互式读取转发参数
read -rp "请输入本机转发端口 (FORWARD_PORT): " FORWARD_PORT
read -rp "请输入目标 IP (TARGET_IP): " TARGET_IP
read -rp "请输入目标端口 (TARGET_PORT): " TARGET_PORT

# 配置文件路径
NFT_CONF="/etc/nftables.conf"
SYSCTL_CONF="/etc/sysctl.d/99-nft-forward.conf"
TABLE_NAME="port_forward"

# 检查是否以 root 权限运行
if [[ "${EUID}" -ne 0 ]]; then
  echo "请以 root 权限运行此脚本。"
  exit 1
fi

# 自动安装 nftables，支持主流 Linux 发行版
install_nftables() {
  echo "未找到 nft 命令，正在尝试自动安装 nftables..."

  if command -v apt-get >/dev/null 2>&1; then
    # Debian / Ubuntu
    apt-get update -qq && apt-get install -y nftables
  elif command -v dnf >/dev/null 2>&1; then
    # Fedora / RHEL 8+ / AlmaLinux / Rocky Linux
    dnf install -y nftables
  elif command -v yum >/dev/null 2>&1; then
    # CentOS 7 / 旧版 RHEL
    yum install -y nftables
  elif command -v zypper >/dev/null 2>&1; then
    # openSUSE / SLES
    zypper install -y nftables
  elif command -v pacman >/dev/null 2>&1; then
    # Arch Linux / Manjaro
    pacman -Sy --noconfirm nftables
  elif command -v apk >/dev/null 2>&1; then
    # Alpine Linux
    apk add --no-cache nftables
  elif command -v emerge >/dev/null 2>&1; then
    # Gentoo
    emerge --ask=n net-firewall/nftables
  else
    echo "无法识别的包管理器，请手动安装 nftables 后重试。"
    exit 1
  fi

  # 安装后再次确认
  if ! command -v nft >/dev/null 2>&1; then
    echo "nftables 安装失败，请手动排查。"
    exit 1
  fi

  echo "nftables 安装成功。"
}

# 检查 nft 命令是否存在，不存在则自动安装
if ! command -v nft >/dev/null 2>&1; then
  install_nftables
fi

# 校验端口必须为纯数字
if ! [[ "${FORWARD_PORT}" =~ ^[0-9]+$ && "${TARGET_PORT}" =~ ^[0-9]+$ ]]; then
  echo "端口必须为数字。"
  exit 1
fi

# 校验端口范围 1-65535
if (( FORWARD_PORT < 1 || FORWARD_PORT > 65535 || TARGET_PORT < 1 || TARGET_PORT > 65535 )); then
  echo "端口值必须在 1-65535 范围内。"
  exit 1
fi

# 校验目标 IP 不为空
if [[ -z "${TARGET_IP}" ]]; then
  echo "目标 IP 不能为空。"
  exit 1
fi

# 写入 sysctl 配置，开启内核 IP 转发
cat > "${SYSCTL_CONF}" <<EOF
net.ipv4.ip_forward=1
EOF

# 使 sysctl 配置立即生效
sysctl --system >/dev/null

# 生成 nftables 规则配置文件
cat > "${NFT_CONF}" <<EOF
#!/usr/sbin/nft -f

flush ruleset

table ip ${TABLE_NAME} {
    chain prerouting {
        type nat hook prerouting priority 0; policy accept;
        # 将 TCP/UDP 流量 DNAT 到目标地址
        tcp dport ${FORWARD_PORT} dnat to ${TARGET_IP}:${TARGET_PORT}
        udp dport ${FORWARD_PORT} dnat to ${TARGET_IP}:${TARGET_PORT}
        # 转发多台落地服务器，在下面直接复写添加就行
        # tcp dport 3333 dnat to 7.7.7.7:7777
        # udp dport 3333 dnat to 7.7.7.7:7777
    }

    chain postrouting {
        type nat hook postrouting priority 100; policy accept;
        # 对出口流量做 MASQUERADE（源地址伪装）
        masquerade
    }
}
EOF

# 加载 nftables 规则
nft -f "${NFT_CONF}"

# 若系统使用 systemd，则启用并重启 nftables 服务（使规则开机自动生效）
if command -v systemctl >/dev/null 2>&1; then
  systemctl enable nftables >/dev/null 2>&1 || true
  systemctl restart nftables >/dev/null 2>&1 || true
fi

# 输出最终配置信息
echo "nftables 端口转发配置成功。"
echo "本机转发端口 : ${FORWARD_PORT}"
echo "目标主机     : ${TARGET_IP}"
echo "目标端口     : ${TARGET_PORT}"
echo "配置文件     : ${NFT_CONF}"
