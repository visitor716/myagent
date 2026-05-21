# Reimbursement Screenshot Classification Rules

## Category Aliases

Use these normalized categories in the plan JSON when possible:

| Category | Folder | Use for |
| --- | --- | --- |
| `invoice` | `01-发票` | 增值税电子普通发票、专用发票、数电票、PDF/图片发票页面 |
| `payment` | `02-支付凭证` | 微信支付、支付宝、银行卡、转账、收款、付款成功截图 |
| `transport` | `03-交通行程` | 滴滴/高德/出租车、火车票、机票、停车、过路费、加油、公交地铁 |
| `lodging` | `04-住宿` | 酒店发票、酒店水单、住宿平台订单 |
| `meal` | `05-餐饮` | 餐厅、小票、外卖、咖啡、商务餐 |
| `purchase` | `06-办公采购` | 办公用品、设备、耗材、软件、快递、资料打印 |
| `other` | `07-其他票据` | 可报销但不属于以上分类的凭证 |
| `uncertain` | `99-待确认` | 信息缺失、截图模糊、重复待判、非报销图片 |

`快递费` can stay in `purchase`/`办公采购` unless the user wants a separate express folder. In the compliance plan, distinguish it with `expense_kind: "express"` and `fee_type` such as `修理费`, `办公费`, or `差旅快递费`.

## Field Extraction Priority

1. `date`: invoice issue date, ticket date, order date, then payment date.
2. `merchant`: seller name, payee name, platform merchant, issuer, then app/platform name.
3. `amount`: total amount, paid amount, fare, room fee, then visible subtotal.
4. `document_type`: concise Chinese type such as `发票`, `付款截图`, `打车行程`, `酒店订单`, `餐饮小票`.
5. `invoice_type`: invoice title/type when visible, such as `增值税电子普通发票`, `增值税专用发票`, `公路通行费普通发票`.
6. `project_name`: visible invoice item/project name when present, such as `通行费`.
7. `evidence_type`: attachment role for compliance checks. Use `invoice`, `itinerary`, `self_made_itinerary`, `payment_proof`, `order_screenshot`, `lodging_detail`, `warehouse_slip`, `reimbursement_cover`, or `expense_form`. Use `evidence_types` when one file has multiple roles.
8. `claim_id`: same value for files that belong to one expense/transaction.
9. `expense_kind`: one of `transport`, `lodging`, `purchase`, `express`, `meal`, `other`.
10. `oa_remarks`: OA reimbursement detail-row remarks when visible. For lodging, preserve phrases such as `酒店前台付款`, `前台付款`, `到店付`, or `现场付款`; these phrases explain why an online order screenshot may be absent.
11. `confidence`:
   - `high`: date, merchant, amount, and type are readable.
   - `medium`: one non-critical field is inferred from context.
   - `low`: key fields are missing, ambiguous, or unreadable.

## Extra Print Requirements

Set `requires_extra_print: true` and include `print_note` for:

- 增值税专用发票/专票.
- 公路通行费普通发票 where the project/item name contains `通行费`.

Recommended note for the toll rule:

```text
公路通行费普通发票，项目名称含通行费，报销需额外打印一份
```

If the screenshot clearly shows `通行费` but the invoice type is unclear, set confidence to `medium` or `low` and mention the uncertainty in `notes`.

## Filename Guidance

Default generated filename shape:

```text
YYYY-MM-DD_分类_商户_金额_类型.ext
```

Examples:

```text
2026-05-20_发票_滴滴出行_35.80_发票.png
2026-05-20_支付凭证_微信支付_35.80_付款截图.jpg
2026-05-20_发票_滴滴出行科技有限公司_111.90_滴滴电子发票.pdf
2026-05-20_交通行程_滴滴出行_111.90_扬州行程报销单.pdf
日期未知_待确认_商户未知_金额未知_截图.png
```

Use short names. Avoid adding invoice codes, order IDs, or long descriptions unless they are necessary to distinguish multiple files with the same date, merchant, and amount. The script adds numeric suffixes when a destination filename already exists.

For transport post-processing requests such as numbering railway e-tickets, Didi itinerary PDFs, or comparison chart screenshots by travel time, use `references/transport-filename-rules.md` instead of the generic filename shape above.

## Ambiguity Handling

- If one image contains both an invoice and a payment confirmation, classify by the dominant reimbursement evidence. Official invoice wins over payment screenshot.
- If two screenshots appear to represent the same transaction but one is an invoice and one is payment evidence, keep both and classify separately.
- If a screenshot is a cropped detail of another screenshot, keep both unless byte-identical duplicate detection proves it is the same file.
- If the user supplied a category policy that differs from this reference, follow the user's policy and note it in the final summary.
- For toll ordinary invoices, classify the file as `invoice` because the official invoice is the primary reimbursement evidence; use the print reminder rather than moving it to a separate category.
- For railway e-ticket PDFs, classify as `invoice` and set `evidence_types: ["invoice", "itinerary"]` because the file contains both invoice and travel evidence.
- For Didi invoice mail, classify `滴滴电子发票.pdf` as `invoice` and `滴滴出行行程报销单.pdf` as `transport`; assign both files the same `claim_id`.
- For modern all-digital/electronic invoices that visibly provide only a `发票号码`, set `invoice_number` and put `invoice_code` as `无（票面仅显示发票号码）` rather than leaving it blank.

## Comparison Chart Benchmark

When a comparison chart (比价图) shows a reference price for a trip route, use it as the reimbursement cap:

- Set `benchmark_price` to the comparison chart reference price, e.g. `"288.00"`.
- Set `benchmark_note` to describe which comparison chart and route was used.
- When multiple items share a `claim_id`, the `check` command finds the smallest `benchmark_price` in the group and compares the claim total against it.
- If the claim total exceeds the benchmark, the `check` command reports the reimbursable amount (capped at benchmark) and the reduction.
- If a claim has no route matching any comparison chart, use the available comparison chart price for the same trip direction (outbound/return) as the benchmark.
