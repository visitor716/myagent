"""Regression tests for the daily report table parser."""

from __future__ import annotations

import io
import sys
import tempfile
import unittest
import zipfile
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

    def test_problem_review_normalizes_directional_spot_missing_to_spot_hole(self) -> None:
        metadata = {
            'date': '2026/4/26',
            'name': '陈治宇',
            'group': report_table.DEFAULTS['group'],
            'base': report_table.DEFAULTS['base'],
            'device': report_table.DEFAULTS['device'],
            'business': report_table.DEFAULTS['business'],
            'category': report_table.DEFAULTS['category'],
            'area': 'F3',
        }
        parsed_entries = [
            report_table.parse_entry('4A2光斑上下缺失，调整扩束镜倍率发散角和整形镜后恢复'),
            report_table.parse_entry('13B2光斑左边缺失，调整DOE后恢复'),
            report_table.parse_entry('7B1光斑能量上半部分缺失，调整DOE后恢复'),
        ]

        main_rows = report_table.build_main_rows(parsed_entries, metadata)

        self.assertEqual([row[7] for row in main_rows], ['光斑上下缺失', '光斑左边缺失', '光斑能量上半部分缺失'])
        self.assertEqual([row[9] for row in main_rows], ['光斑破洞', '光斑破洞', '光斑能量上半部分缺失'])

    def test_problem_review_normalizes_directional_energy_offset(self) -> None:
        metadata = {
            'date': '2026/5/17',
            'name': '詹香平',
            'group': report_table.DEFAULTS['group'],
            'base': report_table.DEFAULTS['base'],
            'device': report_table.DEFAULTS['device'],
            'business': report_table.DEFAULTS['business'],
            'category': report_table.DEFAULTS['category'],
            'area': 'F3',
        }
        parsed_entries = [
            report_table.parse_entry('3A1光斑能量偏左下，调整倍率及发散角，调整DOE后光斑形貌OK'),
            report_table.parse_entry('4B1光斑形貌能量偏上，调整倍率及发散角，调整DOE后光斑形貌OK'),
            report_table.parse_entry('5A1能量往右偏，调整倍率及发散角后恢复'),
            report_table.parse_entry('7B1光斑能量上半部分缺失，调整DOE后恢复'),
        ]

        main_rows = report_table.build_main_rows(parsed_entries, metadata)

        self.assertEqual(
            [row[7] for row in main_rows],
            ['光斑能量偏左下', '光斑形貌能量偏上', '能量往右偏', '光斑能量上半部分缺失'],
        )
        self.assertEqual([row[9] for row in main_rows], ['能量偏移', '能量偏移', '能量偏移', '光斑能量上半部分缺失'])

    def test_problem_review_normalizes_hole_and_shrink_to_spot_issue(self) -> None:
        metadata = {
            'date': '2026/5/18',
            'name': '詹香平',
            'group': report_table.DEFAULTS['group'],
            'base': report_table.DEFAULTS['base'],
            'device': report_table.DEFAULTS['device'],
            'business': report_table.DEFAULTS['business'],
            'category': report_table.DEFAULTS['category'],
            'area': 'F3',
        }
        parsed_entries = [
            report_table.parse_entry('7B1光斑中间破洞，调整倍率及发散角，调整DOE后光斑形貌OK'),
            report_table.parse_entry('9B2下边破洞，调整DOE后光斑形貌OK'),
            report_table.parse_entry('7B2光斑内缩，调整倍率及发散角，调整DOE后光斑形貌OK'),
        ]

        main_rows = report_table.build_main_rows(parsed_entries, metadata)

        self.assertEqual([row[7] for row in main_rows], ['光斑中间破洞', '下边破洞', '光斑内缩'])
        self.assertEqual([row[9] for row in main_rows], ['光斑破洞', '光斑破洞', '光斑内缩'])

    def test_resolve_path_converts_windows_path_for_wsl(self) -> None:
        default_output_dir = r'D:\Obsidian\MyNote\03.工作\扬州晶澳F3日报表格自动化'

        self.assertEqual(report_table.DEFAULTS['output_dir'], default_output_dir)
        with patch.object(report_table, 'running_on_windows', return_value=False):
            resolved = report_table.resolve_path(default_output_dir)
        self.assertEqual(str(resolved), '/mnt/d/Obsidian/MyNote/03.工作/扬州晶澳F3日报表格自动化')
        self.assertEqual(
            report_table.display_path('/mnt/d/Obsidian/MyNote/03.工作/扬州晶澳F3日报表格自动化/企业微信日报.html'),
            r'D:\Obsidian\MyNote\03.工作\扬州晶澳F3日报表格自动化\企业微信日报.html',
        )

    def test_resolve_path_keeps_windows_path_on_windows(self) -> None:
        output_dir = r'D:\Daily Reports'

        with patch.object(report_table, 'running_on_windows', return_value=True):
            resolved = report_table.resolve_path(output_dir)

        self.assertEqual(str(resolved), output_dir)

    def test_resolve_path_converts_wsl_mount_path_on_windows(self) -> None:
        with patch.object(report_table, 'running_on_windows', return_value=True):
            resolved = report_table.resolve_path('/mnt/d/Daily Reports')

        self.assertEqual(str(resolved), r'D:\Daily Reports')

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
        self.assertEqual(chart_map['4B-BD'], '光斑破洞')
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
            main_tsv = Path(temp_dir) / '每天日报.tsv'
            spot_tsv = Path(temp_dir) / '光斑调试记录.tsv'
            xlsx_file = Path(temp_dir) / '日报表格-2026-04-16.xlsx'
            spot_xlsx_file = Path(temp_dir) / '光斑调试记录-2026-04-16.xlsx'

            main_content = main_note.read_text(encoding='utf-8')
            spot_content = spot_note.read_text(encoding='utf-8')
            main_tsv_content = main_tsv.read_text(encoding='utf-8')
            spot_tsv_content = spot_tsv.read_text(encoding='utf-8')

            self.assertIn('# 每天日报', main_content)
            self.assertEqual(main_content.count('|  |  |  |  | 9A |  | 工艺调试 | 驱动器报警EE | 处理过程1 | 驱动器报警EE | 詹香平 |'), 2)
            self.assertIn('| F3 | 4月16号 | 9B | AC | 光斑破洞 | 处理过程2 | 詹香平 |  |', spot_content)
            self.assertTrue(main_tsv.read_bytes().startswith(report_table.UTF8_BOM))
            self.assertTrue(spot_tsv.read_bytes().startswith(report_table.UTF8_BOM))
            self.assertIn('日期\t组别\t客户基地\t设备类型\t机台编号\t业务\t异常分类\t异常现象\t调试过程\t问题复盘\t记录人员', main_tsv_content)
            self.assertEqual(main_tsv_content.count('\t9A\t'), 2)
            self.assertIn('F3\t4月16号\t9B\tAC\t光斑破洞\t处理过程2\t詹香平\t', spot_tsv_content)
            self.assertTrue(xlsx_file.exists())
            with zipfile.ZipFile(xlsx_file) as workbook:
                workbook_names = workbook.namelist()
                sheet_xml = workbook.read('xl/worksheets/sheet1.xml').decode('utf-8')
                styles_xml = workbook.read('xl/styles.xml').decode('utf-8')
            self.assertIn('xl/styles.xml', workbook_names)
            self.assertIn('<alignment horizontal="center" vertical="center" wrapText="1"/>', styles_xml)
            self.assertIn('<left style="thin"><color auto="1"/></left>', styles_xml)
            self.assertIn('<c r="A1" s="1" t="inlineStr"><is><t>日期</t></is></c>', sheet_xml)
            self.assertIn('<c r="B1" s="1" t="inlineStr"><is><t>组别</t></is></c>', sheet_xml)
            self.assertIn('<c r="C1" s="1" t="inlineStr"><is><t>客户基地</t></is></c>', sheet_xml)
            self.assertTrue(spot_xlsx_file.exists())
            with zipfile.ZipFile(spot_xlsx_file) as workbook:
                spot_workbook_names = workbook.namelist()
                spot_sheet_xml = workbook.read('xl/worksheets/sheet1.xml').decode('utf-8')
                spot_styles_xml = workbook.read('xl/styles.xml').decode('utf-8')
            self.assertIn('xl/styles.xml', spot_workbook_names)
            self.assertIn('<alignment horizontal="center" vertical="center" wrapText="1"/>', spot_styles_xml)
            self.assertIn('<bottom style="thin"><color auto="1"/></bottom>', spot_styles_xml)
            self.assertIn('<col min="6" max="6" width="48" customWidth="1"/>', spot_sheet_xml)
            self.assertIn('<c r="F2" s="1" t="inlineStr"><is><t>处理过程2</t></is></c>', spot_sheet_xml)

    def test_tsv_write_mode_only_writes_tsv_tables(self) -> None:
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
            ['', '', '', '', '6B1', '', '工艺调试', '能量偏右上', '能量偏右上，调整DOE后光斑形貌OK', '能量偏移', '詹香平'],
        ]
        spot_rows = [
            ['F3', '4月16号', '6B', 'AC', '能量偏移', '能量偏右上，调整DOE后光斑形貌OK', '詹香平', ''],
        ]

        with tempfile.TemporaryDirectory() as temp_dir:
            metadata['output_dir'] = temp_dir
            messages = report_table.persist_outputs(main_rows, spot_rows, metadata, 'markdown', 'tsv', None, False)

            self.assertFalse((Path(temp_dir) / '每天日报.md').exists())
            self.assertFalse((Path(temp_dir) / '光斑调试记录.md').exists())
            self.assertTrue((Path(temp_dir) / '每天日报.tsv').exists())
            self.assertTrue((Path(temp_dir) / '光斑调试记录.tsv').exists())
            self.assertIn('已跳过日报/光斑 Markdown 写入。', messages)

    def test_xlsx_write_mode_only_writes_excel_workbook(self) -> None:
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
            'xlsx_file': '日报表格-2026-04-16.xlsx',
            'wecom_html_file': '企业微信日报-2026-04-16.html',
            'chart_column_file': '光斑异常图表列-2026-04-16.tsv',
            'chart_copy_html_file': '光斑异常图表复制-2026-04-16.html',
            'chart_target_sheet': '',
            'chart_start_cell': '',
        }
        main_rows = [
            ['2026/4/16', '罗威组', '扬州晶澳F3', 'TCP', '6B1', '运维', '工艺调试', '能量偏右上', '能量偏右上，调整DOE后光斑形貌OK', '能量偏移', '詹香平'],
        ]

        with tempfile.TemporaryDirectory() as temp_dir:
            metadata['output_dir'] = temp_dir
            messages = report_table.persist_outputs(main_rows, [], metadata, 'markdown', 'xlsx', None, False)

            self.assertFalse((Path(temp_dir) / '每天日报.md').exists())
            self.assertFalse((Path(temp_dir) / '每天日报.tsv').exists())
            xlsx_file = Path(temp_dir) / '日报表格-2026-04-16.xlsx'
            self.assertTrue(xlsx_file.exists())
            with zipfile.ZipFile(xlsx_file) as workbook:
                workbook_names = workbook.namelist()
                sheet_xml = workbook.read('xl/worksheets/sheet1.xml').decode('utf-8')
                styles_xml = workbook.read('xl/styles.xml').decode('utf-8')
            self.assertIn('xl/workbook.xml', workbook_names)
            self.assertIn('xl/styles.xml', workbook_names)
            self.assertIn('<alignment horizontal="center" vertical="center" wrapText="1"/>', styles_xml)
            self.assertIn('<c r="A2" s="1" t="inlineStr"><is><t>2026/4/16</t></is></c>', sheet_xml)
            self.assertIn('<c r="B2" s="1" t="inlineStr"><is><t>罗威组</t></is></c>', sheet_xml)
            self.assertIn('已生成 Excel 表格:', '\n'.join(messages))

    def test_existing_tsv_without_bom_is_upgraded_on_append(self) -> None:
        legacy_content = '日期\t组别\n2026/4/15\t罗威组\n'.encode('utf-8')
        rows = [['2026/4/16', '罗威组']]

        with tempfile.TemporaryDirectory() as temp_dir:
            tsv_file = Path(temp_dir) / '每天日报.tsv'
            tsv_file.write_bytes(legacy_content)

            report_table.append_rows_to_tsv_table(tsv_file, ['日期', '组别'], rows)

            content = tsv_file.read_bytes()
            self.assertTrue(content.startswith(report_table.UTF8_BOM))
            self.assertEqual(content.count(report_table.UTF8_BOM), 1)
            self.assertIn('2026/4/16\t罗威组', tsv_file.read_text(encoding='utf-8-sig'))

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
            self.assertTrue(chart_file.read_bytes().startswith(report_table.UTF8_BOM))
            self.assertIn('4B-BD', report_table.build_chart_rows(7))

    def test_interactive_report_input_stops_at_end_marker(self) -> None:
        with patch('builtins.input', side_effect=['1、6B1能量偏右上，调整DOE后光斑形貌OK', 'END']):
            with patch('sys.stdout', new_callable=io.StringIO):
                report_text = report_table.read_interactive_report_text()

        self.assertEqual(report_text, '1、6B1能量偏右上，调整DOE后光斑形貌OK')

    def test_prompt_output_choice_accepts_quoted_custom_path(self) -> None:
        with patch('builtins.input', side_effect=['3', r'"D:\Daily Reports"']):
            with patch('sys.stdout', new_callable=io.StringIO):
                output_dir, write_mode = report_table.prompt_output_choice(report_table.DEFAULTS['output_dir'])

        self.assertEqual(output_dir, r'D:\Daily Reports')
        self.assertEqual(write_mode, 'xlsx')

    def test_default_output_dir_reads_saved_config(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            config_file = Path(temp_dir) / 'config.json'
            with patch.dict('os.environ', {report_table.CONFIG_ENV_VAR: str(config_file)}):
                report_table.remember_output_dir(r'D:\Daily Reports')

                self.assertEqual(report_table.default_output_dir(), r'D:\Daily Reports')
                self.assertEqual(report_table.build_parser().parse_args([]).output_dir, r'D:\Daily Reports')
                self.assertEqual(report_table.build_parser().parse_args([]).write_mode, 'xlsx')

    def test_interactive_save_choice_remembers_output_dir(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            config_file = Path(temp_dir) / 'config.json'
            output_dir = str(Path(temp_dir) / 'reports')
            with patch.dict('os.environ', {report_table.CONFIG_ENV_VAR: str(config_file)}):
                with patch('sys.stdin.isatty', return_value=True):
                    with patch('builtins.input', side_effect=['6B1能量偏右上，调整DOE后光斑形貌OK', 'END', '3', output_dir]):
                        with patch.object(report_table, 'persist_outputs', return_value=['已保存。']):
                            with patch('sys.stdout', new_callable=io.StringIO):
                                result = report_table.main([])

                self.assertEqual(result, 0)
                self.assertEqual(report_table.default_output_dir(), output_dir)

    def test_preview_only_does_not_remember_output_dir(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            config_file = Path(temp_dir) / 'config.json'
            with patch.dict('os.environ', {report_table.CONFIG_ENV_VAR: str(config_file)}):
                with patch('sys.stdin.isatty', return_value=True):
                    with patch('builtins.input', side_effect=['6B1能量偏右上，调整DOE后光斑形貌OK', 'END', '4']):
                        with patch.object(report_table, 'persist_outputs', return_value=['已跳过日报/光斑笔记写入。']):
                            with patch('sys.stdout', new_callable=io.StringIO):
                                result = report_table.main([])

                self.assertEqual(result, 0)
                self.assertFalse(config_file.exists())

    def test_no_args_tty_runs_wizard_and_can_preview_only(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            config_file = Path(temp_dir) / 'config.json'
            with patch.dict('os.environ', {report_table.CONFIG_ENV_VAR: str(config_file)}):
                with patch('sys.stdin.isatty', return_value=True):
                    with patch('builtins.input', side_effect=['6B1能量偏右上，调整DOE后光斑形貌OK', 'END', '4']):
                        with patch.object(report_table, 'persist_outputs', return_value=['已跳过日报/光斑笔记写入。']) as persist_outputs:
                            with patch('sys.stdout', new_callable=io.StringIO):
                                result = report_table.main([])

        self.assertEqual(result, 0)
        persist_args = persist_outputs.call_args[0]
        self.assertEqual(persist_args[4], 'none')
        self.assertEqual(persist_args[2]['output_dir'], report_table.DEFAULTS['output_dir'])

    def test_no_args_piped_input_keeps_non_interactive_flow(self) -> None:
        stdin = io.StringIO('6B1能量偏右上，调整DOE后光斑形貌OK')
        with patch('sys.stdin', stdin):
            with patch.object(report_table, 'read_interactive_report_text') as read_interactive_report_text:
                with patch.object(report_table, 'persist_outputs', return_value=['已保存。']) as persist_outputs:
                    with patch('sys.stdout', new_callable=io.StringIO):
                        result = report_table.main([])

        self.assertEqual(result, 0)
        read_interactive_report_text.assert_not_called()
        persist_args = persist_outputs.call_args[0]
        self.assertEqual(persist_args[4], 'xlsx')


if __name__ == '__main__':
    unittest.main()
