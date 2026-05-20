#!/usr/bin/env python3
"""Fill the current browser work-hours form from an overtime note.

The script only fills fields. It does not save or submit the page.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Sequence

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

import work_hours_sheet


FILL_FORM_JS = r"""
() => {
  const values = __VALUES__;
  const report = [];

  const normalize = (text) => String(text || '').replace(/\s+/g, '').trim();
  const isVisible = (element) => {
    if (!element) return false;
    const style = window.getComputedStyle(element);
    if (style.display === 'none' || style.visibility === 'hidden') return false;
    const rect = element.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  };
  const visibleText = (element) => normalize(element.innerText || element.textContent || '');
  const queryVisible = (selector, root = document) =>
    Array.from(root.querySelectorAll(selector)).filter(isVisible);

  const findLabelRoot = (label) => {
    const target = normalize(label);
    const elements = queryVisible('td, th, label, span, div');
    const exact = elements.find((element) => visibleText(element) === target);
    if (!exact) return null;
    return exact.closest('td,th,label') || exact;
  };

  const findValueArea = (label) => {
    const root = findLabelRoot(label);
    if (!root) return null;
    const row = root.closest('tr');
    if (row && root.cellIndex >= 0) {
      return row.cells[root.cellIndex + 1] || root.nextElementSibling || root.parentElement;
    }
    return root.nextElementSibling || root.parentElement;
  };

  const setElementValue = (element, value) => {
    element.focus();
    const prototype =
      element instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    const descriptor = Object.getOwnPropertyDescriptor(prototype, 'value');
    if (descriptor && descriptor.set) {
      descriptor.set.call(element, value);
    } else {
      element.value = value;
    }
    element.dispatchEvent(new Event('input', { bubbles: true }));
    element.dispatchEvent(new Event('change', { bubbles: true }));
    element.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
    element.dispatchEvent(new KeyboardEvent('keyup', { key: 'Enter', bubbles: true }));
    element.blur();
  };

  const fillInputByLabel = (label, value) => {
    const area = findValueArea(label);
    if (!area) {
      report.push({ label, value, status: 'label-not-found' });
      return;
    }
    const input =
      queryVisible('input:not([type="hidden"]), textarea', area)[0] ||
      queryVisible('input:not([type="hidden"]), textarea').find((element) => {
        const rect = element.getBoundingClientRect();
        const areaRect = area.getBoundingClientRect();
        return rect.left >= areaRect.left && rect.top >= areaRect.top - 4;
      });
    if (!input) {
      report.push({ label, value, status: 'input-not-found' });
      return;
    }
    setElementValue(input, value);
    report.push({ label, value, status: 'filled' });
  };

  const fillSelectByLabel = (label, value) => {
    const area = findValueArea(label);
    if (!area) {
      report.push({ label, value, status: 'label-not-found' });
      return;
    }
    const select = queryVisible('select', area)[0];
    if (select) {
      const option = Array.from(select.options).find((item) => normalize(item.text) === normalize(value) || item.value === value);
      select.value = option ? option.value : value;
      select.dispatchEvent(new Event('change', { bubbles: true }));
      report.push({ label, value, status: option ? 'selected' : 'selected-by-value' });
      return;
    }
    const input = queryVisible('input:not([type="hidden"])', area)[0];
    if (input) {
      setElementValue(input, value);
      report.push({ label, value, status: 'filled-select-input' });
      return;
    }
    report.push({ label, value, status: 'select-not-found' });
  };

  const fillDetailDuration = (value) => {
    const header = queryVisible('td, th, div, span').find((element) => visibleText(element) === normalize('时长'));
    const table = header && header.closest('table');
    if (!table || header.cellIndex < 0) {
      report.push({ label: '明细时长', value, status: 'duration-column-not-found' });
      return;
    }
    const rows = Array.from(table.rows).filter((row) => row.rowIndex > header.parentElement.rowIndex);
    const targetCell = rows.map((row) => row.cells[header.cellIndex]).find(Boolean);
    const input = targetCell && queryVisible('input:not([type="hidden"]), textarea', targetCell)[0];
    if (!input) {
      report.push({ label: '明细时长', value, status: 'duration-input-not-found' });
      return;
    }
    setElementValue(input, value);
    report.push({ label: '明细时长', value, status: 'filled' });
  };

  fillInputByLabel('终端客户', values.terminalCustomer);
  fillSelectByLabel('是否包含收费改造项目', values.chargedProject);
  fillInputByLabel('出勤小时', values.attendanceHours);
  fillInputByLabel('加班小时', values.overtimeHours);
  fillInputByLabel('合计工时', values.totalHours);
  fillDetailDuration(values.detailDuration);

  return report;
}
""".strip()


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description='Fill the active work-hours browser form without submitting it.')
    parser.add_argument('text', nargs='*', help='一句话输入，例如：4.4 加班11')
    parser.add_argument('--date', help='指定日期，例如 2026-04-25、4.4、昨天')
    parser.add_argument('--overtime', help='指定加班小时数，例如 11')
    parser.add_argument('--session', default='wsl-windows-chrome', help='playwright-cli session name')
    parser.add_argument('--dry-run', action='store_true', help='只打印将要填写的数据，不操作浏览器')
    return parser


def read_input_text(args: argparse.Namespace) -> str:
    if args.text:
        return ' '.join(args.text).strip()
    if not sys.stdin.isatty():
        return sys.stdin.read().strip()
    return ''


def build_eval_code(values: dict[str, str]) -> str:
    return FILL_FORM_JS.replace('__VALUES__', json.dumps(values, ensure_ascii=False))


def run_playwright_eval(session: str, values: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ['playwright-cli', f'-s={session}', 'eval', build_eval_code(values)],
        check=False,
        text=True,
        capture_output=True,
    )


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)
    input_text = read_input_text(args)
    if not input_text and not args.overtime:
        parser.error('请提供加班数据，例如：4.4 加班11')

    try:
        sheet = work_hours_sheet.build_sheet(input_text, args.date, args.overtime)
    except ValueError as exc:
        parser.error(str(exc))

    values = work_hours_sheet.build_form_values(sheet)
    if args.dry_run:
        print(json.dumps(values, ensure_ascii=False, indent=2))
        return 0

    result = run_playwright_eval(args.session, values)
    if result.stdout:
        print(result.stdout.strip())
    if result.stderr:
        print(result.stderr.strip(), file=sys.stderr)
    return result.returncode


if __name__ == '__main__':
    raise SystemExit(main())
