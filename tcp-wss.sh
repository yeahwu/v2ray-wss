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
v2path=$(cat /dev/urandom | head -1 | md5sum | head -c 6)
v2uuid=$(cat /proc/sys/kernel/random/uuid)
ssport=$(shuf -i 2000-65000 -n 1)

getIP(){
    local serverIP=
    serverIP=$(curl -s -4 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}')
    if [[ -z "${serverIP}" ]]; then
        serverIP=$(curl -s -6 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}')
    fi
    echo "${serverIP}"
}

install_precheck(){
    echo "====输入已经DNS解析好的域名===="
    read domain

    read -t 15 -p "回车或等待15秒为默认端口443，或者自定义端口请输入(1-65535)："  getPort
    if [ -z $getPort ];then
        getPort=443
    fi
    
    if [ -f "/usr/bin/apt-get" ]; then
        apt-get update -y && apt-get upgrade -y
        apt-get install -y net-tools curl
    else
        yum update -y && yum upgrade -y
        yum install -y epel-release
        yum install -y net-tools curl
    fi

    sleep 3
    isPort=`netstat -ntlp| grep -E ':80 |:443 '`
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
}

install_nginx_80_only(){
    if [ -f "/usr/bin/apt-get" ];then
        apt-get install -y nginx cron socat
    else
        yum install -y nginx cronie socat
    fi

    mkdir -p /var/www/letsencrypt

cat >/etc/nginx/conf.d/v2ray_wss.conf<<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $domain;

    # ACME http-01 challenge
    location ^~ /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
        default_type text/plain;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}
EOF

    systemctl enable nginx && systemctl restart nginx
    open_firewall 80 tcp
}

install_nginx_tls_site(){
cat >/etc/nginx/conf.d/v2ray_wss_tls.conf<<EOF
server {
    listen $getPort ssl http2;
    listen [::]:$getPort ssl http2;
    server_name $domain;

    # Modern TLS settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256:HIGH:!aNULL:!MD5:!RC4:!DHE';
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    location / {
        default_type text/plain;
        return 200 "Hello World !";
    }

    location /$v2path {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
    }
}
EOF

    nginx -t && systemctl reload nginx
    open_firewall "$getPort" tcp
}

acme_ssl(){
    local email
    email="${ACME_EMAIL:-admin@example.com}"
    curl https://get.acme.sh | sh -s email="${email}"
    mkdir -p /etc/letsencrypt/live/$domain
    # Use webroot to avoid stopping nginx
    ~/.acme.sh/acme.sh --issue -d "$domain" -w /var/www/letsencrypt --keylength ec-256
    ~/.acme.sh/acme.sh --installcert -d "$domain" --ecc \
        --fullchain-file "/etc/letsencrypt/live/$domain/fullchain.pem" \
        --key-file "/etc/letsencrypt/live/$domain/privkey.pem" \
        --reloadcmd "systemctl reload nginx"
}

install_v2ray(){    
    bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)
    
cat >/usr/local/etc/v2ray/config.json<<EOF
{
  "inbounds": [
    {
      "port": 8080,
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

    systemctl enable v2ray.service && systemctl restart v2ray.service && systemctl restart nginx.service

# Machine-readable client JSON
cat >/usr/local/etc/v2ray/client.json<<EOF
{
  "protocol": "vmess",
  "address": "${domain}",
  "port": ${getPort},
  "uuid": "${v2uuid}",
  "encryption": "none",
  "network": "ws",
  "path": "/${v2path}",
  "tls": true,
  "sni": "${domain}",
  "host": "${domain}"
}
EOF

    clear
}

install_ssrust(){
    wget https://raw.githubusercontent.com/yeahwu/v2ray-wss/main/ss-rust.sh && bash ss-rust.sh
}

install_reality(){
    wget https://raw.githubusercontent.com/yeahwu/v2ray-wss/main/reality.sh && bash reality.sh
}

install_hy2(){
    wget https://raw.githubusercontent.com/yeahwu/v2ray-wss/main/hy2.sh && bash hy2.sh
}

install_https(){
    wget https://raw.githubusercontent.com/yeahwu/v2ray-wss/main/https.sh && bash https.sh
}

client_v2ray(){
    wslink=$(echo -n "{\"port\":${getPort},\"ps\":\"1024-wss\",\"tls\":\"tls\",\"id\":\"${v2uuid}\",\"aid\":0,\"v\":2,\"host\":\"${domain}\",\"type\":\"none\",\"path\":\"/${v2path}\",\"net\":\"ws\",\"add\":\"${domain}\",\"allowInsecure\":0,\"method\":\"none\",\"peer\":\"${domain}\",\"sni\":\"${domain}\"}" | base64 -w 0)

    echo
    echo "安装已经完成"
    echo
    echo "===========v2ray配置参数============"
    echo "协议：VMess"
    echo "地址：${domain}"
    echo "端口：${getPort}"
    echo "UUID：${v2uuid}"
    echo "加密方式：none"
    echo "传输协议：ws"
    echo "路径：/${v2path}"
    echo "底层传输：tls"
    echo "注意：8080是免流端口不需要打开tls"
    echo "===================================="
    echo "vmess://${wslink}"
    # Human-readable client info
    cat >/usr/local/etc/v2ray/client.txt<<TXT
===========配置参数=============
协议：VMess
地址：${domain}
端口：${getPort}
UUID：${v2uuid}
加密方式：none
传输协议：ws
路径：/${v2path}
底层传输：tls
====================================
vmess://${wslink}
TXT
    echo
}

start_menu(){
    clear
    local line="+----------------------------------------------------------+"
    echo "$line"
    printf "| %-56s |\n" "脚本菜单 / Script Menu"
    echo "$line"
    printf "| %-56s |\n" "论坛: https://1024.day"
    printf "| %-56s |\n" "功能: 一键安装 SS-Rust / V2Ray+WSS / Reality / Hysteria2 / HTTPS"
    printf "| %-56s |\n" "系统: Ubuntu / Debian / CentOS"
    echo "$line"
    printf "| %-56s |\n" " 1) 安装 Shadowsocks-rust (落地)"
    printf "| %-56s |\n" " 2) 安装 V2Ray + WebSocket + TLS"
    printf "| %-56s |\n" " 3) 安装 Reality (Xray)"
    printf "| %-56s |\n" " 4) 安装 Hysteria2 (QUIC)"
    printf "| %-56s |\n" " 5) 安装 HTTPS 正向代理 (Caddy)"
    printf "| %-56s |\n" " 0) 退出"
    echo "$line"
    echo
    read -p "请选择 [0-5]: " num
    case "$num" in
    1)
    install_ssrust
    ;;
    2)
    install_precheck
    install_nginx_80_only
    acme_ssl
    install_nginx_tls_site
    install_v2ray
    client_v2ray
    ;;
    3)
    install_reality
    ;;
    4)
    install_hy2
    ;;
    5)
    install_https
    ;;
    0)
    exit 1
    ;;
    *)
    clear
    echo "请输入正确选项 [0-5]"
    sleep 2s
    start_menu
    ;;
    esac
}

start_menu
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
