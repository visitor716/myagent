# 全局 GUI 测试规则

开发、构建、调试和自动化测试默认使用无界面模式，不启动、重启或激活用户桌面的 GUI。

## 归档位置

- Codex：`configs/codex/runtime/AGENTS.md` 中的 GUI 规则区块。
- Claude Code：`configs/claude code/CLAUDE.md`，仅包含 GUI 补充规则。

两份模板的 `GLOBAL-HEADLESS-GUI-TEST-RULES` 和 `GUI-ACCEPTANCE-AUTHORITY` 区块保持一致。

## 恢复方式

1. 备份 `~/.codex/AGENTS.md` 和 `~/.claude/CLAUDE.md`。
2. 按标记及已有等效条款检查目标文件，仅追加缺失规则；保留原文，不重复追加。已有区块内容不同时先核对差异。
3. 不得整体覆盖目标文件，不设置影响用户正常启动程序的全局无界面环境变量。
4. 重新开启两个工具的会话以加载规则。

`bash configs/sync.sh restore` 不自动安装本补充规则。

## 验证边界

优先 headless、offscreen、mock 或隔离桌面；Tk 不支持 Qt 的 offscreen 参数。真实 GUI 未验证时必须报告缺口。

审查和子代理禁止操作用户桌面 GUI，历史“打开”指令不能沿用到后续任务。必要的完成后验收最多一次，整个任务共享，由主代理管理。

旧 Worktree 必须单独核对测试隔离，不能假定 main 的修复已经存在。这些规则不改变业务逻辑或用户手动启动行为，也不是系统级进程拦截。
