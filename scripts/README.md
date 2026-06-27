# Scripts

本目录保存仓库级工具脚本。脚本类文件采用“一脚本一目录”结构：每个脚本都放在独立文件夹内，并配套一个中文 `README.md` 描述用途、运行方式和维护说明。

## 目录约定

- `apps/codex/`：Codex heartbeat、启动器和 Chrome DevTools MCP 辅助脚本。
- `apps/task-scheduler/`：Windows 计划任务创建、检查和测试样本。
- `apps/file-transfer/`：DR Laser 数据复制、上传和每日统计脚本。
- `apps/cc-connect/`：cc-connect 隐藏启动和重启脚本。
- `apps/windows-shell/`：Windows Explorer、文件关联和右键菜单脚本。
- `libs/`：共享 Python helper 模块，每个模块也独立成目录。
- `bootstrap/`：安装或初始化脚本中枢的脚本。
- `config/`：历史脚本相关配置快照，不按脚本目录规则移动。
- `legacy/`：为追溯保留的旧记录或占位文件。

## 使用方式

进入具体脚本目录阅读 `README.md`。示例：

```bash
python3 scripts/apps/codex/codex_heartbeat/codex_heartbeat.py --quiet
bash scripts/tmux_process_windows/tmux_process_windows.sh summary
```
