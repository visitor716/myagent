#!/usr/bin/env python3
"""Generate a Markdown work-hours allocation sheet from an overtime note."""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from datetime import date, timedelta
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Sequence

DEFAULTS = {
    'output_dir': r'D:\Obsidian\MyNote\03.工作\扬州晶澳F3日报表格自动化',
    'filename_template': '工时分配单-{date}.md',
    'terminal_customer': '扬州晶澳',
    'charged_project': '否',
    'module': '运维模块',
}

SMALL_WEEK_SATURDAY = date(2026, 4, 25)
WORKDAY_ATTENDANCE_HOURS = Decimal('8')
RESTDAY_ATTENDANCE_HOURS = Decimal('0')

WINDOWS_DRIVE_RE = re.compile(r'^(?P<drive>[A-Za-z]):[\\/](?P<rest>.*)$')
FULL_DATE_RE = re.compile(
    r'(?P<year>20\d{2})\s*[年./-]\s*(?P<month>\d{1,2})\s*[月./-]\s*(?P<day>\d{1,2})\s*日?'
)
MONTH_DAY_RE = re.compile(r'(?<!\d)(?P<month>\d{1,2})\s*月\s*(?P<day>\d{1,2})\s*日?')
MONTH_DAY_NUMERIC_RE = re.compile(r'(?<![\d.])(?P<month>\d{1,2})\s*[.-]\s*(?P<day>\d{1,2})(?![\d.])')
OVERTIME_PATTERNS = [
    re.compile(r'加班(?:小时|时长)?\s*[:：为是]?\s*(?P<hours>\d+(?:\.\d+)?)'),
    re.compile(r'(?P<hours>\d+(?:\.\d+)?)\s*(?:个)?(?:小时|h|H)\s*(?:的)?加班'),
    re.compile(r'(?P<hours>\d+(?:\.\d+)?)\s*(?:个)?(?:小时|h|H)'),
]


@dataclass(frozen=True)
class WorkHoursSheet:
    work_date: date
    attendance_hours: Decimal
    overtime_hours: Decimal
    total_hours: Decimal
    terminal_customer: str = DEFAULTS['terminal_customer']
    charged_project: str = DEFAULTS['charged_project']
    module: str = DEFAULTS['module']


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


def parse_date_value(value: str, reference_date: date | None = None) -> date:
    current = reference_date or date.today()
    text = value.strip()
    if not text:
        return current

    full_match = FULL_DATE_RE.search(text)
    if full_match:
        return date(
            int(full_match.group('year')),
            int(full_match.group('month')),
            int(full_match.group('day')),
        )

    month_day_match = MONTH_DAY_RE.search(text)
    if month_day_match:
        return date(current.year, int(month_day_match.group('month')), int(month_day_match.group('day')))

    numeric_month_day = parse_numeric_month_day(text, current)
    if numeric_month_day:
        return numeric_month_day

    relative_dates = {
        '今天': current,
        '今日': current,
        '昨天': current - timedelta(days=1),
        '昨日': current - timedelta(days=1),
        '前天': current - timedelta(days=2),
        '明天': current + timedelta(days=1),
        '明日': current + timedelta(days=1),
    }
    for token, resolved_date in relative_dates.items():
        if token in text:
            return resolved_date

    raise ValueError(f'无法识别日期: {value}')


def parse_numeric_month_day(text: str, reference_date: date) -> date | None:
    for match in MONTH_DAY_NUMERIC_RE.finditer(text):
        prefix = text[max(0, match.start() - 4) : match.start()]
        suffix = text[match.end() : match.end() + 4]
        if '加班' in prefix or re.match(r'\s*(?:个)?(?:小时|h|H)', suffix):
            continue

        try:
            return date(reference_date.year, int(match.group('month')), int(match.group('day')))
        except ValueError:
            continue
    return None


def parse_sheet_date(text: str, date_override: str | None = None, reference_date: date | None = None) -> date:
    if date_override:
        return parse_date_value(date_override, reference_date)

    current = reference_date or date.today()
    if FULL_DATE_RE.search(text) or MONTH_DAY_RE.search(text) or parse_numeric_month_day(text, current):
        return parse_date_value(text, current)
    if any(token in text for token in ('今天', '今日', '昨天', '昨日', '前天', '明天', '明日')):
        return parse_date_value(text, current)
    return current


def parse_overtime_hours(text: str, overtime_override: str | None = None) -> Decimal:
    raw_value = overtime_override
    if raw_value is None:
        for pattern in OVERTIME_PATTERNS:
            match = pattern.search(text)
            if match:
                raw_value = match.group('hours')
                break

    if raw_value is None:
        raise ValueError('没有识别到加班小时数，请输入类似“今天加班2.5小时”的内容')

    try:
        hours = Decimal(raw_value)
    except InvalidOperation as exc:
        raise ValueError(f'无法识别加班小时数: {raw_value}') from exc

    if hours < 0:
        raise ValueError('加班小时数不能为负数')
    return hours


