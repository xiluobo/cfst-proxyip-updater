#!/usr/bin/env bash
set -Eeuo pipefail

# 卸载 CFST ProxyIP Auto Updater。
# 删除安装目录、定时任务和 systemd timer。

if [[ $EUID -ne 0 ]]; then
  echo "请使用 sudo 运行: sudo ./uninstall.sh" >&2
  exit 1
fi

INSTALL_DIR="${INSTALL_DIR:-/opt/cfst_proxyip}"
SERVICE_NAME="${SERVICE_NAME:-cfst-proxyip-updater}"
TIMER_NAME="${TIMER_NAME:-${SERVICE_NAME}.timer}"

echo "=========================================="
echo "  卸载 CFST ProxyIP Auto Updater"
echo "=========================================="

if command -v systemctl >/dev/null 2>&1; then
  systemctl disable --now "${TIMER_NAME}" >/dev/null 2>&1 || true
  systemctl disable --now "${SERVICE_NAME}" >/dev/null 2>&1 || true
  rm -f "/etc/systemd/system/${SERVICE_NAME}.service" "/etc/systemd/system/${TIMER_NAME}"
  systemctl daemon-reload >/dev/null 2>&1 || true
  echo "已移除 systemd 服务和定时器"
fi

if command -v crontab >/dev/null 2>&1; then
  current_jobs="$(crontab -l 2>/dev/null || true)"
  if [[ -n "$current_jobs" ]]; then
    filtered_jobs="$(printf '%s\n' "$current_jobs" | grep -Fv "$INSTALL_DIR/update_proxyip.sh" || true)"
    if [[ -n "$filtered_jobs" ]]; then
      printf '%s\n' "$filtered_jobs" | crontab -
    else
      crontab -r 2>/dev/null || true
    fi
    echo "已移除 cron 定时任务"
  fi
fi

if [[ -d "$INSTALL_DIR" ]]; then
  rm -rf -- "$INSTALL_DIR"
  echo "已删除目录: $INSTALL_DIR"
else
  echo "未找到安装目录: $INSTALL_DIR"
fi

echo "卸载完成。"
