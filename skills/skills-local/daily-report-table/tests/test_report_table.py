"""Regression tests for the daily report table parser."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT_DIR = Path(__file__).resolve().parents[1] / 'scripts'
sys.path.insert(0, str(SCRIPT_DIR))

import report_table


class ReportTableTests(unittest.TestCase):
    def test_split_entries_supports_numbered_items(self) -> None:
        text = (
            '1、9A出料一驱动器报警EE，重新断电插拔编码器接头后复位正常。\n'
            '2、9B1光斑能量偏左下，调整倍率及发散角，调整DOE后光斑形貌OK\n'
            '3、9B2光斑下部分破洞，调整倍率及发散角，调整DOE后光斑形貌OK'
        )

        entries = report_table.split_entries(text)

        self.assertEqual(
            entries,
            [
                '9A出料一驱动器报警EE，重新断电插拔编码器接头后复位正常',
                '9B1光斑能量偏左下，调整倍率及发散角，调整DOE后光斑形貌OK',
                '9B2光斑下部分破洞，调整倍率及发散角，调整DOE后光斑形貌OK',
            ],
        )

    def test_build_tables_from_mixed_entries(self) -> None:
        text = (
            '1、9A出料一驱动器报警EE，重新断电插拔编码器接头后复位正常。\n'
            '2、9B1光斑能量偏左下，调整倍率及发散角，调整DOE后光斑形貌OK\n'
            '3、9B2光斑下部分破洞，调整倍率及发散角，调整DOE后光斑形貌OK'
        )
        metadata = {
            'date': '2026/4/16',
            'name': '詹香平',
            'group': report_table.DEFAULTS['group'],
            'base': report_table.DEFAULTS['base'],
            'device': report_table.DEFAULTS['device'],
            'business': report_table.DEFAULTS['business'],
            'category': report_table.DEFAULTS['category'],
            'area': 'F3',
        }

        parsed_entries = [report_table.parse_entry(entry) for entry in report_table.split_entries(text)]
        main_rows = report_table.build_main_rows(parsed_entries, metadata)
        spot_rows = report_table.build_spot_rows(parsed_entries, metadata)

        self.assertEqual(len(main_rows), 3)
        self.assertEqual(len(spot_rows), 2)
        self.assertEqual(main_rows[0][:6], ['2026/4/16', '罗威组', '扬州晶澳F3', 'TCP', '9A', '运维'])
        self.assertEqual(main_rows[0][6], '自动化调试')
        self.assertEqual(main_rows[1][6], '工艺调试')
        self.assertEqual(main_rows[2][6], '工艺调试')
        self.assertEqual(main_rows[0][4], '9A')
        self.assertEqual(main_rows[0][7], '驱动器报警EE')
        self.assertEqual(spot_rows[0][0], 'F3')
        self.assertEqual(spot_rows[0][1], '4月16号')
        self.assertEqual(spot_rows[0][2], '9B')
        self.assertEqual(spot_rows[0][3], 'AC')
        self.assertEqual(spot_rows[0][4], '能量偏移')
        self.assertEqual(spot_rows[1][3], 'BD')
        self.assertEqual(spot_rows[1][4], '光斑破洞')

    def test_abnormal_category_is_inferred_from_process_keywords(self) -> None:
        metadata = {
            'date': '2026/4/21',
            'name': '詹香平',
            'group': report_table.DEFAULTS['group'],
            'base': report_table.DEFAULTS['base'],
            'device': report_table.DEFAULTS['device'],
            'business': report_table.DEFAULTS['business'],
            'category': report_table.DEFAULTS['category'],
            'area': 'F3',
        }
        parsed_entries = [
            report_table.parse_entry('1A1光斑破洞，调整DOE后恢复'),
            report_table.parse_entry('2A PT 值极差大，校准后恢复'),
            report_table.parse_entry('3B精度异常，重新标定后恢复'),
            report_table.parse_entry('4A出料一驱动器报警EE，重新插拔编码器后恢复'),
        ]

        main_rows = report_table.build_main_rows(parsed_entries, metadata)

        self.assertEqual([row[6] for row in main_rows], ['工艺调试', '工艺调试', '工艺调试', '自动化调试'])

    def test_abnormal_and_review_keep_symptom_without_handling_result(self) -> None:
        metadata = {
            'date': '2026/4/25',
            'name': '詹香平',
            'group': report_table.DEFAULTS['group'],
            'base': report_table.DEFAULTS['base'],
            'device': report_table.DEFAULTS['device'],
            'business': report_table.DEFAULTS['business'],
            'category': report_table.DEFAULTS['category'],
            'area': 'F3',
        }
        parsed_entries = [
            report_table.parse_entry('3B毛刷气缸接头缩回异常，更换接头并固定接头后恢复生产'),
            report_table.parse_entry('2A生产操作机台，误锁定上位机软件，重启工控机后恢复正常'),
        ]

        main_rows = report_table.build_main_rows(parsed_entries, metadata)

        self.assertEqual(main_rows[0][7], '毛刷气缸接头缩回异常')
        self.assertEqual(main_rows[0][9], '毛刷气缸接头缩回异常')
        self.assertEqual(main_rows[1][7], '误锁定上位机软件')
        self.assertEqual(main_rows[1][9], '误锁定上位机软件')

    def test_explicit_category_overrides_inferred_category(self) -> None:
        entry = report_table.parse_entry('1A1光斑破洞，调整DOE后恢复')
        metadata = {
            'date': '2026/4/21',
            'name': '詹香平',
            'group': '',
            'base': '',
            'device': '',
            'business': '',
            'category': '现场确认',
            'area': 'F3',
        }

        main_rows = report_table.build_main_rows([entry], metadata)

        self.assertEqual(main_rows[0][6], '现场确认')

    def test_resolve_path_accepts_windows_path(self) -> None:
        default_output_dir = r'D:\Obsidian\MyNote\03.工作\扬州晶澳F3日报表格自动化'

        self.assertEqual(report_table.DEFAULTS['output_dir'], default_output_dir)
        resolved = report_table.resolve_path(default_output_dir)
        self.assertEqual(str(resolved), '/mnt/d/Obsidian/MyNote/03.工作/扬州晶澳F3日报表格自动化')
        self.assertEqual(
            report_table.display_path('/mnt/d/Obsidian/MyNote/03.工作/扬州晶澳F3日报表格自动化/企业微信日报.html'),
            r'D:\Obsidian\MyNote\03.工作\扬州晶澳F3日报表格自动化\企业微信日报.html',
        )

    def test_filename_template_uses_normalized_date(self) -> None:
        self.assertEqual(
            report_table.resolve_filename_template('企业微信日报-{date}.html', '2026/4/18'),
            '企业微信日报-2026-04-18.html',
        )

    def test_format_chart_date_uses_month_day_chinese_label(self) -> None:
        self.assertEqual(report_table.format_chart_date('2026/4/18'), '4月18日')

    def test_col_index_to_label_supports_excel_columns(self) -> None:
        self.assertEqual(report_table.col_index_to_label(0), 'A')
        self.assertEqual(report_table.col_index_to_label(25), 'Z')
        self.assertEqual(report_table.col_index_to_label(26), 'AA')
        self.assertEqual(report_table.col_index_to_label(125), 'DV')

    def test_detect_chart_target_converts_live_indices_to_cell(self) -> None:
        with patch.object(
            report_table,
            'run_playwright_eval_json',
            return_value={
                'sheetName': '光斑异常图表',
                'colIndex': 125,
                'rowIndex': 1,
                'dateLabel': '4月18日',
                'anchorLabel': '1A-AC',
            },
        ):
            target = report_table.detect_chart_target('wecom-fast-fail', '光斑异常图表', '4月18日', '1A-AC')

        self.assertEqual(target['sheet_name'], '光斑异常图表')
        self.assertEqual(target['start_cell'], 'DV2')

    def test_render_sections_chart_copy_summary_includes_target(self) -> None:
        output = report_table.render_sections(
            [],
            [],
            'markdown',
            'summary',
            True,
            {'chart_target_sheet': '光斑异常图表', 'chart_start_cell': 'DV2'},
        )

        self.assertIn('输出格式: 图表复制', output)
        self.assertIn('图表工作表: 光斑异常图表', output)
        self.assertIn('图表起始格: DV2', output)

    def test_render_sections_supports_tsv_preview_with_wecom_html(self) -> None:
        main_rows = [
            ['', '', '', '', '3B2', '', '工艺调试', '光斑破洞', '处理过程1', '光斑破洞', '詹香平'],
        ]
        spot_rows = [
            ['F3', '4月19号', '3B', 'BD', '光斑破洞', '处理过程1', '詹香平', ''],
        ]

        output = report_table.render_sections(
            main_rows,
            spot_rows,
            'wecom-html',
            'tsv',
            False,
            None,
        )

        self.assertIn('日期\t组别\t客户基地\t设备类型\t机台编号\t业务\t异常分类\t异常现象\t调试过程\t问题复盘\t记录人员', output)
        self.assertIn('\n光斑调试表\n', output)
        self.assertIn('区域\t日期\t机台\t通道\t异常类型\t处理说明\t记录人员\t备注', output)

    def test_build_chart_export_maps_machine_and_channel_to_fixed_rows(self) -> None:
        parsed_entries = [
            report_table.parse_entry('4B2光斑缺失，调整后恢复'),
            report_table.parse_entry('5A2光斑破洞，调整后恢复'),
            report_table.parse_entry('4B1 光斑能量偏移调整后恢复'),
            report_table.parse_entry('3A光斑破洞，AC和BD调整后恢复'),
        ]

        chart_export = report_table.build_chart_export(parsed_entries, 7)
        chart_map = dict(zip(chart_export.rows, chart_export.values))

        self.assertEqual(chart_map['4B-AC'], '能量偏移')
        self.assertEqual(chart_map['4B-BD'], '光斑缺失')
        self.assertEqual(chart_map['5A-BD'], '光斑破洞')
        self.assertEqual(chart_map['3A-AC'], '光斑破洞')
        self.assertEqual(chart_map['3A-BD'], '光斑破洞')

    def test_persist_outputs_appends_rows_to_fixed_notes(self) -> None:
        metadata = {
            'date': '2026/4/16',
            'name': '詹香平',
            'group': '',
            'base': '',
            'device': '',
            'business': '',
            'category': '工艺调试',
            'area': 'F3',
            'output_dir': '',
            'main_note': '每天日报.md',
            'spot_note': '光斑调试记录.md',
            'wecom_html_file': '企业微信日报-2026-04-16.html',
            'chart_column_file': '光斑异常图表列-2026-04-16.tsv',
            'chart_copy_html_file': '光斑异常图表复制-2026-04-16.html',
            'chart_target_sheet': '',
            'chart_start_cell': '',
        }
        main_rows = [
            ['', '', '', '', '9A', '', '工艺调试', '驱动器报警EE', '处理过程1', '驱动器报警EE', '詹香平'],
            ['', '', '', '', '9B1', '', '工艺调试', '光斑下部分破洞', '处理过程2', '光斑下部分破洞', '詹香平'],
        ]
        spot_rows = [
            ['F3', '4月16号', '9B', 'AC', '光斑破洞', '处理过程2', '詹香平', ''],
        ]

        with tempfile.TemporaryDirectory() as temp_dir:
            metadata['output_dir'] = temp_dir
            report_table.persist_outputs(main_rows, spot_rows, metadata, 'markdown', 'all', None, False)
            report_table.persist_outputs(main_rows[:1], [], metadata, 'markdown', 'all', None, False)

            main_note = Path(temp_dir) / '每天日报.md'
            spot_note = Path(temp_dir) / '光斑调试记录.md'

            main_content = main_note.read_text(encoding='utf-8')
            spot_content = spot_note.read_text(encoding='utf-8')

            self.assertIn('# 每天日报', main_content)
            self.assertEqual(main_content.count('|  |  |  |  | 9A |  | 工艺调试 | 驱动器报警EE | 处理过程1 | 驱动器报警EE | 詹香平 |'), 2)
            self.assertIn('| F3 | 4月16号 | 9B | AC | 光斑破洞 | 处理过程2 | 詹香平 |  |', spot_content)

    def test_chart_copy_outputs_are_written(self) -> None:
        metadata = {
            'date': '2026/4/18',
            'name': '陈治宇',
            'group': '',
            'base': '',
            'device': '',
            'business': '',
            'category': '工艺调试',
            'area': 'F3',
            'output_dir': '',
            'main_note': '每天日报.md',
            'spot_note': '光斑调试记录.md',
            'wecom_html_file': '企业微信日报-2026-04-18.html',
            'chart_column_file': '光斑异常图表列-2026-04-18.tsv',
            'chart_copy_html_file': '光斑异常图表复制-2026-04-18.html',
            'chart_target_sheet': '光斑异常图表',
            'chart_start_cell': 'DV2',
        }
        parsed_entries = [
            report_table.parse_entry('4B2光斑缺失，调整后恢复'),
            report_table.parse_entry('4B1 光斑能量偏移调整后恢复'),
        ]

        with tempfile.TemporaryDirectory() as temp_dir:
            metadata['output_dir'] = temp_dir
            chart_export = report_table.build_chart_export(parsed_entries, 7)
            report_table.persist_outputs([], [], metadata, 'markdown', 'none', chart_export, True)

            chart_file = Path(temp_dir) / '光斑异常图表列-2026-04-18.tsv'
            html_file = Path(temp_dir) / '光斑异常图表复制-2026-04-18.html'
            self.assertTrue(chart_file.exists())
            self.assertTrue(html_file.exists())
            self.assertIn('4B-BD', report_table.build_chart_rows(7))


if __name__ == '__main__':
    unittest.main()