def is_small_week_saturday(target_date: date) -> bool:
    if target_date.weekday() != 5:
        return False
    week_delta = (target_date - SMALL_WEEK_SATURDAY).days // 7
    return week_delta % 2 == 0


def attendance_hours_for_date(target_date: date) -> Decimal:
    weekday = target_date.weekday()
    if weekday <= 4:
        return WORKDAY_ATTENDANCE_HOURS
    if weekday == 5 and is_small_week_saturday(target_date):
        return WORKDAY_ATTENDANCE_HOURS
    return RESTDAY_ATTENDANCE_HOURS


def build_sheet(
    text: str,
    date_override: str | None = None,
    overtime_override: str | None = None,
    reference_date: date | None = None,
) -> WorkHoursSheet:
    work_date = parse_sheet_date(text, date_override, reference_date)
    overtime_hours = parse_overtime_hours(text, overtime_override)
    attendance_hours = attendance_hours_for_date(work_date)
    return WorkHoursSheet(
        work_date=work_date,
        attendance_hours=attendance_hours,
        overtime_hours=overtime_hours,
        total_hours=attendance_hours + overtime_hours,
    )


def format_date(value: date) -> str:
    return value.isoformat()


def format_hours(value: Decimal) -> str:
    normalized = value.normalize()
    text = format(normalized, 'f')
    if '.' in text:
        text = text.rstrip('0').rstrip('.')
    return text or '0'


def markdown_cell(value: str) -> str:
    return value.replace('\n', ' ').replace('|', '\\|').strip()


def build_form_values(sheet: WorkHoursSheet) -> dict[str, str]:
    total = format_hours(sheet.total_hours)
    return {
        'terminalCustomer': sheet.terminal_customer,
        'chargedProject': sheet.charged_project,
        'attendanceHours': format_hours(sheet.attendance_hours),
        'overtimeHours': format_hours(sheet.overtime_hours),
        'totalHours': total,
        'detailDuration': total,
    }


def render_markdown(sheet: WorkHoursSheet) -> str:
    values = build_form_values(sheet)

    lines = [
        f"|  |  |  | {markdown_cell(values['terminalCustomer'])} |",
        '| --- | --- | --- | ---- |',
        f"|  | {markdown_cell(values['chargedProject'])} |  | {values['attendanceHours']} |",
        f"|  | {values['overtimeHours']} |  | {values['totalHours']} |",
        '|  |  |  |  |',
        '',
        values['detailDuration'],
        '',
    ]
    return '\n'.join(lines)


def resolve_output_file(output_dir: str, work_date: date, filename_template: str = DEFAULTS['filename_template']) -> Path:
    output_path = resolve_path(output_dir)
    filename = filename_template.format(date=format_date(work_date))
    return output_path / filename


def write_sheet(sheet: WorkHoursSheet, output_dir: str, filename_template: str = DEFAULTS['filename_template']) -> Path:
    output_file = resolve_output_file(output_dir, sheet.work_date, filename_template)
    output_file.parent.mkdir(parents=True, exist_ok=True)
    output_file.write_text(render_markdown(sheet), encoding='utf-8')
    return output_file


def read_input_text(args: argparse.Namespace) -> str:
    if args.text:
        return ' '.join(args.text).strip()
    if not sys.stdin.isatty():
        return sys.stdin.read().strip()
    return ''


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description='Generate a Markdown work-hours allocation sheet.')
    parser.add_argument('text', nargs='*', help='一句话输入，例如：今天加班2.5小时')
    parser.add_argument('--date', help='指定日期，例如 2026-04-25、2026/4/25、昨天')
    parser.add_argument('--overtime', help='指定加班小时数，例如 2.5')
    parser.add_argument('--output-dir', default=DEFAULTS['output_dir'], help='输出目录，支持 Windows 或 WSL 路径')
    parser.add_argument('--filename-template', default=DEFAULTS['filename_template'], help='输出文件名模板，支持 {date}')
    parser.add_argument('--dry-run', action='store_true', help='只打印 Markdown，不写文件')
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)
    input_text = read_input_text(args)

    if not input_text and not args.overtime:
        parser.error('请提供加班数据，例如：今天加班2.5小时')

    try:
        sheet = build_sheet(input_text, args.date, args.overtime)
    except ValueError as exc:
        parser.error(str(exc))

    content = render_markdown(sheet)
    if args.dry_run:
        print(content)
        return 0

    output_file = write_sheet(sheet, args.output_dir, args.filename_template)
    print(f'已生成: {display_path(output_file)}')
    print(content)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
