# Changelog

## Phase 1 — Baseline Hardening

Date: YYYY-MM-DD

Changes:
- Shebangs unified to `#!/usr/bin/env bash` across all scripts
- Enabled strict mode: `set -Eeuo pipefail` and safe IFS
- Timezone changes gated by `TZ_AUTO=1` (default off)
- ACME email in `tcp-wss.sh` parameterized via `ACME_EMAIL` (default `admin@example.com`)
- Removed self-deleting lines from all scripts (retain scripts for troubleshooting)
- No behavioral protocol changes yet (kept for Phase 2)

Notes:
- Subsequent phases will refine protocol configs, TLS settings, and idempotency.

## Phase 2 — Protocol & Web Server Correctness

Date: YYYY-MM-DD

Changes:
- tcp-wss.sh: Switched ACME issuance to webroot mode; added two-stage Nginx setup (80-only for ACME, then TLS site) with modern TLS (1.2/1.3) and enabled logs
- tcp-wss.sh: Stopped overwriting `nginx.conf`; now uses `conf.d` site files
- tcp-wss.sh: Client output encryption label aligned to `none` for VMess
- ws.sh: Inbound `streamSettings.security` set to `none`; share link `method` set to `none`; client output aligned
 - Normalized client outputs: now write machine-readable JSON and human-readable TXT for VMess (ws/wss)
 - https.sh: Switched to domain-hosted Caddyfile (auto HTTP->HTTPS), added global ACME email, checksum verification for Caddy tarball

Pending:
- HTTPS forward proxy Caddy: clarify auto-cert behavior; add checksum validation
- Further VMess link field normalization if needed across clients

## Phase 3 — Reality/Hy2/SS-rust Enhancements

Date: YYYY-MM-DD

Changes:
- reality.sh: Parse X25519 public key only from Public/PublicKey fields; generate random hex shortId; propagate into config and share-link
- reality.sh: Client output and saved JSON now include dynamic shortId
- hy2.sh: Support using real certificate/key via `HY2_CERT`/`HY2_KEY`; SNI via `HY2_SNI`; client `insecure` auto-set based on certificate type
- ss-rust.sh: Allow version pin using `SS_VERSION`; optional tarball integrity check via `SS_SHA256`

Pending:
- reality.sh: Optional multi-user/multi-port support
- ss-rust.sh: 2022 ciphers option

## Phase 4 — System Tuning & Idempotency

Date: YYYY-MM-DD

Changes:
- Rewrote `tcp-window.sh` to an idempotent, CLI-driven script using `/etc/sysctl.d` and `/etc/security/limits.d` drop-ins
- Added `--apply`, `--revert`, and `--status` commands; removed forced reboot

Notes:
- Some settings may require service restart or reboot to take effect

## Phase 5 — Automation & Docs

Date: YYYY-MM-DD

Changes:
- Added CI workflow for ShellCheck and shfmt to enforce script quality
- Updated README with environment variables and tuning script usage
 - Added uninstall.sh and doctor.sh helper scripts

Pending:
- Add uninstall and doctor scripts; expand docs for firewall/SELinux
