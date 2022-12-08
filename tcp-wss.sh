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

install_precheck() {
    read -p "请输入你的域名" domain

    if [ -f "/usr/bin/apt-get" ]; then
        apt-get update -y
        apt-get install -y net-tools curl
    else
        yum update -y
        yum install -y epel-release
        yum install -y net-tools curl
    fi

    isPort=$(netstat -ntlp | grep -E ':80 |:443 ')
    if [ "$isPort" != "" ]; then
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

install_nginx() {
    if [ -f "/usr/bin/apt-get" ]; then
        apt-get install -y nginx
    else
        yum install -y nginx
    fi

    cat >/etc/nginx/nginx.conf <<EOF
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
            return 301 https://\$server_name\$request_uri;
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

acme_ssl() {
    echo
    if [ -f "/usr/bin/apt-get" ]; then
        apt-get install -y certbot
    else
        yum install -y certbot
    fi

    if /etc/letsencrypt/live/$domain/fullchain.pem; then
        echo "证书已经申请过，无需再次申请"
    else
        echo "证书申请中，请稍等..."
        certbot certonly \
            --standalone \
            --agree-tos \
            --no-eff-email \
            --email ssl@app.ml \
            -d ${domain}
    fi
}

install_v2ray() {
    bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh) --version v4.45.2

    cat >/usr/local/etc/v2ray/config.json <<EOF
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

    systemctl enable v2ray.service && systemctl restart v2ray.service
    rm -f tcp-wss.sh install-release.sh

    cat >/usr/local/etc/v2ray/client.json <<EOF
{
===========配置参数=============
地址：${domain}
端口：443/8080
UUID：${v2uuid}
加密方式：aes-128-gcm
传输协议：ws
路径：/${v2path}
底层传输：tls
注意：8080是免流端口不需要打开tls
}
EOF

}

install_sslibev() {
    if [ -f "/usr/bin/apt-get" ]; then
        apt-get update -y
        apt-get install -y --no-install-recommends \
            autoconf automake debhelper pkg-config asciidoc xmlto libpcre3-dev apg pwgen rng-tools \
            libev-dev libc-ares-dev dh-autoreconf libsodium-dev libmbedtls-dev git
    else
        yum update -y
        yum install epel-release -y
        yum install gcc gettext autoconf libtool automake make pcre-devel asciidoc xmlto c-ares-devel libev-devel libsodium-devel mbedtls-devel git -y
    fi

    git clone https://github.com/shadowsocks/shadowsocks-libev.git
    cd shadowsocks-libev
    git submodule update --init --recursive
    ./autogen.sh && ./configure --prefix=/usr && make
    make install
    mkdir -p /etc/shadowsocks-libev

    cat >/etc/shadowsocks-libev/config.json <<EOF
{
    "server":["[::0]","0.0.0.0"],
    "server_port":10240,
    "password":"$v2uuid",
    "timeout":600,
    "method":"chacha20-ietf-poly1305"
}
EOF

    cat >/etc/systemd/system/shadowsocks.service <<EOF
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

client_v2ray() {
    echo
    echo "安装已经完成"
    echo
    echo "===========v2ray配置参数============"
    echo "地址：${domain}"
    echo "端口：443/8080"
    echo "UUID：${v2uuid}"
    echo "加密方式：aes-128-gcm"
    echo "传输协议：ws"
    echo "路径：/${v2path}"
    echo "底层传输：tls"
    echo "注意：8080是免流端口不需要打开tls"
    echo
    echo "===========surge 配置参数============"
    echo
    echo "v2ray = vmess, ${domain}, 443, username=${v2uuid}, skip-cert-verify=true, sni=${domain}, ws=true, ws-path=/dad464, ws-headers=Host:"${domain}", vmess-aead=true, tls=true"
    echo
    echo "===========clash 配置参数============"
}

client_sslibev() {
    echo
    echo "安装已经完成"
    echo
    echo "===========Shadowsocks配置参数============"
    echo "地址：0.0.0.0"
    echo "端口：10240"
    echo "密码：${v2uuid}"
    echo "加密方式：chacha20-ietf-poly1305"
    echo "传输协议：tcp"
    echo
}

start_menu() {
    clear
    echo " ================================================== "
    echo " 论坛：https://1024.day                              "
    echo " 介绍：一键安装Shadowsocks-libev和v2ray+ws+tls代理    "
    echo " 系统：Ubuntu、Debian、CentOS                        "
    echo " ================================================== "
    echo
    echo " 1. 安装Shadowsocks-libev"
    echo " 2. 安装v2ray+ws+tls"
    echo " 3. 同时安装上述两种代理"
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
        install_precheck
        install_nginx
        acme_ssl
        install_v2ray
        install_sslibev
        client_v2ray
        client_sslibev
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
