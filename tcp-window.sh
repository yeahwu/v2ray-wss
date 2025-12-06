#!/bin/sh
# Issues https://1024.day

# 必须 root
if [ "$(id -u)" -ne 0 ]; then
    clear
    echo "Error: This script must be run as root!"
    exit 1
fi

echo "[*] Configuring limits (nofile, nproc)..."

# 增大句柄数
cat >/etc/security/limits.d/99-nofile-nproc.conf <<EOF
* soft     nproc    131072
* hard     nproc    131072
* soft     nofile   262144
* hard     nofile   262144

root soft  nproc    131072
root hard  nproc    131072
root soft  nofile   262144
root hard  nofile   262144
EOF

# 确保 pam_limits 启用
if ! grep -q '^session\s\+required\s\+pam_limits.so' /etc/pam.d/common-session 2>/dev/null; then
    echo "session required pam_limits.so" >> /etc/pam.d/common-session
fi

if ! grep -q '^session\s\+required\s\+pam_limits.so' /etc/pam.d/common-session-noninteractive 2>/dev/null; then
    echo "session required pam_limits.so" >> /etc/pam.d/common-session-noninteractive
fi

echo "[*] Configuring systemd default limits..."

# 使用 system.conf.d drop-in
mkdir -p /etc/systemd/system.conf.d

cat >/etc/systemd/system.conf.d/99-limits.conf <<EOF
[Manager]
DefaultLimitNOFILE=262144
DefaultLimitNPROC=131072
EOF

systemctl daemon-reexec

echo "[*] Backing up and configuring sysctl..."

# 备份 sysctl.conf
if [ -f /etc/sysctl.conf ]; then
    cp /etc/sysctl.conf /etc/sysctl.conf.bak.$(date +%F-%T)
fi

# 优化部分tcp参数
cat >/etc/sysctl.d/99-tcp-tuning.conf <<EOF
fs.file-max = 524288
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_slow_start_after_idle = 0
#net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_rmem = 8192 262144 536870912
net.ipv4.tcp_wmem = 4096 16384 536870912
net.ipv4.tcp_adv_win_scale = -2
net.ipv4.tcp_notsent_lowat = 131072
#net.ipv6.conf.all.disable_ipv6 = 1
#net.ipv6.conf.default.disable_ipv6 = 1
#net.ipv6.conf.lo.disable_ipv6 = 1
#net.ipv4.ip_forward = 1
EOF

# 加载 sysctl
sysctl --system

# 删除当前目录下的脚本文件 tcp-window.sh
rm -- tcp-window.sh

echo
echo "[*] Done."
echo "    - limits.d 已配置 nofile/nproc"
echo "    - pam_limits 已启用"
echo "    - systemd 默认限制通过 /etc/systemd/system.conf.d/99-limits.conf 设置"
echo "    - sysctl 参数写入 /etc/sysctl.d/99-tcp-tuning.conf 并已加载"
echo
echo "建议现在重启以完全生效：reboot"
