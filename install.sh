#!/usr/bin/env bash
set -Eeuo pipefail

echo "=========================================="
echo "  安装 CFST + ProxyIP 自动更新"
echo "=========================================="

if [[ $EUID -ne 0 ]]; then
  echo "请使用 sudo 运行: sudo ./install.sh" >&2
  exit 1
fi

command -v apt-get >/dev/null 2>&1 || { echo "错误: 当前安装脚本仅支持 Debian/Ubuntu（需要 apt-get）" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { apt-get update -qq; apt-get install -y -qq curl; }
command -v python3 >/dev/null 2>&1 || { apt-get update -qq; apt-get install -y -qq python3; }

apt-get update -qq
apt-get install -y -qq ca-certificates curl cron tar gzip python3 >/dev/null

INSTALL_DIR="/opt/cfst_proxyip"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_CRON="${INSTALL_CRON:-true}"
INSTALL_SYSTEMD="${INSTALL_SYSTEMD:-true}"
SYSTEMD_SERVICE_NAME="${SYSTEMD_SERVICE_NAME:-cfst-proxyip-updater}"

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
ARCHIVE="$TMP_DIR/cfst.tar.gz"
URL="https://github.com/XIU2/CloudflareSpeedTest/releases/latest/download/cfst_linux_amd64.tar.gz"

echo "下载 CloudflareSpeedTest..."
curl --fail --silent --show-error --location --retry 3 --retry-delay 2 -o "$ARCHIVE" "$URL"
tar -xzf "$ARCHIVE" -C "$TMP_DIR"
CFST_PATH="$(find "$TMP_DIR" -type f -name cfst -print -quit)"
[[ -n "$CFST_PATH" ]] || { echo "错误: 下载包中未找到 cfst" >&2; exit 1; }
install -m 0755 "$CFST_PATH" "$INSTALL_DIR/cfst"

curl --fail --silent --show-error --location --retry 3 -o "$INSTALL_DIR/ip.txt" \
  "https://raw.githubusercontent.com/XIU2/CloudflareSpeedTest/master/ip.txt" || \
  echo "警告: 官方 IP 列表下载失败，可稍后手动放置 ip.txt"

install -m 0755 "$SCRIPT_DIR/update_proxyip.sh" "$INSTALL_DIR/update_proxyip.sh"
install -m 0755 "$SCRIPT_DIR/healthcheck.sh" "$INSTALL_DIR/healthcheck.sh"
if [[ -f "$SCRIPT_DIR/config.conf" ]]; then
  install -m 0600 "$SCRIPT_DIR/config.conf" "$INSTALL_DIR/config.conf"
elif [[ ! -f "$INSTALL_DIR/config.conf" ]]; then
  install -m 0600 "$SCRIPT_DIR/config.example.conf" "$INSTALL_DIR/config.conf"
  echo "已复制配置模板，请编辑 $INSTALL_DIR/config.conf 填写真实 Token"
else
  echo "保留已有配置: $INSTALL_DIR/config.conf"
fi

install_cron_job() {
  local cron_script="$INSTALL_DIR/update_proxyip.sh"
  local cron_log="$INSTALL_DIR/cron.log"
  local cron_entry="0 */6 * * * ${cron_script} >> ${cron_log} 2>&1"
  local current_jobs

  current_jobs="$(crontab -l 2>/dev/null || true)"
  if echo "$current_jobs" | grep -Fq "$cron_script"; then
    echo "已存在 cron 任务，跳过重复安装"
    return 0
  fi

  if [[ -n "$current_jobs" ]]; then
    (printf '%s\n' "$current_jobs"; printf '%s\n' "$cron_entry") | crontab -
  else
    printf '%s\n' "$cron_entry" | crontab -
  fi

  echo "已安装 cron 定时任务：${cron_entry}"
}

install_systemd_service() {
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "未检测到 systemctl，跳过 systemd 安装"
    return 0
  fi

  local service_file="/etc/systemd/system/${SYSTEMD_SERVICE_NAME}.service"
  local timer_file="/etc/systemd/system/${SYSTEMD_SERVICE_NAME}.timer"

  cat > "$service_file" <<EOF
[Unit]
Description=CFST ProxyIP Auto Updater
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory=/opt/cfst_proxyip
ExecStart=/opt/cfst_proxyip/update_proxyip.sh --config /opt/cfst_proxyip/config.conf
StandardOutput=append:/opt/cfst_proxyip/cron.log
StandardError=append:/opt/cfst_proxyip/cron.log

[Install]
WantedBy=multi-user.target
EOF

  cat > "$timer_file" <<EOF
[Unit]
Description=Run CFST ProxyIP Auto Updater every 6 hours

[Timer]
OnBootSec=5min
OnUnitActiveSec=6h
Persistent=true
Unit=${SYSTEMD_SERVICE_NAME}.service

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now "${SYSTEMD_SERVICE_NAME}.timer" >/dev/null 2>&1 || true
  echo "已安装 systemd timer：${SYSTEMD_SERVICE_NAME}.timer"
}

if [[ "$INSTALL_CRON" == "true" ]]; then
  install_cron_job
fi

if [[ "$INSTALL_SYSTEMD" == "true" ]]; then
  install_systemd_service
fi

cat <<EOF

安装完成。
1. 编辑配置: nano $INSTALL_DIR/config.conf
2. 试运行:   cd $INSTALL_DIR && ./update_proxyip.sh --dry-run
3. 诊断检查: cd $INSTALL_DIR && ./healthcheck.sh
4. 定时任务: crontab -l | grep "$INSTALL_DIR/update_proxyip.sh"  查看是否已注册
5. systemd:   systemctl status ${SYSTEMD_SERVICE_NAME}.timer
6. 手工执行:  $INSTALL_DIR/update_proxyip.sh >> $INSTALL_DIR/cron.log 2>&1
EOF
