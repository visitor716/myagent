#!/usr/bin/env python3
from __future__ import annotations
import argparse
import time
from pathlib import Path
from _windows_helpers import require_windows, run


def default_log_path() -> str:
    return str(Path(__file__).resolve().parent / 'Test' / 'task-action.log')


def main() -> int:
    require_windows()
    parser = argparse.ArgumentParser(description='运行 Windows 计划任务并查看日志')
    parser.add_argument('--task-name', default='DailyMorningTask', help='计划任务名称')
    parser.add_argument('--log-file', default=default_log_path(), help='日志文件路径')
    parser.add_argument('--wait', type=int, default=3, help='任务启动后等待秒数（默认 3）')
    args = parser.parse_args()

    print(f'正在运行计划任务: {args.task_name}')
    result = run(['schtasks', '/Run', '/TN', args.task_name], check=False)

    if result.returncode != 0:
        print(f'任务启动失败，错误码: {result.returncode}')
        return result.returncode

    print('任务启动成功！')

    if args.wait > 0:
        print(f'等待 {args.wait} 秒...')
        time.sleep(args.wait)

    log_path = Path(args.log_file)
    print(f'正在查看日志: {log_path}')
    print('-' * 50)

    if not log_path.exists():
        print(f'日志文件不存在: {log_path}')
        return 1

    try:
        print(log_path.read_text(encoding='utf-8'))
    except Exception as e:
        print(f'读取日志失败: {e}')
        return 1

    print('-' * 50)
    print('日志查看完毕')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
