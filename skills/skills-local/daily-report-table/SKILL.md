---
name: daily-report-table
description: Convert pasted TCP daily report text into fixed table rows for the main daily report and the optional 光斑调试表. Use when the user provides Chinese日报/调试记录, wants fixed企业微信或Markdown表格输出, or needs to turn光斑、能量偏移、设备异常 notes into structured rows.
---

# Daily Report Table

Use this skill when the user pastes raw TCP 日报文本 and wants fixed table rows back.

## Workflow

1. Collect the raw daily report text from the user message.
2. Use the provided date and recorder name when available; otherwise default to today and `詹香平`.
3. Choose the lightest output mode that matches the user task.
4. The script should:
   - generate `日报表格-{date}.xlsx` by default (main report + 光斑调试记录 in two sheets)
   - append 光斑 rows to the cumulative `光斑调试记录.xlsx` when spot content exists
   - print a compact preview in the terminal, defaulting to summary mode for `wecom-html`
   - optionally generate a paste-ready chart column for the enterprise WeChat spot abnormal sheet

## Follow-up shorthand

- If the user first asks for the standard日报 table and then follows with `yes` / `继续` / `导出`, treat that as a request for the enterprise WeChat delivery bundle for the same raw text.
- Preferred one-shot command for that follow-up:

```bash
python3 ~/.codex/skills/daily-report-table/scripts/report_table.py \
  --date 2026/4/19 \
  --name 詹香平 \
  --format wecom-html \
  --write-mode html \
  --preview tsv
```

- Return:
  - the generated 企业微信 HTML file path
  - the main table TSV block
  - the 光斑调试表 TSV block when spot content exists

## Defaults

- 主表列 `日期`、`组别`、`客户基地`、`设备类型`、`业务`: 默认自动填入 `日报日期`、`罗威组`、`扬州晶澳F3`、`TCP`、`运维`
- `异常分类`: 默认自动判断；`光斑`、`PT值`/`PT 值`、`精度`、能量偏移类写 `工艺调试`，其他写 `自动化调试`
- `区域`: `F3`
- `记录人员`: `詹香平`
- `输出目录`: `D:\Obsidian\MyNote\03.工作\扬州晶澳F3日报表格自动化`
- `日报笔记`: `每天日报.md`（追加模式，Obsidian 中直接查看）
- `光斑调试笔记`: `光斑调试记录.md`（追加模式，Obsidian 中直接查看）
- `Excel 表格文件`: `日报表格-{date}.xlsx`
- `光斑调试记录 Excel`: `光斑调试记录.xlsx`（累计追加，不按日期分文件）
- `企业微信文件`: `企业微信日报-{date}.html`
- `图表列文件`: `光斑异常图表列-{date}.tsv`
- `图表复制页`: `光斑异常图表复制-{date}.html`

### Output directory troubleshooting

- Runtime config `~/.tcp-daily-report-table.json` overrides the built-in `输出目录`. If files stop appearing in Obsidian, inspect this file first.
- To restore Obsidian output, set it to:

```json
{
  "output_dir": "D:\\Obsidian\\MyNote\\03.工作\\扬州晶澳F3日报表格自动化"
}
```

- In WSL this resolves to `/mnt/d/Obsidian/MyNote/03.工作/扬州晶澳F3日报表格自动化`.

## Run The Script

Script path:

```bash
python3 ~/.codex/skills/daily-report-table/scripts/report_table.py
```

Standard report:

```bash
python3 ~/.codex/skills/daily-report-table/scripts/report_table.py \
  --date 2026/4/16 \
  --name 詹香平 <<'EOF'
1、9A出料一驱动器报警EE，重新断电插拔编码器接头后复位正常。
2、9B1光斑能量偏左下，调整倍率及发散角，调整DOE后光斑形貌OK
3、9B2光斑下部分破洞，调整倍率及发散角，调整DOE后光斑形貌OK
EOF
```

Daily use:

```bash
tcp-daily-report-table --date 2026/4/16 --name 詹香平
```

Interactive CLI flow:

```bash
tcp-daily-report-table
```

