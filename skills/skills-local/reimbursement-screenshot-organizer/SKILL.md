---
name: reimbursement-screenshot-organizer
description: Organize and audit reimbursement/expense screenshots, PDFs, and downloaded email attachments by reading file content, extracting date, merchant, amount, document type, evidence type, invoice fields, and confidence, then safely renaming, classifying, checking compliance, simplifying/numbering train-ticket, Didi-itinerary, and comparison-chart filenames, cropping/merging itinerary PDFs into Word documents, merging comparison chart images into a single Word grid, generating copy-ready OA travel/detail invoice tables, and optionally browser-filling OA fields without saving/submitting. Use when the user mentions 报销, 费用报销, 报销规范核对, 发票截图, 支付凭证, 票据整理, 滴滴发票, 火车票命名, 铁路电子客票, 行程单, 行程单命名, 行程单合并, 行程单转 Word, 比价图, 比价图命名, 比价图合并, 邮箱发票, OA复制填写, OA自动填, 差旅报销模块, 发票号码填写, receipt screenshots, PDF invoices, expense evidence, or asks Codex to rename/classify/check/download/crop/merge files in a reimbursement directory.
---

# Reimbursement Screenshot Organizer

## Overview

Use this skill to turn reimbursement screenshots, PDFs, and downloaded email attachments into auditable, consistently named files grouped by evidence type, then check whether the claim package matches the local reimbursement rules. The agent performs the visual/OCR judgment; the bundled script inventories files, unpacks email ZIPs, crops itinerary PDFs into clean images, merges itinerary crops into Word, applies a reviewed rename/classification plan, and runs plan-level compliance checks without overwriting data.

## Workflow

1. Confirm the target directory from the user request or current context.
2. Inventory the directory:

```bash
python3 ~/.codex/skills/reimbursement-screenshot-organizer/scripts/expense_organizer.py inventory /path/to/报销目录
```

3. If evidence arrives as downloaded ZIP archives, unpack them first:

```bash
python3 ~/.codex/skills/reimbursement-screenshot-organizer/scripts/expense_organizer.py unpack /path/to/报销目录/00-下载临时
```

4. Inspect every image/PDF using available vision/OCR/text tools. For local files, open images directly or create a small batch review list from `expense-inventory.json`.
5. Extract these fields for each evidence file:
   - transaction date or invoice issue date
   - merchant/payee/issuer
   - amount
   - document type
   - invoice type and project/item name when visible
   - category
   - expense kind and claim id for grouping related files
   - evidence role, or multiple roles via `evidence_types`
   - confidence: `high`, `medium`, or `low`
   - extra print requirement, especially for special VAT invoices and highway toll ordinary invoices
   - comparison chart benchmark price and note when a 比价图 is available
   - OA detail-row remarks such as `oa_remarks`, especially lodging remarks like `酒店前台付款`
   - notes for anything uncertain
6. Read `references/classification-rules.md` when deciding categories, filenames, or uncertainty handling.
7. Read `references/transport-filename-rules.md` when the user asks to simplify, number, or normalize transport evidence filenames such as railway e-tickets, Didi itinerary PDFs, or comparison chart screenshots.
8. Read `references/company-reimbursement-manual.md` when checking reimbursement policy, required attachments, timing, company invoice title, printing, and submission rules.
9. Read `references/oa-copy-data.md` when the user asks to generate OA data for manual copying, especially the travel reimbursement module or invoice-code/number module. Prefer copy-ready TSV/Markdown output over direct OA browser autofill when the user mentions autofill risk. This step should also generate or update `oa-fill-data-YYYYMMDD.json` in the reimbursement directory as the normalized, reviewed source for both manual copy and browser autofill.
10. Read `references/oa-browser-fill.md` when the user asks to optimize, complete, or fill a logged-in OA reimbursement page, including phrases like `当前表单`, `内容缺失`, `OA自动填`, or `优化表单`. Before filling, load `oa-fill-data-YYYYMMDD.json` from the reimbursement directory if available. If it does not exist, first generate it from the current reimbursement evidence and OA/copy-data references per step 9, then proceed with filling. Fill the form incrementally: after each main section and each detail row, click `保存` to protect against data loss from session timeout. Validate every field after filling. Never click `提交` unless explicitly instructed.
11. Read `references/email-intake.md` when the user asks to fetch invoices/itineraries from 163 mail, Didi invoice mail, or downloaded ZIP attachments.
12. Read `references/itinerary-word.md` when the user asks to crop itinerary main content, merge itinerary PDFs, or create a Word document for printed travel evidence. Typical command:

