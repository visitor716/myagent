# TCP Daily Report CLI

把 TCP 日报文本转换成固定日报表、光斑调试表、企业微信粘贴 HTML 或 TSV。这个工具不依赖 AI，目标电脑只需要安装 Python 3.10 或更高版本。

## 安装

把整个 `daily-report-table` 目录复制到目标电脑后，在该目录运行：

```bash
python -m pip install --user .
```

Windows PowerShell 也可以使用 Python Launcher：

```powershell
py -m pip install --user .
```

如果安装时报 `No module named 'setuptools'` 或构建工具相关错误，先运行：

```bash
python -m pip install --upgrade pip setuptools
```

Windows 如果提示找不到 `tcp-daily-report-table` 命令，说明 Python 用户脚本目录还没加入 `PATH`。可以先用下面方式运行：

```bash
python -m report_table --help
```

如果不想安装，也可以直接运行脚本：

```bash
python scripts/report_table.py --help
```

开发或本机调试时可以用 editable 安装：

```bash
python -m pip install --user -e .
```

## 常用命令

最简单的交互式用法：

```bash
tcp-daily-report-table
```

运行后按提示操作：

1. 粘贴日报内容。
2. 单独输入一行 `END` 后回车。
3. 查看解析预览。
4. 输入序号选择保存位置：
   - `1` 默认 Obsidian 日报目录
   - `2` 当前目录
   - `3` 自定义路径
   - `4` 只预览不保存

选择 `1`、`2` 或 `3` 并实际保存后，CLI 会记住这个保存目录。后续直接运行 `tcp-daily-report-table`，或不带 `--output-dir` 的命令，都会默认使用上次保存目录。

默认写入当前月份文件夹：

```text
<输出目录>\YYYY-MM\每天日报.md
<输出目录>\YYYY-MM\光斑调试记录.md
<输出目录>\YYYY-MM\日报表格-YYYY-MM-DD.xlsx
<输出目录>\YYYY-MM\光斑调试记录.xlsx
```

Markdown 笔记用于 Obsidian 查看，新记录会插入在表头下面的前几行，最新日报不再追加到文件最底部。

直接生成日报并写入默认保存目录的当月文件夹：

```bash
tcp-daily-report-table --date 2026/5/17 --name 詹香平 --text "6B1能量偏右上，调整DOE后光斑形貌OK"
```

Windows PowerShell 粘贴多行日报：

```powershell
@"
1、6B1能量偏右上，调整发散角及DOE后光斑形貌OK
2、7B1光斑中间破洞，调整倍率及发散角，调整DOE后光斑形貌OK
"@ | tcp-daily-report-table --date 2026/5/17 --name 詹香平
```

Linux、macOS、WSL 粘贴多行日报：

```bash
tcp-daily-report-table --date 2026/5/17 --name 詹香平 <<'EOF'
1、6B1能量偏右上，调整发散角及DOE后光斑形貌OK
2、7B1光斑中间破洞，调整倍率及发散角，调整DOE后光斑形貌OK
EOF
```

只预览 TSV，不写入文件：

```bash
tcp-daily-report-table --write-mode none --preview tsv --text "6B1能量偏右上，调整DOE后光斑形貌OK"
```

生成的是实际 `.xlsx` 工作簿，日期、组别、客户基地等字段会在不同单元格里。

指定输出目录：

```bash
tcp-daily-report-table --output-dir "D:\Obsidian\MyNote\03.工作\扬州晶澳F3日报表格自动化" --text "6B1能量偏右上，调整DOE后光斑形貌OK"
```

路径兼容规则：

- 在 Windows 原生 Python 里，`D:\...` 会直接按 Windows 路径写入。
- 在 WSL/Linux 里，`D:\...` 会自动转换为 `/mnt/d/...` 写入。
- 如果在 Windows 里传入 `/mnt/d/...`，会自动转换回 `D:\...`。

生成企业微信粘贴 HTML：

```bash
tcp-daily-report-table --format wecom-html --write-mode html --preview tsv --text "6B1能量偏右上，调整DOE后光斑形貌OK"
```

企业微信 HTML 的表格边框、单元格居中和表头样式会写成内联样式，复制到企业微信或在线表格后更容易保留外边框和居中效果。

## 安装后的命令

- `tcp-daily-report-table` 是独立日报 CLI 主命令。

## 输出文件

默认输出目录是：

```text
D:\Obsidian\MyNote\03.工作\扬州晶澳F3日报表格自动化
```

可以用 `--output-dir` 改成任意根目录。实际文件会按日报日期自动写入根目录下的月度子目录，例如 `2026-05`。

默认写入：

- `YYYY-MM\每天日报.md`
- `YYYY-MM\光斑调试记录.md`
- `YYYY-MM\日报表格-{date}.xlsx`
- `YYYY-MM\光斑调试记录.xlsx`

`每天日报.md` 的新记录仍插入到表头下方；`光斑调试记录.md` 的新记录追加到表格底部。

同一天的 `日报表格-{date}.xlsx` 再次生成时不会覆盖旧数据；新的日报行和该文件内的光斑调试行会插入到表头下方，旧数据下移。

光斑调试表的异常类型会按规则归一化：文本里出现 `功率衰减`（兼容错字 `功率摔减`）时写 `光斑破洞`。

仅在显式指定对应写入模式时生成：

- `YYYY-MM\企业微信日报-{date}.html`
- `YYYY-MM\光斑异常图表列-{date}.tsv`
- `YYYY-MM\光斑异常图表复制-{date}.html`

CLI 会把上次选择的保存目录记录到用户配置文件：

```text
~/.tcp-daily-report-table.json
```

如果某次临时要保存到别的位置，可以继续用 `--output-dir`，它会覆盖本次运行的保存目录。
