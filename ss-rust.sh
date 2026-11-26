#!/bin/bash
# Shadowsocks Rust Installation Script
# Author: https://1024.day

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误：此脚本必须以 root 用户身份运行！${PLAIN}" >&2
        exit 1
    fi
}

install_dependencies() {
    echo -e "${CYAN}安装必要的依赖包...${PLAIN}"

    if command -v apt-get &>/dev/null; then
        apt-get update -q &&
            apt-get install -y -q curl xz-utils jq || return 1
    elif command -v dnf &>/dev/null; then
        dnf -q install -y curl xz jq || return 1
    elif command -v yum &>/dev/null; then
        yum -q install -y curl xz jq || return 1
    else
        echo -e "${RED}不支持的 Linux 发行版，请手动安装 curl、xz 和 jq。${PLAIN}" >&2
        return 1
    fi

    echo -e "${GREEN}依赖包安装完成${PLAIN}"
}

generate_credentials() {
    if [[ -r /proc/sys/kernel/random/uuid ]]; then
        SS_PASSWORD=$(cat /proc/sys/kernel/random/uuid) || return 1
    elif command -v uuidgen &>/dev/null; then
        SS_PASSWORD=$(uuidgen) || return 1
    else
        echo -e "${RED}无法生成随机密码：系统不支持 UUID 生成。${PLAIN}" >&2
        return 1
    fi

    echo -e "${YELLOW}请输入端口号 [1-65535]${PLAIN}"
    echo -e "${YELLOW}默认：随机端口（15 秒后自动选择）${PLAIN}"
    read -r -t 15 -p "> " SS_PORT || true

    if [[ -z "$SS_PORT" ]]; then
        SS_PORT=$(shuf -i 10000-65000 -n 1) || return 1
    elif ! [[ "$SS_PORT" =~ ^[0-9]{1,5}$ ]] ||
        (( 10#$SS_PORT < 1 || 10#$SS_PORT > 65535 )); then
        echo -e "${YELLOW}输入的端口无效，使用随机端口${PLAIN}"
        SS_PORT=$(shuf -i 10000-65000 -n 1) || return 1
    else
        SS_PORT=$((10#$SS_PORT))
    fi
}

detect_architecture() {
    echo -e "${CYAN}检测系统架构...${PLAIN}"

    case "$(uname -m)" in
        x86_64|amd64)
            TARGET="x86_64-unknown-linux-musl"
            ;;
        aarch64|arm64)
            TARGET="aarch64-unknown-linux-musl"
            ;;
        i386|i686)
            TARGET="i686-unknown-linux-musl"
            ;;
        armv7l|armv7)
            TARGET="armv7-unknown-linux-musleabihf"
            ;;
        *)
            echo -e "${RED}不支持的架构：$(uname -m)${PLAIN}" >&2
            return 1
            ;;
    esac

    echo -e "${GREEN}下载目标：${TARGET}${PLAIN}"
}

install_shadowsocks() (
    set -o pipefail

    local version archive url tmpdir

    echo -e "${CYAN}获取 Shadowsocks Rust 最新版本...${PLAIN}"

    version=$(curl -fsSL \
        https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest |
        jq -er '.tag_name | select(type == "string" and length > 0)') || {
        echo -e "${RED}无法获取最新版本，请检查网络或 GitHub API 限制。${PLAIN}" >&2
        return 1
    }

    archive="shadowsocks-${version}.${TARGET}.tar.xz"
    url="https://github.com/shadowsocks/shadowsocks-rust/releases/download/${version}/${archive}"

    tmpdir=$(mktemp -d) || {
        echo -e "${RED}无法创建临时目录。${PLAIN}" >&2
        return 1
    }
    trap 'rm -rf -- "$tmpdir"' EXIT

    echo -e "${CYAN}正在下载 ${url}${PLAIN}"
    curl -fL --progress-bar -o "${tmpdir}/${archive}" "$url" || {
        echo -e "${RED}下载失败，请检查网络连接。${PLAIN}" >&2
        return 1
    }

    echo -e "${CYAN}解压文件...${PLAIN}"
    tar -xJf "${tmpdir}/${archive}" -C "$tmpdir" ssserver || {
        echo -e "${RED}解压失败。${PLAIN}" >&2
        return 1
    }

    chmod +x "${tmpdir}/ssserver" || return 1

    "${tmpdir}/ssserver" --version || {
        echo -e "${RED}下载的二进制文件无法在当前系统运行。${PLAIN}" >&2
        return 1
    }

    install -m 755 "${tmpdir}/ssserver" /usr/local/bin/ssserver || {
        echo -e "${RED}安装二进制文件失败。${PLAIN}" >&2
        return 1
    }

    echo -e "${GREEN}Shadowsocks Rust ${version} 安装完成！${PLAIN}"
)

