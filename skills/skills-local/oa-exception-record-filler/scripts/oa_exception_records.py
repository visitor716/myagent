#!/usr/bin/env python3
"""Prepare OA exception-record fill data from pasted TCP daily reports."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from dataclasses import asdict, dataclass, field
from datetime import date
from pathlib import Path
from typing import Sequence


DEFAULT_CUSTOMER_ROW = '扬州晶澳F3车间'
DEFAULT_MACHINE_MODEL = '量产机'
DEFAULT_PROJECT = 'TCSE'
DEFAULT_BUSINESS_CATEGORY = '运维'
DEFAULT_PROCESS = '激光1'
DEFAULT_OPTICAL_PATH = '光路1'
DEFAULT_REVIEWER = '罗威'
DEFAULT_DURATION = ''
SANITIZED_OA_LIST_URL = 'http://oa.drlaser.com.cn:9000/spa/workflow/static/index.html#/main/workflow/listMine'
PROCESS_CATEGORY = '工艺调试'
AUTOMATION_CATEGORY = '自动化调试'
AUTO_CATEGORY = 'auto'
MACHINE_RE = re.compile(r'(\d+[A-Za-z](?:\d+)?)')
NUMBERED_SPLIT_RE = re.compile(r'(?<![0-9A-Za-z])\d+(?:[、．)]|\.(?!\d))\s*')
ENTRY_STRIP_CHARS = ' \n\t\r，,。；;'
PROCESS_VERB_RE = re.compile(
    r'(调整|更换|清洗|擦拭|断电|插拔|复位|优化|移动|校正|校准|补偿|检查|清理|处理|交付|重调|重新|重启|联系|恢复)'
)
RESULT_MARKER_RE = re.compile(r'(恢复生产|恢复正常|复位正常|光斑(?:形貌)?OK|光斑OK|正常生产|OK)')
ABNORMAL_PATTERNS = [
    re.compile(r'相机[^，。；;,.]{0,16}?报警[^，。；;,.]*'),
    re.compile(r'[^，。；;,.]{0,12}?感应信号异常'),
    re.compile(r'[^，。；;,.]{0,8}?感应器[^，。；;,.]{0,8}?异常'),
    re.compile(r'[^，。；;,.]{0,8}?皮带[^，。；;,.]{0,12}?短'),
    re.compile(r'激光器[^，。；;,.]{0,20}'),
    re.compile(r'光斑[^，。；;,.]{0,18}?破洞'),
    re.compile(r'光斑[^，。；;,.]{0,18}?内缩'),
    re.compile(r'光斑[^，。；;,.]{0,18}?偏[^，。；;,.]{0,8}'),
    re.compile(r'能量[^，。；;,.]{0,12}?偏[^，。；;,.]{0,8}'),
]

MACHINE_SERIALS = {
    1: '4643',
    2: '4642',
    3: '4645',
    4: '4644',
    5: '4660',
    6: '4646',
    7: '4656',
    8: '4657',
    9: '4658',
    10: '4659',
    11: '4666',
    12: '4661',
    13: '5655',
}


@dataclass
class OaExceptionRecord:
    table_date: str
    source_machine: str
    source_machines: list[str]
    machine_index: int | None
    factory_serial: str
    device_search_keyword: str
    device_result_keyword: str
    candidate_factory_serials: list[str]
    machine_model: str
    project: str
    business_category: str
    process: str
    optical_path: str
    exception_type: str
    type_name: str
    debug_process: str
    duration: str
    reviewer: str
    source_entry: str
    source_entries: list[str]
    warnings: list[str] = field(default_factory=list)


@dataclass
class OaExceptionPlan:
    oa_list_url: str
    table_date: str
    records: list[OaExceptionRecord]
    warnings: list[str] = field(default_factory=list)


@dataclass
class ParsedEntry:
    original_text: str
    machine_full: str
    abnormal: str
    process: str
    is_spot: bool
    warnings: list[str] = field(default_factory=list)


def today_string() -> str:
    current = date.today()
    return f'{current.year}/{current.month}/{current.day}'


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
        return [part.strip(ENTRY_STRIP_CHARS) for part in parts if part.strip(ENTRY_STRIP_CHARS)]
    return [line.strip(ENTRY_STRIP_CHARS) for line in normalized.split('\n') if line.strip(ENTRY_STRIP_CHARS)]


def parse_date_string(raw_date: str) -> tuple[int, int, int]:
    match = re.match(r'^\s*(\d{4})[-/.年](\d{1,2})[-/.月](\d{1,2})', raw_date)
    if not match:
        raise ValueError(f'无法解析日期: {raw_date}')
    return int(match.group(1)), int(match.group(2)), int(match.group(3))


def extract_machine(text: str) -> tuple[str, str]:
    match = MACHINE_RE.search(text)
    if not match:
        return '待确认', text.strip(ENTRY_STRIP_CHARS)
    machine = match.group(1).upper()
    remainder = text[match.end() :].strip(ENTRY_STRIP_CHARS)
    return machine, remainder


def strip_handling_result(text: str) -> str:
    if not text:
        return ''
    result_match = RESULT_MARKER_RE.search(text)
    if result_match and result_match.start() > 0:
        text = text[: result_match.start()]
    verb_match = PROCESS_VERB_RE.search(text)
    if verb_match and verb_match.start() > 0:
        text = text[: verb_match.start()]
    return text.strip(ENTRY_STRIP_CHARS)


def extract_abnormal(process_text: str) -> str:
    if not process_text:
        return '待确认'
    phenomenon_text = strip_handling_result(process_text)
    for pattern in ABNORMAL_PATTERNS:
        match = pattern.search(phenomenon_text)
        if match:
            return match.group(0).strip(ENTRY_STRIP_CHARS)
    first_clause = re.split(r'[，,。；;]', phenomenon_text or process_text, maxsplit=1)[0].strip(ENTRY_STRIP_CHARS)
    return first_clause or '待确认'


def detect_spot(process_text: str, abnormal: str) -> bool:
    combined = f'{abnormal} {process_text}'
    return any(keyword in combined for keyword in ('光斑', '能量偏', 'DOE', '扩束镜'))


def parse_entry(entry_text: str) -> ParsedEntry:
    machine_full, process_text = extract_machine(entry_text)
    abnormal = extract_abnormal(process_text)
    warnings: list[str] = []
    if machine_full == '待确认':
        warnings.append(f'未识别机台编号: {entry_text}')
    if abnormal == '待确认':
        warnings.append(f'未识别异常现象: {entry_text}')
    return ParsedEntry(
        original_text=entry_text,
        machine_full=machine_full,
        abnormal=abnormal,
        process=process_text or entry_text.strip(),
        is_spot=detect_spot(process_text, abnormal),
        warnings=warnings,
    )


def infer_abnormal_category(entry: ParsedEntry) -> str:
    combined = re.sub(r'\s+', '', f'{entry.abnormal} {entry.process}').upper()
    if '光斑' in combined or 'PT值' in combined or '精度' in combined:
        return PROCESS_CATEGORY
    if '能量' in combined and ('偏' in combined or '聚集' in combined):
        return PROCESS_CATEGORY
    return AUTOMATION_CATEGORY


def render_markdown_table(headers: list[str], rows: list[list[str]]) -> str:
    if not rows:
        return ''
    header_line = '| ' + ' | '.join(headers) + ' |'
    separator_line = '| ' + ' | '.join([':---:'] * len(headers)) + ' |'
    body_lines = ['| ' + ' | '.join(cell.replace('\n', ' ').replace('|', '\\|').strip() for cell in row) + ' |' for row in rows]
    return '\n'.join([header_line, separator_line, *body_lines])


def parse_machine_index(machine_full: str) -> int | None:
    match = re.match(r'^(\d+)', machine_full)
    if not match:
        return None
    return int(match.group(1))


def format_table_date(raw_date: str) -> str:
    _, month, day = parse_date_string(raw_date)
    return f'{month}.{day}'


def normalized_debug_process(raw_text: str) -> str:
    entries = split_entries(raw_text)
    if not entries:
        return normalize_whitespace(raw_text)
    return '\n'.join(f'{index}、{entry}' for index, entry in enumerate(entries, start=1))


def infer_exception_type(entry: ParsedEntry) -> str:
    combined = re.sub(r'\s+', '', f'{entry.original_text}{entry.abnormal}{entry.process}')
    if entry.is_spot or any(token in combined for token in ('光斑', 'DOE', '扩束镜', '能量偏')):
        return '光斑'
    if '相机' in combined:
        return '相机'
    if any(token in combined for token in ('感应', '信号', '气压', '气缸', '舌头')):
        return '感应信号'
    if '激光器' in combined:
        return '激光器'
    if any(token in combined for token in ('皮带', '模组')):
        return '设备机构'
    return '自动化'


def infer_type_name(entry: ParsedEntry) -> str:
    return infer_abnormal_category(entry)


def choose_machine_entry(
    entries: list[ParsedEntry],
    raw_date: str,
    debug_process: str,
    machine_choice: str,
) -> ParsedEntry:
    serial_candidates = [
        entry for entry in entries
        if (parse_machine_index(entry.machine_full) in MACHINE_SERIALS)
    ]
    candidates = serial_candidates or entries
    if machine_choice == 'first' or len(candidates) <= 1:
        return candidates[0]

    digest = hashlib.sha256(f'{raw_date}\n{debug_process}'.encode('utf-8')).hexdigest()
    return candidates[int(digest, 16) % len(candidates)]


def infer_plan_exception_type(entries: list[ParsedEntry]) -> str:
    priority = ('光斑', '相机', '感应信号', '激光器', '设备机构')
    inferred = [infer_exception_type(entry) for entry in entries]
    for value in priority:
        if value in inferred:
            return value
    return inferred[0] if inferred else '自动化'


def infer_plan_type_name(entries: list[ParsedEntry]) -> str:
    inferred = [infer_type_name(entry) for entry in entries]
    if PROCESS_CATEGORY in inferred:
        return PROCESS_CATEGORY
    if AUTOMATION_CATEGORY in inferred:
        return AUTOMATION_CATEGORY
    return inferred[0] if inferred else AUTOMATION_CATEGORY


def candidate_serials(entries: list[ParsedEntry]) -> list[str]:
    values: list[str] = []
    seen: set[str] = set()
    for entry in entries:
        machine_index = parse_machine_index(entry.machine_full)
        factory_serial = MACHINE_SERIALS.get(machine_index or -1, '')
        if not factory_serial:
            continue
        value = f'{entry.machine_full}={factory_serial}'
        if value not in seen:
            values.append(value)
            seen.add(value)
    return values


def build_record(
    entries: list[ParsedEntry],
    chosen_entry: ParsedEntry,
    table_date: str,
    debug_process: str,
    args: argparse.Namespace,
) -> OaExceptionRecord:
    machine_index = parse_machine_index(chosen_entry.machine_full)
    warnings = [warning for entry in entries for warning in entry.warnings]
    for entry in entries:
        current_index = parse_machine_index(entry.machine_full)
        if current_index is not None and current_index not in MACHINE_SERIALS:
            warnings.append(f'未配置 {current_index} 号机的设备出厂编号')

    factory_serial = ''
    if machine_index is None:
        warnings.append(f'无法从机台编号识别数字序号: {chosen_entry.machine_full}')
    else:
        factory_serial = MACHINE_SERIALS.get(machine_index, '')
        if not factory_serial:
            warnings.append(f'未配置 {machine_index} 号机的设备出厂编号')

    return OaExceptionRecord(
        table_date=table_date,
        source_machine=chosen_entry.machine_full,
        source_machines=[entry.machine_full for entry in entries],
        machine_index=machine_index,
        factory_serial=factory_serial,
        device_search_keyword=factory_serial,
        device_result_keyword=args.device_result_keyword,
        candidate_factory_serials=candidate_serials(entries),
        machine_model=args.machine_model,
        project=args.project,
        business_category=args.business_category,
        process=args.process,
        optical_path=args.optical_path,
        exception_type=infer_plan_exception_type(entries),
        type_name=infer_plan_type_name(entries),
        debug_process=debug_process,
        duration=args.duration,
        reviewer=args.reviewer,
        source_entry=chosen_entry.original_text,
        source_entries=[entry.original_text for entry in entries],
        warnings=warnings,
    )


def build_plan(raw_text: str, args: argparse.Namespace) -> OaExceptionPlan:
    entry_texts = split_entries(raw_text)
    if not entry_texts:
        raise ValueError('未读取到日报内容。')

    table_date = args.table_date or format_table_date(args.date)
    debug_process = normalized_debug_process(raw_text)
    parsed_entries = [parse_entry(entry_text) for entry_text in entry_texts]
    chosen_entry = choose_machine_entry(parsed_entries, args.date, debug_process, args.machine_choice)
    records = [build_record(parsed_entries, chosen_entry, table_date, debug_process, args)]
    warnings = [warning for record in records for warning in record.warnings]
    return OaExceptionPlan(
        oa_list_url=SANITIZED_OA_LIST_URL,
        table_date=table_date,
        records=records,
        warnings=warnings,
    )


def render_markdown(plan: OaExceptionPlan) -> str:
    headers = [
        '表格日期',
        '日报机台',
        '设备出厂编号',
        '机型',
        '项目归属',
        '业务分类',
        '工序',
        '光路',
        '异常类型',
        '类型',
        '复核人',
    ]
    rows = []
    for record in plan.records:
        rows.append(
            [
                record.table_date,
                f'{record.source_machine} ({", ".join(record.source_machines)})',
                record.factory_serial or '待确认',
                record.machine_model,
                record.project,
                record.business_category,
                record.process,
                record.optical_path,
                record.exception_type,
                record.type_name,
                record.reviewer,
            ]
        )
    sections = [
        f'OA异常记录填报计划: {plan.table_date}',
        render_markdown_table(headers, rows),
        '',
        '调试过程',
        plan.records[0].debug_process if plan.records else '',
    ]
    if plan.warnings:
        sections.extend(['', '警告', *[f'- {warning}' for warning in plan.warnings]])
    return '\n'.join(section for section in sections if section is not None)


def render_json(plan: OaExceptionPlan) -> str:
    payload = {
        'oa_list_url': plan.oa_list_url,
        'table_date': plan.table_date,
        'records': [asdict(record) for record in plan.records],
        'warnings': plan.warnings,
    }
    return json.dumps(payload, ensure_ascii=False, indent=2)


def read_report_text(args: argparse.Namespace) -> str:
    if args.text:
        return args.text
    if args.input_file:
        return Path(args.input_file).read_text(encoding='utf-8')
    if sys.stdin.isatty():
        print('请粘贴日报内容，完成后按 Ctrl-D：', file=sys.stderr)
    return sys.stdin.read()


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description='Prepare OA exception-record fill data from a TCP daily report.')
    parser.add_argument('--date', default=today_string(), help='日报日期，例如 2026/5/28。默认今天。')
    parser.add_argument('--table-date', default='', help='OA 异常记录表日期标签，例如 5.28；默认从 --date 推导。')
    parser.add_argument('--machine-model', default=DEFAULT_MACHINE_MODEL, help='机型，默认量产机。')
    parser.add_argument('--project', default=DEFAULT_PROJECT, help='项目归属，默认 TCSE。')
    parser.add_argument('--business-category', default=DEFAULT_BUSINESS_CATEGORY, help='业务分类，默认运维。')
    parser.add_argument('--process', default=DEFAULT_PROCESS, help='工序，默认激光1。')
    parser.add_argument('--optical-path', default=DEFAULT_OPTICAL_PATH, help='光路，默认光路1。')
    parser.add_argument('--duration', default=DEFAULT_DURATION, help='耗时，默认留空。')
    parser.add_argument('--reviewer', default=DEFAULT_REVIEWER, help='复核人，默认罗威。')
    parser.add_argument('--device-result-keyword', default=DEFAULT_CUSTOMER_ROW, help='设备搜索结果需要选择的关键词。')
    parser.add_argument(
        '--machine-choice',
        choices=('stable-random', 'first'),
        default='stable-random',
        help='多机台日报选择设备编号的方式。stable-random=按日期和日报内容稳定随机；first=选第一台可映射机台。',
    )
    parser.add_argument('--format', choices=('json', 'markdown'), default='markdown', help='输出格式。')
    parser.add_argument('--text', help='直接传入日报文本。')
    parser.add_argument('--input-file', help='从文件读取日报文本。')
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)
    report_text = read_report_text(args)
    try:
        plan = build_plan(report_text, args)
    except ValueError as exc:
        parser.error(str(exc))

    if args.format == 'json':
        print(render_json(plan))
    else:
        print(render_markdown(plan))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
