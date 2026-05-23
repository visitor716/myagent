使用中文回复，除非用户明确要求使用其他语言。
Git 提交信息优先使用中文，除非仓库约定或用户明确要求使用其他语言。
cc-switch官方地址： https://github.com/farion1231/cc-switch 

2026-05-23 Codex 使用偏好：
- 用户信任 Codex 在本机全自动管理本地工作；默认保持 approval_policy=never 和 sandbox_mode=danger-full-access，除非用户明确要求降低权限。
- 浏览器自动化从 WSL 走 /home/zhanxp/projects/myagent/skills/skills-local/wsl-windows-chrome，不使用 Chrome/Browser MCP；连接不上专用 Windows Chrome CDP 时输出诊断，不回退到新的 WSL/Linux 浏览器。
- 长期记忆 source of truth 位于 /home/zhanxp/projects/myagent/docs/agent-memory/，稳定偏好、决策和未完成事项应写入该目录。
- 本机 heartbeat 由 /home/zhanxp/projects/myagent/scripts/codex_heartbeat.py 生成，不启用 MCP，不启动 fallback 浏览器。
