# CFST ProxyIP Auto Updater

自动测速 Cloudflare 优选/反代 IP，并安全更新 Cloudflare Workers 的 plain-text binding。

## 功能

- 合并官方 `ip.txt` 与可配置的公开 IP 源，并去重、过滤非法 IPv4
- 支持 `CFCOLO` 地区筛选和 CFST 延迟测速
- 使用临时文件，避免测速失败覆盖上一次有效结果
- 更新任务加锁，避免 cron 重复并发执行
- 校验 Cloudflare HTTP 状态和 API `success` 字段；失败时返回非零状态
- 更新前会校验 Worker 是否存在，并保留现有其他 binding，避免覆盖其他环境变量
- 支持 `DRY_RUN=true` 只测速不更新，便于首次验证
- 安装脚本支持自动写入 cron 定时任务与 systemd timer，方便长期运行

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
sudo ./update_proxyip.sh --dry-run
```

确认测速结果正常后，执行正式更新：

```bash
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
./update_proxyip.sh --dry-run
```

需要填写 `ACCOUNT_ID`、`API_TOKEN`、`WORKER_NAME` 和 `ENV_VAR_NAME`。Token 至少需要 Account → Workers Scripts → Edit 权限。不要把真实 `config.conf` 提交到 GitHub。

默认每 6 小时运行一次；安装脚本会自动注册 cron 任务和 systemd timer。若想关闭某一种，可在 `config.conf` 中设置：

```ini
INSTALL_CRON=false
INSTALL_SYSTEMD=false
```

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
- `INSTALL_SYSTEMD`：安装时是否自动注册 systemd timer
- `SYSTEMD_SERVICE_NAME`：systemd 定时任务命名

## 高级用法

支持通过命令行覆盖配置：

```bash
cd /opt/cfst_proxyip
./update_proxyip.sh --config /opt/cfst_proxyip/config.conf --dry-run --log /opt/cfst_proxyip/update.log
```

运行状态检查：

```bash
cd /opt/cfst_proxyip
./healthcheck.sh
```

## 故障排查

- 没有测速结果：检查 VPS 网络，或放宽 `CFCOLO`、增大 `TL`
- Worker 更新失败：检查 Account ID、Worker 名称和 Token 权限；脚本会输出完整 API 错误
- 任务未执行：检查 `cron.log` 或 `systemctl status cfs...`，确认 `cfst`、`config.conf` 和 `ip.txt` 位于 `/opt/cfst_proxyip`

## 目录结构

```text
config.example.conf   # 配置模板
healthcheck.sh        # 诊断当前 Worker 绑定与日志
install.sh             # Debian/Ubuntu 安装脚本
update_proxyip.sh      # 主更新脚本
cfst-proxyip-updater.service
cfst-proxyip-updater.timer
```

## License

仅供学习和个人使用。请遵守 Cloudflare 服务条款。
