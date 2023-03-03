#!/bin/bash
xuiygV="22.11.26 V 1.1"
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
bblue='\033[0;34m'
plain='\033[0m'
red(){ echo -e "\033[31m\033[01m$1\033[0m";}
green(){ echo -e "\033[32m\033[01m$1\033[0m";}
yellow(){ echo -e "\033[33m\033[01m$1\033[0m";}
blue(){ echo -e "\033[36m\033[01m$1\033[0m";}
white(){ echo -e "\033[37m\033[01m$1\033[0m";}
readp(){ read -p "$(yellow "$1")" $2;}
remoteV=`wget -qO- https://gitlab.com/rwkgyg/x-ui-yg/raw/main/install.sh | sed  -n 2p | cut -d '"' -f 2`
clear
green 

sleep 2
cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}����${plain} ����ʹ��root�û����д˽ű���\n" && exit 1
#[[ -e /etc/hosts ]] && grep -qE '^ *172.65.251.78 gitlab.com' /etc/hosts || echo -e '\n172.65.251.78 gitlab.com' >> /etc/hosts

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif cat /etc/system-release-cpe | grep -Eqi "amazon_linux"; then
    release="amazon_linux"
else
    echo -e "${red}δ��⵽ϵͳ�汾������ϵ�ű����ߣ�${plain}\n" && exit 1
fi

arch=$(arch)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
  arch="amd64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
  arch="arm64"
elif [[ $arch == "s390x" ]]; then
  arch="s390x"
else
  arch="amd64"
  echo -e "${red}���ܹ�ʧ�ܣ�ʹ��Ĭ�ϼܹ�: ${arch}${plain}"
fi
sys(){
[ -f /etc/os-release ] && grep -i pretty_name /etc/os-release | cut -d \" -f2 && return
[ -f /etc/lsb-release ] && grep -i description /etc/lsb-release | cut -d \" -f2 && return
[ -f /etc/redhat-release ] && awk '{print $0}' /etc/redhat-release && return;}
op=`sys`
version=`uname -r | awk -F "-" '{print $1}'`
vi=`systemd-detect-virt`
white "VPS����ϵͳ: $(blue "$op") \c" && white " �ں˰汾: $(blue "$version") \c" && white " CPU�ܹ� : $(blue "$arch") \c" && white " ���⻯����: $(blue "$vi")"
sleep 2

if [ $(getconf WORD_BIT) != '32' ] && [ $(getconf LONG_BIT) != '64' ] ; then
    echo "�������֧�� 32 λϵͳ(x86)����ʹ�� 64 λϵͳ(x86_64)����������������ϵ����"
    exit -1
fi

os_version=""

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}��ʹ�� CentOS 7 ����߰汾��ϵͳ��${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}��ʹ�� Ubuntu 16 ����߰汾��ϵͳ��${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}��ʹ�� Debian 8 ����߰汾��ϵͳ��${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"amazon_linux" ]]; then
    if [[ ${os_version} -lt 2 ]]; then
        echo -e "${red}��ʹ�� Amazon Linux 2 ����߰汾��ϵͳ��${plain}\n" && exit 1
    fi
