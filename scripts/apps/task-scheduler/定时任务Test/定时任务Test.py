#!/usr/bin/env python3
from __future__ import annotations
import argparse, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'libs' / '_windows_helpers'))
from _windows_helpers import require_windows, run

def default_task_path() -> str:
    return str(Path(__file__).resolve().parents[1] / 'task-action' / 'task-action.py')

def main() -> int:
    require_windows()
    parser = argparse.ArgumentParser()
    parser.add_argument('--task-name', default='DailyMorningTask')
    parser.add_argument('--task-time', default='08:00')
    parser.add_argument('--task-path', default=default_task_path())
    args = parser.parse_args()
    task_path = str(Path(args.task_path).resolve())
    print(f'Creating scheduled task: {args.task_name}')
    print(f'Script path: {task_path}')
    print(f'Execution time: {args.task_time} daily')
    run(['schtasks','/Delete','/TN',args.task_name,'/F'], check=False)
    action = f'python "{task_path}"'
    result = run(['schtasks','/Create','/TN',args.task_name,'/TR',action,'/SC','DAILY','/ST',args.task_time,'/F'], check=False)
    if result.returncode == 0:
        print('Task created successfully!')
        run(['schtasks','/Query','/TN',args.task_name], check=False)
    else:
        print(f'Failed to create task. Exit code: {result.returncode}')
        print('This might require administrator privileges')
    return result.returncode
if __name__ == '__main__': raise SystemExit(main())
