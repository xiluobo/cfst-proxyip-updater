# CFST ProxyIP Auto Updater

Automatically benchmark Cloudflare proxy/optimized IPs and safely update Cloudflare Workers plain-text bindings.

This project is designed for long-running VPS deployments where proxy IP lists need to be periodically tested, filtered, and updated without replacing a previously working configuration when an update fails.

## Highlights

- 🔍 Benchmark and filter Cloudflare proxy/optimized IPv4 addresses
- 🌐 Combine the official `ip.txt` with configurable public IP sources
- ⚡ Use CFST latency testing with configurable region and threshold filters
- 🛡️ Fail-safe updates using temporary files and validation before replacement
- 🔒 Prevent concurrent executions with a lock
- ☁️ Validate Cloudflare API responses before accepting an update
- 🧩 Preserve existing Worker bindings while updating selected variables
- 🧪 Support `--dry-run` for safe first-time testing
- 🔄 Support multiple Worker bindings
- ⏰ Support cron and systemd timers for scheduled execution
- 🩺 Include a health-check script for operational diagnostics

## How it works

```text
IP sources
    ↓
merge / deduplicate / validate
    ↓
CFST benchmark
    ↓
filter by region / latency
    ↓
validate result
    ↓
update Cloudflare Worker binding
```

If the benchmark or Cloudflare API update fails, the previous working configuration is preserved.

## Requirements

- Debian/Ubuntu VPS
- Bash and common Unix utilities
- `curl`
- `jq`
- `cfst` available to the installation script
- A Cloudflare API token with the permissions required to update the target Worker

## One-command installation

The following command downloads the project and runs the installer:

```bash
bash -c 'set -Eeuo pipefail; TMP_DIR="$(mktemp -d)"; trap "rm -rf \"$TMP_DIR\"" EXIT; curl -fsSL https://github.com/xiluobo/cfst-proxyip-updater/archive/refs/heads/main.tar.gz | tar -xz -C "$TMP_DIR"; cd "$TMP_DIR/cfst-proxyip-updater-main"; sudo ./install.sh'
```

After installation, edit the configuration:

```bash
sudo nano /opt/cfst_proxyip/config.conf
```

At minimum, configure:

```ini
ACCOUNT_ID="your_account_id"
API_TOKEN="your_api_token"
WORKER_NAME="your_worker_name"
ENV_VAR_NAME="proxyip"
# Optional: update multiple bindings at once
ENV_VAR_NAMES="proxyip,proxyip_backup"
```

> **Security:** Never commit a real `config.conf` or expose your Cloudflare API token. Use `config.example.conf` as the template.

## First run: dry-run mode

Before changing Cloudflare, validate the setup with dry-run mode:

```bash
cd /opt/cfst_proxyip
sudo ./update_proxyip.sh --dry-run
```

After confirming the benchmark results, run the real update:

```bash
sudo /opt/cfst_proxyip/update_proxyip.sh
```

## Uninstall

```bash
sudo /opt/cfst_proxyip/uninstall.sh
```

The uninstall script removes the installation directory and the cron/systemd scheduling configured by the installer.

## Manual installation

```bash
git clone https://github.com/xiluobo/cfst-proxyip-updater.git
cd cfst-proxyip-updater
cp config.example.conf config.conf
nano config.conf
sudo ./install.sh
cd /opt/cfst_proxyip
./update_proxyip.sh --dry-run
```

The API token should have the minimum permissions required for the target Worker update. Do not commit `config.conf` containing real credentials.

By default, the installer configures execution every 6 hours. You can disable either scheduler in `config.conf`:

```ini
INSTALL_CRON=false
INSTALL_SYSTEMD=false
```

Example cron entry:

```cron
0 */6 * * * /opt/cfst_proxyip/update_proxyip.sh >> /opt/cfst_proxyip/cron.log 2>&1
```

## Configuration

- `CFCOLO`: e.g. `TPE,KHH` or `HKG`; empty means no region restriction
- `N` / `DN` / `TL`: CFST test count, download threads, and latency threshold
- `USE_PUBLIC_PROXY_IP`: whether to fetch public IP sources
- `IP_FILE`: local IP source used by the updater
- `CURL_TIMEOUT` / `CURL_RETRIES` / `RETRY_DELAY`: public-source request timeout and retry controls
- `LOG_FILE`: update log path
- `LOG_KEEP_DAYS`: retention period for old logs
- `DRY_RUN`: when `true`, do not call the Cloudflare update API
- `ENV_VAR_NAME`: single binding name for compatibility
- `ENV_VAR_NAMES`: comma-separated list of binding names
- `INSTALL_CRON`: whether installation should configure cron
- `INSTALL_SYSTEMD`: whether installation should configure a systemd timer
- `SYSTEMD_SERVICE_NAME`: systemd service/timer name

See `config.example.conf` for the complete configuration reference.

## Advanced usage

Override configuration values from the command line:

```bash
cd /opt/cfst_proxyip
./update_proxyip.sh --config /opt/cfst_proxyip/config.conf --dry-run --log /opt/cfst_proxyip/update.log
```

Check Worker bindings without benchmarking or updating:

```bash
cd /opt/cfst_proxyip
./update_proxyip.sh --check-only
```

Run operational diagnostics:

```bash
cd /opt/cfst_proxyip
./healthcheck.sh
```

## Troubleshooting

- **No benchmark results:** check VPS connectivity or relax `CFCOLO` / increase `TL`.
- **Worker update fails:** verify Account ID, Worker name, token permissions, and the API error printed by the script.
- **Scheduled task does not run:** inspect `cron.log` or `systemctl status` for the configured service/timer and verify that `cfst`, `config.conf`, and `ip.txt` are available under `/opt/cfst_proxyip`.

## Project structure

```text
config.example.conf                 # Configuration template
healthcheck.sh                       # Worker binding and log diagnostics
install.sh                           # Debian/Ubuntu installation script
uninstall.sh                         # Uninstall script
update_proxyip.sh                    # Main updater
cfst-proxyip-updater.service         # systemd service
cfst-proxyip-updater.timer           # systemd timer
.github/ISSUE_TEMPLATE/              # Issue templates
.github/workflows/test.yml           # Shell syntax and repository checks
```

## Contributing

Bug reports, feature requests, documentation improvements, and pull requests are welcome. Please avoid posting credentials, API tokens, or private deployment details in issues or logs.

## License

This project is currently provided for learning and personal use. Please comply with the Cloudflare Terms of Service and the terms of any third-party IP sources you use.
