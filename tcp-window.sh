##!/bin/sh
# Issues https://1024.day

if [[ $EUID -ne 0 ]]; then
    clear
    echo "Error: This script must be run as root!"
    exit 1
fi

cat >/etc/security/limits.conf<<EOF
* soft     nproc    131072
* hard     nproc    131072
* soft     nofile   262144
* hard     nofile   262144

root soft  nproc    131072
root hard  nproc    131072
root soft  nofile   262144
root hard  nofile   262144
EOF

echo "session required pam_limits.so" >> /etc/pam.d/common-session

echo "session required pam_limits.so" >> /etc/pam.d/common-session-noninteractive

echo "DefaultLimitNOFILE=262144" >> /etc/systemd/system.conf

echo "DefaultLimitNPROC=131072" >> /etc/systemd/system.conf

cp /etc/sysctl.conf /etc/sysctl.conf.bak.$(date +%F-%T)

cat >/etc/sysctl.conf<<EOF
fs.file-max = 524288
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_slow_start_after_idle = 0
#net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_rmem = 8192 262144 536870912
net.ipv4.tcp_wmem = 4096 16384 536870912
#net.ipv4.udp_rmem_min = 8192
#net.ipv4.udp_wmem_min = 8192
net.ipv4.tcp_adv_win_scale = -2
net.ipv4.tcp_notsent_lowat = 131072
#net.ipv6.conf.all.disable_ipv6 = 1
#net.ipv6.conf.default.disable_ipv6 = 1
#net.ipv6.conf.lo.disable_ipv6 = 1
#net.ipv4.ip_forward = 1
EOF

rm tcp-window.sh

sleep 3 && reboot >/dev/null 2>&1
