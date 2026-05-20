#!/usr/bin/env python3
from __future__ import annotations
from datetime import datetime
from pathlib import Path
LOG_PATH = Path(r'D:\DevProject\脚本\Test\定时任务测试样本.log')
def main():
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    with LOG_PATH.open('a', encoding='utf-8') as h:
        h.write(f"Task ran at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
    return 0
if __name__ == '__main__': raise SystemExit(main())
