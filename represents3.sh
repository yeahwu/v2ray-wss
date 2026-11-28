#!/bin/bash
#
# represents3 一键安装管理脚本
# 项目地址：https://github.com/yeahwu/represents3
# 功能：Go 语言编写的 HTTPS 正向代理，支持 CONNECT 隧道、自动 Let's Encrypt 证书、Basic 认证
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# ===================== 全局变量 =====================
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/represents3"
DATA_DIR="/var/lib/represents3"
SERVICE_NAME="represents3"
BINARY_NAME="represents3"
REPO="yeahwu/represents3"
API_URL="https://api.github.com/repos/${REPO}/releases/latest"
TMP_FILE=""

# ===================== 清理钩子 =====================
cleanup() {
    if [[ -n "${TMP_FILE:-}" && -e "$TMP_FILE" ]]; then
        rm -f "$TMP_FILE"
    fi
}
trap cleanup EXIT

# ===================== 工具函数 =====================
info()  { echo -e "${GREEN}[INFO]${PLAIN} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${PLAIN} $*"; }
error() { echo -e "${RED}[ERROR]${PLAIN} $*" >&2; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "请以 root 用户运行此脚本！"
        exit 1
    fi
}

check_systemd() {
    if ! command -v systemctl &>/dev/null || [[ ! -d /run/systemd/system ]]; then
        error "当前环境不支持 systemd，无法管理服务！"
        exit 1
    fi
}

get_os() {
    local os
    os=$(uname -s | tr '[:upper:]' '[:lower:]')
    case "$os" in
        linux) echo "linux" ;;
        *)
            error "不支持的系统: ${os}（本脚本仅支持 Linux + systemd 环境）"
            exit 1
            ;;
    esac
}

get_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)  echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l)        echo "armv7" ;;
        armv6l)        echo "armv6" ;;
        i386|i686)     echo "386"   ;;
        *)
            error "不支持的架构: ${arch}"
            exit 1
            ;;
    esac
}

# 安全读取配置文件中的值（兼容不存在的键和值中包含 '='）
get_env_val() {
    local key="$1"
    local file="${CONFIG_DIR}/env"
    [[ -r "$file" ]] || return 0
    local line
    line=$(grep -E "^${key}=" "$file" | tail -n 1 || true)
    printf '%s' "${line#*=}"
}

