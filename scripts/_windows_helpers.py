#!/usr/bin/env python3
from __future__ import annotations
import ctypes, os, shutil, subprocess
from pathlib import Path

def is_windows() -> bool:
    return os.name == 'nt'

def require_windows() -> None:
    if not is_windows():
        raise SystemExit('This script manages Windows resources and must be run with Windows Python.')

def is_admin() -> bool:
    if not is_windows(): return False
    try: return bool(ctypes.windll.shell32.IsUserAnAdmin())
    except Exception: return False

def run(command: list[str], *, check: bool = True, capture: bool = False):
    print('+ ' + ' '.join(str(x) for x in command))
    return subprocess.run(command, check=check, text=True, capture_output=capture)

def ensure_dir(path):
    p = Path(path); p.mkdir(parents=True, exist_ok=True); return p

def copy_then_move(source, temp_destination, final_directory, message: str) -> bool:
    source = Path(source); temp_destination = Path(temp_destination); final_directory = Path(final_directory)
    if not source.exists():
        print(f'未找到文件: {source.name}')
        print('请确认文件是否存在或检查日期格式是否正确')
        return False
    ensure_dir(final_directory)
    shutil.copy2(source, temp_destination)
    final_path = final_directory / temp_destination.name
    if final_path.exists():
        if final_path.is_dir(): shutil.rmtree(final_path)
        else: final_path.unlink()
    shutil.move(str(temp_destination), str(final_path))
    print(message)
    return True
