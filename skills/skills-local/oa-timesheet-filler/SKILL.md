---
name: oa-timesheet-filler
description: Fill and save DR Laser OA technical service timesheet forms. Use when the user asks to fill OA 工时单, 技术服务部-工时分配单, daily work-hour allocation sheets, 出勤工时, 扬州晶澳工时, or says to fill/save the OA timesheet without submitting.
---

# OA Timesheet Filler

## Overview

Use this skill to fill DR Laser OA `技术服务部-工时分配单` forms through an already logged-in Windows browser. The default behavior is conservative: fill the requested sheet, click `保存`, verify the persisted values, and never click `提交`.

Always use the `wsl-windows-chrome` workflow first so the browser keeps Windows-side OA and Enterprise WeChat login state.

## Default Rules

- Target workflow: `技术服务部-工时分配单`.
- Default customer: `扬州晶澳`.
- Default `是否包含收费改造项目`: `否`.
- Default module in detail row 1: `运维模块`.
- Detail row 1 `时长` is `出勤小时 + 加班小时`.
- Leave blank unless the user explicitly provides values:
  - `加班小时`
  - `序列号`
  - `备注`
- Save only. Do not submit, forward, transfer, or approve.

## Attendance Rules

Use the form's `被分配日期`, not the page title date, to decide `出勤小时`.

For the provided 2026-05 attendance table:

- Rest days: `2026-05-01`, `2026-05-02`, `2026-05-03`, `2026-05-04`, `2026-05-05`, `2026-05-10`, `2026-05-16`, `2026-05-17`, `2026-05-24`, `2026-05-30`, `2026-05-31`.
- Work days: `2026-05-06` through `2026-05-09`, `2026-05-11` through `2026-05-15`, `2026-05-18` through `2026-05-23`, and `2026-05-25` through `2026-05-29`.
- Fill `出勤小时` as `8` on work days.
- Fill `出勤小时` as `0` on rest days.
- Fill detail row 1 `时长` as `出勤小时 + 加班小时`. Treat blank `加班小时` as `0`.

For other months, use the attendance table or instructions the user provides. If no table is available, fill weekdays as `8` and weekends/rest days as `0` only when the user explicitly identifies them as rest days.

## Browser Workflow

1. Attach to the existing Windows automation browser:

```bash
playwright-cli list
playwright-cli -s=<session> tab-list
```

Prefer an existing attached session such as `txdocs`. If no session exists, use `wsl-windows-chrome` helpers to attach to Windows Chrome over CDP. Do not open a fresh Linux browser for OA work.

2. If the supplied OA URL says `oauth_code已失效`, open OA without the expired one-time code:

```text
http://oa.drlaser.com.cn:9000/spa/workflow/static/index.html#/main/workflow/listMine
```

3. If OA displays `由于长时间未操作，系统自动退出，需要重新登录`, stop page actions and ask the user to scan the Enterprise WeChat QR code. Continue after the user says they are logged in.

4. On `我的请求`, open the requested `技术服务部-工时分配单` link. Match by title date when the user gave a date. For the daily generated sheet, the title date is usually one day after `被分配日期`.

5. Switch to the new form tab and verify:

- Page title contains `技术服务部-工时分配单`.
- `被分配日期` is the intended work date.
- Top buttons include `提 交` and `保 存`; only use `保 存`.

## Field Map

Observed on workflow `技术服务部-工时分配单`; verify IDs on the open page before relying on them:

| Field | ID |
| --- | --- |
| 被分配日期 | `field10961` |
| 终端客户 | `field10966` |
| 是否包含收费改造项目 | `field10972` |
| 出勤小时 | `field10964` |
| 加班小时 | `field10963` |
| 合计工时 | `field10965` |
| 明细合计 | `field10973` |
| 工号 | `field10979` |
| 明细模块 row 1 | `field10968_0` |
| 明细序列号 row 1 | `field10974_0` |
| 明细时长 row 1 | `field10971_0` |
| 明细备注 row 1 | `field11039_0` |

Use `window.WfForm` to verify values:

```js
window.WfForm.getFieldValue("field10964")
window.WfForm.getBrowserShowName("field10966")
window.WfForm.getSelectShowName("field10972")
window.WfForm.getSelectShowName("field10968_0")
```

## Fill Steps

1. Select `终端客户`.
   - Click the search button in the `终端客户` browser field.
   - Search `扬州晶澳`.
   - Select the row `扬州晶澳 / 杨昌平 / 罗威`.
   - Click `确 定`.
   - Verify `WfForm.getBrowserShowName("field10966") === "扬州晶澳"`.

2. Select `是否包含收费改造项目 = 否`.
   - Click the dropdown and choose `否`.
   - Verify `WfForm.getSelectShowName("field10972") === "否"`.

3. Fill `出勤小时`.
   - Use `8` only when the assigned date is a work day under the active attendance rules.
   - Use `0` when the assigned date is a rest day.
   - Fill `加班小时` only when the user provides it.
   - Verify `合计工时` updates to `出勤小时 + 加班小时`.

4. Select detail row 1 module.
   - Click row 1 `模块` dropdown.
   - Choose `运维模块`.
   - Verify `WfForm.getSelectShowName("field10968_0") === "运维模块"`.
   - Fill row 1 `时长` as `出勤小时 + 加班小时`.
   - Leave `序列号` and `备注` blank unless the user explicitly provides values.

5. Verify before saving:

```js
({
  assignedDate: WfForm.getFieldValue("field10961"),
  customer: WfForm.getBrowserShowName("field10966"),
  paidTransform: WfForm.getSelectShowName("field10972"),
  attendance: WfForm.getFieldValue("field10964"),
  overtime: WfForm.getFieldValue("field10963"),
  total: WfForm.getFieldValue("field10965"),
  module: WfForm.getSelectShowName("field10968_0"),
  serial: WfForm.getBrowserShowName("field10974_0"),
  duration: WfForm.getFieldValue("field10971_0"),
  remark: WfForm.getFieldValue("field11039_0")
})
```

6. Click only `保 存`.
   - The page may refresh; an automation command can report `Execution context was destroyed` during navigation. Treat that as normal only if the current tab remains on the same `requestid`.
   - After refresh, read the fields again and report the saved values.

## Safety Rules

- Never click `提 交`.
- Never fill `加班小时`, `序列号`, or `备注` unless the user explicitly provides values.
- Always fill row 1 `时长` as `出勤小时 + 加班小时`; use `0` for blank components.
- Do not expose `em_auth_code`, `_key`, cookies, request tokens, or session IDs in final summaries.
- If a modal appears after save, inspect it before clicking anything. Confirm it is a save confirmation, not a submit confirmation.
