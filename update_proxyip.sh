#!/bin/bash
set -e
cd /opt/cfst_proxyip 2>/dev/null || cd "$(dirname "$0")"
source config.conf

echo "=========================================="
echo "  CFST 优选IP → 自动更新 Workers proxyip"
echo "  时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "  地区: ${CFCOLO:-不限制}"
echo "=========================================="

if [ ! -f ./cfst ]; then
  echo "错误: 未找到 cfst，请先运行 install.sh"
  exit 1
fi

if [ -z "$API_TOKEN" ] || [ "$API_TOKEN" = "你的API_Token" ]; then
  echo "错误: 请先在 config.conf 中填写有效的 API_TOKEN"
  exit 1
fi

echo "[1/4] 准备IP列表..."
if [ "$USE_PUBLIC_PROXY_IP" = "true" ]; then
  > "$PROXY_IP_FILE"
  curl -sL "$PROXY_SOURCE1" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' >> "$PROXY_IP_FILE" || true
  curl -sL "$PROXY_SOURCE2" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' >> "$PROXY_IP_FILE" || true
  sort -u "$PROXY_IP_FILE" -o "$PROXY_IP_FILE" 2>/dev/null || true
  [ -f "$IP_FILE" ] && cat "$IP_FILE" >> "$PROXY_IP_FILE" && sort -u "$PROXY_IP_FILE" -o "$PROXY_IP_FILE"
  TEST_FILE="$PROXY_IP_FILE"
  echo "  公开源+官方IP已合并"
else
  TEST_FILE="$IP_FILE"
fi

echo "[2/4] 开始测速（仅延迟，适合小机器）..."
ARGS="-n ${N:-100} -dn ${DN:-5} -tl ${TL:-300} -dd -o ${RESULT:-result.csv} -f $TEST_FILE"
if [ -n "$CFCOLO" ]; then
  ARGS="$ARGS -httping -cfcolo $CFCOLO"
fi
./cfst $ARGS || ./cfst -n ${N:-100} -dn ${DN:-5} -tl ${TL:-400} -dd -o ${RESULT:-result.csv} -f ${IP_FILE:-ip.txt}

BEST_IP=$(tail -n +2 "${RESULT:-result.csv}" 2>/dev/null | head -1 | cut -d, -f1 | tr -d ' \r')
if [ -z "$BEST_IP" ]; then
  echo "错误: 无法获取最快IP，请检查网络或放宽 CFCOLO / TL"
  exit 1
fi
echo "  最快IP: $BEST_IP"

echo "[3/4] 更新 Workers ${ENV_VAR_NAME}..."
RESPONSE=$(curl -s -X PATCH \
  "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/workers/scripts/${WORKER_NAME}/settings" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"bindings\":[{\"type\":\"plain_text\",\"name\":\"${ENV_VAR_NAME}\",\"text\":\"${BEST_IP}\"}]}")

if echo "$RESPONSE" | grep -q '"success":true'; then
  echo "  更新成功！${ENV_VAR_NAME} = $BEST_IP"
else
  echo "  API 返回: $RESPONSE"
  echo "  请检查 Token 权限（需要 Workers Scripts Edit）和 Account/Worker 名称"
fi

echo "[4/4] 完成 $(date '+%Y-%m-%d %H:%M:%S')"
echo "$(date '+%Y-%m-%d %H:%M:%S') ${ENV_VAR_NAME}=$BEST_IP" >> update.log
echo "=========================================="
