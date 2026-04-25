#!/usr/bin/env python3
"""Generate fixed daily report tables from pasted TCP debug notes."""

from __future__ import annotations

import argparse
import html
import json
import re
import subprocess
import sys
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path
from typing import Iterable

DEFAULTS = {
    'group': '罗威组',
    'base': '扬州晶澳F3',
    'device': 'TCP',
    'business': '运维',
    'category': 'auto',
    'area': 'F3',
    'name': '詹香平',
    'output_dir': r'D:\Obsidian\MyNote\03.工作\扬州晶澳F3日报表格自动化',
    'main_note': '每天日报.md',
    'spot_note': '光斑调试记录.md',
    'wecom_html_file': '企业微信日报-{date}.html',
    'chart_column_file': '光斑异常图表列-{date}.tsv',
    'chart_copy_html_file': '光斑异常图表复制-{date}.html',
    'chart_target_sheet': '光斑异常图表',
    'chart_anchor_label': '1A-AC',
}

MAIN_HEADERS = [
    '日期',
    '组别',
    '客户基地',
    '设备类型',
    '机台编号',
    '业务',
    '异常分类',
    '异常现象',
    '调试过程',
    '问题复盘',
    '记录人员',
]

SPOT_HEADERS = [
    '区域',
    '日期',
    '机台',
    '通道',
    '异常类型',
    '处理说明',
    '记录人员',
    '备注',
]

MAIN_HTML_WIDTHS = ['80px', '80px', '100px', '100px', '90px', '90px', '100px', '140px', '320px', '140px', '100px']
SPOT_HTML_WIDTHS = ['70px', '90px', '80px', '90px', '100px', '360px', '100px', '110px']

MACHINE_RE = re.compile(r'(\d+[A-Za-z](?:\d+)?)')
NUMBERED_SPLIT_RE = re.compile(r'\s*\d+[、.．)]\s*')
SECONDARY_ENTRY_SPLIT_RE = re.compile(r'(?<=[。；;])\s*(?=\d+[A-Za-z](?:\d+)?)')
WINDOWS_DRIVE_RE = re.compile(r'^(?P<drive>[A-Za-z]):[\\/](?P<rest>.*)$')
PROCESS_VERB_RE = re.compile(
    r'(调整|更换|清洗|擦拭|断电|插拔|复位|优化|移动|校正|校准|补偿|检查|清理|处理|交付|重调|重新|联系|恢复)'
)

ABNORMAL_PATTERNS = [
    re.compile(r'驱动器报警[0-9A-Za-z-]+'),
    re.compile(r'MES软件\s*无法打开'),
    re.compile(r'PT\s*值极差大'),
    re.compile(r'精度异常'),
    re.compile(r'光斑能量偏移'),
    re.compile(r'光斑缺失'),
    re.compile(r'光斑[^，。；;,.]{0,18}?破洞'),
    re.compile(r'光斑[^，。；;,.]{0,18}?内缩'),
    re.compile(r'光斑[^，。；;,.]{0,18}?偏[^，。；;,.]{0,8}'),
    re.compile(r'能量[^，。；;,.]{0,12}?偏[^，。；;,.]{0,8}'),
    re.compile(r'能量偏移'),
]

AUTO_CATEGORY = 'auto'
PROCESS_CATEGORY = '工艺'
AUTOMATION_CATEGORY = '自动化调试'


@dataclass
class ParsedEntry:
    original_text: str
    machine_full: str
    machine_base: str
    abnormal: str
    process: str
    is_spot: bool
    channel: str
    warnings: list[str] = field(default_factory=list)


@dataclass
class ChartExport:
    rows: list[str]
    values: list[str]
    unmapped_rows: list[str] = field(default_factory=list)


def today_string() -> str:
    current = date.today()
    return f'{current.year}/{current.month}/{current.day}'


def clean_cell(value: str) -> str:
    return value.replace('\n', ' ').replace('|', '\\|').strip()


def escape_html_cell(value: str) -> str:
    return html.escape(value.strip()).replace('\n', '<br>')


def resolve_path(path_value: str) -> Path:
    windows_match = WINDOWS_DRIVE_RE.match(path_value)
    if windows_match:
        drive = windows_match.group('drive').lower()
        rest = windows_match.group('rest').replace('\\', '/')
        return Path(f'/mnt/{drive}/{rest}')
    return Path(path_value)


def display_path(path_value: Path | str) -> str:
    raw_path = str(path_value)
    windows_match = WINDOWS_DRIVE_RE.match(raw_path)
    if windows_match:
        drive = windows_match.group('drive').upper()
        rest = windows_match.group('rest').replace('/', '\\')
        return f'{drive}:\\{rest}'

    mount_match = re.match(r'^/mnt/([A-Za-z])/(.*)$', raw_path)
    if mount_match:
        drive = mount_match.group(1).upper()
        rest = mount_match.group(2).replace('/', '\\')
        return f'{drive}:\\{rest}'
    return raw_path