```bash
python3 ~/.codex/skills/reimbursement-screenshot-organizer/scripts/expense_organizer.py merge-itineraries /path/to/报销目录/03-交通行程 -o /path/to/报销目录/03-交通行程/2026-05-20_滴滴行程报销单合并.docx
```

13. When the user has comparison images (比价图) that need to be placed into a single Word document:

```bash
python3 ~/.codex/skills/reimbursement-screenshot-organizer/scripts/expense_organizer.py merge-charts /path/to/比价图目录 -o /path/to/比价图目录/比价图汇总.docx
```

Adjust `--cols` (default 2), `--width` (default 8.5 cm), and `--title` as needed.

14. Write a plan JSON file in the reimbursement directory, then dry-run it:

```bash
python3 ~/.codex/skills/reimbursement-screenshot-organizer/scripts/expense_organizer.py apply /path/to/报销目录/expense-plan.json
```

15. Run the compliance checker before moving files:

```bash
python3 ~/.codex/skills/reimbursement-screenshot-organizer/scripts/expense_organizer.py check /path/to/报销目录/expense-plan.json
```

16. If the dry-run and compliance result are clean enough, execute it:

```bash
python3 ~/.codex/skills/reimbursement-screenshot-organizer/scripts/expense_organizer.py apply /path/to/报销目录/expense-plan.json --execute
```

## Plan JSON

Use this shape:

```json
{
  "root": "/path/to/报销目录",
  "items": [
    {
      "source": "IMG_001.png",
      "category": "invoice",
      "date": "2026-05-20",
      "merchant": "滴滴出行",
      "amount": "35.80",
      "document_type": "发票",
      "evidence_type": "invoice",
      "evidence_types": ["invoice"],
      "claim_id": "taxi-001",
      "expense_kind": "transport",
      "invoice_type": "增值税电子普通发票",
      "project_name": "通行费",
      "requires_extra_print": true,
      "print_note": "公路通行费普通发票，项目名称含通行费，报销需额外打印一份",
      "benchmark_price": "288.00",
      "benchmark_note": "比价图：扬州东→武汉 G1549 二等座 ¥288",
      "oa_remarks": "酒店前台付款",
      "confidence": "high",
      "notes": "金额和日期清晰"
    }
  ]
}
```

`source` must be relative to `root`. `category` may be English or Chinese; the script maps common aliases to the standard folders. `new_name` is optional; omit it unless a specific filename is needed.

For compliance checks, add `claim_id` to group files for the same expense and `evidence_type` to identify each attachment. Use `evidence_types` when one file has multiple roles, such as a railway e-ticket that is both invoice and itinerary. Supported evidence types include `invoice`, `itinerary`, `self_made_itinerary`, `payment_proof`, `order_screenshot`, `lodging_detail`, `warehouse_slip`, `reimbursement_cover`, and `expense_form`.

For comparison chart (比价图) price capping, set `benchmark_price` to the reference price from the comparison chart and `benchmark_note` to explain which comparison chart was used. When grouped by `claim_id`, the `check` command compares the claim group total against the smallest `benchmark_price` in the group and warns when the total exceeds the benchmark, showing the reimbursable amount and reduction.

## Decision Rules

