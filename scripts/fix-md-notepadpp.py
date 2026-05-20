#!/usr/bin/env python3
from __future__ import annotations
import argparse, subprocess
from datetime import datetime
from pathlib import Path
import winreg
from _windows_helpers import require_windows, run

def set_value(root, subkey, name, value):
    with winreg.CreateKeyEx(root, subkey, 0, winreg.KEY_SET_VALUE) as key: winreg.SetValueEx(key, name, 0, winreg.REG_SZ, value)
def delete_tree(root, subkey):
    try:
        with winreg.OpenKey(root, subkey, 0, winreg.KEY_READ | winreg.KEY_WRITE) as key:
            children=[]; i=0
            while True:
                try: children.append(winreg.EnumKey(key,i)); i+=1
                except OSError: break
        for child in children: delete_tree(root, subkey+'\\'+child)
        winreg.DeleteKey(root, subkey)
    except FileNotFoundError: pass

def main():
    require_windows(); p=argparse.ArgumentParser(); p.add_argument('--notepad-path', default=r'D:\DevTools\Notepad++\notepad++.exe'); p.add_argument('--backup-dir', default=''); p.add_argument('--skip-explorer-restart', action='store_true'); p.add_argument('--what-if', action='store_true'); args=p.parse_args()
    notepad=Path(args.notepad_path)
    if not notepad.exists(): raise SystemExit(f'未找到 Notepad++: {notepad}')
    backup_dir=Path(args.backup_dir) if args.backup_dir else Path(__file__).resolve().parent.parent/'.codex-reg-backup'
    backup=backup_dir/('md-association-'+datetime.now().strftime('%Y%m%d-%H%M%S'))
    if args.what_if: print('Would set .md association to Notepad++'); print('备份目录:', backup); return 0
    backup.mkdir(parents=True, exist_ok=True)
    for reg_path,name in [(r'HKCU\Software\Classes\.md','hkcu-classes-dot-md.reg'),(r'HKCU\Software\Classes\Notepad++_file','hkcu-classes-notepadpp-file.reg'),(r'HKCU\Software\Classes\Applications\notepad++.exe','hkcu-classes-app-notepadpp.reg'),(r'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.md','hkcu-fileexts-md.reg')]: run(['reg','export',reg_path,str(backup/name),'/y'], check=False)
    cmd=f'"{notepad.resolve()}" "%1"'
    delete_tree(winreg.HKEY_CURRENT_USER, r'Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.md\UserChoice')
    set_value(winreg.HKEY_CURRENT_USER, r'Software\Classes\.md', '', 'Notepad++_file')
    set_value(winreg.HKEY_CURRENT_USER, r'Software\Classes\.md\OpenWithProgids', 'Notepad++_file', '')
    set_value(winreg.HKEY_CURRENT_USER, r'Software\Classes\Notepad++_file\shell\open\command', '', cmd)
    set_value(winreg.HKEY_CURRENT_USER, r'Software\Classes\Notepad++_file', 'FriendlyTypeName', 'Markdown File')
    set_value(winreg.HKEY_CURRENT_USER, r'Software\Classes\Applications\notepad++.exe\shell\open\command', '', cmd)
    set_value(winreg.HKEY_CURRENT_USER, r'Software\Classes\Applications\notepad++.exe', 'FriendlyAppName', 'Notepad++')
    set_value(winreg.HKEY_CURRENT_USER, r'Software\Classes\Applications\notepad++.exe\SupportedTypes', '.md', '')
    set_value(winreg.HKEY_CURRENT_USER, r'Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.md\OpenWithProgids', 'Notepad++_file', '')
    set_value(winreg.HKEY_CURRENT_USER, r'Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.md\OpenWithList', 'a', 'notepad++.exe')
    set_value(winreg.HKEY_CURRENT_USER, r'Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.md\OpenWithList', 'MRUList', 'a')
    if not args.skip_explorer_restart: run(['taskkill','/IM','explorer.exe','/F'], check=False); subprocess.Popen(['explorer.exe'])
    print('已写入 .md -> Notepad++ 关联。'); print('备份目录:', backup); print('Notepad++ 路径:', notepad.resolve())
if __name__ == '__main__': raise SystemExit(main())