def normalize_whitespace(text: str) -> str:
    text = text.replace('\r\n', '\n').replace('\r', '\n')
    lines = [re.sub(r'\s+', ' ', line).strip() for line in text.split('\n')]
    return '\n'.join(line for line in lines if line)


def split_entries(raw_text: str) -> list[str]:
    normalized = normalize_whitespace(raw_text)
    if not normalized:
        return []

    if NUMBERED_SPLIT_RE.search(normalized):
        parts = NUMBERED_SPLIT_RE.split(normalized)
        entries = [part.strip(' ，,。；;') for part in parts if part.strip(' ，,。；;')]
    else:
        entries = [line.strip(' ，,。；;') for line in normalized.split('\n') if line.strip(' ，,。；;')]

    expanded: list[str] = []
    for entry in entries:
        sub_entries = SECONDARY_ENTRY_SPLIT_RE.split(entry)
        expanded.extend(part.strip(' ，,。；;') for part in sub_entries if part.strip(' ，,。；;'))
    return expanded


def extract_machine(text: str) -> tuple[str, str]:
    match = MACHINE_RE.search(text)
    if not match:
        return '待确认', text.strip(' ，,。；;')
    machine = match.group(1).upper()
    remainder = text[match.end() :].strip(' ，,。；;')
    return machine, remainder


def extract_abnormal(process_text: str) -> str:
    if not process_text:
        return '待确认'

    for pattern in ABNORMAL_PATTERNS:
        match = pattern.search(process_text)
        if match:
            return match.group(0).strip(' ，,。；;')

    verb_match = PROCESS_VERB_RE.search(process_text)
    if verb_match and verb_match.start() > 0:
        candidate = process_text[: verb_match.start()].strip(' ，,。；;')
        if candidate:
            return candidate

    first_clause = re.split(r'[，,。；;]', process_text, maxsplit=1)[0].strip(' ，,。；;')
    return first_clause or '待确认'


def detect_spot(process_text: str, abnormal: str) -> bool:
    combined = f'{abnormal} {process_text}'
    keywords = ('光斑', '能量偏')
    return any(keyword in combined for keyword in keywords)


def normalize_spot_issue(abnormal: str, process_text: str) -> str:
    combined = f'{abnormal} {process_text}'
    if '缺失' in combined:
        return '光斑缺失'
    if '破洞' in combined:
        return '光斑破洞'
    if '内缩' in combined:
        return '光斑内缩'
    if '能量' in combined and '偏' in combined:
        return '能量偏移'
    if '偏移' in combined:
        return '能量偏移'
    if '光斑' in abnormal:
        return abnormal
    return '光斑异常'


def infer_abnormal_category(entry: ParsedEntry) -> str:
    combined = re.sub(r'\s+', '', f'{entry.abnormal} {entry.process}').upper()
    if '光斑' in combined or 'PT值' in combined or '精度' in combined:
        return PROCESS_CATEGORY
    if '能量' in combined and ('偏' in combined or '聚集' in combined):
        return PROCESS_CATEGORY
    return AUTOMATION_CATEGORY


def resolve_abnormal_category(entry: ParsedEntry, requested_category: str) -> str:
    if requested_category and requested_category != AUTO_CATEGORY:
        return requested_category
    return infer_abnormal_category(entry)


def infer_channel(machine_full: str, text: str) -> str:
    compact_text = text.replace(' ', '').upper()
    if any(token in compact_text for token in ('AC和BD', 'BD和AC', 'AC&BD', 'BD&AC', 'AC/BD', 'BD/AC', 'AC及BD', 'BD及AC')):
        return 'AC和BD'
    if 'AC' in compact_text:
        return 'AC'
    if 'BD' in compact_text:
        return 'BD'

    match = re.match(r'^(\d+[A-Z])(\d+)$', machine_full)
    if match:
        suffix = match.group(2)
        if suffix == '1':
            return 'AC'
        if suffix == '2':
            return 'BD'
    return 'AC和BD'


def base_machine(machine_full: str) -> str:
    match = re.match(r'^(\d+[A-Z])(\d+)$', machine_full)
    if match:
        return match.group(1)
    return machine_full