- When a reimbursement directory already contains `oa-fill-data-YYYYMMDD.json`, `OA复制填写数据-YYYYMMDD.md`, or `报销核对报告-YYYYMMDD.md`, load those first and treat them as the preferred structured source. Re-OCR only when the structured data is missing or conflicts with the live OA page. When neither exists and browser autofill is requested, generate `oa-fill-data-YYYYMMDD.json` from the current reimbursement evidence before connecting to the OA page.
- If several reimbursement PDFs exist, prefer the root-level/latest generated OA reimbursement PDF and final attachment package over older copies under `00-报销单/`. If the live OA title/date differs from the latest PDF, report the mismatch instead of changing it silently.
- Use `01-发票` for official VAT/e-invoice/数电票 images even when a payment amount is also visible.
- Use `02-支付凭证` for WeChat, Alipay, bank, card, transfer, or reimbursement platform payment screenshots.
- Use `03-交通行程` for taxi, ride-hailing, train, flight, fuel, toll, parking, bus, or metro evidence.
- Use `04-住宿` for hotel invoices, hotel bills, and lodging platform orders.
- Use `05-餐饮` for restaurant, takeaway, coffee, and meal receipts.
- Use `06-办公采购` for office supplies, equipment, software, stationery, shipping, and work purchases.
- Use `07-其他票据` for valid reimbursement evidence that does not fit above.
- Use `99-待确认` when the amount, merchant, or document type is unreadable or the image is unrelated/duplicate.
- Keep duplicate-looking files separate unless they are byte-identical or the user explicitly asks to deduplicate.
- Prefer the date printed on the document. If only payment time is visible, use payment date. If no reliable date is visible, use `日期未知`.
- Mark `requires_extra_print: true` for VAT special invoices and for highway toll ordinary invoices whose project/item name contains `通行费`; include a concise `print_note`.
- For Didi invoice emails, keep the invoice PDF in `01-发票` and the Didi itinerary/reimbursement PDF in `03-交通行程`; group them with the same `claim_id`.
- Put low-confidence items in `99-待确认` and preserve the reason in `notes`.
- Use `check` findings as warnings for missing evidence, timing risk, wrong invoice title, missing electronic invoice code/number, missing extra print copy, lodging amount mismatch, benchmark price exceeded, and unsupported/unclear reimbursement type.
- When a comparison chart (比价图) is available, set `benchmark_price` on items. If a claim group total exceeds the benchmark, reimbursable amount is capped at the benchmark price. If a claim has no route matching any comparison chart, use the available comparison chart price for that trip direction.
- For lodging, require invoice, hotel front-desk detail bill, and payment/preorder proof. Require an online order screenshot only when the OA lodging row does not clearly say `酒店前台付款`, `前台付款`, `到店付`, or an equivalent front-desk/offline payment remark.
- Treat non-required OA fields such as `所属项目` as ask-before-fill unless a clear project id/name is present in the reimbursement materials.
- For electronic invoice codes on the OA form, inspect the live page header for `无发票代码填写001`. When present, use `001` as the invoice code for all-digital/electronic invoices and railway e-tickets. When the header is not yet visible, default to `001` and note that the user should verify.
- For OA browser autofill, click `保存` after each section (main fields, all travel rows at once, all invoice rows at once, attachments) — not per-row — because the OA page reloads on save and `addDetailRow`-created rows do not survive the reload. Never click `提交` unless explicitly instructed. If save fails, stop and report the error.

## Output Contract

When finished, report:

- the root directory processed
- counts by category
- low-confidence or unreadable files
- files that require an extra printed copy
- compliance errors and warnings from the check command
- the manifest path written by the script
- generated cropped itinerary image paths and Word document path, when requested
- generated comparison chart Word document path, when requested
- simplified/numbered transport evidence filenames, when requested
- generated OA copy-data Markdown/TSV/JSON paths, when requested
- OA browser-fill validation result, and whether save/submit was avoided, when requested
- any ask-before-fill items that remain unknown, such as project, date/title mismatch, or policy exceptions
- whether files were moved or copied
