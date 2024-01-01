#!/bin/sh

DEFAULT_START_PORT=20000                         #默认起始端口
DEFAULT_SOCKS_USERNAME="userb"                   #默认socks账号
DEFAULT_SOCKS_PASSWORD="passwordb"               #默认socks密码
DEFAULT_WS_PATH="/ws"                            #默认ws路径
DEFAULT_UUID="059ab893-7a38-4a01-a4fa-8111bb7e50cb" #默认随机UUID
UUID=${UUID:-$DEFAULT_UUID}
WS_PATH=${WS_PATH:-$DEFAULT_WS_PATH}
IP_ADDRESSES=($(hostname -I))
apt update && apt install -y supervisor wget unzip iproute2
wget https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip
unzip Xray-linux-64.zip
mv xray /usr/local/bin/xrayLL
chmod +x /usr/local/bin/xrayLL
cat <<EOF >/etc/systemd/system/xrayLL.service
[Unit]
Description=xrayLL Service
After=network.target

[Service]
ExecStart=/usr/local/bin/xrayLL -c /etc/xrayLL/config.yaml
Restart=on-failure
User=nobody
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
	systemctl daemon-reload
	systemctl enable xrayLL.service
	systemctl start xrayLL.service
	echo "Xray 安装完成."


# argo与加密方案出自fscarmen
mkdir -p /etc/xrayLL
	for ((i = 0; i < ${#IP_ADDRESSES[@]}; i++)); do
        config_content+="inbounds:\n"
        config_content+="- port: 10000\n"
        config_content+="  protocol: vless\n"
        config_content+="  settings:\n"
        config_content+="    decryption: none\n"
        config_content+="    clients:\n"
        config_content+="    - id: ${UUID:-$DEFAULT_UUID}\n"
        config_content+="  streamSettings:\n"
        config_content+="    network: ws\n"
        config_content+="    wsSettings:\n"
        config_content+="      path: ${WS_PATH:-$DEFAULT_WS_PATH}\n"
        config_content+="  sniffing:\n"
        config_content+="    enabled: true\n"
        config_content+="    destOverride:\n"
        config_content+="    - http\n"
        config_content+="    - tls\n"
        config_content+="    - quic\n"
        config_content+="- port: 20000\n"
        config_content+="  protocol: vmess\n"
        config_content+="  settings:\n"
        config_content+="    clients:\n"
        config_content+="    - id: ${UUID:-$DEFAULT_UUID}\n"
        config_content+="  streamSettings:\n"
        config_content+="    network: ws\n"
        config_content+="    wsSettings:\n"
        config_content+="      path: ${WS_PATH:-$DEFAULT_WS_PATH}\n"
        config_content+="  sniffing:\n"
        config_content+="    enabled: true\n"
        config_content+="    destOverride:\n"
        config_content+="    - http\n"
        config_content+="    - tls\n"
        config_content+="    - quic\n"
        config_content+="- port: 40000\n"
        config_content+="  protocol: shadowsocks\n"
        config_content+="  settings:\n"
        config_content+="    password: "$SOCKS_PASSWORD"\n"
        config_content+="    method: chacha20-ietf-poly1305\n"
        config_content+="    ivcheck: true\n"
        config_content+="  streamSettings:\n"
        config_content+="    network: ws\n"
        config_content+="    wsSettings:\n"
        config_content+="      path: ${WS_PATH:-$DEFAULT_WS_PATH}\n"
        config_content+="  sniffing:\n"
        config_content+="    enabled: true\n"
        config_content+="    destOverride:\n"
        config_content+="    - http\n"
        config_content+="    - tls\n"
        config_content+="    - quic\n"
        config_content+="- port: 30000\n"
        config_content+="  protocol: trojan\n"
        config_content+="  settings:\n"
        config_content+="    clients:\n"
        config_content+="    - password: "$SOCKS_PASSWORD"\n"
        config_content+="  streamSettings:\n"
        config_content+="    network: ws\n"
        config_content+="    wsSettings:\n"
        config_content+="      path: ${WS_PATH:-$DEFAULT_WS_PATH}\n"
        config_content+="  sniffing:\n"
        config_content+="    enabled: true\n"
        config_content+="    destOverride:\n"
        config_content+="    - http\n"
        config_content+="    - tls\n"
        config_content+="    - quic\n"
        config_content+="- port: 50000\n"
        config_content+="  protocol: socks\n"
        config_content+="  settings:\n"
        config_content+="    auth: password\n"
        config_content+="    accounts:\n"
        config_content+="    - user: "$SOCKS_USERNAME"\n"
        config_content+="      pass: "$SOCKS_PASSWORD"\n"
        config_content+="  streamSettings:\n"
        config_content+="    network: ws\n"
        config_content+="    wsSettings:\n"
        config_content+="      path: ${WS_PATH:-$DEFAULT_WS_PATH}\n"
        config_content+="  sniffing:\n"
        config_content+="    enabled: true\n"
        config_content+="    destOverride:\n"
        config_content+="    - http\n"
        config_content+="    - tls\n"
        config_content+="    - quic\n"
        config_content+="outbounds:\n"
        config_content+="- protocol: freedom\n"
        config_content+="  tag: direct\n\n\n"
	done

echo -e "$config_content" >/etc/xrayLL/config.yaml
systemctl restart xrayLL.service
systemctl --no-pager status xrayLL.service
UA_Browser="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/80.0.3987.87 Safari/537.36"
v4=$(curl -s4m6 ip.sb -k)
v4l=`curl -sm6 --user-agent "${UA_Browser}" http://ip-api.com/json/$v4?lang=zh-CN -k | cut -f2 -d"," | cut -f4 -d '"'`

echo ""
Argo_xray_vmess="vmess://$(echo -n "\
{\
\"v\": \"2\",\
\"ps\": \"${v4}\",\
\"add\": \"${v4}\",\
\"port\": \"20000\",\
\"id\": \"$UUID\",\
\"aid\": \"0\",\
\"net\": \"ws\",\
\"type\": \"none\",\
\"host\": \"\",\
\"path\": \"/$WS_PATH\",\
\"tls\": \"tls\",\
\"sni\": \"${ARGO}\"\
}"\
    | base64 -w 0)" 
Argo_xray_vless="vless://${UUID}@${v4}:443?encryption=none&security=tls&sni=$v4&type=ws&host=${v4}&path=/$WS_PATH#Argo_xray_vless"
Argo_xray_trojan="trojan://${UUID}@${v4}:443?security=tls&type=ws&host=${v4}&path=/$WS_PATH&sni=$v4#Argo_xray_trojan"

cat > log << EOF
================================================================
当前网络的IP：$v4
IP归属地区：$v4l
================================================================
1：Vmess+ws+tls配置明文如下，相关参数可复制到客户端
uuid：$UUID
传输协议：ws
host/sni：$v4
path路径：/$WS_PATH

分享链接如下（默认443端口、tls开启，服务器地址可更改为自选IP）
${Argo_xray_vmess}

----------------------------------------------------------------
2：Vless+ws+tls配置明文如下，相关参数可复制到客户端
uuid：$UUID
传输协议：ws
host/sni：$v4
path路径：/$WS_PATH

分享链接如下（默认443端口、tls开启，服务器地址可更改为自选IP）
${Argo_xray_vless}

----------------------------------------------------------------
3：Trojan+ws+tls配置明文如下，相关参数可复制到客户端
密码：$UUID
传输协议：ws
host/sni：$v4
path路径：/$WS_PATH

分享链接如下（默认443端口、tls开启，服务器地址可更改为自选IP）
${Argo_xray_trojan}

----------------------------------------------------------------
4：Shadowsocks+ws+tls配置明文如下，相关参数可复制到客户端
密码：$UUID
加密方式：chacha20-ietf-poly1305
传输协议：ws
host/sni：$v4
path路径：/$WS_PATH

----------------------------------------------------------------
5：Socks+ws+tls配置明文如下，相关参数可复制到客户端
用户名：$UUID
密码：$UUID
传输协议：ws
host/sni：$v4
path路径：/$WS_PATH
echo ""

