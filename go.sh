#!/bin/sh

is64=`uname -m`
    if [ "$is64" = "x86_64" ];then
        wget https://studygolang.com/dl/golang/go1.16.6.linux-amd64.tar.gz -O - | tar -xz -C /usr/local/
        sleep 3s
    else
        wget https://studygolang.com/dl/golang/go1.16.6.linux-arm64.tar.gz -O - | tar -xz -C /usr/local/
        sleep 3s 
    fi 
echo -e "export PATH=\$PATH:/usr/local/go/bin\nexport PATH=\$PATH:\$HOME/.cargo/bin\nexport GOROOT=/usr/local/go\nexport GOBIN=\$GOROOT/bin\nexport PATH=\$PATH:\$GOBIN" >> ~/.profile

source ~/.profile
