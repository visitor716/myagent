#!/usr/bin/env python3
from __future__ import annotations
import argparse, subprocess
from _windows_helpers import require_windows, run

def main():
    require_windows()
    p = argparse.ArgumentParser(); p.add_argument('--task-name', default='DailyMorningTask'); args = p.parse_args()
    print(f'Checking scheduled task: {args.task_name}')
    result = subprocess.run(['schtasks','/Query','/TN',args.task_name,'/FO','LIST','/V'], text=True)
    if result.returncode == 0: return 0
    print(f"Task '{args.task_name}' not found")
    print('Available tasks:')
    run(['schtasks','/Query','/FO','TABLE'], check=False)
    return result.returncode
if __name__ == '__main__': raise SystemExit(main())
