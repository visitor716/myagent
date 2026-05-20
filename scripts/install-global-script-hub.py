#!/usr/bin/env python3
from __future__ import annotations
import argparse, shutil
from pathlib import Path
README = """# Script Hub

统一脚本目录，按用途分层：

- `bin/`：全局 Python 入口，面向命令行直接调用
- `apps/cc-connect/`：cc-connect 专属启动/重启脚本
- `apps/task-scheduler/`：计划任务相关脚本
- `apps/file-transfer/`：文件复制、汇总、上传
- `libs/`：共享 Python 模块和可复用函数
- `bootstrap/`：安装器、初始化脚本
- `docs/`：使用说明
- `legacy/`：旧脚本迁移缓冲区
- `reports/`：迁移报告和盘点结果

约定：脚本语言统一使用 Python。
建议将 `D:\\Script\\bin` 加入用户级 PATH。
"""
LAYOUT = """# Script Hub Layout

- `bin/`: 面向命令行的全局入口
- `apps/cc-connect/`: cc-connect 启动、重启、日志
- `apps/task-scheduler/`: Windows 计划任务创建、检查、测试
- `apps/file-transfer/`: 文件复制、汇总、上传
- `libs/`: 可复用 Python 函数和模块
- `legacy/non-python/`: `.bat`、`.cmd` 等非 Python 脚本
- `legacy/scratch/`: 临时实验脚本
- `legacy/folders/`: 暂不分类的历史目录
- `legacy/notes/`: `.txt`、`.log` 等记录文件
"""
def write_file(path, content): path.parent.mkdir(parents=True, exist_ok=True); path.write_text(content, encoding='utf-8')
def main():
    p=argparse.ArgumentParser(); p.add_argument('--root', default=r'D:\Script'); p.add_argument('--project-root', default=r'D:\Projects\offMusicPlayer'); args=p.parse_args(); root=Path(args.root)
    for d in [root,root/'bin',root/'apps',root/'apps'/'cc-connect',root/'apps'/'cc-connect'/'logs',root/'apps'/'task-scheduler',root/'apps'/'file-transfer',root/'libs',root/'bootstrap',root/'docs',root/'legacy',root/'legacy'/'non-python',root/'legacy'/'scratch',root/'legacy'/'folders',root/'legacy'/'notes',root/'reports']: d.mkdir(parents=True, exist_ok=True)
    write_file(root/'README.md', README); write_file(root/'docs'/'layout.md', LAYOUT)
    current=Path(__file__).resolve().parent
    for name in ['start-cc-connect-hidden.py','restart-cc-connect-hidden.py','fileCopyUpMain.py','CheckTask.py','CreateDailyTask.py']:
        source=current/name
        if source.exists():
            target = root/'apps'/('cc-connect' if 'cc-connect' in name else 'file-transfer' if name == 'fileCopyUpMain.py' else 'task-scheduler')/name
            shutil.copy2(source,target)
    print(f'已安装 Python 脚本中枢: {root}'); print(f'项目根目录: {args.project_root}')
if __name__ == '__main__': raise SystemExit(main())
