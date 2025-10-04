#!/usr/bin/env bash
# Diagnostic helper for this repository

set -Eeuo pipefail
IFS=$'\n\t'

bold() { printf "\033[1m%s\033[0m\n" "$*"; }

section() {
  echo; bold "== $* =="; }

cmd_ok() { command -v "$1" >/dev/null 2>&1; }

service_status() {
  local svc="$1"
  if cmd_ok systemctl; then
    systemctl is-active --quiet "$svc" && echo active || echo inactive
  else
    echo unknown
  fi
}

show_port_listen() {
  if cmd_ok ss; then
    ss -lntup || true
  elif cmd_ok netstat; then
    netstat -lntup || true
  else
    echo "No ss/netstat available"
  fi
}

extract_domain_nginx() {
  awk '/server_name/{print $2}' /etc/nginx/conf.d/v2ray_wss_tls.conf 2>/dev/null | tr -d ';' | head -1 || true
}

extract_domain_caddy() {
  awk 'NF && $1 !~ /^[{#]/ {print $1; exit}' /etc/caddy/https.caddyfile 2>/dev/null || true
}

check_cert() {
  local crt="$1"
  [[ -f "$crt" ]] || { echo "Not found"; return; }
  openssl x509 -noout -dates -in "$crt" 2>/dev/null || echo "Unable to parse"
}

section "System"
uname -a || true
if [[ -f /etc/os-release ]]; then . /etc/os-release; echo "$NAME $VERSION"; fi

section "Services"
for s in nginx v2ray xray hysteria-server caddy shadowsocks; do
  printf "%-18s %s\n" "$s" "$(service_status "$s")"
done

section "Listening Ports"
show_port_listen

section "Nginx"
cmd_ok nginx && (nginx -t || true)
domain_nginx="$(extract_domain_nginx)"
if [[ -n "$domain_nginx" ]]; then
  echo "Detected domain: $domain_nginx"
  echo "Certificate: /etc/letsencrypt/live/$domain_nginx/fullchain.pem"
  check_cert "/etc/letsencrypt/live/$domain_nginx/fullchain.pem"
fi

section "Caddy"
if [[ -f /etc/caddy/https.caddyfile ]]; then
  echo "Caddyfile present: /etc/caddy/https.caddyfile"
  domain_caddy="$(extract_domain_caddy)"
  [[ -n "$domain_caddy" ]] && echo "Detected site: $domain_caddy"
fi

section "V2Ray/Xray Versions"
/usr/local/bin/v2ray version 2>/dev/null || true
/usr/local/bin/xray version 2>/dev/null || true

section "Firewall"
if cmd_ok ufw; then
  ufw status || true
elif cmd_ok firewall-cmd; then
  firewall-cmd --state || true
  firewall-cmd --list-ports || true
else
  echo "No ufw/firewalld detected"
fi

echo
bold "Diagnostics completed."

