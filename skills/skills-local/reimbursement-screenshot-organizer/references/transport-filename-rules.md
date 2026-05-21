# Transport Evidence Filename Rules

Use this reference when the user asks to simplify, normalize, or number filenames for transport evidence such as railway e-tickets, Didi itinerary PDFs, and comparison chart screenshots.

## General Workflow

1. Inventory the requested directory and limit renames to the evidence type the user named. Do not rename generated Word summaries such as `比价图汇总.docx` or `滴滴行程报销单合并.docx` unless the user explicitly asks.
2. Extract route, departure or pickup time, amount, and document type from the file content, not only from the old filename.
3. Sort by real travel start datetime, then add numeric prefixes before the date: `1_`, `2_`, `3_`.
4. Use Windows-safe time text. Do not put `:` in filenames; use `HHMM`.
5. Before renaming, verify the target path does not already exist. If files are already numbered, strip or stage old number prefixes before renumbering so numbers are not duplicated.
6. After renaming, list the directory and check that old unnormalized names are gone.

Useful extraction commands:

```bash
pdftotext -layout '/path/to/file.pdf' -
```

When `pdftotext` cannot read Chinese railway ticket fields because of font mapping errors, render and OCR:

```bash
tmp="$(mktemp -d)"
pdftoppm -png -r 220 '/path/to/ticket.pdf' "$tmp/page" >/dev/null
tesseract "$tmp/page-1.png" stdout -l chi_sim+eng --psm 6
rm -rf "$tmp"
```

## Railway E-Ticket PDFs

Use this for railway e-ticket PDFs in `01-发票`, including old filenames containing `发票_铁路电子客票`.

Filename format:

```text
N_YYYY-MM-DD_HHMM_火车票_起点-终点_金额.pdf
```

Rules:

- Use the passenger departure date and departure time printed on the ticket, not the invoice issue date.
- Replace verbose `发票_铁路电子客票` wording with `火车票`.
- Keep route and amount unchanged when already present and correct.
- Classify railway e-tickets as invoice evidence with itinerary value: `evidence_types: ["invoice", "itinerary"]`.

Example:

```text
1_2026-04-30_1150_火车票_扬州东-苏州园区_117.00.pdf
```

## Didi Itinerary PDFs

Use this for Didi trip reimbursement PDFs in `03-交通行程`.

Filename format:

```text
N_YYYY-MM-DD-HHMM_滴滴出行_金额.pdf
```

Rules:

- Use `pdftotext -layout` and read the `上车时间` rows.
- If one PDF contains multiple rides, sort and name the PDF by the earliest pickup datetime in that PDF.
- Use the `合计` amount from the PDF.
- Keep matching Didi invoice PDFs in `01-发票`; this rule is for itinerary PDFs only.

Example:

```text
1_2026-04-30-1053_滴滴出行_111.90.pdf
```

## Comparison Chart Screenshots

Use this for train comparison chart screenshots in a `比价图` directory.

Filename format:

```text
N_YYYY-MM-DD-HHMM_比价图_起点-终点_车次_金额.ext
```

Rules:

- Extract departure time, route, train number, selected seat class, and benchmark price from the screenshot.
- Use the ordinary/selected ticket price as `金额`; do not use package surcharge prices such as `携程全能保障`, `优享预订`, or hotel/coupon bundle amounts.
- If the screenshot lacks a date, infer the date from the matching ticket or reimbursement route context and mention the inference in the final summary.
- Store the same amount in `benchmark_price` when building a compliance plan, and write a `benchmark_note` such as `比价图：扬州东→武汉 G1549 二等座 ¥288`.

Example:

```text
1_2026-04-30-0830_比价图_扬州东-武汉_G1549_288.00.jpg
```
