#!/usr/bin/env python3
# 启动固定独立 Profile 的 Chrome，供 Codex 的 chrome-mcp-fixed-profile 配置使用。

import os
import subprocess
from pathlib import Path

chrome_path = r'C:\Program Files\Google\Chrome\Application\chrome.exe'
profile_dir = r'C:\Users\zhanxp\.codex\chrome-mcp-profile'
remote_debugging_port = 9222

# 检查 Chrome 是否存在
if not Path(chrome_path).exists():
    raise FileNotFoundError(f'未找到 Chrome：{chrome_path}')

# 创建 profile 目录（如果不存在）
Path(profile_dir).mkdir(parents=True, exist_ok=True)

# 启动 Chrome
args = [
    chrome_path,
    f'--remote-debugging-port={remote_debugging_port}',
    f'--user-data-dir={profile_dir}',
    '--no-first-run',
    '--no-default-browser-check'
]

# 使用 subprocess.Popen 启动，不等待进程结束
subprocess.Popen(args, shell=False)
