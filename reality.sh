#!/bin/bash
# forum: https://1024.day
# Improved Reality script with cross-platform compatibility

if [[ $EUID -ne 0 ]]; then
    clear
    echo "Error: This script must be run as root!" 1>&2
    exit 1
fi

# Color output functions
red() {
    echo -e "\033[31m$1\033[0m"
}

green() {
    echo -e "\033[32m$1\033[0m"
}

yellow() {
    echo -e "\033[33m$1\033[0m"
}

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Error handling function
error_exit() {
    red "错误: $1"
    exit 1
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Detect distribution
detect_distribution() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_ID=$ID
        OS_VERSION=$VERSION_ID
        OS_CODENAME=${VERSION_CODENAME:-}
    elif [[ -f /etc/redhat-release ]]; then
        if grep -q "CentOS" /etc/redhat-release; then
            OS_ID="centos"
            OS_VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release | head -1)
        elif grep -q "Red Hat" /etc/redhat-release; then
            OS_ID="rhel"
            OS_VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release | head -1)
        fi
    elif [[ -f /etc/debian_version ]]; then
        OS_ID="debian"
        OS_VERSION=$(cat /etc/debian_version)
    else
        OS_ID="unknown"
        OS_VERSION="unknown"
    fi
    log "检测到系统: $OS_ID $OS_VERSION"
}

# Check network connectivity
check_network() {
    log "检查网络连接..."
    if ! curl -s --connect-timeout 10 http://www.cloudflare.com/cdn-cgi/trace >/dev/null; then
        if ! curl -s --connect-timeout 10 https://www.google.com >/dev/null; then
            error_exit "网络连接失败，请检查网络设置"
        fi
    fi
    green "网络连接正常"
}

# Enhanced package manager detection
detect_package_manager() {
    if command_exists apt-get; then
        PKG_MANAGER="apt"
        PKG_UPDATE="apt-get update -y"
        PKG_UPGRADE="apt-get upgrade -y"
        PKG_INSTALL="apt-get install -y"
    elif command_exists yum; then
        PKG_MANAGER="yum"
        PKG_UPDATE="yum update -y"
        PKG_UPGRADE="yum upgrade -y"
        PKG_INSTALL="yum install -y"
        # Install EPEL repository for additional packages
        yum install -y epel-release 2>/dev/null || true
    elif command_exists dnf; then
        PKG_MANAGER="dnf"
        PKG_UPDATE="dnf update -y"
        PKG_UPGRADE="dnf upgrade -y"
        PKG_INSTALL="dnf install -y"
        # Install EPEL repository for additional packages
        dnf install -y epel-release 2>/dev/null || true
    elif command_exists zypper; then
        PKG_MANAGER="zypper"
        PKG_UPDATE="zypper ref"
        PKG_UPGRADE="zypper up -y"
        PKG_INSTALL="zypper in -y"
    elif command_exists pacman; then
        PKG_MANAGER="pacman"
        PKG_UPDATE="pacman -Sy"
        PKG_UPGRADE="pacman -Syu --noconfirm"
        PKG_INSTALL="pacman -S --noconfirm"
    else
        error_exit "不支持的包管理器，请手动安装依赖包"
    fi
    log "检测到包管理器: $PKG_MANAGER"
}

# Check service manager
check_service_manager() {
    if command_exists systemctl; then
        SERVICE_MANAGER="systemctl"
        SERVICE_ENABLE="systemctl enable"
        SERVICE_START="systemctl start"
        SERVICE_RESTART="systemctl restart"
        SERVICE_STATUS="systemctl status"
    elif command_exists service; then
        SERVICE_MANAGER="service"
        SERVICE_ENABLE="chkconfig --add"
        SERVICE_START="service"
        SERVICE_RESTART="service"
        SERVICE_STATUS="service"
    else
        error_exit "不支持的服务管理器"
    fi
    log "检测到服务管理器: $SERVICE_MANAGER"
}

# Initialize distribution detection and package manager
detect_distribution
detect_package_manager
check_service_manager
check_network

# Set timezone with error handling
if command_exists timedatectl; then
    timedatectl set-timezone Asia/Shanghai 2>/dev/null || log "时区设置失败，继续安装..."
else
    log "timedatectl 不可用，跳过时区设置"
fi

# Generate UUID
v2uuid=$(cat /proc/sys/kernel/random/uuid)

read -r -t 15 -p "回车或等待15秒为默认端口443，或者自定义端口请输入(1-65535)："  getPort
if [ -z "$getPort" ];then
    getPort=443
    echo ""
fi

echo

