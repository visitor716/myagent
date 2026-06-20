"""Regression tests for the OA timesheet CDP helper."""

from __future__ import annotations

import json
import subprocess
import textwrap
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[1] / 'scripts' / 'fill_oa_timesheets_via_cdp.cjs'


def run_node_json(source: str) -> dict:
    result = subprocess.run(
        ['node', '-e', textwrap.dedent(source)],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


class OaTimesheetsCliTests(unittest.TestCase):
    def test_overtime_entry_uses_attendance_calendar(self) -> None:
        payload = run_node_json(
            f"""
            const helper = require({json.dumps(str(SCRIPT_PATH))});
            const entry = helper.parseOvertimeEntry('2026-06-07:11.5');
            console.log(JSON.stringify(entry));
            """
        )

        self.assertEqual(payload['date'], '2026-06-07')
        self.assertEqual(payload['attendance'], '0.00')
        self.assertEqual(payload['overtime'], '11.50')
        self.assertEqual(payload['total'], '11.50')

    def test_verify_only_and_fill_missing_flags_parse(self) -> None:
        payload = run_node_json(
            f"""
            const helper = require({json.dumps(str(SCRIPT_PATH))});
            console.log(JSON.stringify({{
              verify: helper.parseArgs(['--auto-from-list', '--verify-only']).verifyOnly,
              fill: helper.parseArgs(['--auto-from-list', '--fill-missing']).fillMissing
            }}));
            """
        )

        self.assertEqual(payload, {'verify': True, 'fill': True})

    def test_verify_only_and_fill_missing_are_mutually_exclusive(self) -> None:
        payload = run_node_json(
            f"""
            const helper = require({json.dumps(str(SCRIPT_PATH))});
            try {{
              helper.parseArgs(['--auto-from-list', '--verify-only', '--fill-missing']);
              console.log(JSON.stringify({{ ok: false }}));
            }} catch (error) {{
              console.log(JSON.stringify({{ ok: true, message: error.message }}));
            }}
            """
        )

        self.assertTrue(payload['ok'])
        self.assertIn('cannot be used together', payload['message'])

    def test_build_verification_reports_matching_and_missing_forms(self) -> None:
        payload = run_node_json(
            f"""
            const helper = require({json.dumps(str(SCRIPT_PATH))});
            const entry = helper.parseOvertimeEntry('2026-06-02:4.5');
            const matching = {{
              assignedDate: '2026-06-02',
              customer: '扬州晶澳',
              paidTransform: '否',
              attendance: '8.00',
              overtime: '4.50',
              total: '12.50',
              detailTotal: '12.50',
              module: '运维模块',
              duration: '12.50',
              serial: '',
              remark: ''
            }};
            const missing = {{
              assignedDate: '2026-06-02',
              customer: '',
              paidTransform: '',
              attendance: '',
              overtime: '',
              total: '',
              detailTotal: '0.00',
              module: '',
              duration: '',
              serial: '',
              remark: ''
            }};
            console.log(JSON.stringify({{
              matching: helper.buildVerification(matching, entry),
              missing: helper.buildVerification(missing, entry)
            }}));
            """
        )

        self.assertTrue(payload['matching']['matches'])
        self.assertFalse(payload['matching']['needsFill'])
        self.assertFalse(payload['missing']['matches'])
        self.assertTrue(payload['missing']['needsFill'])
        self.assertTrue(any('customer' in item for item in payload['missing']['errors']))


if __name__ == '__main__':
    unittest.main()
