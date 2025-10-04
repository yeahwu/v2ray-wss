#!/usr/bin/env bash
# Uninstall helper for this repository

set -Eeuo pipefail
IFS=$'\n\t'

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Error: must run as root" 1>&2
  exit 1
fi

confirm() { read -r -p "$1 [y/N]: " _ans; [[ "${_ans,,}" == "y" ]]; }

remove_v2ray() {
  systemctl stop v2ray.service 2>/dev/null || true
  systemctl disable v2ray.service 2>/dev/null || true
  rm -rf /usr/local/etc/v2ray 2>/dev/null || true
  echo "V2Ray removed (config)."
}

remove_nginx_site() {
  rm -f /etc/nginx/conf.d/v2ray_wss.conf /etc/nginx/conf.d/v2ray_wss_tls.conf 2>/dev/null || true
  nginx -t && systemctl reload nginx || true
  echo "Nginx v2ray site removed."
}

remove_xray() {
  systemctl stop xray.service 2>/dev/null || true
  systemctl disable xray.service 2>/dev/null || true
  rm -rf /usr/local/etc/xray 2>/dev/null || true
  echo "Xray (Reality) removed (config)."
}

remove_hysteria() {
  systemctl stop hysteria-server.service 2>/dev/null || true
  systemctl disable hysteria-server.service 2>/dev/null || true
  rm -rf /etc/hysteria 2>/dev/null || true
  echo "Hysteria2 removed (config)."
}

remove_shadowsocks() {
  systemctl stop shadowsocks.service 2>/dev/null || true
  systemctl disable shadowsocks.service 2>/dev/null || true
  rm -rf /etc/shadowsocks 2>/dev/null || true
  echo "Shadowsocks-rust removed (config)."
}

remove_caddy() {
  systemctl stop caddy.service 2>/dev/null || true
  systemctl disable caddy.service 2>/dev/null || true
  rm -f /etc/systemd/system/caddy.service 2>/dev/null || true
  systemctl daemon-reload || true
  rm -rf /etc/caddy 2>/dev/null || true
  rm -f /usr/local/caddy 2>/dev/null || true
  echo "Caddy removed."
}

remove_all() {
  remove_v2ray
  remove_nginx_site
  remove_xray
  remove_hysteria
  remove_shadowsocks
  remove_caddy
  echo "All components removed (configs/binaries where safe)."
}

show_menu() {
  clear
  local line="+------------------------------------------+"
  echo "$line"
  printf "| %-40s |\n" "卸载工具 / Uninstall"
  echo "$line"
  printf "| %-40s |\n" " 1) 移除 V2Ray (配置)"
  printf "| %-40s |\n" " 2) 移除 Nginx 站点配置"
  printf "| %-40s |\n" " 3) 移除 Xray (Reality 配置)"
  printf "| %-40s |\n" " 4) 移除 Hysteria2 (配置)"
  printf "| %-40s |\n" " 5) 移除 Shadowsocks-rust (配置)"
  printf "| %-40s |\n" " 6) 移除 Caddy"
  printf "| %-40s |\n" " 7) 全部移除"
  printf "| %-40s |\n" " 0) 退出"
  echo "$line"
  echo
  read -p "请选择 [0-7]: " num
  case "$num" in
    1) confirm "确认移除 V2Ray?" && remove_v2ray ;;
    2) confirm "确认移除 Nginx 站点?" && remove_nginx_site ;;
    3) confirm "确认移除 Xray (Reality)?" && remove_xray ;;
    4) confirm "确认移除 Hysteria2?" && remove_hysteria ;;
    5) confirm "确认移除 Shadowsocks-rust?" && remove_shadowsocks ;;
    6) confirm "确认移除 Caddy?" && remove_caddy ;;
    7) confirm "确认全部移除?" && remove_all ;;
    0) exit 0 ;;
    *) echo "无效选项"; sleep 1 ;;
  esac
}

while true; do
  show_menu
done

