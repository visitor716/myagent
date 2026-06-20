"""Regression tests for OA exception-record fill data."""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parents[1] / 'scripts'
sys.path.insert(0, str(SCRIPT_DIR))

import oa_exception_records


class OaExceptionRecordsTests(unittest.TestCase):
    def build_args(self, *args: str):
        return oa_exception_records.build_arg_parser().parse_args(
            ['--date', '2026/5/28', '--machine-choice', 'first', *args]
        )

    def test_build_plan_maps_daily_report_to_one_oa_detail_row(self) -> None:
        text = (
            '1、13A相机频繁报警调整，检查发现进料模组皮带尺寸偏短，联系设备更换后恢复\n'
            '2、10B1更换激光器，调整基础光路及扩束镜，调整DOE后光斑形貌OK\n'
            '3、8A出料舌头缩回感应信号异常，调整气压大小及缩回感应器位置后观察跑片正常'
        )

        plan = oa_exception_records.build_plan(text, self.build_args())

        self.assertEqual(plan.table_date, '5.28')
        self.assertEqual(len(plan.records), 1)
        record = plan.records[0]
        self.assertEqual(record.source_machine, '13A')
        self.assertEqual(record.source_machines, ['13A', '10B1', '8A'])
        self.assertEqual(record.factory_serial, '5655')
        self.assertEqual(record.device_search_keyword, '5655')
        self.assertEqual(record.candidate_factory_serials, ['13A=5655', '10B1=4659', '8A=4657'])
        self.assertEqual(record.exception_type, '光斑')
        self.assertEqual(record.type_name, '工艺调试')
        self.assertTrue(record.debug_process.startswith('1、13A相机频繁报警调整'))
        self.assertEqual(record.duration, '')
        self.assertEqual(record.reviewer, '罗威')

    def test_stable_random_choice_is_reproducible(self) -> None:
        args = oa_exception_records.build_arg_parser().parse_args(['--date', '2026/5/28'])
        text = (
            '1、13A相机频繁报警调整，检查发现进料模组皮带尺寸偏短，联系设备更换后恢复\n'
            '2、10B1更换激光器，调整基础光路及扩束镜，调整DOE后光斑形貌OK\n'
            '3、8A出料舌头缩回感应信号异常，调整气压大小及缩回感应器位置后观察跑片正常'
        )

        first = oa_exception_records.build_plan(text, args).records[0]
        second = oa_exception_records.build_plan(text, args).records[0]

        self.assertEqual(first.source_machine, second.source_machine)
        self.assertIn(first.factory_serial, {'5655', '4659', '4657'})

    def test_machine_14_reuses_machine_13_serial(self) -> None:
        plan = oa_exception_records.build_plan('14A出料感应信号异常，调整后恢复', self.build_args())

        self.assertEqual(plan.records[0].machine_index, 14)
        self.assertEqual(plan.records[0].factory_serial, '5655')
        self.assertNotIn('未配置 14 号机的设备出厂编号', plan.warnings)

    def test_missing_machine_serial_is_reported_as_warning(self) -> None:
        plan = oa_exception_records.build_plan('15A出料感应信号异常，调整后恢复', self.build_args())

        self.assertEqual(plan.records[0].machine_index, 15)
        self.assertEqual(plan.records[0].factory_serial, '')
        self.assertIn('未配置 15 号机的设备出厂编号', plan.warnings)

    def test_json_output_uses_sanitized_oa_url(self) -> None:
        plan = oa_exception_records.build_plan('10B1光斑破洞，调整DOE后恢复', self.build_args())

        payload = json.loads(oa_exception_records.render_json(plan))

        self.assertEqual(payload['oa_list_url'], oa_exception_records.SANITIZED_OA_LIST_URL)
        self.assertNotIn('em_auth_code', payload['oa_list_url'])
        self.assertNotIn('_key', payload['oa_list_url'])

    def test_markdown_output_renders_fill_plan(self) -> None:
        plan = oa_exception_records.build_plan('10B1光斑破洞，调整DOE后恢复', self.build_args())

        output = oa_exception_records.render_markdown(plan)

        self.assertIn('OA异常记录填报计划: 5.28', output)
        self.assertIn('| 5.28 | 10B1 (10B1) | 4659 | 量产机 | TCSE | 运维 | 激光1 | 光路1 | 光斑 | 工艺调试 | 罗威 |', output)
        self.assertIn('调试过程', output)


if __name__ == '__main__':
    unittest.main()
