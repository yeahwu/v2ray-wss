
搭建 Shadowsocks-libev， V2ray+ Nginx + WebSocket 和 Reality 代理脚本，支持 Debian、Ubuntu、Centos，并支持甲骨文ARM平台。

简单点讲，没域名的用户可以安装 Shadowsocks-libev 和 Reality 代理，有域名的可以安装 V2ray+ Nginx + WebSocket 代理，各取所需。

运行脚本：

```
wget https://raw.githubusercontent.com/yeahwu/v2ray-wss/main/tcp-wss.sh && bash tcp-wss.sh
```

便宜VPS推荐：https://hostalk.net/deals.html

![image](https://user-images.githubusercontent.com/13328328/235636662-5df2a97d-dd2c-4ca1-af0d-1b4e69119111.png)

已测试系统如下：

Debian 9, 10, 11

Ubuntu 16.04, 18.04, 20.04

CentOS 7

WSS客户端配置信息保存在：
`cat /usr/local/etc/v2ray/client.json`

Shadowsocks客户端配置信息：
`cat /etc/shadowsocks-libev/config.json`

Reality客户端配置信息保存在：
`cat /usr/local/etc/xray/reclient.json`

卸载方法如下：
https://1024.day/d/1296

~~ 提醒：连不上的朋友，建议先检查一下服务器自带防火墙有没有关闭？~~