read -r -t 30 -p "回车或等待30秒为默认域名 www.amazon.com，或者自定义SNI请输入："  getSni
if [ -z "$getSni" ];then
    getSni=www.amazon.com
    echo ""
fi

getIP(){
    local serverIP=
    log "获取服务器IP地址..."
    
    # Try multiple methods to get IP
    serverIP=$(curl -s -4 --connect-timeout 10 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}')
    if [[ -z "${serverIP}" ]]; then
        serverIP=$(curl -s -6 --connect-timeout 10 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}')
    fi
    
    # Fallback methods
    if [[ -z "${serverIP}" ]]; then
        serverIP=$(curl -s --connect-timeout 10 https://ipv4.icanhazip.com/ 2>/dev/null)
    fi
    if [[ -z "${serverIP}" ]]; then
        serverIP=$(curl -s --connect-timeout 10 https://ipinfo.io/ip 2>/dev/null)
    fi
    if [[ -z "${serverIP}" ]]; then
        serverIP=$(wget -qO- --timeout=10 http://ipecho.net/plain 2>/dev/null)
    fi
    
    if [[ -z "${serverIP}" ]]; then
        error_exit "无法获取服务器IP地址，请检查网络连接"
    fi
    
    echo "${serverIP}"
}

install_xray(){ 
    log "开始安装系统依赖和Xray..."
    
    # Update package lists
    log "更新软件包列表..."
    if ! eval "$PKG_UPDATE"; then
        error_exit "更新软件包列表失败"
    fi
    
    # Upgrade system (optional, with error handling)
    log "升级系统软件包..."
    eval "$PKG_UPGRADE" || log "系统升级过程中出现警告，继续安装..."
    
    # Install basic dependencies with distribution-specific package names
    log "安装基础依赖包..."
    local basic_packages=""
    
    case $PKG_MANAGER in
        "apt")
            basic_packages="curl wget gawk ca-certificates gnupg lsb-release"
            ;;
        "yum"|"dnf")
            basic_packages="curl wget gawk ca-certificates gnupg2"
            ;;
        "zypper")
            basic_packages="curl wget gawk ca-certificates gnupg2"
            ;;
        "pacman")
            basic_packages="curl wget gawk ca-certificates gnupg"
            ;;
    esac
    
    if ! eval "$PKG_INSTALL $basic_packages"; then
        error_exit "安装基础依赖包失败"
    fi
    
    # Verify critical tools are available
    for tool in curl wget; do
        if ! command_exists $tool; then
            error_exit "$tool 安装失败，无法继续"
        fi
    done
    
    green "基础依赖安装完成"
    
    # Install Xray with error handling
    log "下载并安装Xray..."
    local install_script_url="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"
    
    # Download install script with retries
    local script_path="/tmp/xray-install.sh"
    local retry_count=0
    while [ $retry_count -lt 3 ]; do
        if curl -L --connect-timeout 30 --max-time 300 "$install_script_url" -o "$script_path"; then
            break
        fi
        retry_count=$((retry_count + 1))
        log "下载安装脚本失败，重试 $retry_count/3..."
        sleep 5
    done
    
    if [ $retry_count -eq 3 ]; then
        error_exit "下载Xray安装脚本失败"
    fi
    
    # Run install script
    if ! bash "$script_path" install; then
        error_exit "Xray安装失败"
    fi
    
    # Verify Xray installation
    if [[ ! -f "/usr/local/bin/xray" ]]; then
        error_exit "Xray安装验证失败"
    fi
    
    # Clean up
    rm -f "$script_path"
    
    green "Xray安装完成"
}