def parse_entry(entry_text: str) -> ParsedEntry:
    machine_full, process_text = extract_machine(entry_text)
    abnormal = extract_abnormal(process_text)
    is_spot = detect_spot(process_text, abnormal)
    channel = infer_channel(machine_full, process_text)
    warnings: list[str] = []

    if machine_full == '待确认':
        warnings.append(f'未识别机台编号: {entry_text}')
    if abnormal == '待确认':
        warnings.append(f'未识别异常现象: {entry_text}')

    return ParsedEntry(
        original_text=entry_text,
        machine_full=machine_full,
        machine_base=base_machine(machine_full),
        abnormal=abnormal,
        process=process_text or entry_text.strip(),
        is_spot=is_spot,
        channel=channel,
        warnings=warnings,
    )


def parse_date_string(raw_date: str) -> tuple[int, int, int]:
    match = re.match(r'^\s*(\d{4})[-/.年](\d{1,2})[-/.月](\d{1,2})', raw_date)
    if not match:
        raise ValueError(f'无法解析日期: {raw_date}')
    return int(match.group(1)), int(match.group(2)), int(match.group(3))


def format_main_date(raw_date: str) -> str:
    year, month, day = parse_date_string(raw_date)
    return f'{year}/{month}/{day}'


def format_spot_date(raw_date: str) -> str:
    _, month, day = parse_date_string(raw_date)
    return f'{month}月{day}号'


def format_file_date(raw_date: str) -> str:
    year, month, day = parse_date_string(raw_date)
    return f'{year:04d}-{month:02d}-{day:02d}'


def format_chart_date(raw_date: str) -> str:
    _, month, day = parse_date_string(raw_date)
    return f'{month}月{day}日'


def resolve_filename_template(template: str, raw_date: str) -> str:
    return template.replace('{date}', format_file_date(raw_date))


def build_main_rows(entries: Iterable[ParsedEntry], metadata: dict[str, str]) -> list[list[str]]:
    rows: list[list[str]] = []
    for entry in entries:
        rows.append(
            [
                format_main_date(metadata['date']),
                metadata['group'],
                metadata['base'],
                metadata['device'],
                entry.machine_full,
                metadata['business'],
                resolve_abnormal_category(entry, metadata['category']),
                entry.abnormal,
                entry.process,
                entry.abnormal,
                metadata['name'],
            ]
        )
    return rows


def build_spot_rows(entries: Iterable[ParsedEntry], metadata: dict[str, str]) -> list[list[str]]:
    rows: list[list[str]] = []
    spot_date = format_spot_date(metadata['date'])
    for entry in entries:
        if not entry.is_spot:
            continue
        rows.append(
            [
                metadata['area'],
                spot_date,
                entry.machine_base,
                entry.channel,
                normalize_spot_issue(entry.abnormal, entry.process),
                entry.process,
                metadata['name'],
                '',
            ]
        )
    return rows


def render_markdown(headers: list[str], rows: list[list[str]]) -> str:
    if not rows:
        return ''
    header_line = '| ' + ' | '.join(headers) + ' |'
    separator_line = '| ' + ' | '.join(['---'] * len(headers)) + ' |'
    body_lines = ['| ' + ' | '.join(clean_cell(cell) for cell in row) + ' |' for row in rows]
    return '\n'.join([header_line, separator_line, *body_lines])


def render_tsv(headers: list[str], rows: list[list[str]]) -> str:
    if not rows:
        return ''
    lines = ['\t'.join(headers)]
    lines.extend('\t'.join(clean_cell(cell) for cell in row) for row in rows)
    return '\n'.join(lines)


def render_html_td(value: str, highlighted: bool) -> str:
    escaped = escape_html_cell(value)
    if not highlighted:
        return f'<td>{escaped}</td>'
    return f'<td><span style="{selected_option_style()}">{escaped}</span></td>'


def selected_option_style() -> str:
    return (
        'display:inline-block;'
        'min-width:40px;'
        'padding:3px 10px;'
        'border-radius:2px;'
        'background:#2f6bff;'
        'color:#ffffff;'
        'font-weight:600;'
        'line-height:1.4;'
        'text-align:center;'
        'box-sizing:border-box;'
    )


def render_html_table(
    headers: list[str],
    rows: list[list[str]],
    column_widths: list[str],
    highlighted_columns: set[int] | None = None,
) -> str:
    if not rows:
        return ''

    highlighted_columns = highlighted_columns or set()
    colgroup = ''.join(f'<col style="width: {width};" />' for width in column_widths)
    header_line = ''.join(f'<th>{escape_html_cell(header)}</th>' for header in headers)
    body_lines = []
    for row in rows:
        cells = ''.join(render_html_td(cell, index in highlighted_columns) for index, cell in enumerate(row))
        body_lines.append(f'<tr>{cells}</tr>')
    tbody = ''.join(body_lines)
    return (
        '<table class="report-table">'
        f'<colgroup>{colgroup}</colgroup>'
        f'<thead><tr>{header_line}</tr></thead>'
        f'<tbody>{tbody}</tbody>'
        '</table>'
    )


