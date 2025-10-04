搭建 Shadowsocks-rust， V2ray+ Nginx + WebSocket 和 Reality, Hysteria2, https 正向代理脚本，支持 Debian、Ubuntu、Centos，并支持甲骨文ARM平台。

简单点讲，没域名的用户可以安装 Reality 和 hy2 代理，有域名的可以安装 V2ray+wss 和 https 正向代理，各取所需。

运行脚本：

```
wget git.io/tcp-wss.sh && bash tcp-wss.sh
```

**便宜VPS推荐：** https://hostalk.net/deals.html

![image](https://github.com/user-attachments/assets/0b6db263-a8ee-48c5-8605-048e3e25c967)

已测试系统如下：

Debian 9, 10, 11, 12

Ubuntu 16.04, 18.04, 20.04, 22.04

CentOS 7

* WSS客户端配置信息：
  - 机器可读 JSON: `/usr/local/etc/v2ray/client.json`
  - 可读文本: `/usr/local/etc/v2ray/client.txt`

* Shadowsocks客户端配置信息：
`cat /etc/shadowsocks/config.json`

* Reality客户端配置信息保存在：
`cat /usr/local/etc/xray/reclient.json`

* Hysteria2客户端配置信息保存在：
`cat /etc/hysteria/hyclient.json`

* Https正向代理客户端配置信息：
  - 机器可读 JSON: `/etc/caddy/https.json`
  - 可读文本: `/etc/caddy/https.txt`

卸载方法如下：
https://1024.day/d/1296

**提醒：连不上的朋友，建议先检查一下服务器自带防火墙有没有关闭？**

环境变量与参数（可选）：

- `TZ_AUTO=1` 与可选 `TZ_VALUE=Asia/Shanghai`：启用脚本内时区设置（默认不修改时区）。
- `ACME_EMAIL=you@example.com`：`v2ray+ws+tls` 与 HTTPS（Caddy）申请证书使用的邮箱（默认 `admin@example.com`）。
- `HY2_CERT=/path/server.crt`、`HY2_KEY=/path/server.key`、`HY2_SNI=example.com`：Hysteria2 使用真实证书（存在时客户端将不再跳过证书验证）。
- `SS_VERSION=vX.Y.Z`、`SS_SHA256=<sha256>`：固定安装 Shadowsocks-rust 的版本并可选校验下载的完整性。
- `FIREWALL_AUTO=1`：安装后自动尝试放通所需端口（UFW/Firewalld）。
  - WS/WSS: 80、443（WSS 可自定义端口）
  - Reality: 指定 TCP 端口
  - Hysteria2: 指定 UDP 端口
  - HTTPS 正向代理: 80、443

TCP/系统调优脚本（可选）：

- 使用方式：`bash tcp-window.sh --apply` 应用调优；`--revert` 回滚；`--status` 查看状态。
- 实现：通过 `/etc/sysctl.d/99-tuning.conf` 和 `/etc/security/limits.d/99-nofile.conf` 等 drop-in 文件实现，避免覆盖系统默认配置；不再强制重启。

辅助脚本：

- 诊断：`bash doctor.sh` 输出服务状态、监听端口、证书情况、防火墙信息。
- 卸载：`bash uninstall.sh` 选择性移除 V2Ray/Xray/Hysteria2/Shadowsocks/Caddy/Nginx 站点配置。
