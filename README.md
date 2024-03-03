
搭建 Shadowsocks-rust， V2ray+ Nginx + WebSocket 和 Reality 代理脚本，支持 Debian、Ubuntu、Centos，并支持甲骨文ARM平台。

简单点讲，没域名的用户可以安装 Reality 和 ws 代理，有域名的可以安装 V2ray+ Nginx + WebSocket 代理，各取所需。

运行脚本：

```
wget https://raw.githubusercontent.com/yeahwu/v2ray-wss/main/tcp-wss.sh && bash tcp-wss.sh
```

**便宜VPS推荐：** https://hostalk.net/deals.html

![image](https://github.com/yeahwu/v2ray-wss/assets/13328328/cf45b803-a5f1-4fe6-aa53-765416bb37e0)

已测试系统如下：

Debian 9, 10, 11, 12

Ubuntu 16.04, 18.04, 20.04, 22.04

CentOS 7

WSS客户端配置信息保存在：
`cat /usr/local/etc/v2ray/client.json`

Shadowsocks客户端配置信息：
`cat /etc/shadowsocks/config.json`

Reality客户端配置信息保存在：
`cat /usr/local/etc/xray/reclient.json`

卸载方法如下：
https://1024.day/d/1296

**提醒：连不上的朋友，建议先检查一下服务器自带防火墙有没有关闭？**
