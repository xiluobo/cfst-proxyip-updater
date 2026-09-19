# CFST ProxyIP Auto Updater

自动测速 Cloudflare 优选/反代 IP，并更新到 Cloudflare Workers 的 `proxyip` 变量。

适用于：
- Google Cloud 免费 e2-micro / 其他 Linux VPS
- 需要给 Workers（如 square 项目）自动更换 proxyip 的场景

## 功能

- 自动拉取公开优选/反代 IP 列表
- 支持指定国家/地区（`-cfcolo`）
- 测速后自动更新 Workers 环境变量 `proxyip`
- 可配合 crontab 定时检测与更新

## 快速开始

### 1. 克隆仓库

```bash
git clone https://github.com/你的用户名/cfst-proxyip-updater.git
cd cfst-proxyip-updater
```

### 2. 配置

```bash
cp config.example.conf config.conf
nano config.conf
```

填写：
- `ACCOUNT_ID`：Cloudflare 账号 ID
- `API_TOKEN`：具有 Workers Scripts Edit 权限的 Token
- `WORKER_NAME`：Worker 名称（如 square）
- `ENV_VAR_NAME`：变量名（默认 proxyip）
- `CFCOLO`：优选地区，如 `TPE,KHH`（台湾）、`HKG`（香港），留空不限制

### 3. 安装并运行

```bash
chmod +x install.sh update_proxyip.sh
sudo ./install.sh
cd /opt/cfst_proxyip
./update_proxyip.sh
```

### 4. 定时任务（每 6 小时）

```bash
crontab -e
```

添加：

```
0 */6 * * * /opt/cfst_proxyip/update_proxyip.sh >> /opt/cfst_proxyip/cron.log 2>&1
```

## 创建 API Token

1. 打开 https://dash.cloudflare.com/profile/api-tokens
2. Create Token → Custom token
3. 权限：
   - Account → Workers Scripts → **Edit**
4. 创建后复制 Token 填入 `config.conf`

## 注意事项

- **不要**把含真实 `API_TOKEN` 的 `config.conf` 提交到 GitHub
- Google Cloud 免费机器性能有限，建议使用 `-dd`（只测延迟）或减小测速数量
- 从美国机房测台湾/香港节点可能结果较少，可按实际网络调整 `CFCOLO`

## 目录结构

```
├── config.example.conf   # 配置模板（可提交）
├── install.sh            # 安装脚本
├── update_proxyip.sh     # 主更新脚本
└── README.md
```

## License

仅供学习与个人使用。请遵守 Cloudflare 服务条款。
