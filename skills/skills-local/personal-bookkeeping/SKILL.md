---
name: personal-bookkeeping
description: Analyze personal transaction exports from Alipay, WeChat Pay, or bank CSV files. Use when the user asks for 记账, 账单分析, 每月花费, 支付宝/微信/银行卡交易明细统计, 消费分类, 支出汇总, or wants reimbursable work expenses such as 出差酒店房费 removed from personal spending.
---

# Personal Bookkeeping

Use this skill to turn exported payment/bank bills into a conservative personal spending summary.

## Default Workflow

1. Resolve the bill path. Convert Windows paths like `D:\Personal\账单\a.csv` to WSL paths like `/mnt/d/Personal/账单/a.csv` when running in WSL.
2. Inspect the file header, encoding, and row count before calculating. Alipay CSV exports are commonly `gb18030` and include metadata before the real CSV header.
3. Prefer the bundled parser for Alipay CSV files:

```bash
python3 ~/.codex/skills/personal-bookkeeping/scripts/bookkeeping.py \
  "/path/to/支付宝交易明细.csv"
```

4. If the user asks to remove reimbursable spending, use exact merchant matches and report every removed row. The default reimbursable merchant profile includes:
   - `扬州沁润居酒店管理有限公司`
   - `扬州沁润局酒店管理有限公司`
5. If the user asks for raw total spending or says `不剔除`, rerun with:

```bash
python3 ~/.codex/skills/personal-bookkeeping/scripts/bookkeeping.py \
  --no-default-exclusions "/path/to/账单.csv"
```

6. For an additional reimbursable merchant:

```bash
python3 ~/.codex/skills/personal-bookkeeping/scripts/bookkeeping.py \
  --exclude-merchant "商户名称" "/path/to/账单.csv"
```

## Accounting Rules

- Monthly personal spending means consumption outflow after refunds, not account movement.
- For Alipay, compute actual spending as `支出金额合计 - 消费退款`.
- Do not count `不计收支` investment, fund conversion, Yu'ebao, transfer, recharge, withdrawal, repayment, or internal account movement as consumption.
- Treat refund rows as negative consumption when the status/category/description contains `退款`, unless the category is investment/wealth management.
- Keep credit-card repayments, fund purchases, transfers, and balance moves out of personal consumption unless the user explicitly asks for cash-flow analysis.
- When multiple source files are provided, warn about duplicate counting risk if the same Alipay quick-pay transaction may also appear in a bank/card statement.
- Always separate:
  - original actual spending
  - reimbursable amount removed
  - final personal spending

## Output Contract

Return a compact summary with:

- source file(s) and detected encoding/type
- monthly table: original actual spending, reimbursable exclusions, final personal spending
- total and average monthly personal spending
- removed reimbursable rows with date, merchant, category, status, and amount
- any reconciliation note, especially whether the calculated Alipay total matches the export summary
- top categories or merchants when useful
- assumptions and remaining risks, such as unmatched reimbursable merchants or possible duplicate bank records

## Script Notes

The parser intentionally uses only the Python standard library. It supports Alipay CSV exports directly and provides a clear error if the header is unsupported. For unsupported bank or WeChat formats, inspect the header and either normalize the CSV to the Alipay-like fields or extend `scripts/bookkeeping.py` with a new parser.