- Paste the report text.
- Enter a standalone `END` line to finish input.
- Review the summary preview.
- Choose where to save: default directory, current directory, custom path, or preview-only.
- When a save location is selected and saved, remember it in `~/.tcp-daily-report-table.json`; later runs use that path by default unless `--output-dir` is provided.

Standalone CLI install for a computer without AI/Codex:

```bash
cd /path/to/daily-report-table
python -m pip install --user .
tcp-daily-report-table --help
```

The standalone package is defined by `pyproject.toml`; detailed usage is in `README.md`.

Work hours allocation sheet:

```bash
python3 ~/.codex/skills/daily-report-table/scripts/work_hours_sheet.py "今天加班2.5小时"
```

Browser fill for the open form:

```bash
python3 ~/.codex/skills/daily-report-table/scripts/fill_work_hours_form.py "今天加班2.5小时"
```

- 生成文件: `工时分配单-{YYYY-MM-DD}.md`
- 输出目录: `D:\Obsidian\MyNote\03.工作\扬州晶澳F3日报表格自动化`
- 仅输出可复制到表格的值位，不输出字段名或说明文字
- 固定值: `扬州晶澳`、`否`
- 计算值: `出勤小时`、`加班小时`、`合计工时`、末尾独立 `时长`
- 普通网页输入框不会把整段粘贴自动分配到多个控件；需要用填表脚本按标签分别填入搜索框、选择框和输入框。
- 周一到周五出勤 8 小时，周日出勤 0 小时；周六以 `2026-04-25` 为小周起点大小周交替。

Fast enterprise WeChat HTML refresh:

```bash
python3 ~/.codex/skills/daily-report-table/scripts/report_table.py \
  --date 2026/4/18 \
  --name 陈治宇 \
  --format wecom-html \
  --write-mode html \
  --preview summary
```

One-shot enterprise WeChat delivery bundle: generate HTML and print TSV blocks in one run:

```bash
python3 ~/.codex/skills/daily-report-table/scripts/report_table.py \
  --date 2026/4/19 \
  --name 詹香平 \
  --format wecom-html \
  --write-mode html \
  --preview tsv <<'EOF'
1、3B2光斑破洞清洗有残留，调整激光器频率及功率后光斑形貌OK交付工艺
2、1A出料一驱动器报警EE，重新断电插拔编码器后恢复，重新固定编码器线不拉扯恢复生产
EOF
```

Chart copy mode for the enterprise WeChat abnormal sheet, with fixed target:

```bash
python3 ~/.codex/skills/daily-report-table/scripts/report_table.py \
  --date 2026/4/18 \
  --name 陈治宇 \
  --chart-copy \
  --chart-target-sheet 光斑异常图表 \
  --chart-start-cell DV2 \
  --write-mode none \
  --preview summary
```

Chart copy mode with live target auto-detection from an attached browser session:

```bash
python3 ~/.codex/skills/daily-report-table/scripts/report_table.py \
  --date 2026/4/18 \
  --name 陈治宇 \
  --chart-copy \
  --chart-session wecom-fast-fail \
  --write-mode none \
  --preview summary
```

## Parsing Rules

- Main table is always generated.
- 主表 `异常分类` 默认按异常描述自动判断：光斑、PT值、精度、能量偏移类为 `工艺调试`，其他为 `自动化调试`；只有用户明确指定 `--category` 时才覆盖自动分类。
- 主表 `异常现象` 只写异常/现象本身，不写处理动作或处理结果（例如不要包含"重启后恢复正常""更换后恢复生产""光斑OK"等）。
- 主表 `问题复盘` 保持简短，只简要复述异常现象，默认与精简后的 `异常现象` 一致；当异常现象描述为能量向某方向偏（如 `能量偏左下`、`能量往右偏`）时，统一写 `能量偏移`；当异常现象包含 `破洞` 时，统一写 `光斑破洞`；当异常现象包含 `内缩` 时，统一写 `光斑内缩`。
- 光斑调试表 is generated when an entry contains `光斑` or `能量偏`.
- `机台编号` uses the full machine token, such as `9B2` or `4A1`.
- Machine ranges like `1-14同步检查所有机台...` may be parsed as `待确认`; after running the script, verify the preview. If a range was misparsed, manually correct `机台编号` to the range (for example `1-14`) and use clearer `异常现象`/`问题复盘` text such as `CT稳定性同步检查`.
- 光斑调试表的 `机台` uses the base machine, such as `9B2 -> 9B`.
- 通道 detection priority:
  - explicit `AC和BD` / `AC&BD`
  - explicit `AC`
  - explicit `BD`
  - machine suffix `1 -> AC`
  - machine suffix `2 -> BD`
  - fallback `AC和BD`

