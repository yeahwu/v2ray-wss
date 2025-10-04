# Improvement Plan and Progress

This document tracks the ongoing optimization roadmap and stage-by-stage progress.

## Overview

Goal: Improve security, correctness, portability, and maintainability of the installation scripts and tooling for Shadowsocks-rust, V2Ray (WS/WSS), Reality (Xray), Hysteria2, and HTTPS forward proxy.

## Phases

1) Baseline Hardening (In Progress)
- Unify shebangs to bash and enable strict mode
- Add safe defaults and environment toggles (e.g., TZ gating)
- Remove in-script self-deletions
- Parameterize ACME email
- Prepare for idempotent operations and safer downloads

2) Protocol & Web Server Correctness (In Progress)
- Nginx: separate site config, modern TLS (1.2/1.3), ciphers, enable logs [done]
- ACME: switch to webroot; customizable email [done]
- V2Ray (VMess+WS): align inbound and share-link fields; fix `security` [done for ws.sh; wss prints aligned]
- HTTPS proxy (Caddy): clarified auto-cert via host matcher and global email; checksum validation for release tarball [done]
- Client outputs normalized: machine-readable JSON + human-readable TXT [done]

3) Reality/Hy2/SS-rust Enhancements (In Progress)
- Reality: robust key parsing (PublicKey) [done], random shortIds [done], multi-user optional [todo]
- Hysteria2: real-cert option via HY2_CERT/HY2_KEY and HY2_SNI [done]; QUIC windows defaults [kept]
- Shadowsocks-rust: version pin via SS_VERSION and checksum via SS_SHA256 [done]; 2022 ciphers option [todo]

4) System Tuning & Idempotency (In Progress)
- Converted `tcp-window.sh` to idempotent tuning via sysctl.d/limits.d [done]
- Removed forced reboot; added `--apply`/`--revert`/`--status` [done]

5) Automation & Docs (In Progress)
- ShellCheck/shfmt CI [done]
- Expanded README with env flags and tuning usage [done]
- Firewall/SELinux guidance [todo]
- Add `uninstall.sh` and `doctor.sh` [done]

## Stage Logs

### Phase 1 — Baseline Hardening
Applied:
- Shebangs unified to `#!/usr/bin/env bash`
- Added `set -Eeuo pipefail` and safe IFS
- Timezone change gated behind `TZ_AUTO=1` (default off)
- ACME email parameterized via `ACME_EMAIL` (default `admin@example.com`)
- Removed in-script self-deletion lines

Next:
- Introduce common utility library without breaking standalone usage
- Add optional checksum verification helpers
