##!/bin/sh
# Issues https://1024.day

if [[ $EUID -ne 0 ]]; then
    clear
    echo "Error: This script must be run as root!"
    exit 1
fi

cat >/etc/security/limits.conf<<EOF
* soft     nproc          1048576
* hard     nproc          1048576
* soft     nofile         1048576
* hard     nofile         1048576

root soft     nproc          1048576
root hard     nproc          1048576
root soft     nofile         1048576
root hard     nofile         1048576

bro soft     nproc          1048576
bro hard     nproc          1048576
bro soft     nofile         1048576
bro hard     nofile         1048576
EOF

echo "session required pam_limits.so" >> /etc/pam.d/common-session

echo "session required pam_limits.so" >> /etc/pam.d/common-session-noninteractive

echo "DefaultLimitNOFILE=1048576" >> /etc/systemd/system.conf

cp /etc/sysctl.conf /etc/sysctl.conf.bak

cat >/etc/sysctl.conf<<EOF
fs.file-max = 1048576
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_slow_start_after_idle = 0
#net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_rmem = 8192 262144 536870912
net.ipv4.tcp_wmem = 4096 16384 268435456
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