get_keys(){
    log "生成Reality密钥对..."
    local raw tries=0
    
    # Verify xray is available
    if [[ ! -f "/usr/local/bin/xray" ]]; then
        error_exit "Xray未正确安装，无法生成密钥"
    fi
    
    while (( tries < 5 )); do
        raw=$(/usr/local/bin/xray x25519 2>/dev/null || true)
        
        if [[ -z "$raw" ]]; then
            ((tries++))
            log "密钥生成失败，重试 $tries/5..."
            sleep 2
            continue
        fi
        
        # 私钥：匹配 Private key: / PrivateKey:
        rePrivateKey=$(printf '%s\n' "$raw" | awk -F ': *' '/^[Pp]rivate[[:space:]]*[Kk]ey/{print $2; exit}')
        # 公钥优先：Public key / PublicKey
        rePublicKey=$(printf '%s\n' "$raw" | awk -F ': *' '/^[Pp]ublic[[:space:]]*[Kk]ey/{print $2; exit}')
        # 若无 Public，则尝试把 Password 当作"公钥"使用（适配你看到的新输出）
        if [[ -z "${rePublicKey:-}" ]]; then
            rePublicKey=$(printf '%s\n' "$raw" | awk -F ': *' '/^[Pp]assword/{print $2; exit}')
        fi
        
        # 记录原始输出供调试
        if [[ -n "${rePrivateKey:-}" && -n "${rePublicKey:-}" ]]; then
            break
        fi
        ((tries++))
        log "密钥解析失败，重试 $tries/5..."
        sleep 1
    done
    
    if [[ -z "${rePrivateKey:-}" || -z "${rePublicKey:-}" ]]; then
        red "生成（或解析）X25519 密钥失败。原始输出："
        echo "--------------------------------"
        echo "$raw"
        echo "--------------------------------"
        red "请手动执行：/usr/local/bin/xray x25519 复制输出，把第一行设为 privateKey，第二行(或 Password)当作 pbk。"
        exit 1
    fi
    
    # 去掉可能的空白
    rePrivateKey=$(echo -n "$rePrivateKey" | tr -d ' \r\n')
    rePublicKey=$(echo -n "$rePublicKey" | tr -d ' \r\n')
    
    # Validate key format (basic check)
    if [[ ${#rePrivateKey} -lt 40 || ${#rePublicKey} -lt 40 ]]; then
        red "生成的密钥格式不正确，请检查Xray版本"
        exit 1
    fi
    
    green "密钥生成成功"
    log "Private Key: ${rePrivateKey:0:10}..."
    log "Public Key: ${rePublicKey:0:10}..."
}

reconfig(){
    log "配置Xray服务..."
    
    # Ensure config directory exists
    mkdir -p /usr/local/etc/xray
    
cat >/usr/local/etc/xray/config.json<<EOF
{
    "inbounds": [
        {
            "port": $getPort,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$v2uuid",
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "dest": "$getSni:443",
                    "xver": 0,
                    "serverNames": [
                        "$getSni"
                    ],
                    "privateKey": "$rePrivateKey",
                    "minClientVer": "",
                    "maxClientVer": "",
                    "maxTimeDiff": 0,
                    "shortIds": [
                        "88"
                    ]
                }
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "tag": "direct"
        },
        {
            "protocol": "blackhole",
            "tag": "blocked"
        }
    ]    
}
EOF

    # Start and enable Xray service with proper error handling
    log "启动Xray服务..."
    if [[ "$SERVICE_MANAGER" == "systemctl" ]]; then
        if ! systemctl enable xray.service; then
            yellow "启用Xray服务失败，尝试继续..."
        fi
        if ! systemctl restart xray.service; then
            error_exit "启动Xray服务失败"
        fi
        # Check if service is running
        sleep 2
        if ! systemctl is-active --quiet xray.service; then
            red "Xray服务未正常启动，检查配置..."
            systemctl status xray.service
            error_exit "Xray服务启动失败"
        fi
    else
        # Fallback for non-systemd systems
        if ! service xray start; then
            error_exit "启动Xray服务失败"
        fi
    fi
    
    green "Xray服务启动成功"
    
    # Clean up installation files
    rm -f tcp-wss.sh install-release.sh reality.sh

cat >/usr/local/etc/xray/reclient.json<<EOF
{
===========配置参数=============
代理模式：vless
地址：$(getIP)
端口：${getPort}
UUID：${v2uuid}
流控：xtls-rprx-vision
传输协议：tcp
Public key：${rePublicKey}
底层传输：reality
SNI: ${getSni}
shortIds: 88
====================================
vless://${v2uuid}@$(getIP):${getPort}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${getSni}&fp=chrome&pbk=${rePublicKey}&sid=88&type=tcp&headerType=none#1024-reality

}
EOF

    clear
}

client_re(){
    echo
    green "安装已经完成"
    echo
    green "===========reality配置参数============"
    echo "代理模式：vless"
    echo "地址：$(getIP)"
    echo "端口：${getPort}"
    echo "UUID：${v2uuid}"
    echo "流控：xtls-rprx-vision"
    echo "传输协议：tcp"
    echo "Public key：${rePublicKey}"
    echo "底层传输：reality"
    echo "SNI: ${getSni}"
    echo "shortIds: 88"
    green "===================================="
    echo "vless://${v2uuid}@$(getIP):${getPort}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${getSni}&fp=chrome&pbk=${rePublicKey}&sid=88&type=tcp&headerType=none#1024-reality"
    echo
    log "配置信息已保存到: /usr/local/etc/xray/reclient.json"
}

# Main execution
log "开始Reality安装和配置..."
install_xray
get_keys
reconfig
client_re
green "Reality安装完成！"