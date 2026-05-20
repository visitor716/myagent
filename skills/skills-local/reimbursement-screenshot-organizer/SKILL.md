---
name: reimbursement-screenshot-organizer
description: Organize and audit reimbursement/expense screenshots, PDFs, and downloaded email attachments by reading file content, extracting date, merchant, amount, document type, evidence type, invoice fields, and confidence, then safely renaming, classifying, and checking compliance for receipt, invoice, travel, payment, meal, lodging, purchase, express, reimbursement form, Didi invoice/itinerary, and 163 mail attachment files. Use when the user mentions 报销, 费用报销, 报销规范核对, 发票截图, 支付凭证, 票据整理, 滴滴发票, 行程单, 邮箱发票, receipt screenshots, PDF invoices, expense evidence, or asks Codex to rename/classify/check/download files in a reimbursement directory.
---

# Reimbursement Screenshot Organizer

## Overview

Use this skill to turn reimbursement screenshots, PDFs, and downloaded email attachments into auditable, consistently named files grouped by evidence type, then check whether the claim package matches the local reimbursement rules. The agent performs the visual/OCR judgment; the bundled script inventories files, unpacks email ZIPs, applies a reviewed rename/classification plan, and runs plan-level compliance checks without overwriting data.

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
   - evidence role, or multiple roles via `evidence_types`
   - confidence: `high`, `medium`, or `low`
   - extra print requirement, especially for special VAT invoices and highway toll ordinary invoices
   - notes for anything uncertain
6. Read `references/classification-rules.md` when deciding categories, filenames, or uncertainty handling.
7. Read `references/company-reimbursement-manual.md` when checking reimbursement policy, required attachments, timing, company invoice title, printing, and submission rules.
8. Read `references/email-intake.md` when the user asks to fetch invoices/itineraries from 163 mail, Didi invoice mail, or downloaded ZIP attachments.
9. Write a plan JSON file in the reimbursement directory, then dry-run it:

```bash
python3 ~/.codex/skills/reimbursement-screenshot-organizer/scripts/expense_organizer.py apply /path/to/报销目录/expense-plan.json
```

10. Run the compliance checker before moving files:

```bash
python3 ~/.codex/skills/reimbursement-screenshot-organizer/scripts/expense_organizer.py check /path/to/报销目录/expense-plan.json
```

11. If the dry-run and compliance result are clean enough, execute it:

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
      "confidence": "high",
      "notes": "金额和日期清晰"
    }
  ]
}
```

`source` must be relative to `root`. `category` may be English or Chinese; the script maps common aliases to the standard folders. `new_name` is optional; omit it unless a specific filename is needed.

For compliance checks, add `claim_id` to group files for the same expense and `evidence_type` to identify each attachment. Use `evidence_types` when one file has multiple roles, such as a railway e-ticket that is both invoice and itinerary. Supported evidence types include `invoice`, `itinerary`, `self_made_itinerary`, `payment_proof`, `order_screenshot`, `lodging_detail`, `warehouse_slip`, `reimbursement_cover`, and `expense_form`.

## Decision Rules

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
- Use `check` findings as warnings for missing evidence, timing risk, wrong invoice title, missing electronic invoice code/number, missing extra print copy, lodging amount mismatch, and unsupported/unclear reimbursement type.

## Output Contract

When finished, report:

- the root directory processed
- counts by category
- low-confidence or unreadable files
- files that require an extra printed copy
- compliance errors and warnings from the check command
- the manifest path written by the script
- whether files were moved or copied
