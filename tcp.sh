#!/bin/sh

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

        config_content+="inbounds:\n"
        config_content+="- port: 10000\n"
        config_content+="  protocol: vless\n"
        config_content+="  settings:\n"
        config_content+="    decryption: none\n"
        config_content+="    clients:\n"
        config_content+="    - id: 059ab893-7a38-4a01-a4fa-8111bb7e50cb\n"
        config_content+="  streamSettings:\n"
        config_content+="    network: tcp\n"
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
        config_content+="    - id: 059ab893-7a38-4a01-a4fa-8111bb7e50cb\n"
        config_content+="  streamSettings:\n"
        config_content+="    network: tcp\n"
        config_content+="  sniffing:\n"
        config_content+="    enabled: true\n"
        config_content+="    destOverride:\n"
        config_content+="    - http\n"
        config_content+="    - tls\n"
        config_content+="    - quic\n"
        config_content+="- port: 40000\n"
        config_content+="  protocol: shadowsocks\n"
        config_content+="  settings:\n"
        config_content+="    password: \"123\"\n"
        config_content+="    method: chacha20-ietf-poly1305\n"
        config_content+="    ivcheck: true\n"
        config_content+="  streamSettings:\n"
        config_content+="    network: tcp\n"
        config_content+="    tcpSettings:\n"
        config_content+="      path: /ws\n"
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
        config_content+="    - password: \"123\"\n"
        config_content+="  streamSettings:\n"
        config_content+="    network: tcp\n"
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
        config_content+="    udp: true\n"
        config_content+="    accounts:\n"
        config_content+="    - user: \"123\"\n"
        config_content+="      pass: \"123\"\n"
        config_content+="  streamSettings:\n"
        config_content+="    network: tcp\n"
        config_content+="  sniffing:\n"
        config_content+="    enabled: true\n"
        config_content+="    destOverride:\n"
        config_content+="    - http\n"
        config_content+="    - tls\n"
        config_content+="    - quic\n"
        config_content+="outbounds:\n"
        config_content+="- protocol: freedom\n"
        config_content+="  tag: direct\n\n\n"


echo -e "$config_content" >/etc/xrayLL/config.yaml
systemctl restart xrayLL.service
systemctl --no-pager status xrayLL.service
UA_Browser="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/80.0.3987.87 Safari/537.36"
v4=$(curl -s4m6 ip.sb -k)
v4l=`curl -sm6 --user-agent "${UA_Browser}" http://ip-api.com/json/$v4?lang=zh-CN -k | cut -f2 -d"," | cut -f4 -d '"'`

Argo_xray_vmess="vmess://$(echo -n "\
{\
\"v\": \"2\",\
\"ps\": \"${v4}\",\
\"add\": \"${v4}\",\
\"port\": \"20000\",\
\"id\": \"059ab893-7a38-4a01-a4fa-8111bb7e50cb\",\
\"net\": \"ws\",\
\"security\": \"none\",\
\"host\": \"\",\
\"path\": \"/ws\",\

}"\
    | base64 -w 0)" 
Argo_xray_vless="vless://059ab893-7a38-4a01-a4fa-8111bb7e50cb@${v4}:10000?host=&path=%2Fws&type=ws&encryption=none#${v4}-vless"

cat > log << EOF
================================================================
当前网络的IP：$v4
IP归属地区：$v4l
================================================================
1：Vmess+ws配置明文如下，相关参数可复制到客户端
${Argo_xray_vmess}

----------------------------------------------------------------
2：Vless+ws配置明文如下，相关参数可复制到客户端
${Argo_xray_vless}

----------------------------------------------------------------
3：Trojan+ws配置明文如下，相关参数可复制到客户端
类型：xray
协议：Trojan
host：$v4
端口：30000
密码：123
传输协议：ws
path路径：/ws

----------------------------------------------------------------
4：Shadowsocks+ws配置明文如下，相关参数可复制到客户端
类型：xray
协议：Shadowsocks
host：$v4
端口：40000
密码：123
加密方式：chacha20-ietf-poly1305
传输协议：ws
path路径：/ws

----------------------------------------------------------------
5：Socks+ws配置明文如下，相关参数可复制到客户端
类型：xray
协议：Socks
host：$v4
端口：50000
用户名：123
密码：123
EOF
cat log
