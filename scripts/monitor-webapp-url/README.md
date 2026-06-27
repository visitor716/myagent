# monitor-webapp-url.sh

## 用途

监控 TG_WEBAPP_URL 的公网可用性，在持续不可用时可轮换 Cloudflare quick tunnel、更新 .env 并重启网关。

## 运行方式

```bash
bash scripts/monitor-webapp-url/monitor-webapp-url.sh --help
```

## 维护说明

- 原始位置：`scripts/monitor-webapp-url.sh`
- 当前脚本：`scripts/monitor-webapp-url/monitor-webapp-url.sh`
- 如需调整参数或路径，优先修改脚本内显式配置，并同步更新本 README。
