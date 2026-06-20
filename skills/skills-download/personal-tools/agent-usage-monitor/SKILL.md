---
name: agent-usage-monitor
description: 监控多个 Agent 的使用量，定期截图并发送通知
argument-hint: "setup | run | config | status"
---

# Agent 使用量监控

## 使用方法

### setup - 初始化配置
```
/agent-usage-monitor setup
```
创建配置文件并进行初始设置。

### run - 运行一次监控
```
/agent-usage-monitor run
```
立即执行一次监控，截图所有启用的 Agent 使用量并发送通知。

### config - 查看/编辑配置
```
/agent-usage-monitor config
```
查看当前配置并提示编辑。

### status - 检查状态
```
/agent-usage-monitor status
```
检查监控工具的状态，包括浏览器连接、通知服务等。

## 定时任务

使用 loop 技能设置每 30 分钟执行一次：
```
/loop 30m /agent-usage-monitor run
```

## 配置文件位置

配置文件位于：`/home/zhanxp/projects/myagent/skills/agent-usage-monitor/config.json`
