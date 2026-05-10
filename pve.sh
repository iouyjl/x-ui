#!/bin/bash

# 全自动安装依赖
apt update -y
apt install -y lm-sensors smartmontools ipmitool

# 下载硬件采集程序
wget -O /root/pve_hw_api https://github.com/iouyjl/x-ui/raw/refs/heads/main/pve_hw_api

# 授权
chmod +x /root/pve_hw_api

# 关闭旧进程
killall -9 pve_hw_api 2>/dev/null

# 后台启动
nohup /root/pve_hw_api > /root/pve_hw.log 2>&1 &

# 加入开机自启
(crontab -l 2>/dev/null | grep -v pve_hw_api; echo "@reboot nohup /root/pve_hw_api > /root/pve_hw.log 2>&1 &") | crontab -

echo "===================================================="
echo "✅ 安装完成！"
echo "✅ 访问地址：http://你的PVE_IP:8080/hw"
echo "===================================================="
