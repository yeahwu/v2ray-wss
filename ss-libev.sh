#!/bin/bash
# Shadowsocks-libev Installation Script
# Author: https://1024.day

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

METHOD="aes-128-gcm"

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 此脚本必须以root用户身份运行!${PLAIN}" 1>&2
        exit 1
    fi
}

generate_credentials() {
    if [[ -f /proc/sys/kernel/random/uuid ]]; then
        SS_PASSWORD=$(cat /proc/sys/kernel/random/uuid)
    else
        SS_PASSWORD=$(uuidgen 2>/dev/null || date +%s%N | md5sum | cut -d ' ' -f1)
    fi

    echo -e "${YELLOW}请输入端口号 [1-65535]${PLAIN}"
    echo -e "${YELLOW}默认: 随机端口 (15秒后自动选择随机端口)${PLAIN}"
    read -t 15 -p "> " SS_PORT
    if [[ -z "$SS_PORT" ]]; then
        SS_PORT=$(shuf -i 10000-65000 -n 1)
    elif ! [[ "$SS_PORT" =~ ^[0-9]+$ ]] || [[ "$SS_PORT" -lt 1 ]] || [[ "$SS_PORT" -gt 65535 ]]; then
        echo -e "${YELLOW}输入的端口无效，使用随机端口${PLAIN}"
        SS_PORT=$(shuf -i 10000-65000 -n 1)
    fi
}

get_server_ip() {
    echo -e "${CYAN}正在获取服务器IP地址...${PLAIN}"
    IP=$(curl -s -4 --max-time 10 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}' | tr -d '\n')
    if [[ -z "$IP" ]]; then
        IP=$(curl -s -6 --max-time 10 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}' | tr -d '\n')
    fi
    if [[ -z "$IP" ]]; then
        IP=$(curl -s -4 --max-time 10 https://api.ipify.org || curl -s -4 --max-time 10 https://ipinfo.io/ip)
    fi
    if [[ -z "$IP" ]]; then
        echo -e "${RED}无法获取服务器IP地址，请手动检查网络连接${PLAIN}"
        IP="<未知IP地址>"
    fi
}

# 通过包管理器安装 shadowsocks-libev
install_shadowsocks() {
    echo -e "${CYAN}安装 Shadowsocks-libev...${PLAIN}"

    if command -v apt-get &>/dev/null; then
        apt-get update -q
        apt-get install -y -q curl shadowsocks-libev
    elif command -v dnf &>/dev/null; then
        dnf -q install -y epel-release
        dnf -q install -y curl shadowsocks-libev
    elif command -v yum &>/dev/null; then
        yum -q install -y epel-release
        yum -q install -y curl shadowsocks-libev
    else
        echo -e "${RED}不支持的Linux发行版，请手动安装 shadowsocks-libev${PLAIN}"
        exit 1
    fi

    SS_BIN=$(command -v ss-server)
    if [[ -z "$SS_BIN" ]]; then
        echo -e "${RED}Shadowsocks-libev 安装失败！${PLAIN}"
        exit 1
    fi

    echo -e "${GREEN}Shadowsocks-libev 安装完成！${PLAIN}"
}

configure_shadowsocks() {
    echo -e "${CYAN}配置Shadowsocks...${PLAIN}"

    # 停用软件包自带服务，避免端口冲突
    systemctl disable --now shadowsocks-libev.service &>/dev/null

    mkdir -p /etc/shadowsocks
    cat > /etc/shadowsocks/config.json << EOF
{
    "server":["::0","0.0.0.0"],
    "server_port":$SS_PORT,
    "password":"$SS_PASSWORD",
    "timeout":600,
    "mode":"tcp_and_udp",
    "method":"$METHOD"
}
EOF

    cat > /etc/systemd/system/shadowsocks.service << EOF
[Unit]
Description=Shadowsocks-libev Server
After=network.target

[Service]
ExecStart=$SS_BIN -c /etc/shadowsocks/config.json
Restart=on-failure
RestartSec=3s
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable shadowsocks.service
    systemctl restart shadowsocks.service

    echo -e "${GREEN}Shadowsocks 配置完成！${PLAIN}"
}

generate_client_info() {
    SS_LINK=$(echo -n "${METHOD}:${SS_PASSWORD}@${IP}:${SS_PORT}" | base64 -w 0)

    if [[ "$(systemctl is-active shadowsocks.service)" == "active" ]]; then
        SERVICE_STATUS="${GREEN}运行中${PLAIN}"
    else
        SERVICE_STATUS="${RED}未运行${PLAIN}"
    fi

    clear
    echo -e "==========================================="
    echo -e "       ${GREEN}Shadowsocks-libev 安装已经完成${PLAIN}"
    echo -e "==========================================="
    echo -e "${YELLOW}服务器地址:${PLAIN} ${IP}"
    echo -e "${YELLOW}端口:${PLAIN} ${SS_PORT}"
    echo -e "${YELLOW}密码:${PLAIN} ${SS_PASSWORD}"
    echo -e "${YELLOW}加密方式:${PLAIN} ${METHOD}"
    echo -e "${YELLOW}传输协议:${PLAIN} tcp+udp"
    echo -e "${YELLOW}服务状态:${PLAIN} ${SERVICE_STATUS}"
    echo -e ""
    echo -e "${YELLOW}SS URL:${PLAIN}"
    echo -e "ss://${SS_LINK}"
    echo -e "==========================================="
}

main() {
    check_root
    generate_credentials
    install_shadowsocks
    configure_shadowsocks
    get_server_ip
    generate_client_info
}

main
