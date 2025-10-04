#!/usr/bin/env bash
# Issues https://1024.day

set -Eeuo pipefail
IFS=$'\n\t'

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "Error: This script must be run as root!"
    exit 1
fi

GREEN="\033[32m"; YELLOW="\033[33m"; RED="\033[31m"; RESET="\033[0m"

LIMITS_D_FILE="/etc/security/limits.d/99-nofile.conf"
SYSCTL_D_FILE="/etc/sysctl.d/99-tuning.conf"
SYSTEMD_DROPIN_DIR="/etc/systemd/system.conf.d"
SYSTEMD_DROPIN_FILE="${SYSTEMD_DROPIN_DIR}/99-limits.conf"

apply_limits() {
    mkdir -p "$(dirname "$LIMITS_D_FILE")"
    cat > "$LIMITS_D_FILE" <<EOF
* soft     nproc    131072
* hard     nproc    131072
* soft     nofile   262144
* hard     nofile   262144
root soft  nproc    131072
root hard  nproc    131072
root soft  nofile   262144
root hard  nofile   262144
EOF

    # Ensure pam_limits is active (best-effort)
    for pamf in /etc/pam.d/common-session /etc/pam.d/common-session-noninteractive; do
        if [[ -f "$pamf" ]] && ! grep -q "^session\s\+required\s\+pam_limits.so" "$pamf"; then
            echo "session required pam_limits.so" >> "$pamf"
        fi
    done

    # systemd limits via drop-in
    mkdir -p "$SYSTEMD_DROPIN_DIR"
    cat > "$SYSTEMD_DROPIN_FILE" <<EOF
[Manager]
DefaultLimitNOFILE=262144
DefaultLimitNPROC=131072
EOF
}

apply_sysctl() {
    cat > "$SYSCTL_D_FILE" <<EOF
fs.file-max = 524288
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_rmem = 8192 262144 536870912
net.ipv4.tcp_wmem = 4096 16384 536870912
net.ipv4.tcp_adv_win_scale = -2
net.ipv4.tcp_notsent_lowat = 131072
EOF
    sysctl --system >/dev/null 2>&1 || sysctl -p "$SYSCTL_D_FILE" || true
}

revert() {
    rm -f "$LIMITS_D_FILE" "$SYSCTL_D_FILE"
    rm -f "$SYSTEMD_DROPIN_FILE"
    echo -e "${GREEN}Reverted tuning files. You may need to restart services to apply changes.${RESET}"
}

status() {
    echo -e "${YELLOW}Limits file:${RESET} $LIMITS_D_FILE $( [[ -f "$LIMITS_D_FILE" ]] && echo '[present]' || echo '[missing]' )"
    echo -e "${YELLOW}Sysctl file:${RESET} $SYSCTL_D_FILE $( [[ -f "$SYSCTL_D_FILE" ]] && echo '[present]' || echo '[missing]' )"
    echo -e "${YELLOW}Systemd drop-in:${RESET} $SYSTEMD_DROPIN_FILE $( [[ -f "$SYSTEMD_DROPIN_FILE" ]] && echo '[present]' || echo '[missing]' )"
    echo -e "${YELLOW}Current tcp_congestion_control:${RESET} $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo 'unknown')"
}

usage() {
    cat <<USAGE
Usage: $0 [--apply|--revert|--status]

  --apply   Apply tuning (idempotent). No reboot is performed.
  --revert  Remove tuning drop-in files.
  --status  Show current tuning status.

Note: Some changes may require service restart or reboot to take full effect.
USAGE
}

case "${1:-}" in
    --apply)
        apply_limits
        apply_sysctl
        echo -e "${GREEN}Tuning applied.${RESET}"
        ;;
    --revert)
        revert
        ;;
    --status)
        status
        ;;
    *)
        usage
        ;;
esac

