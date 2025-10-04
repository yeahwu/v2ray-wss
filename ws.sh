#!/usr/bin/env bash
# forum: https://1024.day

set -Eeuo pipefail
IFS=$'\n\t'

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    clear
    echo "Error: This script must be run as root!" 1>&2
    exit 1
fi

# Optional timezone change: enable by exporting TZ_AUTO=1 (default off)
if [[ "${TZ_AUTO:-0}" == "1" ]]; then
    timedatectl set-timezone "${TZ_VALUE:-Asia/Shanghai}" || true
fi
v2uuid=$(cat /proc/sys/kernel/random/uuid)
v2path=$(cat /dev/urandom | head -1 | md5sum | head -c 6)
v2port=$(shuf -i 2000-65000 -n 1)

getIP(){
    local serverIP=
    serverIP=$(curl -s -4 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}')
    if [[ -z "${serverIP}" ]]; then
        serverIP=$(curl -s -6 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}')
    fi
    echo "${serverIP}"
}

install_update(){ 
    if [ -f "/usr/bin/apt-get" ]; then
        apt-get update -y && apt-get upgrade -y
        apt-get install -y gawk curl
    else
        yum update -y && yum upgrade -y
        yum install -y epel-release
        yum install -y gawk curl
    fi
}

install_v2ray(){    
    bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)
    
cat >/usr/local/etc/v2ray/config.json<<EOF
{
  "inbounds": [
    {
      "port": $v2port,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$v2uuid"
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
        "path": "/$v2path"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

    systemctl enable v2ray.service && systemctl restart v2ray.service
    open_firewall "$v2port" tcp

# Machine-readable client JSON
cat >/usr/local/etc/v2ray/client.json<<EOF
{
  "protocol": "vmess",
  "address": "$(getIP)",
  "port": ${v2port},
  "uuid": "${v2uuid}",
  "encryption": "none",
  "network": "ws",
  "path": "/${v2path}",
  "tls": false
}
EOF

    clear
}

client_v2ray(){
    wslink=$(echo -n "{\"port\":${v2port},\"ps\":\"1024-ws\",\"id\":\"${v2uuid}\",\"aid\":0,\"v\":2,\"add\":\"$(getIP)\",\"type\":\"none\",\"path\":\"/${v2path}\",\"net\":\"ws\",\"method\":\"none\"}" | base64 -w 0)

    echo
    echo "安装已经完成"
    echo
    echo "===========v2ray配置参数============"
    echo "协议：VMess"
    echo "地址：$(getIP)"
    echo "端口：${v2port}"
    echo "UUID：${v2uuid}"
    echo "加密方式：none"
    echo "传输协议：ws"
    echo "路径：/${v2path}"
    echo "注意：不需要打开tls"
    echo "===================================="
    echo "vmess://${wslink}"
    cat >/usr/local/etc/v2ray/client.txt<<TXT
===========配置参数=============
协议：VMess
地址：$(getIP)
端口：${v2port}
UUID：${v2uuid}
加密方式：none
传输协议：ws
路径：/${v2path}
====================================
vmess://${wslink}
TXT
    echo
}

install_update
install_v2ray
client_v2ray
# Optional firewall opening when FIREWALL_AUTO=1
open_firewall() {
    local port="$1"; local proto="${2:-tcp}"
    [[ "${FIREWALL_AUTO:-0}" != "1" ]] && return 0
    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -qi "Status: active"; then
            ufw allow "${port}/${proto}" || true
        fi
    elif command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
        firewall-cmd --add-port="${port}/${proto}" --permanent || true
        firewall-cmd --reload || true
    fi
}
