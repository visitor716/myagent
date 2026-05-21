# OA Browser Fill

Use this reference only when the user explicitly asks to fill an already logged-in OA reimbursement page. This workflow is for reducing manual entry errors; it must not submit or save the form unless the user explicitly asks for that separate action.

## Safety Rules

- Connect only to the user's existing authenticated browser session via the `wsl-windows-chrome` skill. Do not fall back to a fresh browser because it will not share login state.
- Fill only the current requested reimbursement form.
- **Save early, save often — but batch by section, not by row**: Click `保存` after each section (main fields, all travel rows at once, all invoice rows at once, attachment). Do NOT save after each individual detail row because the OA system reloads the page on save, and `addDetailRow`-created rows do not survive the reload — saving after a single row will discard all other pending rows.
- **Never click `提交`** or `转发` unless the user explicitly asks for that exact action after reviewing the page. These actions advance the workflow and may be irreversible.
- Prefer a probe-first workflow: attach, select the OA tab, inspect tables/fields, then fill.
- After filling, read the page state back from the DOM and report validation counts and totals.

## Incremental Save Workflow

The OA session can time out or the form can lose state. Save progressively after each milestone. The save button is `button:has-text("保 存")` in the top toolbar.

### Save Points (in order)

Save points are grouped by section rather than per-row. Per-row saves are unreliable because the OA system reloads the page after each save, and `addDetailRow`-created rows do not survive the reload — the page returns to the default row count, discarding any rows added via the API. Fill an entire section in a single `eval` call, then save.

| Step | When to save | What's been filled |
|------|-------------|-------------------|
| 1 | After all main form fields | 事由, 银行账号, 币种, 审核会计, 是否有电子发票 |
| 2 | After all travel rows filled + cleanup | All detail_1 rows, excess rows deleted |
| 3 | After all invoice rows filled + cleanup | All detail_5 rows, excess rows deleted |
| 4 | After attachment upload (if any) | File uploaded |
| 5 | After final validation passes | Everything verified |

### How to Save

Use Playwright to click the save button, then wait for the success toast to confirm:

```js
// Click save button
await page.locator('button:has-text("保 存")').click();
// Wait for success indication — the OA system shows a toast or the button re-enables
await page.waitForTimeout(2000);
```

After each save, verify the page did not navigate away and the form is still editable:

```js
() => {
  const saveBtn = document.querySelector('button');
  const btns = document.querySelectorAll('button');
  let saveAvailable = false;
  btns.forEach(b => { if (b.textContent.includes('保 存')) saveAvailable = true; });
  return { saveAvailable, url: window.location.href };
}
```

If the save fails (network error, session timeout), stop and report the error. Do not retry save more than twice.

### Save Implementation via page.evaluate

For save operations triggered from inside `eval`, dispatch a click on the save button:

```js
() => {
  const btns = document.querySelectorAll('button');
  for (const b of btns) {
    if (b.textContent.includes('保 存')) {
      b.click();
      return 'save-clicked';
    }
  }
  return 'save-button-not-found';
}
```

After each save milestone, continue to the next fill step without re-inspecting the entire form.

## Input Data

Use `oa-fill-data-YYYYMMDD.json` when available. Load it before re-reading screenshots/PDFs because it is the normalized, reviewed source for OA fields. It should contain:

- `travel_rows`: normalized rows with `type`, `start`, `via`, `end`, `start_date`, `end_date`, `amount`, `roommate`, and `remark`.
- `invoice_rows`: normalized rows with `invoice_code`, `invoice_number`, and optionally `combined_invoice_code_number`.
- base fields such as `reason`, `bank_account`, `currency`, `attachment`, `travel_total`, and `grand_total` when available.

If the JSON does not exist, generate it first from the current reimbursement directory and OA/copy-data references.

When multiple generated files exist, prefer the newest root-level OA reimbursement PDF and final attachment package. Files under `00-报销单/` may be older drafts; do not use them to overwrite the current live form without checking dates/titles.

## Missing-Content Triage

For requests like `当前表单有部分内容缺失，请优化`, first attach to the existing authenticated browser tab, then inspect the live page before writing:

```js
() => ({
  firstMissing: WfForm.getFirstRequiredEmptyField(),
  requiredOk: WfForm.verifyFormRequired(false, true),
  detail1Rows: WfForm.getDetailAllRowIndexStr("detail_1"),
  detail5Rows: WfForm.getDetailAllRowIndexStr("detail_5")
})
```

Use `WfForm.getLayoutStore().fieldAttrMap._data` to map field ids to labels. The `_data` map uses numeric field IDs as keys and stores MobX observable objects. Access field properties via `JSON.parse(JSON.stringify(data[id]))` to bypass non-enumerable getters:

```js
const store = WfForm.getLayoutStore();
const data = store.fieldAttrMap._data;
const fieldInfo = JSON.parse(JSON.stringify(data["10642"]));
// fieldInfo.fieldlabel → "审核会计"
// fieldInfo.fieldname → "shhj"
// fieldInfo.htmltype → 3 (browser)
// fieldInfo.viewattr → 3 (required+visible)
```

