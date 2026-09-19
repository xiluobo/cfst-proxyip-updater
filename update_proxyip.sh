#!/usr/bin/env bash
set -Eeuo pipefail

# CFST 优选 IP 测速并更新 Cloudflare Worker binding。
# 可通过 CONFIG_FILE 指定配置文件，通过 DRY_RUN=true 只测速不更新。

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="${BASE_DIR:-$SCRIPT_DIR}"
CONFIG_FILE="${CONFIG_FILE:-$BASE_DIR/config.conf}"

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
: "${LOCK_DIR:=$BASE_DIR/.update.lock}"
: "${DRY_RUN:=false}"

cd "$BASE_DIR"

fail() { echo "错误: $*" >&2; exit 1; }
require_command() { command -v "$1" >/dev/null 2>&1 || fail "未找到命令 $1，请先安装它"; }
is_uint() { [[ "$1" =~ ^[0-9]+$ ]]; }

require_command curl
require_command awk
require_command sort
[[ -x ./cfst ]] || fail "未找到可执行的 ./cfst，请先运行 install.sh"
[[ -n "$ACCOUNT_ID" && "$ACCOUNT_ID" != "你的Account_ID" ]] || fail "ACCOUNT_ID 未配置"
[[ -n "$WORKER_NAME" && "$WORKER_NAME" =~ ^[A-Za-z0-9_-]+$ ]] || fail "WORKER_NAME 只能包含字母、数字、下划线和短横线"
[[ -n "$ENV_VAR_NAME" && "$ENV_VAR_NAME" =~ ^[A-Za-z0-9_-]+$ ]] || fail "ENV_VAR_NAME 只能包含字母、数字、下划线和短横线"
if [[ "$DRY_RUN" != "true" ]]; then
  [[ -n "$API_TOKEN" && "$API_TOKEN" != "你的API_Token" ]] || fail "API_TOKEN 未配置"
fi
for value in "$N" "$DN" "$TL" "$CURL_TIMEOUT" "$CURL_RETRIES"; do
  is_uint "$value" || fail "测速/网络参数必须是非负整数: $value"
done

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  fail "已有另一个更新任务运行中（锁目录: $LOCK_DIR）"
fi
cleanup() { rm -rf -- "$LOCK_DIR" "${TMP_DIR:-}"; }
trap cleanup EXIT
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cfst-proxyip.XXXXXX")"

fetch_ips() {
  local url="$1" output="$2"
  [[ -n "$url" ]] || return 0
  curl --fail --silent --show-error --location --max-time "$CURL_TIMEOUT" \
    --retry "$CURL_RETRIES" --retry-delay 2 "$url" 2>/dev/null |
    grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' |
    awk -F. '($1<=255 && $2<=255 && $3<=255 && $4<=255) {print}' >> "$output" || true
}

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
  echo "[3/4] 更新 Workers ${ENV_VAR_NAME}..."
  RESPONSE_FILE="$TMP_DIR/response.json"
  HTTP_CODE="$(curl --silent --show-error --location --output "$RESPONSE_FILE" --write-out '%{http_code}' \
    --request PATCH "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/workers/scripts/${WORKER_NAME}/settings" \
    --header "Authorization: Bearer ${API_TOKEN}" --header 'Content-Type: application/json' \
    --data "{\"bindings\":[{\"type\":\"plain_text\",\"name\":\"${ENV_VAR_NAME}\",\"text\":\"${BEST_IP}\"}]}" || true)"
  if [[ "$HTTP_CODE" =~ ^2[0-9][0-9]$ ]] && grep -q '"success"[[:space:]]*:[[:space:]]*true' "$RESPONSE_FILE"; then
    echo "  更新成功！${ENV_VAR_NAME} = $BEST_IP"
    printf '%s %s=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$ENV_VAR_NAME" "$BEST_IP" >> update.log
  else
    echo "  Cloudflare API 更新失败（HTTP ${HTTP_CODE:-unknown}）:" >&2
    cat "$RESPONSE_FILE" >&2
    exit 1
  fi
fi

echo "[4/4] 完成 $(date '+%Y-%m-%d %H:%M:%S')"