def render_wecom_html(main_rows: list[list[str]], spot_rows: list[list[str]]) -> str:
    sections = [
        ('日报主表', render_html_table(MAIN_HEADERS, main_rows, MAIN_HTML_WIDTHS)),
    ]
    if spot_rows:
        sections.append(
            (
                '光斑调试表',
                render_html_table(SPOT_HEADERS, spot_rows, SPOT_HTML_WIDTHS, highlighted_columns={0}),
            )
        )
    else:
        sections.append(('光斑调试表', '<p class="empty-note">未检测到光斑相关内容，未生成光斑调试表。</p>'))

    body = ''.join(
        f'<section class="report-section"><h2>{title}</h2>{content}</section>'
        for title, content in sections
    )
    return f"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <title>企业微信日报</title>
  <style>
    body {{
      margin: 24px;
      color: #1f2329;
      font-family: "Microsoft YaHei", "PingFang SC", sans-serif;
      background: #ffffff;
    }}
    .report-section {{
      margin-bottom: 24px;
    }}
    h2 {{
      margin: 0 0 12px;
      text-align: center;
      font-size: 18px;
      font-weight: 700;
    }}
    .report-table {{
      width: 100%;
      border-collapse: collapse;
      table-layout: fixed;
    }}
    .report-table th,
    .report-table td {{
      border: 1px solid #1f2329;
      padding: 8px 6px;
      text-align: center;
      vertical-align: middle;
      line-height: 1.6;
      font-size: 14px;
      white-space: normal;
      word-break: break-all;
      overflow-wrap: anywhere;
    }}
    .report-table th {{
      background: #f5f7fa;
      font-weight: 700;
    }}
    .empty-note {{
      margin: 0;
      text-align: center;
      color: #5c6570;
    }}
  </style>
</head>
<body>
{body}
</body>
</html>
"""


def render_chart_copy_html(chart_export: ChartExport, raw_date: str, chart_target_sheet: str = '', chart_start_cell: str = '') -> str:
    payload = '\n'.join(chart_export.values)
    target_hint = '先在企业微信表格选中当天列的起始单元格，再粘贴。'
    if chart_target_sheet and chart_start_cell:
        target_hint = f'目标位置: {chart_target_sheet}!{chart_start_cell}。复制后直接粘贴。'
    elif chart_target_sheet:
        target_hint = f'目标工作表: {chart_target_sheet}。先选中当天列的起始单元格，再粘贴。'
    elif chart_start_cell:
        target_hint = f'目标起始单元格: {chart_start_cell}。复制后直接粘贴。'

    preview_rows = ''.join(
        f'<tr><td>{html.escape(row)}</td><td>{html.escape(value or "")}</td></tr>'
        for row, value in zip(chart_export.rows, chart_export.values)
    )
    return f"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <title>光斑异常图表复制</title>
  <style>
    body {{
      margin: 24px;
      color: #1f2329;
      font-family: "Microsoft YaHei", "PingFang SC", sans-serif;
      background: #ffffff;
    }}
    .toolbar {{
      display: flex;
      gap: 12px;
      align-items: center;
      margin-bottom: 16px;
      flex-wrap: wrap;
    }}
    button {{
      padding: 8px 16px;
      border: none;
      border-radius: 6px;
      background: #2f6bff;
      color: #ffffff;
      font-size: 14px;
      cursor: pointer;
    }}
    .hint {{
      color: #5c6570;
      font-size: 13px;
    }}
    textarea {{
      width: 100%;
      height: 320px;
      margin-bottom: 20px;
      padding: 12px;
      box-sizing: border-box;
      font-family: Consolas, "Microsoft YaHei", monospace;
      font-size: 14px;
      line-height: 1.5;
      white-space: pre;
    }}
    table {{
      width: 100%;
      border-collapse: collapse;
      table-layout: fixed;
    }}
    th, td {{
      border: 1px solid #d7dce5;
      padding: 8px 10px;
      font-size: 14px;
    }}
    th {{
      background: #f5f7fa;
      text-align: left;
    }}
    td:last-child {{
      color: #2f6bff;
    }}
  </style>
</head>
<body>
  <div class="toolbar">
    <button type="button" onclick="copyPayload()">复制图表列</button>
    <span class="hint">日期: {html.escape(format_chart_date(raw_date))}。{html.escape(target_hint)}</span>
  </div>
  <textarea id="payload" readonly>{html.escape(payload)}</textarea>
  <table>
    <thead>
      <tr><th>机台行</th><th>填充值</th></tr>
    </thead>
    <tbody>
      {preview_rows}
    </tbody>
  </table>
  <script>
    function copyPayload() {{
      const textarea = document.getElementById('payload');
      textarea.focus();
      textarea.select();
      try {{
        if (navigator.clipboard && window.isSecureContext) {{
          navigator.clipboard.writeText(textarea.value);
        }} else {{
          document.execCommand('copy');
        }}
        alert('已复制图表列，可直接粘贴到企业微信表格。');
      }} catch (error) {{
        alert('自动复制失败，请在文本框内按 Ctrl+C 复制。');
      }}
    }}
  </script>
</body>
</html>
"""


