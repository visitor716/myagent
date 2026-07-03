# 重启网卡

用于在 Windows 上快速重启指定网络适配器，默认目标是无线网卡 `WLAN`。

脚本会：

- 检查目标网卡是否存在
- 在需要时自动请求管理员权限
- 从 `\\wsl.localhost\...` 路径启动时，提权前复制到 Windows 临时目录，避免管理员 PowerShell 访问 WSL UNC 路径失败
- 执行 `Restart-NetAdapter`
- 等待网卡恢复到 `Up`
- 输出当前 WLAN 状态
- 可选做一次公网连通性探测
- 探测失败时，继续刷新 DNS/DHCP，并重启 WLAN AutoConfig 服务后重新连接当前 SSID
- 如果最近发生 `0x9f DRIVER_POWER_STATE_FAILURE` 蓝屏/异常重启，会打印提示：这类驱动电源崩溃不是重启网卡脚本能根治的

## Windows 运行

脚本目录内的双击入口：

```text
重启WLAN网卡.lnk
```

这个快捷方式直接调用 `restart-network-adapter.ps1`，不是 `.cmd` 包装器。

从 PowerShell 运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\restart-network-adapter.ps1 -PauseAfterRun
```

指定其他网卡：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\restart-network-adapter.ps1 -AdapterName "以太网" -PauseAfterRun
```

## PowerShell 运行

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\restart-network-adapter.ps1
```

只检查将要执行的动作，不真正重启：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\restart-network-adapter.ps1 -WhatIf
```

## WSL 运行

在仓库根目录执行：

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w scripts/apps/windows-shell/restart-network-adapter/restart-network-adapter.ps1)"
```

## 维护说明

- `Restart-NetAdapter` 需要管理员权限；非管理员运行时脚本会弹出 UAC 提权窗口。
- 双击目录内快捷方式会运行 `.ps1`，并在执行结束后保留窗口，方便查看是否恢复成功。
- 默认只重启 `WLAN`，不会修改驱动、代理、DNS、路由或电源计划。
- 如果重启网卡后能恢复联网，说明问题更偏向网卡/驱动/无线协商状态卡住，而不是整机必须重启。
- 如果 Windows 事件日志显示连续 `0x9f DRIVER_POWER_STATE_FAILURE`，应优先排查最近的系统/驱动更新或 dump 文件；本脚本只能做恢复动作，不能修复底层驱动电源状态死锁。
