#!/usr/bin/env bash
# forum: https://1024.day

set -Eeuo pipefail
IFS=$'\n\t'

# 确保以root用户运行
if [[ $EUID -ne 0 ]]; then
    clear
    echo "错误: 此脚本必须以root身份运行!" 1>&2
    exit 1
fi

# 全局变量定义
SERVER_IP=""
LOG_FILE="/var/log/reality_install.log"
BACKUP_DIR="/tmp/reality_backup_$(date +%s)"

# 创建日志目录
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
touch "$LOG_FILE" 2>/dev/null || {
    echo "无法创建日志文件，将只在屏幕显示输出"
    LOG_FILE=""
}

# 颜色输出函数 - 带日志
print_red() {
    echo -e "\033[31m$1\033[0m"
    [[ -n "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

print_green() {
    echo -e "\033[32m$1\033[0m"
    [[ -n "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

print_yellow() {
    echo -e "\033[33m$1\033[0m"
    [[ -n "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 只显示颜色文字，不写入日志
display_red() {
    echo -e "\033[31m$1\033[0m"
}

display_green() {
    echo -e "\033[32m$1\033[0m"
}

display_yellow() {
    echo -e "\033[33m$1\033[0m"
}

# 日志记录函数 - 只写入日志，不显示在屏幕上
log_only() {
    [[ -n "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 日志记录函数 - 同时显示在屏幕和日志
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    [[ -n "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 错误处理函数
exit_with_error() {
    print_red "错误: $1"
    [[ -n "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] 错误: $1" >> "$LOG_FILE"
    cleanup_on_error
    exit 1
}

# 清理函数
cleanup_on_error() {
    log_info "执行错误清理..."
    if command_exists systemctl; then
        systemctl stop xray.service 2>/dev/null || true
    elif command_exists service; then
        service xray stop 2>/dev/null || true
    fi
    rm -f /tmp/xray-install.sh
    log_info "错误清理完成"
}

# 信号陷阱
trap 'exit_with_error "脚本被中断"' INT TERM

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 验证端口参数
validate_port() {
    local port_to_check="$1"
    if [[ ! "$port_to_check" =~ ^[0-9]+$ ]] || [[ "$port_to_check" -lt 1 ]] || [[ "$port_to_check" -gt 65535 ]]; then
        exit_with_error "端口号无效: $port_to_check (必须在1-65535之间)"
        return 1
    fi
    return 0
}

# 验证域名格式
validate_domain() {
    local domain_to_check="$1"
    if [[ ! "$domain_to_check" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        exit_with_error "域名格式无效: $domain_to_check"
        return 1
    fi
    return 0
}

# 检测系统发行版
detect_distribution() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        OS_ID=${ID:-unknown}
        OS_VERSION=${VERSION_ID:-unknown}
        OS_CODENAME=${VERSION_CODENAME:-}
    elif [[ -f /etc/redhat-release ]]; then
        if grep -q "CentOS" /etc/redhat-release; then
            OS_ID="centos"
            OS_VERSION=$(grep -oE '[0-9]+(\.[0-9]+)?' /etc/redhat-release | head -1)
        elif grep -q "Red Hat" /etc/redhat-release; then
            OS_ID="rhel"
            OS_VERSION=$(grep -oE '[0-9]+(\.[0-9]+)?' /etc/redhat-release | head -1)
        fi
    elif [[ -f /etc/debian_version ]]; then
        OS_ID="debian"
        OS_VERSION=$(cat /etc/debian_version)
    else
        OS_ID="unknown"
        OS_VERSION="unknown"
    fi
    
    if [[ "$OS_ID" == "unknown" ]]; then
        print_yellow "无法确定系统类型，将尝试继续安装..."
    fi
    
    log_info "检测到系统: $OS_ID $OS_VERSION"
}

# 增强包管理器检测
detect_package_manager() {
    if command_exists apt-get; then
        PKG_MANAGER="apt"
        PKG_UPDATE="apt-get update -y"
        PKG_INSTALL="apt-get install -y"
        # 检查dpkg是否被锁
        while fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
            log_info "等待dpkg锁释放..."
            sleep 3
        done
    elif command_exists yum; then
        PKG_MANAGER="yum"
        PKG_UPDATE="yum makecache"
        PKG_INSTALL="yum install -y"
        # 安装EPEL仓库
        yum install -y epel-release 2>/dev/null || true
    elif command_exists dnf; then
        PKG_MANAGER="dnf"
        PKG_UPDATE="dnf makecache"
        PKG_INSTALL="dnf install -y"
        # 安装EPEL仓库
        dnf install -y epel-release 2>/dev/null || true
    elif command_exists zypper; then
        PKG_MANAGER="zypper"
        PKG_UPDATE="zypper ref"
        PKG_INSTALL="zypper in -y"
    elif command_exists pacman; then
        PKG_MANAGER="pacman"
        PKG_UPDATE="pacman -Sy"
        PKG_INSTALL="pacman -S --noconfirm"
    else
        exit_with_error "不支持的包管理器，请手动安装依赖包"
    fi
    log_info "检测到包管理器: $PKG_MANAGER"
}

# 检查服务管理器
check_service_manager() {
    if command_exists systemctl && systemctl --version >/dev/null 2>&1; then
        SERVICE_MANAGER="systemctl"
        SERVICE_ENABLE="systemctl enable"
        SERVICE_START="systemctl start"
        SERVICE_RESTART="systemctl restart"
        SERVICE_STATUS="systemctl status"
        SERVICE_STOP="systemctl stop"
    elif command_exists service; then
        SERVICE_MANAGER="service"
        SERVICE_ENABLE="chkconfig --add"
        SERVICE_START="service"
        SERVICE_RESTART="service"
        SERVICE_STATUS="service"
        SERVICE_STOP="service"
    else
        exit_with_error "不支持的服务管理器"
    fi
    log_info "检测到服务管理器: $SERVICE_MANAGER"
}

# 获取系统IP地址 - 重写为静默版本，只返回IP，不输出任何日志
get_server_ip_silent() {
    local server_ip=""
    local ip_sources=(
        "http://www.cloudflare.com/cdn-cgi/trace"
        "https://ipv4.icanhazip.com/"
        "https://ipinfo.io/ip"
        "https://api.ipify.org"
        "https://checkip.amazonaws.com"
    )
    
    # 优先尝试IPv4
    for source in "${ip_sources[@]}"; do
        if [[ "$source" == *"cloudflare"* ]]; then
            server_ip=$(curl -s -4 --connect-timeout 10 --max-time 15 "$source" 2>/dev/null | grep "ip=" | awk -F "=" '{print $2}' | tr -d '\r\n' || true)
        else
            server_ip=$(curl -s -4 --connect-timeout 10 --max-time 15 "$source" 2>/dev/null | tr -d '\r\n' || true)
        fi
        
        # 验证IP地址格式
        if [[ "$server_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            # 验证IP地址范围
            local valid=true
            IFS='.' read -ra ADDR <<< "$server_ip"
            for i in "${ADDR[@]}"; do
                if [[ $i -gt 255 ]]; then
                    valid=false
                    break
                fi
            done
            if [[ "$valid" == "true" ]]; then
                log_only "成功获取IPv4地址: $server_ip"
                echo "$server_ip"
                return 0
            fi
        fi
        
        server_ip=""
    done
    
    # 如果IPv4失败，尝试IPv6
    log_only "尝试获取IPv6地址..."
    server_ip=$(curl -s -6 --connect-timeout 10 --max-time 15 "http://www.cloudflare.com/cdn-cgi/trace" 2>/dev/null | grep "ip=" | awk -F "=" '{print $2}' | tr -d '\r\n' || true)
    
    # 基本IPv6验证
    if [[ "$server_ip" =~ ^[0-9a-fA-F:]+$ ]] && [[ "$server_ip" == *":"* ]]; then
        log_only "成功获取IPv6地址: $server_ip"
        echo "$server_ip"
        return 0
    fi
    
    exit_with_error "无法获取服务器IP地址，请检查网络连接"
    return 1
}

# 生成UUID
generate_uuid() {
    local uuid=""
    if [[ -r /proc/sys/kernel/random/uuid ]]; then
        uuid=$(cat /proc/sys/kernel/random/uuid)
    elif command_exists uuidgen; then
        uuid=$(uuidgen)
    else
        # 回退到Python生成UUID
        uuid=$(python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || \
               python -c "import uuid; print(uuid.uuid4())" 2>/dev/null || \
               exit_with_error "无法生成UUID，请安装uuidgen或python")
    fi
    
    # 验证UUID格式
    if [[ ! "$uuid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        exit_with_error "生成的UUID格式无效: $uuid"
    fi
    
    echo "$uuid"
}

# 安装Xray
install_xray() { 
    log_info "开始安装系统依赖和Xray..."
    
    # 创建备份目录
    mkdir -p "$BACKUP_DIR"
    
    # 备份现有的xray配置
    if [[ -f "/usr/local/etc/xray/config.json" ]]; then
        log_info "备份现有Xray配置..."
        cp "/usr/local/etc/xray/config.json" "$BACKUP_DIR/config.json.backup"
    fi
    
    # 更新包列表
    log_info "更新软件包列表..."
    local retry_count=0
    while [[ $retry_count -lt 3 ]]; do
        if eval "$PKG_UPDATE"; then
            break
        fi
        retry_count=$((retry_count + 1))
        log_info "更新失败，重试 $retry_count/3..."
        sleep 5
    done
    
    if [[ $retry_count -eq 3 ]]; then
        exit_with_error "更新软件包列表失败"
    fi
    
    # 安装基础依赖
    log_info "安装基础依赖包..."
    local basic_packages=""
    
    case $PKG_MANAGER in
        "apt")
            basic_packages="curl wget gawk ca-certificates gnupg lsb-release unzip"
            ;;
        "yum"|"dnf")
            basic_packages="curl wget gawk ca-certificates gnupg2 unzip"
            ;;
        "zypper")
            basic_packages="curl wget gawk ca-certificates gnupg2 unzip"
            ;;
        "pacman")
            basic_packages="curl wget gawk ca-certificates gnupg unzip"
            ;;
    esac
    
    # 安装包带重试机制
    retry_count=0
    while [[ $retry_count -lt 3 ]]; do
        if eval "$PKG_INSTALL $basic_packages"; then
            break
        fi
        retry_count=$((retry_count + 1))
        log_info "安装依赖失败，重试 $retry_count/3..."
        sleep 5
    done
    
    if [[ $retry_count -eq 3 ]]; then
        exit_with_error "安装基础依赖包失败"
    fi
    
    # 验证关键工具是否可用
    for tool in curl wget; do
        if ! command_exists "$tool"; then
            exit_with_error "$tool 安装失败，无法继续"
        fi
    done
    
    print_green "基础依赖安装完成"
    
    # 安装Xray
    log_info "下载并安装Xray..."
    local install_script_url="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"
    local script_path="/tmp/xray-install.sh"
    
    # 下载安装脚本带重试机制
    retry_count=0
    while [[ $retry_count -lt 3 ]]; do
        log_info "下载Xray安装脚本 (尝试 $((retry_count + 1))/3)..."
        if curl -L --connect-timeout 30 --max-time 300 --retry 2 --retry-delay 5 "$install_script_url" -o "$script_path"; then
            # 验证脚本下载是否正确
            if [[ -s "$script_path" ]] && head -1 "$script_path" | grep -q "#!/"; then
                chmod +x "$script_path"
                break
            else
                log_info "下载的脚本文件已损坏"
            fi
        fi
        retry_count=$((retry_count + 1))
        rm -f "$script_path"
        sleep 5
    done
    
    if [[ $retry_count -eq 3 ]]; then
        exit_with_error "下载Xray安装脚本失败"
    fi
    
    # 运行安装脚本带错误处理
    log_info "执行Xray安装脚本..."
    if ! timeout 600 bash "$script_path" install; then
        exit_with_error "Xray安装失败或超时"
    fi
    
    # 验证Xray安装
    if [[ ! -f "/usr/local/bin/xray" ]] || [[ ! -x "/usr/local/bin/xray" ]]; then
        exit_with_error "Xray安装验证失败"
    fi
    
    # 测试xray二进制文件
    if ! /usr/local/bin/xray version >/dev/null 2>&1; then
        exit_with_error "Xray二进制文件测试失败"
    fi
    
    # 清理
    rm -f "$script_path"
    
    print_green "Xray安装完成"
}

# 生成密钥对
generate_keys() {
    log_info "生成Reality密钥对..."
    
    # 验证xray是否可用
    if [[ ! -f "/usr/local/bin/xray" ]] || [[ ! -x "/usr/local/bin/xray" ]]; then
        exit_with_error "Xray未正确安装，无法生成密钥"
    fi
    
    # 测试xray二进制文件
    if ! /usr/local/bin/xray version >/dev/null 2>&1; then
        exit_with_error "Xray二进制文件已损坏或不兼容"
    fi
    
    local raw=""
    local tries=0
    local max_tries=5
    
    while (( tries < max_tries )); do
        log_info "尝试生成密钥 ($((tries + 1))/$max_tries)..."
        
        # 使用超时防止挂起
        if raw=$(timeout 30 /usr/local/bin/xray x25519 2>/dev/null); then
            if [[ -n "$raw" ]]; then
                break
            fi
        fi
        
        ((tries++))
        if (( tries < max_tries )); then
            log_info "密钥生成失败，等待重试..."
            sleep 2
        fi
    done
    
    if [[ -z "$raw" ]]; then
        exit_with_error "生成X25519密钥失败，已尝试$max_tries次"
    fi
    
    log_info "解析密钥输出..."
    
    # 解析私钥
    RE_PRIVATE_KEY=$(echo "$raw" | grep -iE "(private|privatekey)" | awk -F ':' '{print $2}' | tr -d ' \r\n\t' || true)
    # 解析公钥，仅使用 Public/PublicKey 字段
    RE_PUBLIC_KEY=$(echo "$raw" | grep -iE "(public|publickey)" | awk -F ':' '{print $2}' | tr -d ' \r\n\t' || true)
    
    # 验证提取的密钥
    if [[ -z "$RE_PRIVATE_KEY" || -z "$RE_PUBLIC_KEY" ]]; then
        print_red "密钥解析失败。原始输出:"
        echo "================================"
        echo "$raw"
        echo "================================"
        print_red "提取的私钥: '$RE_PRIVATE_KEY'"
        print_red "提取的公钥: '$RE_PUBLIC_KEY'"
        print_red "注意: 公钥首先使用Password字段，然后是Public字段"
        exit_with_error "无法正确解析生成的密钥"
    fi
    
    # 验证密钥格式 (X25519密钥应该是44个字符的base64)
    if [[ ${#RE_PRIVATE_KEY} -lt 40 || ${#RE_PUBLIC_KEY} -lt 40 ]]; then
        exit_with_error "生成的密钥格式不正确 (私钥长度: ${#RE_PRIVATE_KEY}, 公钥长度: ${#RE_PUBLIC_KEY})"
    fi
    
    # 额外验证 - 密钥应该是URL安全的base64类型
    if [[ ! "$RE_PRIVATE_KEY" =~ ^[A-Za-z0-9+/=_-]+$ ]] || [[ ! "$RE_PUBLIC_KEY" =~ ^[A-Za-z0-9+/=_-]+$ ]]; then
        exit_with_error "生成的密钥包含非法字符"
    fi
    
    print_green "密钥生成成功"
    log_info "私钥: ${RE_PRIVATE_KEY:0:10}..."
    log_info "公钥: ${RE_PUBLIC_KEY:0:10}..."
}

# 生成 shortId（1-8 字节十六进制，默认 2 字节）
generate_short_id() {
    local bytes=${1:-2}
    bytes=$(( bytes < 1 ? 1 : (bytes > 8 ? 8 : bytes) ))
    local sid=""
    for ((i=0; i<bytes; i++)); do
        sid+=$(printf "%02x" $((RANDOM%256)))
    done
    echo "$sid"
}

# 配置Xray
configure_xray() {
    log_info "配置Xray服务..."
    
    # 确保配置目录存在
    mkdir -p /usr/local/etc/xray
    chmod 755 /usr/local/etc/xray
    
    # 验证必要变量
    local required_vars=("PORT_NUMBER" "UUID" "SERVER_SNI" "RE_PRIVATE_KEY")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            exit_with_error "必要变量 $var 未设置"
        fi
    done
    
    # 创建配置
    log_info "生成Xray配置文件..."
    
    # 先使用临时文件，然后移动到最终位置
    local temp_config="/tmp/xray_config_$$.json"
    
cat > "$temp_config" <<EOF
{
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [
        {
            "port": $PORT_NUMBER,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$UUID",
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
                    "dest": "$SERVER_SNI:443",
                    "xver": 0,
                    "serverNames": [
                        "$SERVER_SNI"
                    ],
                    "privateKey": "$RE_PRIVATE_KEY",
                    "minClientVer": "",
                    "maxClientVer": "",
                    "maxTimeDiff": 0,
                    "shortIds": [
                        "$SHORT_ID"
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
    
    # 移动到最终位置
    mv "$temp_config" /usr/local/etc/xray/config.json
    chmod 644 /usr/local/etc/xray/config.json
    
    # 测试配置
    log_info "验证Xray配置..."
    if ! /usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json >/dev/null 2>&1; then
        exit_with_error "Xray配置验证失败"
    fi
    
    print_green "配置文件验证成功"
    
    # 启动并启用Xray服务
    log_info "启动Xray服务..."
    if [[ "$SERVICE_MANAGER" == "systemctl" ]]; then
        # 如果服务在运行，先停止
        systemctl stop xray.service 2>/dev/null || true
        
        # 启用服务
        if ! systemctl enable xray.service; then
            print_yellow "启用Xray服务失败，尝试继续..."
        fi
        
        # 启动服务
        if ! systemctl start xray.service; then
            log_info "直接启动失败，尝试重启..."
            if ! systemctl restart xray.service; then
                print_red "Xray服务启动失败，检查详细错误信息:"
                systemctl status xray.service --no-pager || true
                journalctl -u xray.service --no-pager -n 20 || true
                exit_with_error "启动Xray服务失败"
            fi
        fi
        
        # 等待并检查服务是否运行
        sleep 3
        local check_attempts=0
        while [[ $check_attempts -lt 5 ]]; do
            if systemctl is-active --quiet xray.service; then
                break
            fi
            ((check_attempts++))
            log_info "等待服务启动... ($check_attempts/5)"
            sleep 2
        done
        
        if ! systemctl is-active --quiet xray.service; then
            print_red "Xray服务未正常运行，服务状态:"
            systemctl status xray.service --no-pager || true
            exit_with_error "Xray服务启动失败"
        fi
    else
        # 对非systemd系统的回退方案
        if ! service xray restart; then
            exit_with_error "启动Xray服务失败"
        fi
    fi
    
    print_green "Xray服务启动成功"
    
    # 生成客户端配置
    generate_client_config
    
    # 清理安装文件
    log_info "清理安装文件..."
    # keep scripts for troubleshooting; do not self-delete
    
    clear
}

# 生成客户端配置
generate_client_config() {
    log_info "生成客户端配置..."
    
    # 验证所有必要参数
    if [[ -z "$SERVER_IP" || -z "$PORT_NUMBER" || -z "$UUID" || -z "$RE_PUBLIC_KEY" || -z "$SERVER_SNI" ]]; then
        exit_with_error "生成客户端配置时缺少必要参数"
    fi
    
    # 生成客户端配置文件
    cat > /usr/local/etc/xray/reclient.json <<EOF
{
"配置参数": {
    "代理模式": "vless",
    "地址": "$SERVER_IP",
    "端口": $PORT_NUMBER,
    "UUID": "$UUID",
    "流控": "xtls-rprx-vision", 
    "传输协议": "tcp",
    "公钥": "$RE_PUBLIC_KEY",
    "底层传输": "reality",
    "SNI": "$SERVER_SNI",
    "shortIds": "$SHORT_ID"
},
"连接链接": "vless://$UUID@$SERVER_IP:$PORT_NUMBER?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$SERVER_SNI&fp=chrome&pbk=$RE_PUBLIC_KEY&sid=$SHORT_ID&type=tcp&headerType=none#1024-reality"
}
EOF
    
    chmod 644 /usr/local/etc/xray/reclient.json
    log_info "客户端配置已保存到: /usr/local/etc/xray/reclient.json"
}

# 显示Xray服务状态
display_xray_status() {
    echo
    display_green "Xray服务状态:"
    if [[ "$SERVICE_MANAGER" == "systemctl" ]]; then
        systemctl status xray.service --no-pager || true
    else
        service xray status || true
    fi
}

# 显示客户端配置 - 完全干净版本，无日志输出
display_client_config() {
    echo
    display_green "安装已经完成"
    echo
    display_green "=========== Reality配置参数 ==========="
    echo "代理模式：vless"
    echo "地址：$SERVER_IP"
    echo "端口：$PORT_NUMBER"
    echo "UUID：$UUID"
    echo "流控：xtls-rprx-vision"
    echo "传输协议：tcp"
    echo "Public key：$RE_PUBLIC_KEY"
    echo "底层传输：reality"
    echo "SNI：$SERVER_SNI"
    echo "shortIds：$SHORT_ID"
    display_green "========================================"
    echo
    display_green "客户端连接链接："
    echo "vless://$UUID@$SERVER_IP:$PORT_NUMBER?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$SERVER_SNI&fp=chrome&pbk=$RE_PUBLIC_KEY&sid=$SHORT_ID&type=tcp&headerType=none#1024-reality"
    echo
    display_green "配置信息已保存到: /usr/local/etc/xray/reclient.json"
    if [[ -n "$LOG_FILE" ]]; then
        display_green "安装日志文件位置: $LOG_FILE"
    fi
}

# 获取用户输入
get_user_input() {
    log_info "获取用户配置参数..."
    
    # 生成UUID
    UUID=$(generate_uuid)
    log_info "已生成UUID: $UUID"
    
    # 获取端口号
    local port_input
    read -r -t 15 -p "回车或等待15秒为默认端口443，或者自定义端口请输入(1-65535)："  port_input
    if [[ -z "$port_input" ]]; then
        PORT_NUMBER=443
        echo ""
    else
        if ! validate_port "$port_input"; then
            PORT_NUMBER=443
            print_yellow "端口号无效，使用默认端口443"
        else
            PORT_NUMBER="$port_input"
        fi
    fi
    log_info "使用端口: $PORT_NUMBER"
    
    echo
    
    # 获取SNI
    local sni_input
    read -r -t 30 -p "回车或等待30秒为默认域名 www.amazon.com，或者自定义SNI请输入："  sni_input
    if [[ -z "$sni_input" ]]; then
        SERVER_SNI="www.amazon.com"
        echo ""
    else
        if ! validate_domain "$sni_input"; then
            SERVER_SNI="www.amazon.com"
            print_yellow "域名格式无效，使用默认域名www.amazon.com"
        else
            SERVER_SNI="$sni_input"
        fi
    fi
    log_info "使用SNI: $SERVER_SNI"
}

# 主函数
main() {
    log_info "开始Reality安装和配置..."
    log_info "脚本版本: Reality Plus $(date)"
    
    # 初始化系统
    detect_distribution
    detect_package_manager
    check_service_manager
    
    # 获取用户输入
    get_user_input
    
    # 获取服务器IP - 静默获取IP，不在屏幕输出任何日志
    log_only "尝试获取服务器IP地址..."
    SERVER_IP=$(get_server_ip_silent)
    log_only "服务器IP地址: $SERVER_IP"
    
    # 安装Xray
    install_xray

    # 生成密钥
    generate_keys

    # 生成shortId（默认2字节十六进制，例如 "88a1"）
    SHORT_ID=$(generate_short_id 2)

    # 配置并启动服务
    configure_xray

    # Open firewall if requested
    open_firewall_tcp "$PORT_NUMBER"

    # 显示配置 - 使用无日志输出版本
    display_client_config
    
    # 显示服务状态
    display_xray_status
    
    log_only "Reality安装完成！"
    log_only "安装成功完成，时间: $(date)"
}

# 执行主函数
main "$@"
# Optional firewall opening when FIREWALL_AUTO=1
open_firewall_tcp() {
    local port="$1"
    [[ "${FIREWALL_AUTO:-0}" != "1" ]] && return 0
    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -qi "Status: active"; then
            ufw allow "${port}/tcp" || true
        fi
    elif command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
        firewall-cmd --add-port="${port}/tcp" --permanent || true
        firewall-cmd --reload || true
    fi
}