def render_summary(
    main_rows: list[list[str]],
    spot_rows: list[list[str]],
    fmt: str,
    chart_copy: bool,
    metadata: dict[str, str] | None = None,
) -> str:
    if chart_copy:
        format_label = '图表复制'
    else:
        format_label = '企业微信HTML' if fmt == 'wecom-html' else fmt.upper()

    lines = [
        '日报预览',
        f'- 主表记录: {len(main_rows)} 条',
        f'- 光斑调试: {len(spot_rows)} 条',
        f'- 输出格式: {format_label}',
    ]
    if chart_copy and metadata:
        lines.append(f"- 图表工作表: {metadata.get('chart_target_sheet') or '未指定'}")
        if metadata.get('chart_start_cell'):
            lines.append(f"- 图表起始格: {metadata['chart_start_cell']}")
    return '\n'.join(lines)


def resolve_preview_mode(fmt: str, preview: str) -> str:
    if preview != 'auto':
        return preview
    return 'summary' if fmt == 'wecom-html' else 'tables'


def render_sections(
    main_rows: list[list[str]],
    spot_rows: list[list[str]],
    fmt: str,
    preview: str,
    chart_copy: bool,
    metadata: dict[str, str] | None = None,
) -> str:
    preview_mode = resolve_preview_mode(fmt, preview)
    if preview_mode == 'none':
        return ''
    if preview_mode == 'summary':
        return render_summary(main_rows, spot_rows, fmt, chart_copy, metadata)
    if preview_mode == 'tsv':
        renderer = render_tsv
    elif fmt == 'wecom-html':
        return render_sections(main_rows, spot_rows, 'markdown', 'tables', chart_copy, metadata)
    else:
        renderer = render_markdown if fmt == 'markdown' else render_tsv
    main_output = renderer(MAIN_HEADERS, main_rows)
    parts = ['日报主表', main_output]
    if spot_rows:
        parts.extend(['', '光斑调试表', renderer(SPOT_HEADERS, spot_rows)])
    else:
        parts.extend(['', '光斑调试表', '未检测到光斑相关内容，未生成光斑调试表。'])
    return '\n'.join(part for part in parts if part is not None)


def markdown_row(row: list[str]) -> str:
    return '| ' + ' | '.join(clean_cell(cell) for cell in row) + ' |'


def ensure_markdown_note(file_path: Path, headers: list[str], title: str) -> None:
    if file_path.exists() and file_path.read_text(encoding='utf-8').strip():
        return

    header_line = '| ' + ' | '.join(headers) + ' |'
    separator_line = '| ' + ' | '.join(['---'] * len(headers)) + ' |'
    content = f'# {title}\n\n{header_line}\n{separator_line}\n'
    file_path.write_text(content, encoding='utf-8')


def append_rows_to_markdown_note(file_path: Path, headers: list[str], title: str, rows: list[list[str]]) -> None:
    if not rows:
        return

    file_path.parent.mkdir(parents=True, exist_ok=True)
    ensure_markdown_note(file_path, headers, title)
    existing_content = file_path.read_text(encoding='utf-8')

    with file_path.open('a', encoding='utf-8') as handle:
        if existing_content and not existing_content.endswith('\n'):
            handle.write('\n')
        for row in rows:
            handle.write(markdown_row(row))
            handle.write('\n')


def write_wecom_html(file_path: Path, main_rows: list[list[str]], spot_rows: list[list[str]]) -> None:
    file_path.parent.mkdir(parents=True, exist_ok=True)
    file_path.write_text(render_wecom_html(main_rows, spot_rows), encoding='utf-8')


def col_index_to_label(index: int) -> str:
    index += 1
    result = []
    while index > 0:
        index, remainder = divmod(index - 1, 26)
        result.append(chr(ord('A') + remainder))
    return ''.join(reversed(result))


