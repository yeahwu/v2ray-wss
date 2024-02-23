#!/bin/sh
# forum: https://1024.day

if [[ $EUID -ne 0 ]]; then
    clear
    echo "Error: This script must be run as root!" 1>&2
    exit 1
fi

timedatectl set-timezone Asia/Shanghai
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

install_nginx(){
    if [ -f "/usr/bin/apt-get" ];then
        apt-get install -y nginx cron socat
    else
        yum install -y nginx cronie socat
    fi

cat >/etc/nginx/nginx.conf<<EOF
pid /var/run/nginx.pid;
worker_processes auto;
worker_rlimit_nofile 51200;
events {
    worker_connections 1024;
    multi_accept on;
    use epoll;
}
http {
    server_tokens off;
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 120s;
    keepalive_requests 10000;
    types_hash_max_size 2048;
    include /etc/nginx/mime.types;
    access_log off;
    error_log /dev/null;

    server {
        listen $getPort ssl http2;
        listen [::]:$getPort ssl http2;
        server_name $domain;
        ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:HIGH:!aNULL:!MD5:!RC4:!DHE;
        ssl_prefer_server_ciphers on;
        ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;        
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
}
EOF
}

acme_ssl(){    
    curl https://get.acme.sh | sh -s email=my@example.com
    mkdir -p /etc/letsencrypt/live/$domain
    ~/.acme.sh/acme.sh --issue -d $domain --standalone --keylength ec-256 --pre-hook "systemctl stop nginx" --post-hook "~/.acme.sh/acme.sh --installcert -d $domain --ecc --fullchain-file /etc/letsencrypt/live/$domain/fullchain.pem --key-file /etc/letsencrypt/live/$domain/privkey.pem --reloadcmd \"systemctl start nginx\""
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
    rm -f tcp-wss.sh install-release.sh

cat >/usr/local/etc/v2ray/client.json<<EOF
{
===========配置参数=============
协议：VMess
地址：${domain}
端口：${getPort}
UUID：${v2uuid}
加密方式：aes-128-gcm
传输协议：ws
路径：/${v2path}
底层传输：tls
注意：8080是免流端口不需要打开tls
}
EOF

    clear
}

install_sslibev(){
    if [ -f "/usr/bin/apt-get" ];then
        apt-get update -y && apt-get upgrade -y
        apt-get install -y --no-install-recommends \
            autoconf automake debhelper pkg-config asciidoc xmlto libpcre3-dev apg pwgen rng-tools \
            libev-dev libc-ares-dev dh-autoreconf libsodium-dev libmbedtls-dev git
    else
        yum update -y && yum upgrade -y
        yum install epel-release -y
        yum install gcc gettext autoconf libtool automake make pcre-devel asciidoc xmlto c-ares-devel libev-devel libsodium-devel mbedtls-devel git -y  
    fi

    git clone https://github.com/shadowsocks/shadowsocks-libev.git
    cd shadowsocks-libev
    git submodule update --init --recursive
    ./autogen.sh && ./configure --prefix=/usr && make
    make install
    mkdir -p /etc/shadowsocks-libev

cat >/etc/shadowsocks-libev/config.json<<EOF
{
    "server":["[::0]","0.0.0.0"],
    "server_port":$ssport,
    "password":"$v2uuid",
    "timeout":600,
    "method":"chacha20-ietf-poly1305"
}
EOF

cat >/etc/systemd/system/shadowsocks.service<<EOF
[Unit]
Description=Shadowsocks Server
After=network.target
[Service]
ExecStart=/usr/bin/ss-server -c /etc/shadowsocks-libev/config.json
Restart=on-abort
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload && systemctl enable shadowsocks.service && systemctl restart shadowsocks.service
    cd ..
    rm -rf shadowsocks-libev tcp-wss.sh
    clear
}

install_reality(){
    wget https://raw.githubusercontent.com/yeahwu/v2ray-wss/main/reality.sh && bash reality.sh
}

install_ws(){
    wget https://raw.githubusercontent.com/yeahwu/v2ray-wss/main/ws.sh && bash ws.sh
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
    echo "加密方式：aes-128-gcm"
    echo "传输协议：ws"
    echo "路径：/${v2path}"
    echo "底层传输：tls"
    echo "注意：8080是免流端口不需要打开tls"
    echo "===================================="
    echo "vmess://${wslink}"
    echo
}

client_sslibev(){
    sslink=$(echo -n "chacha20-ietf-poly1305:${v2uuid}@$(getIP):${ssport}" | base64 -w 0)

    echo
    echo "安装已经完成"
    echo
    echo "===========Shadowsocks配置参数============"
    echo "地址：$(getIP)"
    echo "端口：${ssport}"
    echo "密码：${v2uuid}"
    echo "加密方式：chacha20-ietf-poly1305"
    echo "传输协议：tcp"
    echo "========================================="
    echo "ss://${sslink}"
    echo
}

start_menu(){
    clear
    echo " ================================================== "
    echo " 论坛：https://1024.day                              "
    echo " 介绍：一键安装SS-libev，v2ray+ws+tls和Reality代理    "
    echo " 系统：Ubuntu、Debian、CentOS                        "
    echo " ================================================== "
    echo
    echo " 1. 安装 Shadowsocks-libev"
    echo " 2. 安装 v2ray+ws+tls"
    echo " 3. 安装 Reality"
    echo " 4. 安装 v2ray+ws"
    echo " 0. 退出脚本"
    echo
    read -p "请输入数字:" num
    case "$num" in
    1)
    install_sslibev
    client_sslibev
    ;;
    2)
    install_precheck
    install_nginx
    acme_ssl
    install_v2ray
    client_v2ray
    ;;
    3)
    install_reality
    ;;
    4)
    install_ws
    ;;
    0)
    exit 1
    ;;
    *)
    clear
    echo "请输入正确数字"
    sleep 2s
    start_menu
    ;;
    esac
}

start_menu
