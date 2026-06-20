---
name: my-oa-timesheet-filler
description: Fill, verify, or delegate DR Laser OA 技术服务部-工时分配单 automation. Use when the user asks for 工时单, 工时分配单, 填这个月工时, 补填某天工时, verify OA timesheets, fill missing timesheets, or asks Hermes/another agent to fill OA work-hours forms.
---
> Trigger stats (myagent-trigger-stats): when this skill is used, run `python3 /home/zhanxp/projects/myagent/skills/scripts/record_skill_trigger.py my-oa-timesheet-filler` once near the start; if it fails, continue.

# OA Timesheet Filler

Use this skill for DR Laser OA `技术服务部-工时分配单`.

Always use `my-wsl-windows-chrome` first for browser work so OA keeps the Windows Chrome login state. Never open a fresh WSL/Linux browser profile, incognito window, guest window, or clear cookies/storage.

## Safety Rules

- Click `保存` only. Never click `提交`, `转发`, `转办`, or approval actions unless explicitly requested.
- Treat `this month` as the current month up to the current date; do not fill future dates.
- Skip the current day and previous day when the script reports the 24h overtime window and no submitted overtime form exists.
- Do not store or print transient OA query tokens such as `em_auth_code`, `_key`, cookies, or request tokens.
- For live operation, run a dry-run/verify pass first. Save only after the planned dates and values are clearly in range.

## Script

Canonical script path:

```bash
node /home/zhanxp/projects/myagent/skills/skills-local/oa-exception-record-filler/scripts/fill_oa_timesheets_via_cdp.cjs
```

The script remains under `oa-exception-record-filler` for compatibility, but 工时单 requests should use this skill as the workflow entry.

Useful modes:

```bash
# Read current forms and compare them with planned values; never save.
node /home/zhanxp/projects/myagent/skills/skills-local/oa-exception-record-filler/scripts/fill_oa_timesheets_via_cdp.cjs \
  --auto-from-list --since YYYY-MM-DD --until YYYY-MM-DD --today YYYY-MM-DD --scan-pages 5 --verify-only

# Save only dates whose current values do not match planned values.
node /home/zhanxp/projects/myagent/skills/skills-local/oa-exception-record-filler/scripts/fill_oa_timesheets_via_cdp.cjs \
  --auto-from-list --since YYYY-MM-DD --until YYYY-MM-DD --today YYYY-MM-DD --scan-pages 5 --fill-missing

# Fill explicit dates when auto list scanning is not needed.
node /home/zhanxp/projects/myagent/skills/skills-local/oa-exception-record-filler/scripts/fill_oa_timesheets_via_cdp.cjs \
  --overtime-entry YYYY-MM-DD:OVERTIME_HOURS
```

## Default Workflow

1. Record this skill trigger.
2. Check Windows Chrome CDP:

```bash
bash /home/zhanxp/projects/myagent/skills/skills-local/wsl-windows-chrome/scripts/attach_windows_logged_in_chrome.sh --status --json
```

3. Attach to OA list page if needed:

```bash
bash /home/zhanxp/projects/myagent/skills/skills-local/wsl-windows-chrome/scripts/attach_windows_logged_in_chrome.sh \
  --session oa-timesheet \
  --url 'http://oa.drlaser.com.cn:9000/spa/workflow/static/index.html#/main/workflow/listMine'
```

4. For `this month`, compute exact `--since`, `--until`, and `--today` from the current Asia/Shanghai date.
5. Run `--verify-only` first. Inspect JSON:
   - `verification.matches=true`: already correct.
   - `verification.needsFill=true`: needs saving.
   - `skipped`: report the reason; do not override skipped 24h-window dates.
6. Run `--fill-missing` to save only missing or mismatched forms.
7. Run `--verify-only` again and report:
   - filled dates
   - already-correct dates
   - skipped dates and reasons
   - any failures or manual follow-up

## Hermes Handoff

When the user explicitly asks to arrange Hermes, run Hermes with this skill plus browser access and keep the prompt bounded:

```bash
HERMES_ACCEPT_HOOKS=1 hermes chat \
  --skills my-oa-timesheet-filler \
  --skills my-wsl-windows-chrome \
  --toolsets terminal,browser,file \
  --accept-hooks --yolo --max-turns 80 \
  -q '<task prompt>'
```

Include in the prompt:

- Exact date range, such as `2026-06-01..2026-06-16`.
- Use `--verify-only` before saving.
- Use `--fill-missing`, not a broad overwrite, after verification.
- Save only; never submit.
- Stop and report if OA login, list scan, date range, or overtime source is uncertain.

## Known Recovery

- If scanning fails with `OA list page N is not available`, focus the list tab, return to page 1, and retry. The script also supports the OA quick-jump fallback.
- If a date is missing from auto scan, increase `--scan-pages` or fill explicit dates with `--overtime-entry`.
- If a form has no save button but already matches planned values, report it as already correct. If it does not match, stop and report it as read-only/submitted.