## Output

- Recommended defaults:
  - Normal日报: default XLSX-only write path
  - 企业微信样式调整: `--format wecom-html --write-mode html --preview summary`
  - 企业微信图表列复制: `--chart-copy --write-mode none --preview summary`
- Default format is Markdown (terminal preview).
- Default writes should stay in `D:\Obsidian\MyNote\03.工作\扬州晶澳F3日报表格自动化`; use `--output-dir` only when the user explicitly asks for a different storage location.
- The saved output directory in `~/.tcp-daily-report-table.json` overrides the built-in default for later runs; explicit `--output-dir` overrides both for the current run.
- Path handling is platform-aware: Windows keeps `D:\...` paths native, WSL/Linux maps Windows drive paths to `/mnt/d/...`, and Windows maps `/mnt/d/...` back to `D:\...`.
- Default save mode generates:
  - `每天日报.md` — appends main table rows, viewable directly in Obsidian
  - `光斑调试记录.md` — appends spot rows (when spot content exists), viewable in Obsidian
  - `日报表格-{date}.xlsx` — date-stamped workbook (two sheets: 每天日报 + 光斑调试记录)
  - `光斑调试记录.xlsx` — cumulative spot records, new rows appended each run
- No `.tsv` files are generated.
- XLSX cells are centered horizontally/vertically, use thin borders, enable automatic text wrapping, and set wider process columns for long Chinese descriptions.
- When modifying or debugging XLSX output, verify the workbook internals instead of only checking that the file exists:
  - workbook contains `xl/styles.xml`
  - `xl/styles.xml` contains `<alignment horizontal="center" vertical="center" wrapText="1"/>`
  - `xl/styles.xml` contains thin borders for left/right/top/bottom
  - worksheet cells include `s="1"` style references
  - long text columns such as `调试过程` and `处理说明` have wider `<col ... width="48" .../>` settings
- Use `--format wecom-html` when the user wants enterprise WeChat-friendly table layout. This saves a styled HTML file named like `企业微信日报-2026-04-18.html`, with `F3` rendered as a blue selected tag.
- `--output-dir` supports both Windows paths like `D:\...` and WSL paths like `/mnt/d/...` on both Windows and WSL.
- `--write-mode html` generates only the HTML file. Use this for style tweaks or enterprise WeChat delivery.
- `--write-mode none` skips all XLSX/HTML writes. Pair it with `--chart-copy` when you only need the图表粘贴列.
- `--preview auto` is token-saving by default: `wecom-html` prints a short summary instead of the full HTML payload.
- `--preview tsv` is the follow-up export path for enterprise WeChat delivery: keep `--format wecom-html --write-mode html` and still print TSV blocks for copy/paste.
- Use `--preview tables` only when the user explicitly needs the table preview in terminal.
- `--chart-copy` generates:
  - `光斑异常图表列-{date}.tsv`: a single-column paste payload aligned to the fixed F3 chart row order
  - `光斑异常图表复制-{date}.html`: a one-click copy page with preview rows and a copy button
- `--chart-target-sheet` and `--chart-start-cell` add direct paste instructions into the copy page, for example `光斑异常图表!DV2`.
- `--chart-session` auto-detects the live target start cell from the current attached enterprise WeChat sheet page; this is the preferred path when the user already has an attached `playwright-cli` session.
- `--chart-date-label` and `--chart-anchor-label` are only for unusual sheet headers or non-standard row anchors; avoid setting them unless the live sheet differs from the current F3 chart pattern.
- Chart row order defaults to `1A-AC` through `7B-BD`; adjust with `--chart-max-index` if the sheet expands.
- If no spot rows are found, the 光斑 XLSX file is left unchanged and the script returns a short note that no 光斑调试表 was generated.
