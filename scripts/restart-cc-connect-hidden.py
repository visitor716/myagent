#!/usr/bin/env python3
from __future__ import annotations
import argparse, subprocess, sys
from pathlib import Path
from _windows_helpers import require_windows, run

def main():
    require_windows(); p=argparse.ArgumentParser(); p.add_argument('--config-path', default=str(Path.home()/'.cc-connect'/'config.toml')); p.add_argument('--log-path', default=str(Path.home()/'.cc-connect'/'logs'/'cc-connect.log')); p.add_argument('--what-if', action='store_true'); args=p.parse_args()
    if args.what_if: print('Would stop cc-connect if running')
    else: run(['taskkill','/IM','cc-connect.exe','/F'], check=False)
    cmd=[sys.executable, str(Path(__file__).with_name('start-cc-connect-hidden.py')), '--config-path', args.config_path, '--log-path', args.log_path]
    if args.what_if: cmd.append('--what-if')
    return subprocess.call(cmd)
if __name__ == '__main__': raise SystemExit(main())
