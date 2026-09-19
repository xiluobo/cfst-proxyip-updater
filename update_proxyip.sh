#!/usr/bin/env bash
set -Eeuo pipefail

# CFST 优选 IP 测速并更新 Cloudflare Worker binding。
# 支持 --config / --dry-run / --check-only 等参数，并保留现有 Workers binding。

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="${BASE_DIR:-$SCRIPT_DIR}"
CONFIG_FILE="${CONFIG_FILE:-$BASE_DIR/config.conf}"
LOG_FILE="${LOG_FILE:-$BASE_DIR/update.log}"

usage() {
  cat <<'EOF'
Usage: update_proxyip.sh [options]

Options:
  --config FILE        指定配置文件路径 (默认: ./config.conf)
  --dry-run            仅测速，不更新 Cloudflare Worker
  --check-only         仅检查当前 Worker binding，不测速、不更新
  --log FILE           指定日志文件
  --help               显示帮助
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      [[ $# -ge 2 ]] || { echo "缺少配置文件参数" >&2; exit 1; }
      CONFIG_FILE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --check-only)
      CHECK_ONLY=true
      shift
      ;;
    --log)
      [[ $# -ge 2 ]] || { echo "缺少日志文件参数" >&2; exit 1; }
      LOG_FILE="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "未知参数: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -r "$CONFIG_FILE" ]]; then
  echo "错误: 找不到配置文件: $CONFIG_FILE" >&2
  echo "请先执行: cp config.example.conf config.conf" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG_FILE"

: "${ACCOUNT_ID:=}"
: "${API_TOKEN:=}"
: "${WORKER_NAME:=}"
: "${ENV_VAR_NAME:=proxyip}"
: "${ENV_VAR_NAMES:=}"
: "${CFCOLO:=}"
: "${N:=100}"
: "${DN:=5}"
: "${TL:=300}"
: "${USE_PUBLIC_PROXY_IP:=true}"
: "${PROXY_SOURCE1:=}"
: "${PROXY_SOURCE2:=}"
: "${IP_FILE:=ip.txt}"
: "${PROXY_IP_FILE:=proxy_ips.txt}"
: "${RESULT:=result.csv}"
: "${CURL_TIMEOUT:=30}"
: "${CURL_RETRIES:=2}"
: "${RETRY_DELAY:=10}"
: "${LOCK_DIR:=$BASE_DIR/.update.lock}"
: "${DRY_RUN:=false}"
: "${CHECK_ONLY:=false}"
: "${LOG_FILE:=update.log}"
: "${LOG_KEEP_DAYS:=30}"

if [[ "$LOG_FILE" != /* ]]; then
  LOG_FILE="$BASE_DIR/$LOG_FILE"
fi

cd "$BASE_DIR"

fail() { echo "错误: $*" >&2; exit 1; }
require_command() { command -v "$1" >/dev/null 2>&1 || fail "未找到命令 $1，请先安装它"; }
is_uint() { [[ "$1" =~ ^[0-9]+$ ]]; }
normalize_env_names() {
  local raw_names="${ENV_VAR_NAMES:-$ENV_VAR_NAME}"
  if [[ -z "$raw_names" ]]; then
    echo "$ENV_VAR_NAME"
    return 0
  fi
  echo "$raw_names" | tr ',' '\n' | sed 's/[[:space:]]//g' | awk 'NF' | paste -sd ',' -
}

require_command curl
require_command awk
require_command sort
require_command grep
require_command python3
[[ -x ./cfst ]] || fail "未找到可执行的 ./cfst，请先运行 install.sh"
[[ -n "$ACCOUNT_ID" && "$ACCOUNT_ID" != "你的Account_ID" ]] || fail "ACCOUNT_ID 未配置"
[[ -n "$WORKER_NAME" && "$WORKER_NAME" =~ ^[A-Za-z0-9_-]+$ ]] || fail "WORKER_NAME 只能包含字母、数字、下划线和短横线"
if [[ "$DRY_RUN" != "true" && "$CHECK_ONLY" != "true" ]]; then
  [[ -n "$API_TOKEN" && "$API_TOKEN" != "你的API_Token" ]] || fail "API_TOKEN 未配置"
fi
for value in "$N" "$DN" "$TL" "$CURL_TIMEOUT" "$CURL_RETRIES" "$RETRY_DELAY"; do
  is_uint "$value" || fail "测速/网络参数必须是非负整数: $value"
done

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  fail "已有另一个更新任务运行中（锁目录: $LOCK_DIR）"
fi
cleanup() {
  rm -rf -- "$LOCK_DIR" "${TMP_DIR:-}"
  if [[ -n "$LOG_KEEP_DAYS" ]] && [[ "$LOG_KEEP_DAYS" =~ ^[0-9]+$ ]]; then
    find "$BASE_DIR" -maxdepth 1 -type f -name '*.log' -mtime +"$LOG_KEEP_DAYS" -delete 2>/dev/null || true
  fi
}
trap cleanup EXIT
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cfst-proxyip.XXXXXX")"

fetch_ips() {
  local url="$1" output="$2"
  [[ -n "$url" ]] || return 0
  curl --fail --silent --show-error --location --max-time "$CURL_TIMEOUT" \
    --retry "$CURL_RETRIES" --retry-delay "$RETRY_DELAY" "$url" 2>/dev/null |
    grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' |
    awk -F. '($1<=255 && $2<=255 && $3<=255 && $4<=255) {print}' >> "$output" || true
}

check_worker_exists() {
  local status response_file="$TMP_DIR/worker_check.json"
  status="$(curl --silent --show-error --location --output "$response_file" --write-out '%{http_code}' \
    --header "Authorization: Bearer ${API_TOKEN}" \
    "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/workers/scripts/${WORKER_NAME}" || true)"

  if [[ "$status" == "200" ]]; then
    return 0
  fi

  echo "Cloudflare Worker 检查失败（HTTP ${status:-unknown}）" >&2
  if [[ -s "$response_file" ]]; then
    cat "$response_file" >&2
  fi
  return 1
}

build_update_payload() {
  local settings_json="$1"
  local env_names="$2"
  python3 - "$settings_json" "$env_names" "$BEST_IP" <<'PY'
import json, sys
settings_path, env_names, best_ip = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(settings_path, 'r', encoding='utf-8') as fh:
        data = json.load(fh)
except Exception:
    data = {"result": {"bindings": []}}

names = [n.strip() for n in env_names.split(',') if n.strip()]
if not names:
    names = ["proxyip"]

bindings = data.get("result", {}).get("bindings", [])
if not isinstance(bindings, list):
    bindings = []
updated = []
seen = set()
for binding in bindings:
    if isinstance(binding, dict):
        name = binding.get("name")
        if name in names:
            updated.append({"type": "plain_text", "name": name, "text": best_ip})
            seen.add(name)
        else:
            updated.append(binding)
    else:
        updated.append(binding)
for name in names:
    if name not in seen:
        updated.append({"type": "plain_text", "name": name, "text": best_ip})
print(json.dumps({"bindings": updated}, separators=(",", ":"), ensure_ascii=False))
PY
}

if [[ "$CHECK_ONLY" == "true" ]]; then
  echo "[1/1] 检查 Worker ${WORKER_NAME} 配置..."
  if [[ -n "$API_TOKEN" ]]; then
    check_worker_exists || fail "Worker ${WORKER_NAME} 不存在或权限不足"
    echo "Worker ${WORKER_NAME} 可访问，当前 binding："
    curl --silent --show-error --location \
      --header "Authorization: Bearer ${API_TOKEN}" \
      "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/workers/scripts/${WORKER_NAME}/settings" | python3 -m json.tool 2>/dev/null | sed -n '1,80p'
  else
    echo "检测仅支持在配置中提供 API_TOKEN 的情况下运行"
  fi
  exit 0
fi

SOURCE_FILE="$TMP_DIR/sources.txt"
: > "$SOURCE_FILE"
if [[ "$USE_PUBLIC_PROXY_IP" == "true" ]]; then
  echo "[1/4] 拉取公开 IP 列表..."
  fetch_ips "$PROXY_SOURCE1" "$SOURCE_FILE"
  fetch_ips "$PROXY_SOURCE2" "$SOURCE_FILE"
fi
if [[ -f "$IP_FILE" ]]; then
  cat "$IP_FILE" >> "$SOURCE_FILE"
fi
sort -u "$SOURCE_FILE" -o "$SOURCE_FILE"
[[ -s "$SOURCE_FILE" ]] || fail "没有可测速的 IPv4 地址，请检查 IP_FILE 或公开源"
cp -- "$SOURCE_FILE" "$PROXY_IP_FILE"
TEST_FILE="$SOURCE_FILE"
echo "  待测速 IP 数量: $(wc -l < "$TEST_FILE")"

echo "[2/4] 开始测速..."
CFST_ARGS=(-n "$N" -dn "$DN" -tl "$TL" -dd -o "$TMP_DIR/result.csv" -f "$TEST_FILE")
if [[ -n "$CFCOLO" ]]; then
  CFST_ARGS+=(-httping -cfcolo "$CFCOLO")
fi
if ! ./cfst "${CFST_ARGS[@]}"; then
  echo "  首次测速失败，使用放宽后的延迟阈值重试..."
  CFST_ARGS=(-n "$N" -dn "$DN" -tl "$((TL + 100))" -dd -o "$TMP_DIR/result.csv" -f "$TEST_FILE")
  [[ -n "$CFCOLO" ]] && CFST_ARGS+=(-httping -cfcolo "$CFCOLO")
  ./cfst "${CFST_ARGS[@]}" || fail "测速失败，请检查网络、IP 列表或 CFCOLO/TL 配置"
fi

BEST_IP="$(awk -F, 'NR > 1 {gsub(/[[:space:]\r]/, "", $1); if ($1 ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}$/) {print $1; exit}}' "$TMP_DIR/result.csv")"
[[ -n "$BEST_IP" ]] || fail "测速结果为空，请放宽 CFCOLO / TL"
cp -- "$TMP_DIR/result.csv" "$RESULT"
echo "  最快 IP: $BEST_IP"

if [[ "$DRY_RUN" == "true" ]]; then
  echo "[3/4] DRY_RUN=true，跳过 Cloudflare 更新"
else
  echo "[3/4] 检查 Worker 是否存在..."
  check_worker_exists || fail "Worker ${WORKER_NAME} 不存在或权限不足"

  SETTINGS_FILE="$TMP_DIR/workers_settings.json"
  curl --silent --show-error --location --output "$SETTINGS_FILE" \
    --header "Authorization: Bearer ${API_TOKEN}" \
    "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/workers/scripts/${WORKER_NAME}/settings" \
    || fail "无法读取 Worker 设置，确认脚本权限和配置正确"

  ENV_NAMES="$(normalize_env_names)"
  PATCH_BODY="$(build_update_payload "$SETTINGS_FILE" "$ENV_NAMES")"
  echo "[3/4] 更新 Workers ${ENV_NAMES}..."
  RESPONSE_FILE="$TMP_DIR/response.json"
  HTTP_CODE="$(curl --silent --show-error --location --output "$RESPONSE_FILE" --write-out '%{http_code}' \
    --request PATCH "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/workers/scripts/${WORKER_NAME}/settings" \
    --header "Authorization: Bearer ${API_TOKEN}" --header 'Content-Type: application/json' \
    --data "$PATCH_BODY" || true)"

  if [[ "$HTTP_CODE" =~ ^2[0-9][0-9]$ ]] && grep -q '"success"[[:space:]]*:[[:space:]]*true' "$RESPONSE_FILE"; then
    echo "  更新成功！${ENV_NAMES} = $BEST_IP"
    printf '%s %s=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$ENV_NAMES" "$BEST_IP" >> "$LOG_FILE"
  else
    echo "  Cloudflare API 更新失败（HTTP ${HTTP_CODE:-unknown}）:" >&2
    cat "$RESPONSE_FILE" >&2
    exit 1
  fi
fi

echo "[4/4] 完成 $(date '+%Y-%m-%d %H:%M:%S')"
