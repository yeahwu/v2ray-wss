#!/bin/sh
## blog: https://111111.online

if [[ $EUID -ne 0 ]]; then
    clear
    echo "Error: This script must be run as root!" 1>&2
    exit 1
fi

timedatectl set-timezone Asia/Shanghai

v2path=$(cat /dev/urandom | head -1 | md5sum | head -c 6)

v2uuid=$(cat /proc/sys/kernel/random/uuid)

echo "====输入已经DNS解析好的域名===="
read domain

install_ssl(){
    if [ -f "/usr/bin/apt-get" ];then
            isDebian=`cat /etc/issue|grep Debian`
            if [ "$isDebian" != "" ];then
                    apt install -y nginx certbot
                    systemctl stop nginx.service
                    echo "A" | certbot certonly --renew-by-default --register-unsafely-without-email --standalone -d $domain
                    sleep 3s
            else
                    apt install -y nginx certbot
                    systemctl stop nginx.service
                    echo "A" | certbot certonly --renew-by-default --register-unsafely-without-email --standalone -d $domain
                    sleep 3s
            fi
    else
        yum install epel-release -y
        yum install nginx certbot -y
        systemctl stop nginx.service
        echo "Y" | certbot certonly --renew-by-default --register-unsafely-without-email --standalone -d $domain
        sleep 3s
    fi
}

install_v2ray(){
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
        listen 80;
        listen [::]:80;
        server_name $domain;
        location / {
            return 301 https://$server_name$request_uri;
        }
    }
    server {
        listen 443 ssl http2;
        listen [::]:443 ssl http2;
        server_name $domain;
        ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:HIGH:!aNULL:!MD5:!RC4:!DHE;
        ssl_prefer_server_ciphers on;
        ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
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

    wget https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh && bash install-release.sh

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

    systemctl enable nginx.service && systemctl start nginx.service

    systemctl enable v2ray.service && systemctl start v2ray.service

cat >/usr/local/etc/v2ray/client.json<<EOF
{
===========配置参数=============
地址：${domain}
端口：443/8080
UUID：${v2uuid}
加密方式：aes-128-gcm
传输协议：ws
路径：/${v2path}
底层传输：tls
注意：8080端口不需要打开tls
}
EOF

    clear
    echo
    echo "安装已经完成"
    echo
    echo "===========配置参数============"
    echo "地址：${domain}"
    echo "端口：443/8080"
    echo "UUID：${v2uuid}"
    echo "加密方式：aes-128-gcm"
    echo "传输协议：ws"
    echo "路径：/${v2path}"
    echo "底层传输：tls"
    echo "注意：8080端口不需要打开tls"
    echo
}

install_sslibev(){
        if [ -f "/usr/bin/apt-get" ];then
            isDebian=`cat /etc/issue|grep Debian`
            if [ "$isDebian" != "" ];then
                    apt install -y --no-install-recommends autoconf automake \
                    debhelper pkg-config asciidoc xmlto libpcre3-dev apg pwgen rng-tools \
                    libev-dev libc-ares-dev dh-autoreconf libsodium-dev libmbedtls-dev git
                    sleep 3s
            else
                    apt install -y --no-install-recommends autoconf automake \
                    debhelper pkg-config asciidoc xmlto libpcre3-dev apg pwgen rng-tools \
                    libev-dev libc-ares-dev dh-autoreconf libsodium-dev libmbedtls-dev git
                    sleep 3s
            fi
    else
        yum install epel-release -y
        yum install gcc gettext autoconf libtool automake make pcre-devel asciidoc xmlto c-ares-devel libev-devel libsodium-devel mbedtls-devel git -y  
        sleep 3s
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
    "server_port":1024,
    "password":"$v2uuid",
    "timeout":600,
    "method":"aes-256-gcm"
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

    systemctl daemon-reload && systemctl enable shadowsocks && systemctl start shadowsocks

    clear
    echo
    echo "=========Shadowsocks配置参数========="
    echo
    cat /etc/shadowsocks-libev/config.json
}

config_proxy(){
    clear
    echo
    echo "安装已经完成"
    echo
    echo "===========v2ray配置参数============"
    echo "地址：${domain}"
    echo "端口：443/80/8080"
    echo "UUID：${v2uuid}"
    echo "加密方式：aes-128-gcm"
    echo "传输协议：ws"
    echo "路径：/${v2path}"
    echo "底层传输：tls"
    echo "注意：80和8080端口不需要打开tls"
    echo
    echo "=========Shadowsocks配置参数========="
    echo
    cat /etc/shadowsocks-libev/config.json
}

start_menu(){
    clear
    echo " ============================================="
    echo " 介绍：一键安装Shadowsocks-libev和v2ray+ws+tls代理    "
    echo " 系统：Ubuntu、Debian、CentOS                  "
    echo " ============================================="
    echo
    echo " 1. 安装Shadowsocks-libev"
    echo " 2. 安装v2ray+ws+tls"
    echo " 3. 同时安装Shadowsocks和v2ray-wss代理"
    echo " 0. 退出脚本"
    echo
    read -p "请输入数字:" num
    case "$num" in
    1)
    install_sslibev
    ;;
    2)
    install_ssl
    install_v2ray  
    ;;
    3)
    install_ssl
    install_v2ray
    install_sslibev
    config_proxy
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
