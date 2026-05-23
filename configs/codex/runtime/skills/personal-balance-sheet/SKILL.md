---
name: personal-balance-sheet
description: Use when updating a personal balance-sheet Excel workbook from account screenshots, merging same-month 应收账款/负债 summary workbooks back into an asset workbook, organizing BalanceSheet files by date folders, splitting the main balance sheet into category sheets such as 流动资产, 投资资产, 应收账款, and 负债, exporting receivable/loan detail workbooks, converting 万元 workbooks to actual yuan amounts, organizing detail screenshot folders, renaming screenshots by visible amounts, or validating Chinese personal asset/liability workbooks. Handles WSL/Windows paths, screenshot-derived amounts, unit conversion, and conservative handling of missing financial data.
metadata:
  short-description: Update and split personal balance sheets
---

# Personal Balance Sheet

Use this skill for the user's personal asset/liability workbooks, especially files named like `YYYYMM资产负债表.xlsx` and screenshot folders named like `YYYY.M`.

## Workflow

1. Normalize paths first.
   - `\\wsl.localhost\Ubuntu\home\...` -> `/home/...`
   - `D:\path\file.xlsx` -> `/mnt/d/path/file.xlsx`
2. Inspect the target workbook before editing.
   - Read sheet names and the main sheet rows.
   - Identify whether the main sheet is named `YYYYMM`, `个人资产负债表`, or the first non-empty sheet.
   - If the user points to a month folder such as `BalanceSheet/YYYY.M`, list every same-month workbook first; do not assume `YYYYMM资产表.xlsx` is the whole source of truth.
3. If screenshots are involved, extract data conservatively.
   - Use OCR when available, then visually verify important amounts.
   - Convert yuan screenshots to 万元 in workbook cells.
   - Do not infer unknown amounts unless the inference is explicit and recorded in notes/comments.
4. Choose the helper command that matches the task.

Archive loose spreadsheets into date folders:

```bash
python scripts/balance_sheet_workbook.py archive \
  --directory /path/to/BalanceSheet
```

Split a main workbook into category sheets:

```bash
python scripts/balance_sheet_workbook.py split \
  --workbook /path/to/YYYYMM资产负债表.xlsx \
  --reference /path/to/reference.xlsx
```

Update a main asset workbook from sibling same-month receivable/liability workbooks:

```bash
python scripts/balance_sheet_workbook.py update-main \
  --directory /path/to/BalanceSheet/YYYY.M
```

Use this when a month folder contains separate files like `YYYYMM资产表.xlsx`, `YYYYMM应收账款.xlsx`, and `YYYYMM负债表.xlsx`. The command inserts `应收账款` and `负债` sections into the main sheet, rebuilds those two category sheets, preserves visible formulas, and writes formula caches for `data_only` readers.

Export receivables to a separate workbook:

```bash
python scripts/balance_sheet_workbook.py export-receivables \
  --workbook /path/to/YYYYMM资产负债表.xlsx \
  --ledger
```

Normalize borrower tabs in an existing receivable workbook to the `时间 / 借/还 / 金额 / 剩余待还` ledger template:

```bash
python scripts/balance_sheet_workbook.py receivable-ledgers \
  --workbook /path/to/YYYYMM应收账款.xlsx \
  --template-sheet 游丹
```

Convert all workbook amount fields in a month folder from 万元/W to actual yuan:

```bash
python scripts/balance_sheet_workbook.py convert-units \
  --directory /path/to/BalanceSheet/YYYY.M
```

Organize detail screenshots into platform/account folders:

```bash
python scripts/balance_sheet_workbook.py organize-details \
  --directory /path/to/BalanceSheet/YYYY.M/明细
```

Rename detail screenshots so the filename includes the visible amount:

```bash
python scripts/balance_sheet_workbook.py rename-detail-images \
  --directory /path/to/BalanceSheet/YYYY.M/明细
```

5. Verify before reporting.

```bash
python scripts/balance_sheet_workbook.py verify \
  --workbook /path/to/YYYYMM资产负债表.xlsx
```

If `openpyxl` is missing, create a temporary venv instead of changing project dependencies:

```bash
python3 -m venv /tmp/bs-openpyxl-venv
/tmp/bs-openpyxl-venv/bin/pip install openpyxl
/tmp/bs-openpyxl-venv/bin/python scripts/balance_sheet_workbook.py verify --workbook /path/to/file.xlsx
```

## Classification

Read `references/schema.md` when classification or field interpretation is needed.

Default category sheets:
- `流动资产`: cash-like balances, wallet balances, provident fund.
- `投资资产`: securities, funds, brokerages, Alipay/WeChat wealth products, bank wealth products.
- `应收账款`: personal receivables from named borrowers.
- `负债`: loans, credit products, repayment principal/interest.

## Rules

- Preserve the main sheet unless the user explicitly asks to restructure it.
- Rebuild generated category sheets when splitting, rather than appending duplicate sheets.
- Keep formulas visible in the workbook and set recalculation-on-open when possible.
- For same-month merge/update tasks, treat receivable remaining as `表内应收金额 - 已还金额` when `待还金额` cells are blank or stale; treat liability as `已知待还合计` (`待归还本金 + 待归还利息` when no reliable total is present).
- After editing formulas with `openpyxl`, verify both formula cells and `data_only=True` cached totals when the result will be read by scripts.
- Skip Excel temporary lock files named like `~$*.xlsx`.
- For detail screenshots, use OCR (`tesseract` with `chi_sim+eng`) when available; if OCR is weak, visually inspect before moving/renaming.
- Screenshot names should be searchable and amount-first enough to scan, for example `民生贷款_剩余本金134328.96元_06月应还16997.35元.jpg`.
- When converting units, multiply only fields still marked as `W`/万元; do not multiply rows already in yuan, such as receivable ledger sheets or `累计利息/元`.
- Put uncertainty in cell comments or notes, especially missing interest from screenshots.
- Final response must include changed files, summary, verification, risks, and next step.
