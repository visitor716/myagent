"""Regression tests for the work-hours allocation sheet generator."""

from __future__ import annotations

import sys
import tempfile
import unittest
from datetime import date
from decimal import Decimal
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parents[1] / 'scripts'
sys.path.insert(0, str(SCRIPT_DIR))

import work_hours_sheet


class WorkHoursSheetTests(unittest.TestCase):
    def test_sentence_input_uses_relative_date_and_decimal_overtime(self) -> None:
        sheet = work_hours_sheet.build_sheet('今天加班2.5小时', reference_date=date(2026, 4, 25))

        self.assertEqual(sheet.work_date, date(2026, 4, 25))
        self.assertEqual(sheet.attendance_hours, Decimal('8'))
        self.assertEqual(sheet.overtime_hours, Decimal('2.5'))
        self.assertEqual(sheet.total_hours, Decimal('10.5'))

    def test_weekday_counts_attendance_and_overtime(self) -> None:
        sheet = work_hours_sheet.build_sheet('2026-04-24 加班2小时')

        self.assertEqual(sheet.attendance_hours, Decimal('8'))
        self.assertEqual(sheet.overtime_hours, Decimal('2'))
        self.assertEqual(sheet.total_hours, Decimal('10'))

    def test_numeric_month_day_shorthand_uses_current_year(self) -> None:
        sheet = work_hours_sheet.build_sheet('4.4 加班11', reference_date=date(2026, 4, 25))

        self.assertEqual(sheet.work_date, date(2026, 4, 4))
        self.assertEqual(sheet.attendance_hours, Decimal('0'))
        self.assertEqual(sheet.overtime_hours, Decimal('11'))
        self.assertEqual(sheet.total_hours, Decimal('11'))

    def test_decimal_overtime_is_not_misread_as_numeric_date(self) -> None:
        sheet = work_hours_sheet.build_sheet('今天加班2.5小时', reference_date=date(2026, 4, 25))

        self.assertEqual(sheet.work_date, date(2026, 4, 25))
        self.assertEqual(sheet.overtime_hours, Decimal('2.5'))

    def test_explicit_date_wins_over_relative_date_wording(self) -> None:
        sheet = work_hours_sheet.build_sheet('昨天 2026-04-24 加班2小时', reference_date=date(2026, 4, 25))

        self.assertEqual(sheet.work_date, date(2026, 4, 24))

    def test_small_week_saturday_counts_as_workday(self) -> None:
        sheet = work_hours_sheet.build_sheet('2026-04-25 加班2小时')

        self.assertEqual(sheet.attendance_hours, Decimal('8'))
        self.assertEqual(sheet.total_hours, Decimal('10'))

    def test_big_week_saturday_counts_as_restday(self) -> None:
        sheet = work_hours_sheet.build_sheet('2026-05-02 加班2小时')

        self.assertEqual(sheet.attendance_hours, Decimal('0'))
        self.assertEqual(sheet.total_hours, Decimal('2'))

    def test_sunday_counts_all_hours_as_overtime(self) -> None:
        sheet = work_hours_sheet.build_sheet('2026-04-26 加班3小时')

        self.assertEqual(sheet.attendance_hours, Decimal('0'))
        self.assertEqual(sheet.overtime_hours, Decimal('3'))
        self.assertEqual(sheet.total_hours, Decimal('3'))

    def test_missing_overtime_hours_raises_clear_error(self) -> None:
        with self.assertRaisesRegex(ValueError, '没有识别到加班小时数'):
            work_hours_sheet.build_sheet('今天加班')

    def test_markdown_only_keeps_requested_fields(self) -> None:
        markdown = work_hours_sheet.render_markdown(work_hours_sheet.build_sheet('2026-04-24 加班2小时'))

        self.assertEqual(
            markdown,
            (
                '|  |  |  | 扬州晶澳 |\n'
                '| --- | --- | --- | ---- |\n'
                '|  | 否 |  | 8 |\n'
                '|  | 2 |  | 10 |\n'
                '|  |  |  |  |\n'
                '\n'
                '10\n'
            ),
        )
        self.assertNotIn('申请人', markdown)
        self.assertNotIn('工号', markdown)
        self.assertNotIn('模块', markdown)
        self.assertNotIn('创建日期', markdown)
        self.assertNotIn('终端客户', markdown)
        self.assertNotIn('出勤小时', markdown)

    def test_build_form_values_maps_controls(self) -> None:
        values = work_hours_sheet.build_form_values(work_hours_sheet.build_sheet('4.4 加班11', reference_date=date(2026, 4, 25)))

        self.assertEqual(
            values,
            {
                'terminalCustomer': '扬州晶澳',
                'chargedProject': '否',
                'attendanceHours': '0',
                'overtimeHours': '11',
                'totalHours': '11',
                'detailDuration': '11',
            },
        )

    def test_write_sheet_uses_dated_filename(self) -> None:
        sheet = work_hours_sheet.build_sheet('2026-04-24 加班2小时')

        with tempfile.TemporaryDirectory() as temp_dir:
            output_file = work_hours_sheet.write_sheet(sheet, temp_dir)
            content = output_file.read_text(encoding='utf-8')

        self.assertEqual(output_file.name, '工时分配单-2026-04-24.md')
        self.assertNotIn('# 工时分配单-2026-04-24', content)
        self.assertIn('|  | 2 |  | 10 |', content)


if __name__ == '__main__':
    unittest.main()