fi
ports=$(/usr/local/x-ui/x-ui 2>&1 | grep tcp | awk '{print $5}' | sed "s/://g")
if [[ -n $ports ]]; then
green "����⣬x-ui�Ѱ�װ"
echo
acp=$(/usr/local/x-ui/x-ui setting -show 2>/dev/null)
green "$acp"
echo
readp "�Ƿ�ֱ����װx-ui��������Y/y�����س����粻��װ�������Y/y���س��˳��ű�):" ins
if [[ $ins = [Yy] ]]; then
systemctl stop x-ui
systemctl disable x-ui
rm /etc/systemd/system/x-ui.service -f
systemctl daemon-reload
systemctl reset-failed
rm /etc/x-ui/ -rf
rm /usr/local/x-ui/ -rf
#rm -rf goxui.sh acme.sh
#sed -i '/goxui.sh/d' /etc/crontab
sed -i '/x-ui restart/d' /etc/crontab
else
exit 1
fi
fi
install_base() {
if [[ x"${release}" == x"centos" ]]; then
if [[ ${os_version} =~ 8 ]]; then
cd /etc/yum.repos.d/ && mkdir backup && mv *repo backup/ 
curl -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-8.repo
sed -i -e "s|mirrors.cloud.aliyuncs.com|mirrors.aliyun.com|g " /etc/yum.repos.d/CentOS-*
sed -i -e "s|releasever|releasever-stream|g" /etc/yum.repos.d/CentOS-*
yum clean all && yum makecache
fi
yum install epel-release -y && yum install wget curl tar -y
else
apt update && apt install wget curl tar -y
fi
vi=`systemd-detect-virt`
if [[ $vi = openvz ]]; then
TUN=$(cat /dev/net/tun 2>&1)
if [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ '���ڴ���״̬' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]]; then 
red "��⵽δ����TUN���ֳ������TUN֧��" && sleep 2
cd /dev
mkdir net
mknod net/tun c 10 200
chmod 0666 net/tun
TUN=$(cat /dev/net/tun 2>&1)
if [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ '���ڴ���״̬' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]]; then
green "���TUN֧��ʧ�ܣ�������VPS���̹�ͨ���̨���ÿ���" && exit 0
else
green "��ϲ�����TUN֧�ֳɹ�" && sleep 2
cat>/root/tun.sh<<-\EOF
#!/bin/bash
cd /dev
mkdir net
mknod net/tun c 10 200
chmod 0666 net/tun
EOF
chmod +x /root/tun.sh
grep -qE "^ *@reboot root bash /root/tun.sh >/dev/null 2>&1" /etc/crontab || echo "@reboot root bash /root/tun.sh >/dev/null 2>&1" >> /etc/crontab
fi
fi
fi
echo -e "${green}�رշ���ǽ���������ж˿ڹ��򡭡�${plain}"
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
lsof -i :80|grep -v "PID"|awk '{print "kill -9",$2}'|sh >/dev/null 2>&1
if [[ -z $(grep 'DiG 9' /etc/hosts) ]]; then
v4=$(curl -s4m6 ip.sb -k)
if [ -z $v4 ]; then
echo -e "${green}��⵽VPSΪ��IPV6 Only,���dns64${plain}\n"
echo -e nameserver 2a01:4f8:c2c:123f::1 > /etc/resolv.conf
fi
fi
}
install_x-ui() {
    systemctl stop x-ui
    cd /usr/local/

    if  [ $# == 0 ] ;then
        wget -N --no-check-certificate -O /usr/local/x-ui-linux-${arch}.tar.gz https://gitlab.com/rwkgyg/x-ui-yg/raw/main/x-ui-linux-${arch}.tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${red}���� x-ui ʧ�ܣ���ȷ����ķ������ܹ����� Github ���ļ�${plain}"
            rm -rf install.sh
            exit 1
        fi
    else
        last_version=$1
        url="https://gitlab.com/rwkgyg/x-ui-yg/raw/main/x-ui-linux-${arch}.tar.gz"
        echo -e "��ʼ��װ x-ui v$1"
        wget -N --no-check-certificate -O /usr/local/x-ui-linux-${arch}.tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}���� x-ui v$1 ʧ�ܣ���ȷ���˰汾����${plain}"
            rm -rf install.sh
            exit 1
        fi
    fi

    if [[ -e /usr/local/x-ui/ ]]; then
        rm /usr/local/x-ui/ -rf
    fi

    tar zxvf x-ui-linux-${arch}.tar.gz
    rm x-ui-linux-${arch}.tar.gz -f
    cd x-ui
    chmod +x x-ui bin/xray-linux-${arch}
    cp -f x-ui.service /etc/systemd/system/
    wget --no-check-certificate -O /usr/bin/x-ui https://gitlab.com/rwkgyg/x-ui-yg/raw/main/x-ui.sh
    chmod +x /usr/bin/x-ui
    chmod +x /usr/local/x-ui/x-ui.sh
    systemctl daemon-reload
    systemctl enable x-ui
    systemctl start x-ui
sleep 2
#cat>/root/goxui.sh<<-\EOF
##!/bin/bash
#xui=`ps -aux |grep "x-ui" |grep -v "grep" |wc -l`
#xray=`ps -aux |grep "xray" |grep -v "grep" |wc -l`
#sleep 1
#if [ $xui = 0 ];then
#x-ui restart
#fi
#if [ $xray = 0 ];then
#x-ui restart
#fi
#EOF
#chmod +x /root/goxui.sh
#sed -i '/goxui.sh/d' /etc/crontab
#echo "*/1 * * * * root bash /root/goxui.sh >/dev/null 2>&1" >> /etc/crontab
sed -i '/x-ui restart/d' /etc/crontab
echo "0 1 1 * * x-ui restart >/dev/null 2>&1" >> /etc/crontab
sleep 1
port=18570
username=1857
password=1857
/usr/local/x-ui/x-ui setting -username ${username} -password ${password} >/dev/null 2>&1
/usr/local/x-ui/x-ui setting -port $port >/dev/null 2>&1
sleep 1
xuilogin(){
v4=$(curl -s4m6 ip.sb -k)
v6=$(curl -s6m6 ip.sb -k)
if [[ -z $v4 ]]; then
int="${green}�����������ַ������${plain}  ${bblue}[$v6]:$port${plain}  ${green}����x-ui��¼����\n��ǰx-ui��¼�û�����${plain}${bblue}${username}${plain}${green} \n��ǰx-ui��¼���룺${plain}${bblue}${password}${plain}"
elif [[ -n $v4 && -n $v6 ]]; then
int="${green}�����������ַ������${plain}  ${bblue}$v4:$port${plain}  ${yellow}����${plain}  ${bblue}[$v6]:$port${plain}  ${green}����x-ui��¼����\n��ǰx-ui��¼�û�����${plain}${bblue}${username}${plain}${green} \n��ǰx-ui��¼���룺${plain}${bblue}${password}${plain}"
else
int="${green}�����������ַ������${plain}  ${bblue}$v4:$port${plain}  ${green}����x-ui��¼����\n��ǰx-ui��¼�û�����${plain}${bblue}${username}${plain}${green} \n��ǰx-ui��¼���룺${plain}${bblue}${password}${plain}"
fi
}
if [[ -n $(systemctl status x-ui 2>/dev/null | grep -w active) ]]; then
echo -e ""
yellow "x-ui-yg $remoteV ��װ�ɹ������Ե�3�룬���IP���������x-ui��¼��Ϣ����"
wgcfv6=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
wgcfv4=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
if [[ ! $wgcfv4 =~ on|plus && ! $wgcfv6 =~ on|plus ]]; then
xuilogin
else
systemctl stop wg-quick@wgcf >/dev/null 2>&1
kill -15 $(pgrep warp-go) >/dev/null 2>&1 && sleep 2
xuilogin
systemctl start wg-quick@wgcf >/dev/null 2>&1
systemctl restart warp-go >/dev/null 2>&1
systemctl enable warp-go >/dev/null 2>&1
systemctl start warp-go >/dev/null 2>&1
fi
else
red "x-ui��װʧ�ܣ������� systemctl status x-ui �鿴x-ui״̬"
fi
    sleep 1
    echo -e ""
    echo -e "$int"
    echo -e ""
    echo -e "x-ui ����ű�ʹ�÷���: "
    echo -e "----------------------------------------------"
    echo -e "x-ui              - ��ʾ����˵���һ��֤�����루֧������ֱ��������dns api���룩��warp�ű����ű��Զ���������ʾ��"
    echo -e "x-ui start        - ���� x-ui ���"
    echo -e "x-ui stop         - ֹͣ x-ui ���"
    echo -e "x-ui restart      - ���� x-ui ���"
    echo -e "x-ui status       - �鿴 x-ui ״̬"
    echo -e "x-ui enable       - ���� x-ui ��������"
    echo -e "x-ui disable      - ȡ�� x-ui ��������"
    echo -e "x-ui log          - �鿴 x-ui ��־"
    echo -e "x-ui v2-ui        - Ǩ�Ʊ������� v2-ui �˺������� x-ui"
    echo -e "x-ui update       - ���� x-ui ���"
    echo -e "x-ui install      - ��װ x-ui ���"
    echo -e "x-ui uninstall    - ж�� x-ui ���"
    echo -e "----------------------------------------------"
    rm -rf install.sh
}

echo -e "${green}��ʼ��װx-ui��Ҫ����${plain}"
install_base
echo -e "${green}��ʼ��װx-ui�������${plain}"
install_x-ui $1