def run_playwright_eval_json(session: str, expression: str) -> dict[str, object]:
    try:
        result = subprocess.run(
            ['playwright-cli', '--raw', f'-s={session}', 'eval', expression],
            check=True,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError as exc:
        raise ValueError('未找到 playwright-cli，请先安装并确保它在 PATH 中。') from exc
    except subprocess.CalledProcessError as exc:
        stderr = (exc.stderr or '').strip()
        stdout = (exc.stdout or '').strip()
        detail = stderr or stdout or 'playwright-cli 执行失败。'
        raise ValueError(detail) from exc
    payload = result.stdout.strip()
    if not payload:
        raise ValueError('playwright-cli 未返回任何结果。')
    try:
        decoded = json.loads(payload)
        if isinstance(decoded, str):
            decoded = json.loads(decoded)
        if not isinstance(decoded, dict):
            raise ValueError(f'playwright-cli 返回的 JSON 不是对象: {type(decoded).__name__}')
        return decoded
    except json.JSONDecodeError as exc:
        raise ValueError(f'无法解析 playwright-cli JSON 输出: {payload}') from exc


def detect_chart_target(session: str, sheet_name: str, date_label: str, anchor_label: str) -> dict[str, object]:
    expression = f"""JSON.stringify((() => {{
      const app = window.SpreadsheetApp;
      const sheets = app?.workbook?.worksheetManager?.sheetList || [];
      const matches = sheets.filter(sheet => {{
        const codeName = sheet?.sheetProperties?.codeName || sheet?._AnT || '';
        const currentName = typeof sheet?.getSheetName === 'function' ? sheet.getSheetName() : '';
        const sheetId = typeof sheet?.getSheetId === 'function' ? String(sheet.getSheetId()) : String(sheet?._KL || '');
        return [codeName, currentName, sheetId].includes({json.dumps(sheet_name)});
      }});
      const target = matches[0];
      if (!target) {{
        return {{
          error: 'sheet_not_found',
          sheetName: {json.dumps(sheet_name)},
          availableSheets: sheets.slice(0, 20).map(sheet => {{
            const codeName = sheet?.sheetProperties?.codeName || sheet?._AnT || '';
            const currentName = typeof sheet?.getSheetName === 'function' ? sheet.getSheetName() : '';
            const sheetId = typeof sheet?.getSheetId === 'function' ? String(sheet.getSheetId()) : String(sheet?._KL || '');
            return {{ codeName, currentName, sheetId }};
          }}),
        }};
      }}

      const readLabel = (cell) => {{
        return cell?.formattedValue?.value
          || cell?.displayValue
          || cell?.text
          || ((typeof cell?.value === 'string' || typeof cell?.value === 'number') ? String(cell.value) : '')
          || ((typeof cell?.v === 'string' || typeof cell?.v === 'number') ? String(cell.v) : '');
      }};

      let colIndex = -1;
      for (let c = 0; c < target.getColCount(); c++) {{
        const label = readLabel(target.getCellDataAtPosition(0, c)).trim();
        if (label === {json.dumps(date_label)}) {{
          colIndex = c;
          break;
        }}
      }}

      let rowIndex = -1;
      for (let r = 0; r < target.getRowCount(); r++) {{
        const label = readLabel(target.getCellDataAtPosition(r, 2)).trim();
        if (label === {json.dumps(anchor_label)}) {{
          rowIndex = r;
          break;
        }}
      }}

      return {{
        sheetName: typeof target?.getSheetName === 'function' ? target.getSheetName() : {json.dumps(sheet_name)},
        colIndex,
        rowIndex,
        dateLabel: {json.dumps(date_label)},
        anchorLabel: {json.dumps(anchor_label)},
        colCount: typeof target?.getColCount === 'function' ? target.getColCount() : null,
        rowCount: typeof target?.getRowCount === 'function' ? target.getRowCount() : null,
      }};
    }})())"""

    detected = run_playwright_eval_json(session, expression)
    if detected.get('error') == 'sheet_not_found':
        raise ValueError(f"未找到目标工作表: {sheet_name}")

    col_index = detected.get('colIndex')
    row_index = detected.get('rowIndex')
    if not isinstance(col_index, int) or col_index < 0:
        raise ValueError(f"未在工作表 {sheet_name} 找到日期列: {date_label}")
    if not isinstance(row_index, int) or row_index < 0:
        raise ValueError(f"未在工作表 {sheet_name} 找到锚点行: {anchor_label}")

    start_cell = f'{col_index_to_label(col_index)}{row_index + 1}'
    return {
        'sheet_name': str(detected.get('sheetName') or sheet_name),
        'start_cell': start_cell,
        'col_index': col_index,
        'row_index': row_index,
        'date_label': date_label,
        'anchor_label': anchor_label,
    }


def build_chart_rows(max_index: int) -> list[str]:
    rows: list[str] = []
    for machine_index in range(1, max_index + 1):
        for machine_suffix in ('A', 'B'):
            for channel in ('AC', 'BD'):
                rows.append(f'{machine_index}{machine_suffix}-{channel}')
    return rows


def build_chart_export(entries: Iterable[ParsedEntry], max_index: int) -> ChartExport:
    rows = build_chart_rows(max_index)
    values = ['' for _ in rows]
    row_to_index = {row: idx for idx, row in enumerate(rows)}
    unmapped_rows: list[str] = []

    for entry in entries:
        if not entry.is_spot:
            continue

        channels = ['AC', 'BD'] if entry.channel == 'AC和BD' else [entry.channel]
        for channel in channels:
            row_key = f'{entry.machine_base}-{channel}'
            if row_key in row_to_index:
                values[row_to_index[row_key]] = normalize_spot_issue(entry.abnormal, entry.process)
            elif row_key not in unmapped_rows:
                unmapped_rows.append(row_key)

    return ChartExport(rows=rows, values=values, unmapped_rows=unmapped_rows)


def write_chart_column(file_path: Path, chart_export: ChartExport) -> None:
    file_path.parent.mkdir(parents=True, exist_ok=True)
    file_path.write_text('\n'.join(chart_export.values), encoding='utf-8')


def write_chart_copy_html(file_path: Path, chart_export: ChartExport, raw_date: str, chart_target_sheet: str, chart_start_cell: str) -> None:
    file_path.parent.mkdir(parents=True, exist_ok=True)
    file_path.write_text(
        render_chart_copy_html(chart_export, raw_date, chart_target_sheet, chart_start_cell),
        encoding='utf-8',
    )


def persist_outputs(
    main_rows: list[list[str]],
    spot_rows: list[list[str]],
    metadata: dict[str, str],
    fmt: str,
    write_mode: str,
    chart_export: ChartExport | None,
    chart_copy: bool,
) -> list[str]:
    output_dir = resolve_path(metadata['output_dir'])
    main_path = output_dir / metadata['main_note']
    spot_path = output_dir / metadata['spot_note']
    write_notes = write_mode in ('all', 'notes')
    write_html = fmt == 'wecom-html' and write_mode in ('all', 'html')

    saved_messages: list[str] = []
    if write_notes:
        append_rows_to_markdown_note(main_path, MAIN_HEADERS, '每天日报', main_rows)
        saved_messages.append(f'已追加到: {display_path(main_path)}')
        if spot_rows:
            append_rows_to_markdown_note(spot_path, SPOT_HEADERS, '光斑调试记录', spot_rows)
            saved_messages.append(f'已追加到: {display_path(spot_path)}')
        else:
            saved_messages.append('未检测到光斑相关内容，未写入光斑调试记录。')
    else:
        saved_messages.append('已跳过日报/光斑笔记写入。')

    if write_html:
        wecom_html_path = output_dir / metadata['wecom_html_file']
        write_wecom_html(wecom_html_path, main_rows, spot_rows)
        saved_messages.append(f'已生成企业微信粘贴版: {display_path(wecom_html_path)}')

    if chart_copy and chart_export is not None:
        chart_column_path = output_dir / metadata['chart_column_file']
        chart_copy_html_path = output_dir / metadata['chart_copy_html_file']
        write_chart_column(chart_column_path, chart_export)
        write_chart_copy_html(
            chart_copy_html_path,
            chart_export,
            metadata['date'],
            metadata['chart_target_sheet'],
            metadata['chart_start_cell'],
        )
        saved_messages.append(f'已生成图表粘贴列: {display_path(chart_column_path)}')
        saved_messages.append(f'已生成图表一键复制页: {display_path(chart_copy_html_path)}')
        if chart_export.unmapped_rows:
            saved_messages.append(f'图表未匹配行: {", ".join(chart_export.unmapped_rows)}')

    return saved_messages


def read_report_text(args: argparse.Namespace) -> str:
    if args.text:
        return args.text
    if args.input_file:
        return Path(args.input_file).read_text(encoding='utf-8')
    if sys.stdin.isatty():
        print('请粘贴日报内容，完成后按 Ctrl-D：', file=sys.stderr)
    return sys.stdin.read()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description='Generate fixed daily report tables.')
    parser.add_argument('--date', default=today_string(), help='日报日期，默认今天。')
    parser.add_argument('--name', default=DEFAULTS['name'], help='记录人员，默认詹香平。')
    parser.add_argument('--group', default=DEFAULTS['group'], help='组别，默认罗威组。')
    parser.add_argument('--base', default=DEFAULTS['base'], help='客户基地，默认扬州晶澳F3。')
    parser.add_argument('--device', default=DEFAULTS['device'], help='设备类型，默认TCP。')
    parser.add_argument('--business', default=DEFAULTS['business'], help='业务，默认运维。')
    parser.add_argument('--category', default=DEFAULTS['category'], help='异常分类，默认自动判断；传入具体值可手动覆盖。')
    parser.add_argument('--area', default=DEFAULTS['area'], help='光斑调试表区域，默认F3。')
    parser.add_argument('--output-dir', default=DEFAULTS['output_dir'], help='输出目录。')
    parser.add_argument('--main-note', default=DEFAULTS['main_note'], help='日报笔记文件名。')
    parser.add_argument('--spot-note', default=DEFAULTS['spot_note'], help='光斑笔记文件名。')
    parser.add_argument('--wecom-html-file', default=DEFAULTS['wecom_html_file'], help='企业微信 HTML 文件名。')
    parser.add_argument('--chart-column-file', default=DEFAULTS['chart_column_file'], help='图表列文件名。')
    parser.add_argument('--chart-copy-html-file', default=DEFAULTS['chart_copy_html_file'], help='图表复制页文件名。')
    parser.add_argument('--chart-target-sheet', default=DEFAULTS['chart_target_sheet'], help='图表目标工作表。')
    parser.add_argument('--chart-start-cell', default='', help='图表目标起始单元格。')
    parser.add_argument('--chart-session', default='', help='通过已附着的 playwright-cli session 自动定位图表起始格。')
    parser.add_argument('--chart-date-label', default='', help='图表日期表头，默认从 --date 自动推导。')
    parser.add_argument('--chart-anchor-label', default=DEFAULTS['chart_anchor_label'], help='图表锚点行标签。')
    parser.add_argument('--chart-max-index', type=int, default=7, help='图表最大机台编号。')
    parser.add_argument('--chart-copy', action='store_true', help='生成图表列和复制页。')
    parser.add_argument(
        '--write-mode',
        choices=('all', 'notes', 'html', 'none'),
        default='all',
        help='写入模式。all=笔记+HTML，notes=仅笔记，html=仅HTML，none=全部跳过。',
    )
    parser.add_argument(
        '--preview',
        choices=('auto', 'tables', 'tsv', 'summary', 'none'),
        default='auto',
        help='终端预览模式。auto 会在 wecom-html 下默认输出 summary；tsv 可配合 wecom-html 一次产出 HTML + TSV。',
    )
    parser.add_argument(
        '--format',
        choices=('markdown', 'tsv', 'wecom-html'),
        default='markdown',
        help='输出格式。wecom-html 会额外保存企业微信粘贴版 HTML。',
    )
    parser.add_argument('--text', help='直接传入日报文本。')
    parser.add_argument('--input-file', help='从文件读取日报文本。')
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    report_text = read_report_text(args)
    entry_texts = split_entries(report_text)

    if not entry_texts:
        parser.error('未读取到日报内容。')

    metadata = {
        'date': args.date,
        'name': args.name,
        'group': args.group,
        'base': args.base,
        'device': args.device,
        'business': args.business,
        'category': args.category,
        'area': args.area,
        'output_dir': args.output_dir,
        'main_note': args.main_note,
        'spot_note': args.spot_note,
        'wecom_html_file': resolve_filename_template(args.wecom_html_file, args.date),
        'chart_column_file': resolve_filename_template(args.chart_column_file, args.date),
        'chart_copy_html_file': resolve_filename_template(args.chart_copy_html_file, args.date),
        'chart_target_sheet': args.chart_target_sheet,
        'chart_start_cell': args.chart_start_cell,
    }

    if args.chart_copy and args.chart_session and not args.chart_start_cell:
        chart_date_label = args.chart_date_label or format_chart_date(args.date)
        try:
            detected_target = detect_chart_target(
                args.chart_session,
                args.chart_target_sheet,
                chart_date_label,
                args.chart_anchor_label,
            )
        except Exception as exc:
            parser.error(f'无法从 session {args.chart_session} 自动定位图表起始格: {exc}')
        metadata['chart_target_sheet'] = str(detected_target['sheet_name'])
        metadata['chart_start_cell'] = str(detected_target['start_cell'])

    parsed_entries = [parse_entry(text) for text in entry_texts]
    warnings = [warning for entry in parsed_entries for warning in entry.warnings]
    main_rows = build_main_rows(parsed_entries, metadata)
    spot_rows = build_spot_rows(parsed_entries, metadata)
    chart_export = build_chart_export(parsed_entries, args.chart_max_index) if args.chart_copy else None

    preview_output = render_sections(main_rows, spot_rows, args.format, args.preview, args.chart_copy, metadata)
    if preview_output:
        print(preview_output)

    saved_messages = persist_outputs(
        main_rows,
        spot_rows,
        metadata,
        args.format,
        args.write_mode,
        chart_export,
        args.chart_copy,
    )
    print('\n写入结果:')
    for message in saved_messages:
        print(f'- {message}')

    if warnings:
        print('\n警告:', file=sys.stderr)
        for warning in warnings:
            print(f'- {warning}', file=sys.stderr)

    return 0


if __name__ == '__main__':
    raise SystemExit(main())
