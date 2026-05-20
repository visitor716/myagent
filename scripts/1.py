#!/usr/bin/env python3
"""Add "Open Git Bash Here" to Windows directory background context menu."""
from __future__ import annotations
import argparse, winreg
from _windows_helpers import require_windows

def set_default(root, subkey, value):
    with winreg.CreateKeyEx(root, subkey, 0, winreg.KEY_SET_VALUE) as key:
        winreg.SetValueEx(key, '', 0, winreg.REG_SZ, value)

def main():
    require_windows()
    parser = argparse.ArgumentParser()
    parser.add_argument('--git-path', default=r'D:\DevTools\Git-2.47.1\git-bash.exe')
    args = parser.parse_args()
    shell_key = r'Directory\Background\shell\git_bash'
    set_default(winreg.HKEY_CLASSES_ROOT, shell_key, 'Open Git Bash Here')
    set_default(winreg.HKEY_CLASSES_ROOT, shell_key + r'\command', f'"{args.git_path}" --cd="%V"')
    print('已添加右键菜单: Open Git Bash Here')
if __name__ == '__main__': raise SystemExit(main())