configure_shadowsocks() {
    echo -e "${CYAN}配置 Shadowsocks...${PLAIN}"

    mkdir -p /etc/shadowsocks || return 1

    cat > /etc/shadowsocks/config.json <<EOF
{
    "server": "::",
    "server_port": ${SS_PORT},
    "password": "${SS_PASSWORD}",
    "timeout": 600,
    "mode": "tcp_and_udp",
    "method": "aes-128-gcm"
}
EOF

    chmod 600 /etc/shadowsocks/config.json || return 1

    cat > /etc/systemd/system/shadowsocks.service <<EOF
[Unit]
Description=Shadowsocks Rust Server
After=network.target

[Service]
ExecStart=/usr/local/bin/ssserver -c /etc/shadowsocks/config.json
Restart=on-failure
RestartSec=3s
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload &&
        systemctl enable shadowsocks.service &&
        systemctl restart shadowsocks.service || {
            echo -e "${RED}服务配置或启动失败，请检查 systemd 日志。${PLAIN}" >&2
            return 1
        }

    echo -e "${GREEN}Shadowsocks 配置完成！${PLAIN}"
}

get_server_ip() {
    echo -e "${CYAN}正在获取服务器 IP 地址...${PLAIN}"

    IP=$(curl -fsS -4 --max-time 10 \
        https://www.cloudflare.com/cdn-cgi/trace |
        awk -F= '$1 == "ip" {print $2}')

    if [[ -z "$IP" ]]; then
        IP=$(curl -fsS -6 --max-time 10 \
            https://www.cloudflare.com/cdn-cgi/trace |
            awk -F= '$1 == "ip" {print $2}')
    fi

    if [[ -z "$IP" ]]; then
        IP=$(curl -fsS -4 --max-time 10 https://api.ipify.org ||
            curl -fsS -4 --max-time 10 https://ipinfo.io/ip)
    fi

    if [[ -z "$IP" ]]; then
        echo -e "${YELLOW}无法获取公网 IP，请手动填写客户端服务器地址。${PLAIN}" >&2
        return 1
    fi
}

generate_client_info() {
    local host userinfo service_status

    if systemctl is-active --quiet shadowsocks.service; then
        service_status="${GREEN}运行中${PLAIN}"
    else
        service_status="${RED}未运行${PLAIN}"
    fi

    echo -e ""
    echo -e "==========================================="
    echo -e "       ${GREEN}Shadowsocks 安装完成${PLAIN}"
    echo -e "==========================================="
    echo -e "${YELLOW}服务器地址：${PLAIN} ${IP:-未知，请手动填写}"
    echo -e "${YELLOW}端口：${PLAIN} ${SS_PORT}"
    echo -e "${YELLOW}密码：${PLAIN} ${SS_PASSWORD}"
    echo -e "${YELLOW}加密方式：${PLAIN} aes-128-gcm"
    echo -e "${YELLOW}传输协议：${PLAIN} tcp+udp"
    echo -e "${YELLOW}服务状态：${PLAIN} ${service_status}"

    if [[ -n "$IP" ]]; then
        host="$IP"
        [[ "$host" == *:* ]] && host="[${host}]"
        userinfo=$(printf 'aes-128-gcm:%s' "$SS_PASSWORD" |
            base64 | tr -d '\n')
        echo -e ""
        echo -e "${YELLOW}SS URL：${PLAIN}"
        echo "ss://${userinfo}@${host}:${SS_PORT}"
    fi

    echo -e "==========================================="
}

main() {
    check_root
    install_dependencies || exit 1
    generate_credentials || exit 1
    detect_architecture || exit 1
    install_shadowsocks || exit 1
    configure_shadowsocks || exit 1
    get_server_ip || true
    generate_client_info
}

main
