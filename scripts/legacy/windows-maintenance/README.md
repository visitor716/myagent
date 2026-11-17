# Windows 维护脚本归档

本目录保存从 Windows 桌面迁入的历史系统排障脚本。文件保持原名和原始内容，移动记录及 SHA-256 位于 `00_资料索引/`。

## 分类

- `power/`：关闭快速启动和休眠的历史脚本。
- `diagnostics/`：HP OMEN 驱动状态检查脚本。
- `dump-analysis/`：以管理员权限启动蓝屏 Dump 分析的历史入口。

## 已知限制

- `diagnostics/驱动健康检查.ps1` 包含 2026 年 7 月排障时的固定版本与风险判断，不能作为当前驱动状态的权威结论。
- `dump-analysis/双击我-管理员分析蓝屏dump.cmd` 依赖 `%TEMP%\myagent-analyze-bugcheck-dump\analyze-bugcheck-dump.ps1`；迁移时该依赖已不存在，因此当前仅作历史归档。
- `network-power-monitor/` 已迁移到项目的 `logs/network-power-monitor/`，作为持续更新的本机排障资料；桌面的其他数据目录和快捷方式未纳入本次归档。
