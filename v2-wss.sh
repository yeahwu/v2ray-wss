#!/bin/sh
## blog: https://111111.online

if [[ $EUID -ne 0 ]]; then
    clear
    echo "Error: This script must be run as root!" 1>&2
    exit 1
fi

if [ -f "/usr/bin/apt-get" ];then
        isDebian=`cat /etc/issue|grep Debian`
        if [ "$isDebian" != "" ];then
                apt-get install -y nginx certbot
                apt install -y nginx certbot
                sleep 3s
        else
                apt-get install -y nginx certbot
                apt install -y nginx certbot
                sleep 3s
        fi
else
    yum install -y nginx certbot
    sleep 3s
fi

echo "====输入已经DNS解析好的域名===="
read domain

systemctl stop nginx

if [ -f "/usr/bin/apt-get" ];then
        isDebian=`cat /etc/issue|grep Debian`
        if [ "$isDebian" != "" ];then
                echo "A" | certbot certonly --renew-by-default --register-unsafely-without-email --standalone -d $domain
                sleep 3s
        else
                echo "A" | certbot certonly --renew-by-default --register-unsafely-without-email --standalone -d $domain
                sleep 3s
        fi
else
    echo "Y" | certbot certonly --renew-by-default --register-unsafely-without-email --standalone -d $domain
    sleep 3s
fi

cat >/etc/nginx/nginx.conf<<EOF
pid /run/nginx.pid;
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
            proxy_redirect off;
            proxy_pass http://127.0.0.1:10086;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host \$http_host;
        }
    }

    server {
        listen 443 ssl http2;
        listen [::]:443 ssl http2;
        server_name $domain;
        ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:HIGH:!aNULL:!MD5:!RC4:!DHE;
        ssl_prefer_server_ciphers on;
        ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;

        location / {
            proxy_redirect off;
            proxy_pass http://127.0.0.1:10086;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host \$http_host;
        }
    }
}
EOF

systemctl start nginx

wget https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh && bash install-release.sh

v2uuid=$(cat /proc/sys/kernel/random/uuid)

cat >/usr/local/etc/v2ray/config.json<<EOF
{
  "inbounds": [
    {
      "port": 10086,
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
        "path": "/"
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

systemctl start v2ray

cat >/etc/v2-client.json<<EOF
{
===========配置参数=============
地址：${domain}
端口：443
uuid：${v2uuid}
加密方式：aes-128-gcm
传输协议：ws
路径：/
底层传输：tls
}
EOF

clear
echo
echo "安装已经完成"
echo
echo "===========配置参数============"
echo "地址：${domain}"
echo "端口：443"
echo "uuid：${v2uuid}"
echo "加密方式：aes-128-gcm"
echo "传输协议：ws"
echo "路径：/"
echo "底层传输：tls"
echo
