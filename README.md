
搭建 Shadowsocks-libev 和 V2ray+ Nginx + WebSocket 代理脚本，可以选择单独安装或一起安装，支持 Debian、Ubuntu、Centos，并支持甲骨文ARM平台。

简单点讲，没域名的用户可以安装 Shadowsocks-libev 代理，有域名的可以安装 V2ray+ Nginx + WebSocket 代理，各取所需。

WSS 代理，443和8080端口都是可用端口，8080 是免流端口，关闭 tls 后，只要在伪装域名里填上运营商免流链接就可以免流了。

运行脚本：

`wget https://git.io/tcp-wss.sh && bash tcp-wss.sh`

便宜VPS推荐：https://hostalk.net/deals.html

![image](https://user-images.githubusercontent.com/13328328/127747290-d6485b45-f84f-44da-ad32-6d374f21d35f.JPG)

已测试系统如下：

Debian 9, 10, 11

Ubuntu 16.04, 18.04, 20.04

CentOS 7

WS客户端代理信息保存在：
`cat /usr/local/etc/v2ray/client.json`

Shadowsocks客户端代理信息：
`cat /etc/shadowsocks-libev/config.json`
