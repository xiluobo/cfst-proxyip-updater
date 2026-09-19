#!/bin/bash
set -e
echo "=========================================="
echo "  安装 CFST + ProxyIP 自动更新"
echo "=========================================="

if [ "$EUID" -ne 0 ]; then
  echo "请使用 sudo 运行: sudo ./install.sh"
  exit 1
fi

apt-get update -qq
apt-get install -y -qq curl wget ca-certificates cron > /dev/null

mkdir -p /opt/cfst_proxyip
cd /opt/cfst_proxyip

echo "下载 CloudflareSpeedTest..."
wget -q -O cfst.tar.gz "https://github.com/XIU2/CloudflareSpeedTest/releases/latest/download/cfst_linux_amd64.tar.gz" || \
wget -q -O cfst.tar.gz "https://ghfast.top/https://github.com/XIU2/CloudflareSpeedTest/releases/latest/download/cfst_linux_amd64.tar.gz"
tar -xzf cfst.tar.gz
rm -f cfst.tar.gz
# 兼容解压到子目录的情况
if [ -d cfst_linux_amd64 ]; then
  mv cfst_linux_amd64/* . 2>/dev/null || true
  rmdir cfst_linux_amd64 2>/dev/null || true
fi
chmod +x cfst 2>/dev/null || true

wget -q -O ip.txt "https://raw.githubusercontent.com/XIU2/CloudflareSpeedTest/master/ip.txt" 2>/dev/null || true

# 复制脚本
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp -f "$SCRIPT_DIR/update_proxyip.sh" /opt/cfst_proxyip/
if [ -f "$SCRIPT_DIR/config.conf" ]; then
  cp -f "$SCRIPT_DIR/config.conf" /opt/cfst_proxyip/
elif [ -f "$SCRIPT_DIR/config.example.conf" ]; then
  cp -f "$SCRIPT_DIR/config.example.conf" /opt/cfst_proxyip/config.conf
  echo "已复制 config.example.conf → config.conf，请编辑填写真实 Token"
fi
chmod +x /opt/cfst_proxyip/update_proxyip.sh

echo ""
echo "安装完成。"
echo "1. 编辑配置: nano /opt/cfst_proxyip/config.conf"
echo "2. 运行一次:  cd /opt/cfst_proxyip && ./update_proxyip.sh"
echo "3. 定时任务:  crontab -e  添加: 0 */6 * * * /opt/cfst_proxyip/update_proxyip.sh >> /opt/cfst_proxyip/cron.log 2>&1"
