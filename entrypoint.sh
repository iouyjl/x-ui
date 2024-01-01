#!/bin/sh

DEFAULT_START_PORT=20000                         #默认起始端口
DEFAULT_SOCKS_USERNAME="userb"                   #默认socks账号
DEFAULT_SOCKS_PASSWORD="passwordb"               #默认socks密码
DEFAULT_WS_PATH="/ws"                            #默认ws路径
DEFAULT_UUID="059ab893-7a38-4a01-a4fa-8111bb7e50cb" #默认随机UUID

apt update && apt install -y supervisor wget unzip iproute2
wget -O m.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip
unzip m.zip
chmod a+x xray
sed -i "s/uuid/$uuid/g" ./config.yaml
xpid=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 6)
mv xray $xpid
cat config.yaml | base64 > config
rm -f config.yaml

base64 -d config > config.yaml; ./$xpid -config=config.yaml


# argo与加密方案出自fscarmen

xver=`./$xpid version | sed -n 1p | awk '{print $2}'`
UA_Browser="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/80.0.3987.87 Safari/537.36"
v4=$(curl -s4m6 ip.sb -k)
v4l=`curl -sm6 --user-agent "${UA_Browser}" http://ip-api.com/json/$v4?lang=zh-CN -k | cut -f2 -d"," | cut -f4 -d '"'`
UUID=${UUID:-$DEFAULT_UUID}
WS_PATH=${WS_PATH:-$DEFAULT_WS_PATH}

Argo_xray_vmess="vmess://$(echo -n "\
{\
\"v\": \"2\",\
\"ps\": \"Argo_xray_vmess\",\
\"add\": \"${v4}\",\
\"port\": \"443\",\
\"id\": \"$uuid\",\
\"aid\": \"0\",\
\"net\": \"ws\",\
\"type\": \"none\",\
\"host\": \"${v4}\",\
\"path\": \"/$WS_PATH\",\
\"tls\": \"tls\",\
\"sni\": \"${v4}\"\
}"\
    | base64 -w 0)" 
Argo_xray_vless="vless://${uuid}@${v4}:443?encryption=none&security=tls&sni=$v4&type=ws&host=${v4}&path=/$WS_PATH#Argo_xray_vless"
Argo_xray_trojan="trojan://${uuid}@${v4}:443?security=tls&type=ws&host=${v4}&path=/$WS_PATH&sni=$v4#Argo_xray_trojan"

cat > log << EOF
****************************************************************
相关教程解读，请关注：甬哥侃侃侃
视频教程：https://www.youtube.com/@ygkkk
博客地址：https://ygkkk.blogspot.com
================================================================
当前已安装的Xray正式版本：$xver
当前网络的IP：$v4
IP归属地区：$v4l
================================================================
注意：重构或重启当前平台，Argo服务器地址将重置更新
Cloudflared Argo 隧道模式Xray五协议配置如下：
================================================================
----------------------------------------------------------------
1：Vmess+ws+tls配置明文如下，相关参数可复制到客户端
Argo服务器临时地址（可更改为CDN自选IP）：$v4
https端口：可选443、2053、2083、2087、2096、8443，tls必须开启
http端口：可选80、8080、8880、2052、2082、2086、2095，tls必须关闭
uuid：$uuid
传输协议：ws
host/sni：$v4
path路径：/$WS_PATH

分享链接如下（默认443端口、tls开启，服务器地址可更改为自选IP）
${Argo_xray_vmess}

----------------------------------------------------------------
2：Vless+ws+tls配置明文如下，相关参数可复制到客户端
Argo服务器临时地址（可更改为CDN自选IP）：$v4
https端口：可选443、2053、2083、2087、2096、8443，tls必须开启
http端口：可选80、8080、8880、2052、2082、2086、2095，tls必须关闭
uuid：$uuid
传输协议：ws
host/sni：$v4
path路径：/$WS_PATH

分享链接如下（默认443端口、tls开启，服务器地址可更改为自选IP）
${Argo_xray_vless}

----------------------------------------------------------------
3：Trojan+ws+tls配置明文如下，相关参数可复制到客户端
Argo服务器临时地址（可更改为CDN自选IP）：$v4
https端口：可选443、2053、2083、2087、2096、8443，tls必须开启
http端口：可选80、8080、8880、2052、2082、2086、2095，tls必须关闭
密码：$uuid
传输协议：ws
host/sni：$v4
path路径：/$WS_PATH

分享链接如下（默认443端口、tls开启，服务器地址可更改为自选IP）
${Argo_xray_trojan}

----------------------------------------------------------------
4：Shadowsocks+ws+tls配置明文如下，相关参数可复制到客户端
Argo服务器临时地址（可更改为CDN自选IP）：$v4
https端口：可选443、2053、2083、2087、2096、8443，tls必须开启
http端口：可选80、8080、8880、2052、2082、2086、2095，tls必须关闭
密码：$uuid
加密方式：chacha20-ietf-poly1305
传输协议：ws
host/sni：$v4
path路径：/$WS_PATH

----------------------------------------------------------------
5：Socks+ws+tls配置明文如下，相关参数可复制到客户端
Argo服务器临时地址（可更改为CDN自选IP）：$v4
https端口：可选443、2053、2083、2087、2096、8443，tls必须开启
http端口：可选80、8080、8880、2052、2082、2086、2095，tls必须关闭
用户名：$uuid
密码：$uuid
传输协议：ws
host/sni：$v4
path路径：/$WS_PATH


