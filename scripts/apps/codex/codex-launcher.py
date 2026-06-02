#!/usr/bin/env python3
# Codex 交互式启动器 - 选择 Chrome DevTools MCP 模式

import subprocess
import sys
import os
from pathlib import Path


def main():
    print("=" * 50)
    print("  NeoCD - Codex 启动器")
    print("=" * 50)
    print()
    print("请选择 Chrome DevTools MCP 连接模式：")
    print()
    print("  [1] 自动连接模式 (auto)")
    print("      - 自动连接到可用的 Chrome 浏览器")
    print()
    print("  [2] 固定端口模式 (fixed)")
    print("      - 连接到 http://127.0.0.1:9222")
    print("      - 会自动启动独立 profile 的 Chrome")
    print()
    print("  [0] 取消")
    print()

    while True:
        choice = input("请输入选项 (0-2): ").strip()

        if choice == "0":
            print("已取消")
            return 0
        elif choice == "1":
            return launch_codex(auto=True)
        elif choice == "2":
            return launch_codex(auto=False)
        else:
            print("无效选项，请重新输入！")


def launch_codex(auto: bool) -> int:
    codex_cmd = ["codex"]

    if not auto:
        # 固定端口模式
        print("\n正在启动独立 profile 的 Chrome...")
        chrome_script = Path(__file__).parent / "chrome-devtool-mcp" / "start-chrome-mcp-fixed-profile.py"
        subprocess.Popen([sys.executable, str(chrome_script)])

        # 禁用自动模式，启用固定端口模式
        codex_cmd.extend([
            "--disable", "mcp_servers.chrome-devtools",
            "--enable", "mcp_servers.chrome-devtools-fixed"
        ])

    # 传递额外的参数
    if len(sys.argv) > 1:
        codex_cmd.extend(sys.argv[1:])

    print(f"\n正在启动 Codex...\n命令: {' '.join(codex_cmd)}\n")
    return subprocess.call(codex_cmd)


if __name__ == "__main__":
    raise SystemExit(main())
