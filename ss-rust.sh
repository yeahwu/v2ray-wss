#!/bin/sh
# forum: https://1024.day

if [[ $EUID -ne 0 ]]; then
    clear
    echo "Error: This script must be run as root!" 1>&2
    exit 1
fi

timedatectl set-timezone Asia/Shanghai
sspasswd=$(cat /proc/sys/kernel/random/uuid)
ssport=$(shuf -i 2000-65000 -n 1)

getIP(){
    local serverIP=
    serverIP=$(curl -s -4 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}')
    if [[ -z "${serverIP}" ]]; then
        serverIP=$(curl -s -6 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}')
    fi
    echo "${serverIP}"
}

install_UP(){
    if [ -f "/usr/bin/apt-get" ];then
        apt-get update && apt-get upgrade -y
        apt-get install gzip wget curl unzip xz-utils jq -y
    else
        yum update && yum upgrade -y
        yum install epel-release -y
        yum install gzip wget curl unzip xz jq -y  
    fi
}

sysArch() {
    uname=$(uname -m)
    if [[ "$uname" == "i686" ]] || [[ "$uname" == "i386" ]]; then
        arch="i686"
    elif [[ "$uname" == *"armv7"* ]] || [[ "$uname" == "armv6l" ]]; then
        arch="arm"
    elif [[ "$uname" == *"armv8"* ]] || [[ "$uname" == "aarch64" ]]; then
        arch="aarch64"
    else
        arch="x86_64"
    fi    
}

install_SS() {
	new_ver=$(wget -qO- https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases| jq -r '[.[] | select(.prerelease == false) | select(.draft == false) | .tag_name] | .[0]')

	wget --no-check-certificate -N "https://github.com/shadowsocks/shadowsocks-rust/releases/download/${new_ver}/shadowsocks-${new_ver}.${arch}-unknown-linux-gnu.tar.xz"
	if [[ ! -e "shadowsocks-${new_ver}.${arch}-unknown-linux-gnu.tar.xz" ]]; then
		echo -e "${Error} Shadowsocks Rust 官方源下载失败！"
		return 1 && exit 1
	else
		tar -xvf "shadowsocks-${new_ver}.${arch}-unknown-linux-gnu.tar.xz"
	fi
	if [[ ! -e "ssserver" ]]; then
		echo -e "${Error} Shadowsocks Rust 解压失败！"
		echo -e "${Error} Shadowsocks Rust 安装失败 !"
		return 1 && exit 1
	else
		rm -rf "shadowsocks-${new_ver}.${arch}-unknown-linux-gnu.tar.xz"
        chmod +x ssserver
	    mv -f ssserver /usr/local/bin/
	    rm sslocal ssmanager ssservice ssurl

        echo -e "${Info} Shadowsocks Rust 主程序下载安装完毕！"
		return 0
	fi
}

config_SS(){

	mkdir -p /etc/shadowsocks

cat >/etc/shadowsocks/config.json<<EOF
{
    "server": "::",
    "server_port":$ssport,
    "password":"$sspasswd",
    "timeout":600,
	"mode": "tcp_and_udp",
    "method":"aes-128-gcm"
}
EOF

cat >/etc/systemd/system/shadowsocks.service<<EOF
[Unit]
Description=Shadowsocks Server
After=network.target

[Service]
ExecStart=/usr/local/bin/ssserver -c /etc/shadowsocks/config.json

Restart=on-abort

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload && systemctl enable shadowsocks.service && systemctl restart shadowsocks.service
    cd ..
    rm -rf ss-rust.sh

}

client_SS(){
    sslink=$(echo -n "aes-128-gcm:${sspasswd}@$(getIP):${ssport}" | base64 -w 0)

    echo
    echo "安装已经完成"
    echo
    echo "===========Shadowsocks配置参数============"
    echo "地址：$(getIP)"
    echo "端口：${ssport}"
    echo "密码：${sspasswd}"
    echo "加密方式：aes-128-gcm"
    echo "传输协议：tcp+udp"
    echo "========================================="
    echo "ss://${sslink}"
    echo
}

install_UP
sysArch
install_SS
config_SS
client_SS
