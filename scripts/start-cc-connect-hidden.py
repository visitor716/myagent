#!/usr/bin/env python3
from __future__ import annotations
import argparse, os, subprocess
from pathlib import Path
from _windows_helpers import require_windows

def resolve_cc_connect_exe():
    appdata=Path(os.environ.get('APPDATA',''))
    for c in [appdata/'npm'/'node_modules'/'cc-connect'/'bin'/'cc-connect.exe', appdata/'npm'/'cc-connect.exe']:
        if c.exists(): return c.resolve()
    raise FileNotFoundError('cc-connect.exe not found. Install cc-connect first.')

def main():
    require_windows(); p=argparse.ArgumentParser(); p.add_argument('--config-path', default=str(Path.home()/'.cc-connect'/'config.toml')); p.add_argument('--log-path', default=str(Path.home()/'.cc-connect'/'logs'/'cc-connect.log')); p.add_argument('--what-if', action='store_true'); args=p.parse_args()
    tasklist=subprocess.run(['tasklist','/FI','IMAGENAME eq cc-connect.exe'], text=True, capture_output=True)
    if 'cc-connect.exe' in tasklist.stdout: print('cc-connect is already running'); return 0
    exe=resolve_cc_connect_exe(); config=Path(args.config_path).expanduser().resolve(); log=Path(args.log_path).expanduser(); log.parent.mkdir(parents=True, exist_ok=True)
    cmd=[str(exe),'--config',str(config)]
    if args.what_if: print('FilePath:',exe); print('Arguments:', ' '.join(cmd[1:])); print('LogPath:',log); return 0
    flags=getattr(subprocess,'CREATE_NO_WINDOW',0)
    h=log.open('a', encoding='utf-8')
    proc=subprocess.Popen(cmd, stdout=h, stderr=subprocess.STDOUT, creationflags=flags)
    print(f'Started cc-connect in hidden mode. PID={proc.pid}')
    return 0
if __name__ == '__main__': raise SystemExit(main())
