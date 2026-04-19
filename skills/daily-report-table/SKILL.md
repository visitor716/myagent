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
   - append rows into `每天日报.md`
   - append rows into `光斑调试记录.md` only when the text contains spot-related content
   - print a compact preview in the terminal, defaulting to summary mode for `wecom-html`
   - optionally generate a paste-ready chart column for the enterprise WeChat spot abnormal sheet

## Follow-up shorthand

- If the user first asks for the standard日报 table and then follows with `yes` / `继续` / `导出`, treat that as a request for the enterprise WeChat delivery bundle for the same raw text.
- In that follow-up, do not append the Markdown notes again.
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

- 主表列 `日期`、`组别`、`客户基地`、`设备类型`、`业务`: 默认留空占位
- `异常分类`: `工艺调试`
- `区域`: `F3`
- `记录人员`: `詹香平`
- `输出目录`: `D:\Obsidian\MyNote\03.工作\扬州晶澳F3`
- `日报文件`: `每天日报.md`
- `光斑文件`: `光斑调试记录.md`
- `企业微信文件`: `企业微信日报-{date}.html`
- `图表列文件`: `光斑异常图表列-{date}.tsv`
- `图表复制页`: `光斑异常图表复制-{date}.html`

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

Fast enterprise WeChat HTML refresh without duplicate note appends:

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
- 光斑调试表 is generated when an entry contains `光斑` or `能量偏`.
- `机台编号` uses the full machine token, such as `9B2` or `4A1`.
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
  - Normal日报: default Markdown write path
  - 企业微信样式调整: `--format wecom-html --write-mode html --preview summary`
  - 企业微信图表列复制: `--chart-copy --write-mode none --preview summary`
- Default format is Markdown.
- Use `--format tsv` when the user wants easier spreadsheet pasting.
- Use `--format wecom-html` when the user wants enterprise WeChat-friendly table layout. This saves a styled HTML file named like `企业微信日报-2026-04-18.html`, with `F3` rendered as a blue selected tag.
- `--output-dir` supports both Windows paths like `D:\...` and WSL paths like `/mnt/d/...`.
- `--write-mode html` refreshes only the HTML file and skips note appends. Use this for style tweaks to avoid duplicate rows.
- `--write-mode none` skips note and企业微信日报 HTML writes. Pair it with `--chart-copy` when you only need the图表粘贴列。
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
- By default the script appends generated rows into the two fixed Obsidian notes.
- If no spot rows are found, the 光斑 file is left unchanged and the script returns a short note that no 光斑调试表 was generated.