Be careful with table-level required fields: a required detail field with no row is not necessarily missing. Report only concrete row-level gaps such as `field6492_0` / `field6493_0` date cells.

Known Wuhan reimbursement main fields observed:

- `field6481`: 事由 (htmltype=2 textarea)
- `field6637`: 银行账号 (htmltype=1 text)
- `field10660`: 是否有电子发票 (htmltype=5 select); values: `0`=是, `1`=否
- `field10642`: 审核会计 (htmltype=3 browser); required person browser field
- `field11093`: 币种 (htmltype=3 browser); RMB has resolved as `{id: "1", name: "RMB"}`
- `field6485`: 附件上传 (htmltype=6 file)
- `field17348`: 所属项目 (htmltype=3 browser), usually non-required; ask before filling unless a project id/name is clear.
- `field6488`: internal field (labeled 职务stop), auto-populated, do not fill.

## OA Table Mapping Observed

The Wuhan expense form uses these detail tables. Field IDs and labels are sourced from `WfForm.getLayoutStore().fieldAttrMap._data` and `tableInfo`.

**Travel table (detail_1, formtable_main_36_dt1):**

| Field ID | Label | fieldname | htmltype | viewattr | Notes |
|----------|-------|-----------|----------|----------|-------|
| `field6489` | 类型 | `lx` | 5 (select) | 3 | values: 0=火车票, 1=飞机票, 2=汽车票, 4=住宿费, 5=交通费, ... |
| `field6490` | 交通工具 | `jtgj` | 5 (select) | 0 | hidden |
| `field6491` | 起点 | `qzd` | 1 (text) | 3 | |
| `field6492` | 开始日期 | `ksrq` | 3 (browser) | 3 | hidden input + `.wea-date-picker .text` |
| `field6493` | 结束日期 | `jsrq` | 3 (browser) | 3 | hidden input + `.wea-date-picker .text` |
| `field6494` | 费用 | `fy` | 1 (text) | 3 | decimal(38,2) |
| `field6495` | 备注 | `bz` | 1 (text) | 2 | |
| `field6789` | 途径 | `tj` | 1 (text) | 2 | |
| `field6790` | 终点 | `zd` | 1 (text) | 3 | |
| `field10405` | 同住人 | `tzr` | 3 (browser) | 2 | person browser; fill via `specialobj` or UI |
| `field13330` | 终端客户 | `zdkh` | 3 (browser) | 0 | hidden |

**Electronic invoice table (detail_5):**

| Field ID | Label | fieldname | htmltype | viewattr | Notes |
|----------|-------|-----------|----------|----------|-------|
| `field10403` | 电子发票代码 | | 1 (text) | 3 | Fill `001` when OA header says 无发票代码填写001 |
| `field10402` | 电子发票号码 | | 1 (text) | 3 | 20-digit electronic invoice number |
| `field10404` | 电子代码+电子发票号码 | | 1 (text) | 2 | auto-concatenated from code+number |
| `field10406` | 电子发票状态 | | | 2 | display text often starts as `核准中` |

Treat these field IDs as observed conventions, not guaranteed API. Always inspect the live table via `tableInfo["detail_1"].fieldinfomap` before filling.

## Fill Technique

- Prefer the form's own API for known fields after the live-page probe:

```js
WfForm.changeFieldValue("field6481", { value: data.reason });
WfForm.changeFieldValue("field6637", { value: data.bank_account });
WfForm.changeFieldValue("field10660", { value: "0" });  // 0=是, 1=否
WfForm.changeFieldValue("field11093", { value: "1", specialobj: [{ id: "1", name: "RMB" }] });
WfForm.changeFieldValue("field10642", { value: "马雪婷", specialobj: [{ id: "", name: "马雪婷" }] });
WfForm.changeFieldValue(`field6492_${i}`, { value: row.start_date });
WfForm.changeFieldValue(`field6493_${i}`, { value: row.end_date });
```

- For person browser fields (htmltype=3 browser), `WfForm.changeFieldValue` with `specialobj: [{id: "", name: "显示名"}]` sets the hidden value and display text. An empty `id` is accepted for initial fill but may not resolve the proper internal person ID. After setting, verify the `[id$=span]` element's `title` attribute shows the correct name, and that `WfForm.verifyFormRequired(false, true)` still passes.
- If the browser field display does not update after `changeFieldValue`, fall back to UI interaction: click the `[id$=span]` element to open the associative search dropdown, type the name, and click the matching result.
- For ordinary controlled text inputs, use Playwright's native `fill` first. If the value is duplicated or rejected, use click/select-all/backspace/type for that specific field.
- Ant Design select fields should be filled by opening the dropdown and clicking the exact visible option, such as `火车票`, `交通费`, or `住宿费`.
- Date widgets must update both the hidden input value and the visible `.wea-date-picker .text`; then dispatch `input`, `change`, and `blur`.
- Person browser fields should be selected through the search/modal UI when possible. For known already-resolved users, verify the hidden id and visible chip after selection. In the observed form, `汪毅德` resolved to hidden id `2361`.
- Electronic invoice rows may auto-concatenate. If direct `fill` duplicates the combined field, use the input element's own `value` setter and dispatch `input/change/blur`, then verify the final value.

