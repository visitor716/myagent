#!/usr/bin/env python3
from __future__ import annotations
import argparse, os, re, shutil
from datetime import datetime
from pathlib import Path
NEW_BLOCK = '[mcp_servers.chrome-devtools]\ntype = "stdio"\ncommand = "cmd"\nargs = ["/c", "npx", "-y", "chrome-devtools-mcp@latest", "--autoConnect"]\nenv = { SystemRoot = "C:\\\\Windows", PROGRAMFILES = "C:\\\\Program Files" }\nstartup_timeout_ms = 20_000\n'
def main():
    parser = argparse.ArgumentParser(); parser.add_argument('--config', default=str(Path.home()/'.codex'/'config.toml')); args=parser.parse_args()
    path = Path(os.path.expandvars(args.config)).expanduser()
    content = path.read_text(encoding='utf-8')
    backup = path.with_name(path.name + '.bak-' + datetime.now().strftime('%Y%m%d%H%M%S'))
    pattern = re.compile(r'(?ms)^\[mcp_servers\.chrome-devtools\].*?(?=^\[|\Z)')
    updated = pattern.sub(NEW_BLOCK + '\n', content) if pattern.search(content) else content.rstrip() + '\n\n' + NEW_BLOCK + '\n'
    shutil.copy2(path, backup); path.write_text(updated, encoding='utf-8')
    print(f'已更新: {path}'); print(f'已备份: {backup}')
if __name__ == '__main__': raise SystemExit(main())
