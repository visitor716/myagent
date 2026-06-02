---
name: oa-exception-record-filler
description: Fill and save DR Laser OA 新建异常记录 forms from TCP daily report text. Use when the user asks to add 日报内容 into OA 异常记录表, 新建异常记录, 5.xx 异常记录, or says to save OA exception records without submitting.
---

# OA Exception Record Filler

Use this skill for DR Laser OA `新建异常记录` forms. It turns pasted TCP 日报 entries into OA 异常明细 data, fills the logged-in OA form when requested, clicks `保存`, and never clicks `提交`.

Always use `wsl-windows-chrome` first for browser work so OA keeps the Windows Chrome login state. Do not open a fresh Linux/browser profile.

## Default Rules

- Target workflow: `新建异常记录`.
- Use the report date as the target OA table/form date, such as `2026/5/29 -> 5.29` and form field `2026-05-29`.
- One pasted日报 usually becomes one OA 明细 row; put the full日报 content into `调试过程`.
- `耗时（h）` stays blank unless the user explicitly gives a value.
- Click `保存` only. Never click `提交`, `转发`, `转办`, or approval actions unless explicitly requested.
- Treat `em_auth_code`, `_key`, cookies, and request tokens as transient; do not store or print them.

## Prepare Fill Data

Generate a fill plan from pasted日报:

```bash
python3 ~/.codex/skills/oa-exception-record-filler/scripts/oa_exception_records.py \
  --date 2026/5/29 <<'EOF'
1、13A相机频繁报警调整，检查发现进料模组皮带尺寸偏短，联系设备更换后恢复
2、10B1更换激光器，调整基础光路及扩束镜，调整DOE后光斑形貌OK
3、8A出料舌头缩回感应信号异常，调整气压大小及缩回感应器位置后观察跑片正常
EOF
```

Use `--format json` for browser automation or exact field review.

## OA Values

Default fixed fields:

| Field | Value |
| --- | --- |
| 机型 | `量产机` |
| 项目归属 | `TCSE` |
| 业务分类 | `运维` |
| 工序 | `激光1` |
| 光路 | `光路1` |
| 复核人 | `罗威` |

Device serial mapping by machine number:

| 机台数字 | 搜索编号 | Observed OA display |
| --- | --- | --- |
| 1 | `4643` | device serial containing `4643` |
| 2 | `4642` | device serial containing `4642` |
| 3 | `4645` | device serial containing `4645` |
| 4 | `4644` | device serial containing `4644` |
| 5 | `4660` | device serial containing `4660` |
| 6 | `4646` | device serial containing `4646` |
| 7 | `4656` | device serial containing `4656` |
| 8 | `4657` | device serial containing `4657` |
| 9 | `4658` | device serial containing `4658` |
| 10 | `4659` | `202310134659` |
| 11 | `4666` | device serial containing `4666` |
| 12 | `4661` | device serial containing `4661` |
| 13 | `5655` | device serial containing `5655` |

When multiple machines appear in one日报, choose one mappable machine. The script defaults to stable-random selection so repeated runs choose the same machine for the same date/content. Use `--machine-choice first` for deterministic first-machine selection.

Current serial list does not include machine `14`; if a日报 item uses `14A/14B`, stop that row and ask for the missing serial.

## Browser Workflow

1. Attach to the existing Windows automation browser:

```bash
bash ~/.codex/skills/wsl-windows-chrome/scripts/attach_windows_logged_in_chrome.sh \
  --session oa-exception \
  --url 'http://oa.drlaser.com.cn:9000/spa/workflow/static/index.html#/main/workflow/listMine'
```

2. Prefer an already-open `新建异常记录-詹香平-YYYY-MM-DD` tab for the target date. If several OA tabs exist, scan all tabs before assuming login is missing.

3. Verify before filling:

```js
WfForm.getFieldValue("field13666") // target date, e.g. 2026-05-29
WfForm.getDetailAllRowIndexStr("detail_1")
```

4. Fill the detail row. Observed field IDs on `新建异常记录`:

| Field | ID |
| --- | --- |
| 填报日期 | `field13666` |
| 设备出厂编号 row 1 | `field13654_0` |
| 现场编号 row 1 | `field13655_0` |
| 客户 row 1 | `field13656_0` |
| 机型 row 1 | `field13657_0` |
| 项目归属 row 1 | `field13938_0` |
| 业务分类 row 1 | `field13939_0` |
| 工序 row 1 | `field13667_0` |
| 光路 row 1 | `field13668_0` |
| 异常类型 row 1 | `field13940_0` |
| 异常关键字 row 1 | `field13941_0` |
| 调试过程 row 1 | `field13661_0` |
| 耗时 row 1 | `field13662_0` |
| 复核人 row 1 | `field13805_0` |

Observed stable values from a 2026-05-29 fill:

| Field | Value |
| --- | --- |
| 设备出厂编号 `10B1 -> 4659` | display `202310134659`, value `10436` |
| 客户 `扬州晶澳` | value `823` |
| 机型 `量产机` | value `0` |
| 项目归属 `TCSE` | value `2` |
| 业务分类 `运维` | value `2` |
| 工序 `激光1` | value `0` |
| 光路 `光路1` | value `0` |
| 异常类型 `TCSE-运维-光斑` | value `390` |
| 异常关键字 `光斑-光斑漏洞` | value `1739` |
| 复核人 `罗威` | value `243` |

5. Save and verify:

- Click only the `保 存` button.
- The page may refresh. Verify the same `requestid`/title/date remains open and `调试过程` was read back.
- `WfForm.verifyFormRequired(false, true)` may remain false when `耗时` is blank; that is expected when the user asked to leave耗时 empty.

## Safety Rules

- Never click `提 交`.
- Never fill `耗时` unless the user explicitly gives it.
- Do not overwrite an existing row until the target date and current row contents are verified.
- If a modal appears after save, inspect it before clicking anything. Confirm it is a save confirmation, not a submit confirmation.

## Legacy Timesheet Helper

The old OA 工时单 automation script remains at `scripts/fill_oa_timesheets_via_cdp.cjs` for compatibility. Prefer this skill only for 异常记录 work; if the user asks for 工时单 specifically, use the script by path and preserve the same save-not-submit rule.
