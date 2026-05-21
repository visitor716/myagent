# OA Copy Data Generation

Use this reference when direct OA browser autofill is risky and the user asks to generate data they can copy manually, especially for the travel reimbursement module (`差旅报销`) and invoice-code/number module (`发票号码填写`).

## Required Inputs

- Latest OA reimbursement form PDF, preferably the root-level `费用报销单审批...pdf`.
- Current reimbursement evidence folders, especially `01-发票`, `03-交通行程`, `04-比价图`, and lodging/payment evidence.
- `company-reimbursement-manual.md` for required fields and compliance rules.
- OCR/text extraction for scanned or CMap-broken PDFs. Railway e-ticket PDFs may require image conversion plus OCR because `pdftotext` can miss Chinese text or invoice numbers.

If root-level final PDFs and `00-报销单/` draft PDFs both exist, use the root-level latest PDFs as the default source. Flag date/title differences between the source PDF and a live OA page for human confirmation instead of silently rewriting either side.

## Output Files

Write these files into the reimbursement directory:

- `OA复制填写数据-YYYYMMDD.md`: human-readable copy sheet with source files, base fields, travel rows, invoice rows, and warnings.
- `OA差旅报销模块-可复制.tsv`: tab-separated rows for pasting into spreadsheet-like OA grids.
- `OA发票号码模块-可复制.tsv`: tab-separated invoice number rows.
- Update or create `oa-fill-data-YYYYMMDD.json` with normalized `travel_rows`, `invoice_rows`, and `copy_notes`.

Use UTF-8 or UTF-8-SIG for TSV files so Chinese text opens cleanly on Windows.
Include `attachment`, `reason`, `bank_account`, and `currency` in `oa-fill-data-YYYYMMDD.json` when they can be extracted from the latest OA PDF. These fields let the browser-fill workflow fix missing live form content without re-OCR.

## Travel Module Fields

Use exactly these copy columns unless the current OA page shows a different order:

`序号`, `类型`, `起点`, `途径`, `终点`, `开始日期`, `结束日期`, `费用`, `同住人`, `备注`

Rules:

- The `费用` column is the reimbursable amount, not necessarily the full invoice face amount.
- If a route is capped by a comparison chart or Wuhan benchmark, use the capped/reimbursable amount and explain the cap in `备注`.
- If a trip segment is already reimbursed elsewhere or not claimed this time, keep the row if it exists on the OA form and set amount to `0.00` with a clear remark.
- For lodging, preserve roommate and payment-context remarks such as `酒店前台付款`; these remarks affect attachment checks.

## Invoice Number Module Fields

Recommended copy columns:

`序号`, `对应差旅行`, `票据类型`, `开票日期`, `发票代码建议填`, `发票号码`, `销售方/承运`, `购买方`, `金额`, `项目/路线`, `备注`

Rules:

- Do not swap invoice code and invoice number.
- For all-digital/electronic invoices and railway e-tickets that show only `发票号码`, first inspect the target OA page or latest OA form PDF to determine the invoice-code convention.
- If OA allows a blank invoice-code field, prefer blank over `无`. If the OA field or header says `无发票代码填写001`, use `001` and set the combined field to `001+发票号码`.
- If the target OA page is unknown and the output is only a prefill draft, set `发票代码建议填` to `无（待按OA页面规则确认）` instead of pretending it is final.
- Include every electronic invoice/e-ticket used as evidence even when its face amount is higher than the reimbursed amount due to benchmark capping.
- Include buyer title checks. The required buyer is `武汉帝尔激光科技股份有限公司` with taxpayer ID `91420100672784354A`.

## Copy Notes

Always include concise notes for:

- Travel module total and invoice face-amount total if they differ.
- Any benchmark/capping logic.
- Any invoice extra-print requirement: VAT special invoices and highway toll ordinary invoices whose project/item name contains `通行费`.
- Lodging order screenshot exceptions when OA lodging remarks clearly say `酒店前台付款`, `前台付款`, `到店付`, or equivalent.
