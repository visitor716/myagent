---
name: my-tg-gateway-manager
description: Single entry point for tg-agent-gateway release, runtime recovery, WebApp URL/tunnel monitoring, worktree review/merge/runner-isolation acceptance, and Telegram bot input-flow implementation. Use when the user mentions tg-agent-gateway, TG gateway, /app, /webapp, latest app, Telegram menu recovery, WebApp blank/loading, TG_WEBAPP_URL, trycloudflare tunnel drift, worker worktree review/merge/acceptance, runner cwd/effectiveWorkspace/worktreePath, or Telegram multi-step input/task completion flows.
---

# My TG Gateway Manager

Use this skill as the only active `tg-agent-gateway` workflow entry. Work from:

```text
/home/zhanxp/projects/tg-agent-gateway
```

unless the user gives a different checkout or worktree.

## Boundaries

- Inspect live evidence before editing code.
- Keep `.env`, tokens, logs, `data/bots.json`, and unrelated dirty work safe unless the task explicitly requires touching them.
- Do not commit, push, merge, or restart runtime paths unless the user asked for that operation or the recovery task needs a reversible local restart.
- For browser proof, use `wsl-windows-chrome` and the dedicated Windows Chrome profile; do not use browser MCP.
- Prefer project scripts and bundled scripts over ad hoc shell.

## Router

Choose one lane, then read the matching reference only when needed:

| Intent | Lane | Reference |
| --- | --- | --- |
| Send/fix `/app`, `/webapp`, `/latest_app`, release version, deploy time, update notes, fresh WebApp button | App release | `references/app-release.md` |
| Telegram menu does nothing, mobile WebApp blank/loading, stale button, callback drift, polling/proxy/tunnel incident | Runtime recovery | `references/runtime-recovery.md` |
| `TG_WEBAPP_URL`, quick tunnel, public URL health, auto-rotation, monitor status | URL monitor | `references/runtime-recovery.md` |
| Review worker/candidate branches, decide whether work can enter `master` | Worktree review | `references/review-gate.md` |
| Merge accepted worker work into `master`, restart, `/app`, push/sync/cleanup | Worktree merge | `references/merge-master.md` |
| Implement/repair runner cwd isolation, `useWorktree`, `effectiveWorkspace`, `worktreePath` | Runner isolation | `references/runner-isolation.md` |
| Prove real runner task cwd/pwd is in a worktree | Worktree acceptance | `references/execution-acceptance.md` |
| Convert button-only Telegram UX into tap -> prompt -> next message acts, or add Running/completion reports | Telegram input flow | `references/telegram-input-flow.md` |

Start most runtime incidents with:

```bash
cd /home/zhanxp/projects/tg-agent-gateway
bash /home/zhanxp/projects/myagent/skills/skills-local/my-tg-gateway-manager/scripts/check-runtime.sh
git status --short
```

## Bundled Scripts

Runtime:

```bash
bash /home/zhanxp/projects/myagent/skills/skills-local/my-tg-gateway-manager/scripts/check-runtime.sh
```

Worktree workflows:

```bash
bash /home/zhanxp/projects/myagent/skills/skills-local/my-tg-gateway-manager/scripts/audit_worker_refs.sh
bash /home/zhanxp/projects/myagent/skills/skills-local/my-tg-gateway-manager/scripts/audit_dirty_worktrees.sh
bash /home/zhanxp/projects/myagent/skills/skills-local/my-tg-gateway-manager/scripts/merge_ready_worktrees.sh --dry-run
bash /home/zhanxp/projects/myagent/skills/skills-local/my-tg-gateway-manager/scripts/collect_worktree_evidence.sh --project /home/zhanxp/projects/tg-agent-gateway --worker cc3
```

Use `--probe` on `collect_worktree_evidence.sh` only when a temporary create/delete isolation check is acceptable, and remove the probe file before reporting.

Runner isolation templates live in:

```text
assets/runner-isolation/
```

## Verification

Use the narrow proof required by the selected lane. Common checks:

```bash
npm run type-check
npm run build
npm run test:unit
```

For runtime recovery or App release, also verify local health, current public URL health, and Telegram API result when a live button is sent.

## Reporting

Final reports should include:

- selected lane and result
- changed files, if any
- exact verification commands and pass/fail outcome
- runtime evidence for recovery tasks, including relevant health probes or log lines
- remaining risks, especially stale Telegram WebView cache, quick tunnel reachability, missing recent task logs, or untested live bot paths
