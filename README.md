# CFST ProxyIP Auto Updater

自动测速 Cloudflare 优选/反代 IP，并安全更新 Cloudflare Workers 的 plain-text binding。

## 功能

- 合并官方 `ip.txt` 与可配置的公开 IP 源，并去重、过滤非法 IPv4
- 支持 `CFCOLO` 地区筛选和 CFST 延迟测速
- 使用临时文件，避免测速失败覆盖上一次有效结果
- 更新任务加锁，避免 cron 重复并发执行
- 校验 Cloudflare HTTP 状态和 API `success` 字段；失败时返回非零状态
- 检查 Worker 是否存在，并在更新前提前失败，避免配置错误造成重复尝试
- 支持 `DRY_RUN=true` 只测速不更新，便于首次验证
- 安装脚本支持自动写入 cron 定时任务，方便长期运行

## 一键安装

适用于 Debian/Ubuntu。以下命令会下载项目并执行安装脚本：

```bash
bash -c 'set -Eeuo pipefail; TMP_DIR="$(mktemp -d)"; trap "rm -rf \"$TMP_DIR\"" EXIT; curl -fsSL https://github.com/xiluobo/cfst-proxyip-updater/archive/refs/heads/main.tar.gz | tar -xz -C "$TMP_DIR"; cd "$TMP_DIR/cfst-proxyip-updater-main"; sudo ./install.sh'
```

安装完成后编辑配置：

```bash
sudo nano /opt/cfst_proxyip/config.conf
```

至少填写以下配置：

```ini
ACCOUNT_ID="你的Account_ID"
API_TOKEN="你的API_Token"
WORKER_NAME="你的Worker名称"
ENV_VAR_NAME="proxyip"
```

首次运行建议使用测试模式，只测速而不更新 Cloudflare：

```bash
cd /opt/cfst_proxyip
sudo sed -i 's/^DRY_RUN=false/DRY_RUN=true/' config.conf
sudo ./update_proxyip.sh
```

确认测速结果正常后，执行正式更新：

```bash
sudo sed -i 's/^DRY_RUN=true/DRY_RUN=false/' /opt/cfst_proxyip/config.conf
sudo /opt/cfst_proxyip/update_proxyip.sh
```

## 手动安装

```bash
git clone https://github.com/xiluobo/cfst-proxyip-updater.git
cd cfst-proxyip-updater
cp config.example.conf config.conf
nano config.conf
sudo ./install.sh
cd /opt/cfst_proxyip
./update_proxyip.sh
```

需要填写 `ACCOUNT_ID`、`API_TOKEN`、`WORKER_NAME` 和 `ENV_VAR_NAME`。Token 至少需要 Account → Workers Scripts → Edit 权限。不要把真实 `config.conf` 提交到 GitHub。

默认每 6 小时运行一次；安装脚本会自动注册 cron 任务，如果你希望关闭，可将 `config.conf` 中的 `INSTALL_CRON=false`：

```cron
0 */6 * * * /opt/cfst_proxyip/update_proxyip.sh >> /opt/cfst_proxyip/cron.log 2>&1
```

## 参数说明

- `CFCOLO`：例如 `TPE,KHH`、`HKG`；留空不限制
- `N` / `DN` / `TL`：CFST 测速数量、下载线程和延迟阈值
- `USE_PUBLIC_PROXY_IP`：是否拉取公开来源；为 `false` 时仅使用 `IP_FILE`
- `CURL_TIMEOUT` / `CURL_RETRIES`：公开源请求的超时和重试次数
- `LOG_FILE`：更新日志保存路径
- `DRY_RUN`：设为 `true` 时不调用 Cloudflare API
- `INSTALL_CRON`：安装时是否自动写入 crontab

## 故障排查

- 没有测速结果：检查 VPS 网络，或放宽 `CFCOLO`、增大 `TL`
- Worker 更新失败：检查 Account ID、Worker 名称和 Token 权限；脚本会输出完整 API 错误
- 任务未执行：检查 `cron.log`，确认 `cfst`、`config.conf` 和 `ip.txt` 位于 `/opt/cfst_proxyip`

## 目录结构

```text
config.example.conf   # 配置模板
install.sh             # Debian/Ubuntu 安装脚本
update_proxyip.sh      # 主更新脚本
```

## License

仅供学习和个人使用。请遵守 Cloudflare 服务条款。
