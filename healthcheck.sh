#!/usr/bin/env bash
set -Eeuo pipefail

# 快速检查 Worker 绑定和最近一次更新状态。
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/config.conf}"

if [[ ! -r "$CONFIG_FILE" ]]; then
  echo "错误: 找不到配置文件: $CONFIG_FILE" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG_FILE"

: "${ACCOUNT_ID:=}"
: "${API_TOKEN:=}"
: "${WORKER_NAME:=}"
: "${ENV_VAR_NAME:=proxyip}"
: "${LOG_FILE:=update.log}"

if [[ "$LOG_FILE" != /* ]]; then
  LOG_FILE="$SCRIPT_DIR/$LOG_FILE"
fi

curl --silent --show-error --location \
  --header "Authorization: Bearer ${API_TOKEN}" \
  "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/workers/scripts/${WORKER_NAME}/settings" | \
  python3 - <<'PY'
import json, sys
payload = sys.stdin.read()
try:
    obj = json.loads(payload)
except Exception as exc:
    print(f"解析 JSON 失败: {exc}")
    print(payload)
    raise SystemExit(1)

result = obj.get('result') or {}
bindings = result.get('bindings') or []
for entry in bindings:
    if isinstance(entry, dict) and entry.get('name') == sys.argv[1]:
        print(f"当前 {sys.argv[1]} = {entry.get('text', '')}")
        break
else:
    print(f"未找到绑定: {sys.argv[1]}")
PY
"${ENV_VAR_NAME}"

echo "--- 最近一次日志 ---"
if [[ -f "$LOG_FILE" ]]; then
  tail -n 10 "$LOG_FILE"
else
  echo "未找到日志文件: $LOG_FILE"
fi