## Detail Table Management

**Critical**: Fill all detail rows in a single `eval` call. The OA system reloads the page after each save, and rows added via `addDetailRow` do not persist across reloads — only server-committed (saved) rows survive. If you fill one row, save, then try to add a second row, the page reload will have discarded the first row. Always: cleanup excess rows, add needed rows, then fill ALL rows in one go before saving.

Before filling detail rows, clean up excess empty rows to match the expected row count:

```js
// Read current row count
const currentRows = WfForm.getDetailAllRowIndexStr("detail_1"); // e.g. "0,1,2,3,4,5,6,7,8,9"
const rows = currentRows.split(",").map(Number);
// Delete from highest index to lowest to avoid index shifting
for (let i = rows.length - 1; i >= targetCount; i--) {
  WfForm.delDetailRow("detail_1", String(i));
}
```

Fill detail rows using zero-based row indices:

```js
// Travel row (detail_1): type select values — 0=火车票, 4=住宿费, 5=交通费
WfForm.changeFieldValue("field6489_0", { value: "0" });  // type
WfForm.changeFieldValue("field6491_0", { value: "武汉" }); // start
WfForm.changeFieldValue("field6790_0", { value: "扬州" }); // end
WfForm.changeFieldValue("field6492_0", { value: "2026-01-14" }); // start date
WfForm.changeFieldValue("field6493_0", { value: "2026-01-14" }); // end date
WfForm.changeFieldValue("field6494_0", { value: "288.00" }); // amount
WfForm.changeFieldValue("field6495_0", { value: "G1549 二等座" }); // remark
// For 同住人 (lodging rows): browser field, use same specialobj technique
WfForm.changeFieldValue("field10405_2", { value: "张健健", specialobj: [{ id: "", name: "张健健" }] });

// Invoice row (detail_5)
WfForm.changeFieldValue("field10403_0", { value: "001" }); // invoice code
WfForm.changeFieldValue("field10402_0", { value: "26322000001425208951" }); // invoice number
// Combined field (field10404) auto-concatenates from code + number
```

- If the live invoice table has one blank extra row after the expected invoice rows, delete only when both code and number are empty:

```js
if (WfForm.getDetailRowCount("detail_5") > data.invoice_rows.length &&
    !WfForm.getFieldValue(`field10403_${data.invoice_rows.length}`) &&
    !WfForm.getFieldValue(`field10402_${data.invoice_rows.length}`)) {
  WfForm.delDetailRow("detail_5", String(data.invoice_rows.length));
}
```

## Attachment Upload

If `data.attachment` points to the final merged package, upload it through the existing file input:

```js
await page.locator('input[type=file]').first().setInputFiles(data.attachment);
```

Then verify `WfForm.getFieldValueObj("field6485")` contains the expected filename and a non-empty `filedatas` entry.

## Invoice Code Rules

- Inspect the live OA header before filling invoice codes.
- If the header says `无发票代码填写001`, fill invoice code as `001` for all-digital/electronic invoices and railway e-tickets with no visible traditional invoice code.
- Set `电子代码+电子发票号码` to `001 + 发票号码` in that case.
- Do not put the 20-digit invoice number in the invoice-code field.

## Validation Checklist

Before reporting completion:

- Travel row count matches expected rows.
- Travel sum equals the expected reimbursable total (`field6482` 差旅合计金额 matches sum of `field6494` values).
- Required travel fields are non-empty: type, start, end, start date, end date, amount, remark.
- Lodging rows have roommate hidden id and visible roommate text when a roommate is required.
- Invoice row count matches expected invoice rows.
- Each invoice row has code (`field10403`), 20-digit invoice number (`field10402`), and combined field (`field10404`) equal to code + number.
- `WfForm.getFirstRequiredEmptyField()` returns an empty string and `WfForm.verifyFormRequired(false, true)` returns `true`.
- Browser field display spans (`[id$=span]`) show the correct resolved names via `title` attribute or visible text.
- Uploaded attachment filename matches the final package in the reimbursement directory.
- No selection modal is still open.
- Save button has been clicked after each milestone; form is still editable and did not navigate away.
- Submit button was NOT clicked.
- Any unresolved non-required fields, such as `field17348` (所属项目), are listed as questions instead of guessed.

## Field Discovery Reference

When the live OA form has different field IDs than observed here, use this probe to discover main form fields:

```js
const store = WfForm.getLayoutStore();
const data = store.fieldAttrMap._data;
Object.keys(data).forEach(id => {
  try {
    const s = JSON.parse(JSON.stringify(data[id]));
    if (s && s.fieldlabel && s.isdetail === 0) {
      console.log(`field${id}: ${s.fieldlabel} (htmltype=${s.htmltype}, viewattr=${s.viewattr})`);
    }
  } catch(e) {}
});
```

For detail table fields, inspect `store.tableInfo["detail_1"].fieldinfomap` (travel) and `store.tableInfo["detail_5"].fieldinfomap` (invoice).
