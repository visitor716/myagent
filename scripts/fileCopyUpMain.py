#!/usr/bin/env python3
from __future__ import annotations
import argparse, shutil
from datetime import datetime, timedelta
from pathlib import Path
from _windows_helpers import copy_then_move, ensure_dir

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--alarm-path', default=r'D:\DRLaser\ALARM\Alarm')
    parser.add_argument('--ccd-alarm-path', default=r'D:\DRLaser\ALARM\CCDAlarm')
    parser.add_argument('--data-total-path', default=r'D:\DRLaser\DataTotal')
    parser.add_argument('--machine-number-file', default=r'D:\DRLaser\ALARM\MachineNumber.txt')
    parser.add_argument('--machine-number', default='')
    parser.add_argument('--shared-drive-path', default=r'\\10.116.33.161\dr共享盘\每日产能卡堵数据统计')
    args = parser.parse_args()
    print('fileCopyUpMain.py脚本开始启动')
    machine_number = args.machine_number or Path(args.machine_number_file).read_text(encoding='utf-8').strip()
    print(f'机台编号: {machine_number}')
    alarm_path=Path(args.alarm_path); ccd_alarm_path=Path(args.ccd_alarm_path); data_total_path=Path(args.data_total_path)
    dest_path = Path(r'D:\DRLaser\ALARM') / machine_number
    yesterday = datetime.now() - timedelta(days=1)
    date_label = f'{yesterday.year}年{yesterday.month}月{yesterday.day}日'
    yesterday_file_name = date_label + '.txt'
    shared_drive_directory = Path(args.shared_drive_path) / date_label
    print(f'昨天日期：{yesterday_file_name}')
    print(f'sharedDriveDirectory：{shared_drive_directory}')
    ensure_dir(dest_path)
    copy_then_move(alarm_path/yesterday_file_name, alarm_path/'卡堵数据.txt', dest_path, f'成功复制文件: {yesterday_file_name} -> 卡堵数据.txt')
    copy_then_move(ccd_alarm_path/yesterday_file_name, ccd_alarm_path/'放偏数据.txt', dest_path, f'成功复制文件: {yesterday_file_name} -> 放偏数据.txt')
    copy_then_move(data_total_path/yesterday_file_name, data_total_path/'产能数据.txt', dest_path, f'成功复制文件: {yesterday_file_name} -> 产能数据.txt')
    print(f'{machine_number}数据文件已汇总')
    print('开始上传到dr共享盘...')
    ensure_dir(shared_drive_directory)
    final_path = shared_drive_directory / machine_number
    print(f'finalPath:{final_path}')
    if not final_path.exists():
        shutil.move(str(dest_path), str(final_path)); print(f'{machine_number}数据文件已上传')
    else:
        print(f'{machine_number}数据文件已存在')
    log_path = Path(r'D:\Development\Script\Test\定时任务测试样本.log')
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open('a', encoding='utf-8') as h: h.write('fileCopyUpMain 脚本定时执行完成 at ' + datetime.now().strftime('%Y-%m-%d %H:%M:%S') + '\n')
    return 0
if __name__ == '__main__': raise SystemExit(main())
