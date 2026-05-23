from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from decimal import Decimal
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "bookkeeping.py"
SPEC = importlib.util.spec_from_file_location("bookkeeping", SCRIPT)
bookkeeping = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = bookkeeping
SPEC.loader.exec_module(bookkeeping)


class BookkeepingTest(unittest.TestCase):
    def write_bill(self, content: str) -> Path:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / "alipay.csv"
        path.write_text(content, encoding="gb18030")
        return path

    def test_alipay_monthly_personal_spend_with_refund_and_reimbursable(self) -> None:
        path = self.write_bill(
            "\n".join(
                [
                    "导出信息：",
                    "共4笔记录",
                    "支出：3笔 300.00元",
                    "交易时间,交易分类,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注,",
                    "2026-01-01 09:00:00,餐饮美食,早餐店,/,早餐,支出,100.00,银行卡,交易成功,1,,,",
                    "2026-01-02 09:00:00,酒店旅游,扬州沁润居酒店管理有限公司,/,房费,支出,200.00,银行卡,交易成功,2,,,",
                    "2026-01-03 09:00:00,交通出行,铁路12306,/,火车票,支出,50.00,银行卡,交易关闭,3,,,",
                    "2026-01-04 09:00:00,退款,铁路12306,/,退款-火车票,不计收支,50.00,,退款成功,4,,,",
                ]
            )
        )
        transactions, _, _ = bookkeeping.parse_alipay(path)
        result = bookkeeping.summarize(transactions, {"扬州沁润居酒店管理有限公司"})
        monthly = result["monthly"][0]
        self.assertEqual(monthly["actual"], Decimal("300.00"))
        self.assertEqual(monthly["reimbursable"], Decimal("200.00"))
        self.assertEqual(monthly["personal"], Decimal("100.00"))


if __name__ == "__main__":
    unittest.main()
