# Shadowrocket 自动规则
此目录与现有 cfst-proxyip-updater 项目隔离。仅发布已审核的 8 个域名规则，不包含原始 iPhone 隐私报告。
- 订阅: https://raw.githubusercontent.com/xiluobo/cfst-proxyip-updater/main/shadowrocket/dist/personal_ads.sgmodule
- GitHub Actions: Shadowrocket rules validation and publish（每日调度，且规则或脚本变更时触发）
- 更新审核名单: shadowrocket/data/approved_domains.txt；新增域名必须同时出现在脱敏的 observed_domains.ndjson 中。
- 自动检测仅指构建测试，不包含手机流量实时采集或自动广告识别。
- 真实拦截与误杀需在 iPhone Shadowrocket 请求日志中验证；无需 HTTPS 解密。
- 不要将原始隐私报告、账号、请求 URL、Token 上传到公开仓库。
