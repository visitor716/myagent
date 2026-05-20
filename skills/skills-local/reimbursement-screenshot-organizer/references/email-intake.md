# Email Attachment Intake

Use this reference when the user asks to download reimbursement evidence from mail, especially 163 mail Didi invoice emails.

## 163 Mail With Windows Chrome

When the user needs authenticated mail access from WSL, use the local `wsl-windows-chrome` skill and attach to the Windows automation browser. Do not use a fresh WSL browser if authenticated state matters.

Typical attach command:

```bash
bash /home/zhanxp/projects/myagent/skills/skills-local/wsl-windows-chrome/scripts/attach_windows_logged_in_chrome.sh --session mail163 --url '<mail-url>'
```

If the page is not logged in, stop and ask the user to log in in the opened Windows Chrome window. After login, continue with the same `mail163` session.

## Didi Mail Search

For Didi invoices in 163 mail:

1. Search for `滴滴 发票 行程单`.
2. Use the current date as the target date. For example, on 2026-05-20, only process search results under `今日` whose timestamp is `2026年5月20日`.
3. Confirm sender is `didifapiao <didifapiao@mailgate.xiaojukeji.com>`.
4. Open each matching mail titled `滴滴出行电子发票及行程报销单`.
5. Confirm it has two attachments:
   - `滴滴出行行程报销单.pdf`
   - `滴滴电子发票.pdf`

## Download Strategy

Prefer the mail page's `打包下载` link. If Playwright's download event is canceled, fetch the same URL with the current browser cookies.

Get cookies from the attached browser:

```bash
playwright-cli -s=mail163 --raw run-code \
  "async page => (await page.context().cookies('https://mail.163.com')).map(c => c.name + '=' + c.value).join('; ')"
```

Use the `打包下载` href from the mail page. Save ZIPs under a temporary folder inside the reimbursement root:

```bash
mkdir -p /path/to/报销目录/00-下载临时
curl -L --fail --silent --show-error \
  -A 'Mozilla/5.0' \
  -e 'https://mail.163.com/' \
  -H "Cookie: $cookie" \
  "$readpack_url" \
  -o /path/to/报销目录/00-下载临时/didi-mail-1.zip
```

Do not leave duplicate ZIPs in the final evidence inventory. Clean the temporary folder after the PDFs have been moved into final category folders.

## ZIP Filename Encoding

163 Didi ZIPs may store Chinese filenames in GBK while Python initially displays CP437 mojibake. Use:

```bash
python3 ~/.codex/skills/reimbursement-screenshot-organizer/scripts/expense_organizer.py unpack /path/to/报销目录/00-下载临时
```

This creates `<zip-stem>-clean/` folders with readable filenames.

## Didi Parsing Rules

Use `pdftotext -layout` on the extracted PDFs when available.

Didi invoice PDF fields:

- `invoice_type`: `电子发票（普通发票）`
- `merchant`: seller name, commonly `滴滴出行科技有限公司` or `广州滴滴出行科技有限公司`
- `invoice_number`: value after `发票号码`
- `date`: value after `开票日期`
- `buyer_name`: must be `武汉帝尔激光科技股份有限公司`
- `taxpayer_id`: must be `91420100672784354A`
- `amount`: value after `（ 小 写 ）`
- `project_name`: usually `*运输服务*客运服务费`
- `evidence_type`: `invoice`
- `expense_kind`: `transport`

Didi itinerary PDF fields:

- `document_type`: `滴滴出行行程报销单`
- `merchant`: `滴滴出行`
- `amount`: `合计` amount
- `date`: application date if present, otherwise the trip date range start
- `evidence_type`: `itinerary`
- `expense_kind`: `transport`
- Use the same `claim_id` as the matching Didi invoice.

Recommended filenames:

```text
YYYY-MM-DD_发票_<销售方>_<金额>_滴滴电子发票.pdf
YYYY-MM-DD_交通行程_滴滴出行_<金额>_<城市或路线>行程报销单.pdf
```

For Didi ordinary passenger transport invoices, do not mark extra print unless the invoice is a special VAT invoice or a toll ordinary invoice with item/project name containing `通行费`.
