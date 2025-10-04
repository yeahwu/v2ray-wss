#!/usr/bin/env bash
# HTTPS Proxy Installation Script
# Author: https://1024.day

set -Eeuo pipefail
IFS=$'\n\t'

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    clear
    echo "Error: This script must be run as root!" 1>&2
    exit 1
fi

Passwd=$(cat /dev/urandom | head -1 | md5sum | head -c 12)

# Download Caddy (monthly build) with checksum verification
CADDY_VERSION="v-monthly"
CADDY_BASE_URL="https://github.com/yeahwu/v2ray-wss/releases/download/${CADDY_VERSION}"
CADDY_TARBALL="caddy-${CADDY_VERSION}.tar.gz"
CADDY_SHA256="${CADDY_TARBALL}.sha256"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

echo "Downloading Caddy ${CADDY_VERSION}..."
wget -q "${CADDY_BASE_URL}/${CADDY_TARBALL}" -O "${tmpdir}/${CADDY_TARBALL}"
if [[ -s "${tmpdir}/${CADDY_TARBALL}" ]]; then
  if wget -q "${CADDY_BASE_URL}/${CADDY_SHA256}" -O "${tmpdir}/${CADDY_SHA256}"; then
    echo "Verifying checksum..."
    (cd "$tmpdir" && sha256sum -c "${CADDY_SHA256}")
  else
    echo "Warning: checksum file not found, skipping verification"
  fi
  tar -xzf "${tmpdir}/${CADDY_TARBALL}" -C /usr/local/
else
  echo "Error: failed to download Caddy tarball" 1>&2
  exit 1
fi

chmod +x /usr/local/caddy

echo "====输入已经DNS解析好的域名===="
read domain

    isPort=`netstat -ntlp| grep -E ':80 |:443 ' || true`
    if [ "$isPort" != "" ];then
        clear
        echo " ================================================== "
        echo " 80或443端口被占用，请先释放端口再运行此脚本"
        echo
        echo " 端口占用信息如下："
        echo $isPort
        echo " ================================================== "
        exit 1
    fi

mkdir -p /etc/caddy

email="${ACME_EMAIL:-admin@example.com}"
user="${HTTPS_USER:-1024}"
pass="$Passwd"

cat >/etc/caddy/https.caddyfile<<EOF
{
    email ${email}
}

${domain} {
    route {
        forward_proxy {
            basic_auth ${user} ${pass}
            hide_ip
            hide_via
        }
        file_server
    }
}
EOF

cat >/etc/systemd/system/caddy.service<<EOF
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
User=root
ExecStart=/usr/local/caddy run --environ --config /etc/caddy/https.caddyfile
ExecReload=/usr/local/caddy reload --config /etc/caddy/https.caddyfile --force
TimeoutStopSec=5s
LimitNOFILE=1048576
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

systemctl enable caddy.service && systemctl restart caddy.service && systemctl status --no-pager caddy.service || true

# Optional firewall opening when FIREWALL_AUTO=1
open_firewall_tcp() {
    local port="$1"
    [[ "${FIREWALL_AUTO:-0}" != "1" ]] || {
      if command -v ufw >/dev/null 2>&1; then
          if ufw status | grep -qi "Status: active"; then
              ufw allow "${port}/tcp" || true
          fi
      elif command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
          firewall-cmd --add-port="${port}/tcp" --permanent || true
          firewall-cmd --reload || true
      fi
    }
}
open_firewall_tcp 80
open_firewall_tcp 443

cat >/etc/caddy/https.json<<EOF
{
  "mode": "https-forward-proxy",
  "host": "${domain}",
  "port": 443,
  "user": "${user}",
  "password": "${pass}",
  "tls": {
    "enabled": true,
    "verify": true,
    "sni": "${domain}",
    "tls13": true
  }
}
EOF

cat >/etc/caddy/https.txt<<EOF
===========配置参数=============
代理模式：Https正向代理
地址：${domain}
端口：443
用户：${user}
密码：${pass}
====================================
http=${domain}:443, username=${user}, password=${pass}, over-tls=true, tls-verification=true, tls-host=${domain}, udp-relay=false, tls13=true, tag=https
EOF

    echo
    echo "安装已经完成"
    echo
    echo "===========Https配置参数============"
    echo
    echo "地址：${domain}"
    echo "端口：443"
    echo "用户：${user}"
    echo "密码：${pass}"
    echo
    echo "========================================="
    echo "http=${domain}:443, username=${user}, password=${pass}, over-tls=true, tls-verification=true, tls-host=${domain}, udp-relay=false, tls13=true, tag=https"
    echo
