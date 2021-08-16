搭建 V2ray+ Nginx + WebSocket 和 Shadowsocks-libev 代理脚本，可以选择单独安装或一起安装，支持 Debian、Ubuntu、Centos，并支持甲骨文ARM平台。

简单点讲，没域名的用户可以安装 Shadowsocks-libev 代理，有域名的可以安装 V2ray+ Nginx + WebSocket 代理，各取所需。

注：需 root 用户运行脚本；安装 v2ray+ws+tls 代理前不要占用80端口，否则申请证书会失败。

运行脚本：

`wget https://git.io/tcp-wss.sh && bash tcp-wss.sh`

![image](https://user-images.githubusercontent.com/13328328/127747290-d6485b45-f84f-44da-ad32-6d374f21d35f.JPG)