validate_domains() {
    local input="$1"
    local d
    local IFS=','
    read -ra domains <<< "$input"
    [[ ${#domains[@]} -gt 0 ]] || return 1
    for d in "${domains[@]}"; do
        if [[ ! "$d" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$ ]]; then
            return 1
        fi
    done
    return 0
}

check_ports() {
    command -v ss &>/dev/null || return 0
    local port conflict
    for port in 80 443; do
        conflict=$(ss -tlnp "sport = :${port}" 2>/dev/null | grep -v '^State' | grep -v "\"${BINARY_NAME}\"" || true)
        if [[ -n "$conflict" ]]; then
            warn "端口 ${port} 已被其他进程占用，可能导致服务启动或证书申请失败："
            echo "$conflict"
        fi
    done
}

# ===================== 依赖安装 =====================
install_dependencies() {
    if command -v curl &>/dev/null; then
        return 0
    fi

    info "未检测到 curl，正在安装依赖..."
    if command -v apt-get &>/dev/null; then
        apt-get update
        apt-get install -y curl ca-certificates
    elif command -v dnf &>/dev/null; then
        dnf install -y curl ca-certificates
    elif command -v yum &>/dev/null; then
        yum install -y curl ca-certificates
    elif command -v pacman &>/dev/null; then
        pacman -Sy --needed --noconfirm curl ca-certificates
    else
        error "未识别的包管理器，请先手动安装 curl 后重试"
        exit 1
    fi
}

# ===================== 获取最新版本号 =====================
get_latest_version() {
    local effective_url version=""

    # 优先通过 releases/latest 的 302 重定向获取 tag，避免触发 GitHub API 限流
    effective_url=$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest" 2>/dev/null || true)
    if [[ "$effective_url" == *"/releases/tag/"* ]]; then
        version="${effective_url##*/releases/tag/}"
        version="${version%%[?#]*}"
    fi

    # 回退到 GitHub API
    if [[ -z "$version" ]]; then
        local api_resp
        api_resp=$(curl -fsSL "$API_URL" 2>/dev/null || true)
        if [[ -n "$api_resp" ]]; then
            if command -v jq &>/dev/null; then
                version=$(printf '%s' "$api_resp" | jq -r '.tag_name // empty' || true)
            else
                version=$(set +o pipefail; printf '%s' "$api_resp" | sed -nE 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -n 1)
            fi
        fi
    fi

    printf '%s' "$version"
}

# ===================== 下载安装二进制 =====================
download_and_install() {
    local os arch version download_url asset_name

    os=$(get_os)
    arch=$(get_arch)

    info "检测系统: ${os}/${arch}"
    info "正在获取最新 Release 版本..."

    version=$(get_latest_version)
    if [[ -z "$version" ]]; then
        error "无法获取最新版本号，请检查网络连接或是否触发 GitHub 限流"
        exit 1
    fi

    info "最新版本: ${version}"

    asset_name="${BINARY_NAME}-${version}-${os}-${arch}"
    download_url="https://github.com/${REPO}/releases/download/${version}/${asset_name}"

    info "下载地址: ${download_url}"
    info "正在下载..."

    install -d -m 0755 "$INSTALL_DIR"
    # 在目标同目录创建临时文件，便于后续 mv 原子替换运行中的二进制
    TMP_FILE=$(mktemp "${INSTALL_DIR}/.${BINARY_NAME}.XXXXXX")

    local curl_opts=(-fL)
    if [[ -t 1 ]]; then
        curl_opts+=(--progress-bar)
    else
        curl_opts+=(-sS)
    fi

    if ! curl "${curl_opts[@]}" -o "$TMP_FILE" "$download_url" || [[ ! -s "$TMP_FILE" ]]; then
        error "下载失败！请检查网络或确认是否存在 ${os}/${arch} 的预编译版本"
        exit 1
    fi

    chmod 0755 "$TMP_FILE"
    mv -f "$TMP_FILE" "${INSTALL_DIR}/${BINARY_NAME}"
    TMP_FILE=""

    info "二进制文件已安装到: ${INSTALL_DIR}/${BINARY_NAME} (${version})"
}

# ===================== 配置文件 =====================
configure() {
    info "配置 represents3..."

    install -d -m 0755 "$CONFIG_DIR"
    install -d -m 0755 "$DATA_DIR"
    install -d -m 0755 "${DATA_DIR}/cert-cache"

    if [[ -f "${CONFIG_DIR}/env" ]]; then
        local overwrite=""
        read -rp "检测到已有配置文件 ${CONFIG_DIR}/env，是否重新生成并覆盖？[y/N]: " overwrite || overwrite=""
        if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
            info "保留现有配置文件: ${CONFIG_DIR}/env"
            return 0
        fi
    fi

    echo ""
    echo -e "${CYAN}========== 配置 HTTPS 正向代理 ==========${PLAIN}"
    echo ""

    # 域名输入与校验
    local domain=""
    while true; do
        read -rp "请输入已 DNS 解析到本服务器的域名（多域名用逗号分隔）: " domain || exit 1
        # 去除空白、协议前缀及尾部斜杠
        domain=$(printf '%s' "$domain" | tr -d '[:space:]' | sed -E 's#^[Hh][Tt][Tt][Pp][Ss]?://##; s#/+$##')
        if [[ -n "$domain" ]] && validate_domains "$domain"; then
            break
        fi
        warn "域名格式无效，请重新输入（例如: proxy.example.com）"
    done

    # 固定用户名 + 随机16位密码
    local proxy_user="represents3"
    local proxy_pass
    proxy_pass=$(set +o pipefail; LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)

    # 多域名时取第一个域名生成合法的 ACME 邮箱
    local primary_domain="${domain%%,*}"
    local acme_email="acme@${primary_domain}"

    # 端口固定 443
    local listen_https=":443"

    # 先以 0600 权限创建再写入，避免密钥短暂暴露
    install -m 0600 -o root -g root /dev/null "${CONFIG_DIR}/env"
    cat > "${CONFIG_DIR}/env" <<EOF
# represents3 配置文件
# 由安装脚本自动生成于 $(date '+%Y-%m-%d %H:%M:%S')

# 域名 (必填，多个域名用逗号分隔)
PROXY_DOMAINS=${domain}

# 代理认证 (强烈建议设置)
PROXY_USER=${proxy_user}
PROXY_PASS=${proxy_pass}

# ACME / Let's Encrypt 设置
ACME_EMAIL=${acme_email}
ACME_STAGING=false

# 运行配置
CERT_CACHE_DIR=${DATA_DIR}/cert-cache
LISTEN_HTTP=:80
LISTEN_HTTPS=${listen_https}
UPSTREAM_DIAL_TIMEOUT=10s

# 日志: LOG_LEVEL=debug|info|warn|error, LOG_FORMAT=text|json
LOG_LEVEL=info
LOG_FORMAT=text
LOG_SOURCE=false
EOF

    info "配置文件已写入: ${CONFIG_DIR}/env"
}

# ===================== systemd 服务 =====================
install_service() {
    info "配置 systemd 服务..."
    check_ports

    cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=represents3 HTTPS Forward Proxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${DATA_DIR}
EnvironmentFile=-${CONFIG_DIR}/env
ExecStart=${INSTALL_DIR}/${BINARY_NAME}
Restart=always
RestartSec=2
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl restart "$SERVICE_NAME"

    sleep 2
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        info "服务启动成功！"
    else
        warn "服务启动可能失败，请检查日志: journalctl -u ${SERVICE_NAME} -f"
    fi
}

# ===================== 状态信息 =====================
show_info() {
    local domain primary_domain proxy_user proxy_pass listen_https port tag

    domain=$(get_env_val "PROXY_DOMAINS")
    primary_domain="${domain%%,*}"
    proxy_user=$(get_env_val "PROXY_USER")
    proxy_pass=$(get_env_val "PROXY_PASS")
    listen_https=$(get_env_val "LISTEN_HTTPS")
    port="${listen_https#:}"
    port="${port:-443}"
    tag=$(set +o pipefail; LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 6)

    echo ""
    echo -e "${CYAN}================================================${PLAIN}"
    echo -e "${CYAN}  represents3 HTTPS 正向代理 配置信息${PLAIN}"
    echo -e "${CYAN}================================================${PLAIN}"
    echo ""
    echo -e "  域名:       ${GREEN}${domain}${PLAIN}"
    echo -e "  端口:       ${GREEN}${port}${PLAIN}"
    echo -e "  用户名:     ${GREEN}${proxy_user}${PLAIN}"
    echo -e "  密码:       ${GREEN}${proxy_pass}${PLAIN}"
    echo ""
    echo -e "  ${YELLOW}Quantumult X 节点配置:${PLAIN}"
    echo -e "  http=${primary_domain}:${port}, username=${proxy_user}, password=${proxy_pass}, over-tls=true, tls-verification=true, tls-host=${primary_domain}, udp-relay=false, tls13=true, tag=${tag}"
    echo ""
    echo -e "  ${YELLOW}常用管理命令:${PLAIN}"
    echo -e "  systemctl status  ${SERVICE_NAME}      # 查看状态"
    echo -e "  systemctl restart ${SERVICE_NAME}      # 重启服务"
    echo -e "  systemctl stop    ${SERVICE_NAME}      # 停止服务"
    echo -e "  journalctl -u ${SERVICE_NAME} -f       # 查看日志"
    echo -e "  vim ${CONFIG_DIR}/env                   # 编辑配置"
    echo ""
    echo -e "${CYAN}================================================${PLAIN}"
    echo ""
}

# ===================== 卸载 =====================
uninstall() {
    info "正在卸载 represents3..."

    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    systemctl daemon-reload 2>/dev/null || true

    rm -f "${INSTALL_DIR}/${BINARY_NAME}"

    local del_config=""
    read -rp "是否删除配置文件和证书缓存？[y/N]: " del_config || del_config=""
    if [[ "$del_config" =~ ^[Yy]$ ]]; then
        rm -rf "$CONFIG_DIR"
        rm -rf "$DATA_DIR"
        info "配置文件和数据已删除"
    else
        info "保留配置文件: ${CONFIG_DIR}/env"
    fi

    info "卸载完成！"
}

# ===================== 更新 =====================
update() {
    if [[ ! -f "/etc/systemd/system/${SERVICE_NAME}.service" ]]; then
        error "未检测到已安装的 ${SERVICE_NAME} 服务，请先执行安装"
        exit 1
    fi

    info "正在更新 represents3..."
    install_dependencies
    download_and_install
    systemctl restart "$SERVICE_NAME"

    sleep 2
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        info "更新成功并已重启！"
    else
        warn "更新后服务启动失败，请检查: journalctl -u ${SERVICE_NAME} -f"
    fi
}

# ===================== 主菜单 =====================
start_menu() {
    while true; do
        [[ -t 1 ]] && clear || true
        echo -e "${CYAN} ================================================== ${PLAIN}"
        echo -e "${CYAN}  represents3 - HTTPS 正向代理 一键管理脚本${PLAIN}"
        echo -e "${CYAN}  项目: https://github.com/yeahwu/represents3${PLAIN}"
        echo -e "${CYAN}  系统: Ubuntu / Debian / CentOS / RHEL / Arch${PLAIN}"
        echo -e "${CYAN} ================================================== ${PLAIN}"
        echo ""
        echo -e " ${GREEN}1.${PLAIN} 安装 represents3"
        echo -e " ${GREEN}2.${PLAIN} 更新 represents3"
        echo -e " ${GREEN}3.${PLAIN} 卸载 represents3"
        echo -e " ${GREEN}4.${PLAIN} 查看运行状态"
        echo -e " ${GREEN}5.${PLAIN} 查看配置信息"
        echo -e " ${GREEN}6.${PLAIN} 重启服务"
        echo -e " ${GREEN}7.${PLAIN} 查看实时日志"
        echo -e " ${GREEN}0.${PLAIN} 退出脚本"
        echo ""

        local num=""
        read -rp "请输入数字: " num || exit 0

        case "$num" in
            1)
                check_root
                check_systemd
                install_dependencies
                download_and_install
                configure
                install_service
                show_info
                break
                ;;
            2)
                check_root
                check_systemd
                update
                break
                ;;
            3)
                check_root
                check_systemd
                uninstall
                break
                ;;
            4)
                check_systemd
                systemctl status "$SERVICE_NAME" --no-pager || true
                break
                ;;
            5)
                check_root
                if [[ -f "${CONFIG_DIR}/env" ]]; then
                    show_info
                else
                    error "未找到配置文件，请先安装"
                fi
                break
                ;;
            6)
                check_root
                check_systemd
                systemctl restart "$SERVICE_NAME"
                sleep 2
                if systemctl is-active --quiet "$SERVICE_NAME"; then
                    info "服务已重启"
                else
                    warn "服务重启后状态异常，请检查日志"
                fi
                systemctl status "$SERVICE_NAME" --no-pager || true
                break
                ;;
            7)
                check_root
                check_systemd
                journalctl -u "$SERVICE_NAME" -f
                break
                ;;
            0)
                exit 0
                ;;
            *)
                error "请输入正确的数字"
                sleep 1
                ;;
        esac
    done
}

start_menu
