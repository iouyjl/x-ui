#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}����${plain} ����ʹ��root�û����д˽ű���\n" && exit 1

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

echo "�ܹ�: ${arch}"

if [ $(getconf WORD_BIT) != '32' ] && [ $(getconf LONG_BIT) != '64' ]; then
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
fi

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install wget curl tar -y
    else
        apt install wget curl tar -y
    fi
}

#This function will be called when user installed x-ui out of sercurity
config_after_install() {
        config_account=1857
        config_password=1857
        config_port=18570
        /usr/local/x-ui/x-ui setting -username ${config_account} -password ${config_password}
        /usr/local/x-ui/x-ui setting -port ${config_port}
}

install_x-ui() {
    systemctl stop x-ui
    cd /usr/local/

    if [ $# == 0 ]; then
        last_version=$(curl -Ls "https://api.github.com/repos/vaxilu/x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}��� x-ui �汾ʧ�ܣ������ǳ��� Github API ���ƣ����Ժ����ԣ����ֶ�ָ�� x-ui �汾��װ${plain}"
            exit 1
        fi
        echo -e "��⵽ x-ui ���°汾��${last_version}����ʼ��װ"
        wget -N --no-check-certificate -O /usr/local/x-ui-linux-${arch}.tar.gz https://github.com/vaxilu/x-ui/releases/download/${last_version}/x-ui-linux-${arch}.tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${red}���� x-ui ʧ�ܣ���ȷ����ķ������ܹ����� Github ���ļ�${plain}"
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/vaxilu/x-ui/releases/download/${last_version}/x-ui-linux-${arch}.tar.gz"
        echo -e "��ʼ��װ x-ui v$1"
        wget -N --no-check-certificate -O /usr/local/x-ui-linux-${arch}.tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}���� x-ui v$1 ʧ�ܣ���ȷ���˰汾����${plain}"
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
    wget --no-check-certificate -O /usr/bin/x-ui https://raw.githubusercontent.com/vaxilu/x-ui/main/x-ui.sh
    chmod +x /usr/local/x-ui/x-ui.sh
    chmod +x /usr/bin/x-ui
    config_after_install
	v4=$(curl -s4m6 ip.sb -k)
	v6=$(curl -s6m6 ip.sb -k)
	if [[ -z $v4 ]]; then
int="${green}�����������ַ������${plain}  ${bblue}[$v6]:$config_port${plain}  ${green}����x-ui��¼����\n��ǰx-ui��¼�û�����${plain}${bblue}${config_account}${plain}${green} \n��ǰx-ui��¼���룺${plain}${bblue}${config_password}${plain}"
elif [[ -n $v4 && -n $v6 ]]; then
int="${green}�����������ַ������${plain}  ${bblue}$v4:$config_port${plain}  ${yellow}����${plain}  ${bblue}[$v6]:$config_port${plain}  ${green}����x-ui��¼����\n��ǰx-ui��¼�û�����${plain}${bblue}${config_account}${plain}${green} \n��ǰx-ui��¼���룺${plain}${bblue}${config_password}${plain}"
else
int="${green}�����������ַ������${plain}  ${bblue}$v4:$config_port${plain}  ${green}����x-ui��¼����\n��ǰx-ui��¼�û�����${plain}${bblue}${config_account}${plain}${green} \n��ǰx-ui��¼���룺${plain}${bblue}${config_password}${plain}"
fi
    #echo -e "�����ȫ�°�װ��Ĭ����ҳ�˿�Ϊ ${green}54321${plain}���û���������Ĭ�϶��� ${green}admin${plain}"
    #echo -e "������ȷ���˶˿�û�б���������ռ�ã�${yellow}����ȷ�� 54321 �˿��ѷ���${plain}"
    #    echo -e "���뽫 54321 �޸�Ϊ�����˿ڣ����� x-ui ��������޸ģ�ͬ��ҲҪȷ�����޸ĵĶ˿�Ҳ�Ƿ��е�"
    #echo -e ""
    #echo -e "����Ǹ�����壬����֮ǰ�ķ�ʽ�������"
    #echo -e ""
	
	
    systemctl daemon-reload
    systemctl enable x-ui
    systemctl start x-ui
    echo -e "${green}x-ui v${last_version}${plain} ��װ��ɣ������������"
    echo -e ""
    echo -e "x-ui ����ű�ʹ�÷���: "
    echo -e "----------------------------------------------"
    echo -e "x-ui              - ��ʾ����˵� (���ܸ���)"
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
}

echo -e "${green}��ʼ��װ${plain}"
install_base
install_x-ui $1