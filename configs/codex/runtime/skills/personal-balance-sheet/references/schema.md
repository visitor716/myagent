# Personal Balance Sheet Schema

## Units

- Main workbook amounts are in `W` / 万元 unless a header explicitly says otherwise.
- Screenshot balances are usually in 元. Convert with `yuan / 10000`.
- For detail sheets copied from old templates that say `(K)`, update labels to `(W)` when the new workbook stores 万元.
- If the user asks to switch to actual amounts, convert only fields still labeled `W`/万元 to 元. Rows already labeled `元`, such as `累计利息/元` or receivable ledger entries, must not be multiplied again.

## Main Sheet Layout

Typical rows:

- Rows 2-4: liquid assets.
  - `B`: account name.
  - `C`: amount in 万元.
  - `J`: subtotal formula.
- Rows 5-12: investment assets.
  - `B`: account name.
  - `C`: amount in 万元.
  - `J5`: investment subtotal formula.
- Rows 13-18: receivables.
  - `B`: borrower.
  - `C`: amount in 万元.
  - `D`: date.
  - `E`: repaid amount when present.
  - `I`: notes.
  - `J13`: receivable subtotal formula.
- Rows 19-24: liabilities.
  - `B`: loan name.
  - `C`: original borrowed amount in 万元.
  - `D`: annual rate.
  - `E`: remaining principal in 万元.
  - `F`: known remaining interest in 万元.
  - `H`: known interest in 元 when available.
  - `I`: final/current repayment date.
  - `J19`: negative principal formula.
  - `J22`: negative interest formula.

## Classification Defaults

`流动资产`:
- 云闪付
- 微信余额
- 银行活期
- 公积金

`投资资产`:
- 东方证券
- 东方财富证券
- 长江证券
- 支付宝
- 微众银行理财
- 天天基金
- 老虎证券
- 长桥证券

`应收账款`:
- father
- 范斌哥
- 游丹
- 雄儿哥
- 彬儿

`负债`:
- 民生贷款
- 浦发贷款
- 招行贷款
- 有钱花
- 借呗

## Date Folder Organization

When organizing files under a `BalanceSheet` directory:

- `YYYYMM*.xlsx` -> `YYYY.M/`
- `YYYY*.xlsx` with no month -> `YYYY/`
- Move matching `:Zone.Identifier` sidecar files with their spreadsheet.
- Skip files that do not contain a recognizable date.
- Refuse to overwrite existing destination files.

Examples:

- `202603资产负债表.xlsx` -> `2026.3/`
- `202509资产负债表(1).xlsx` -> `2025.9/`
- `个人资产负债表_2025.xlsx` -> `2025/`

## Receivable Detail Workbook

Receivable exports may contain:

- `汇总`: one row per borrower.
- One sheet per borrower.

Ledger-style borrower sheets use actual yuan amounts and this structure:

| 时间 | 借/还 | 金额 | 剩余待还 |
| --- | --- | --- | --- |

Rules:

- Convert summary amounts in W to yuan when writing ledger rows.
- Keep ambiguous details in a `备注` row.
- If repayment date is unknown, leave the date blank on the repayment row.

## Detail Screenshot Organization

Screenshots under `YYYY.M/明细` should be grouped by platform/account:

- `有钱花`
- `借呗`
- `招行贷款`
- `民生贷款`
- `浦发贷款`
- `微众银行理财`
- `支付宝`
- `天天基金`
- `证券账户`
- `云闪付`

Classification hints:

- `民易贷` -> `民生贷款`
- `剩余待还本金` + 招商/招行 context -> `招行贷款`
- `2027/01/29` + `90,244.13` -> `浦发贷款`
- `先息后本` or `借呗` -> `借呗`
- `查账·还款`, `共4笔借款`, `有钱花` -> `有钱花`
- `东方证券`, `东方财富证券`, `长江证券` -> `证券账户`
- `余额查询`, `可用余额总计` -> `云闪付`
- `活期宝`, `投顾`, `银行黄金` -> `天天基金`
- `我的资产(元)`, `进阶资产`, `会员中心` -> `微众银行理财`
- `余额宝`, `稳健理财`, `指数+` -> `支付宝`

Readable screenshot filenames should include:

- platform/account name;
- the most important visible amount;
- context such as `剩余本金`, `应还`, `总资产`, `可用余额总计`, `利息`.

Examples:

- `有钱花_应还155067.91元_待还本金249932.58元.jpg`
- `民生贷款_剩余本金134328.96元_06月应还16997.35元.jpg`
- `证券账户_东方513800元_东财61994.48_长江11454.40.jpg`

## Screenshot Interpretation

Prefer direct labels:
- `剩余本金`, `剩余待还本金`, `待还本金` -> liability remaining principal.
- `利息`, `待还利息`, repayment-plan interest components -> known remaining interest.
- `应还` is a due amount, not necessarily total liability. Split into principal/interest if detail is shown.
- If a screenshot shows only a due amount and remaining principal, leave total remaining interest blank and add a note.

Do not fabricate data for missing accounts. Keep previous workbook values only when the user asks to update a subset and the existing value is the best available source.
