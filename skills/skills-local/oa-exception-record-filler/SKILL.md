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

Historical example fields (not universal defaults; current customer configuration takes precedence):

| Field | Value |
| --- | --- |
| 机型 | `量产机` |
| 项目归属 | `TCSE` |
| 业务分类 | `运维` |
| 工序 | `激光1` |
| 光路 | `光路1` |
| 复核人 | `罗威` |

Historical customer-specific serial examples (never reuse across customer bases):

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

If the active customer machine library has no reliable match, stop that row and ask for the missing serial; do not guess from these historical examples.

## 实际操作前置与恢复

- 先只读检查 aTrust VPN 登录状态，再访问 OA。可使用 OA 项目的 `atrust_vpn_keeper.ps1 -Action login-state`；只有确需登录且已有授权时才登录。安全桌面锁定时等待用户解锁；状态 Unknown 不等于未登录，不反复发送凭据。
- OA 空白、持续加载或 HTTP 502 时，先分辨 VPN、登录与 OA 服务问题，做有限重试；无法恢复时停止并说明，不把模拟结果当成功。
- 浏览器操作先用 `wsl-windows-chrome`，复用已登录的专用 Windows 浏览器和当前任务标签页，不切换 Profile、不清 Cookie、不关闭其他页面。
- 企业微信登录失效时仅刷新登录页面或二维码。截取当前有效二维码，检查截图后发给用户；只截目标页面，避开其他桌面窗口。截图文件使用可下载的英文文件名；不得记录二维码、凭据或带鉴权参数的 URL 到 Git/长期记录。
- 手机扫码后还需检查电脑端二维码页面：若出现企业微信登录的「确认」或「确认登录」按钮，核对确为当前登录流程后点击，等待跳转，并验证已进入企业微信/OA。不能仅因手机扫码成功就认定网页登录完成；未出现按钮时不盲点。此处仅允许登录确认，不代表授权点击 OA 表单提交或其他业务确认。
- 扫码完成后重新核对当前标签页和表单身份，不直接重复新建。

## 字段联动与可靠保存

- 从当前运行配置确认客户基地、记录人和复核人，从该基地机台库核对设备编号；历史表格和浏览字段 raw ID 仅供定位，不能当作跨客户通用映射。
- 新建前检查是否存在本次草稿；填写前核对 workflow、requestid、日期及明细原文，禁止修改其他日期或已归档记录。
- 标题实际字段曾验证为 `field-1`；`requestname` 返回空不能证明标题为空。以当前页面 DOM 和 API 回读确认字段，不盲目重填。
- 浏览字段按依赖顺序分批填写，待联动稳定后回读：设备/客户 → 项目/业务分类 → 异常类型 → 关键字。不要把一次 `changeFieldValue` 返回成功当作最终字段值。
- 设备选择会自动改写现场编号。核对用户原文、机台库与 OA 联动结果；关联可靠且只是现场标签不符时，仅修正本条草稿现场编号后再回读；设备归属无法确认时停止，不猜编号、不改机台库。
- 身份保护检查失败时先读取当前 requestid、日期、原文及字段，判断异步联动或导航；禁止盲目重跑整段填充、清空表单或重复保存。
- 保存前逐项回读标题、日期、设备显示编号及 raw ID、现场编号、客户、分类、完整调试过程与耗时；未给耗时必须留空，不能为了校验通过编造。
- 只点击规范化文本严格等于「保存」且唯一的按钮；遇弹窗先检查含义，绝不点击提交、审批或流转。
- 保存后取得真实 requestid，重新加载或打开同一单据，回读日期、机台、客户、原文及空耗时，核对仍在创建节点且未流转。toast、可提交按钮或前端字段值本身不能证明持久化成功。
- 最终简报实际保存结果、日期、机台、单据 ID、耗时状态与「未提交」；若未回读成功，明确说明未确认保存，避免重复创建。

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
