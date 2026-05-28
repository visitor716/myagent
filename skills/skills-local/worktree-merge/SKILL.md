---
name: worktree-merge
description: Safely merge, audit, synchronize, push, and clean up tg-agent-gateway worker worktrees, worker branches, stale remote refs, and completed worker tmux sessions. Use when the user asks to merge ready worktrees, batch merge worker branches, sync cc/cx workers to master, push worker refs, inspect which cc2-cc8 worktrees are dirty/active/behind/diverged, delete obsolete historical remote branches, close completed worker tmux windows, or answer whether active worker branches are current.
---

# Worktree Merge

Use this skill for `tg-agent-gateway` multi-worktree integration and worker-branch hygiene. It has four common lanes:

- **Merge lane**: merge ready worker commits into `master`.
- **Accepted patch lane**: finish a reviewed worker diff that Codex already applied into the main checkout, but that has not yet been committed or used to dispose of the worker branch.
- **Sync lane**: after `master` is accepted, align active worker/planner/reviewer branches to the latest `master` and push safe refs.
- **Cleanup lane**: after accepted work is synced, remove obsolete historical remote refs and close completed worker tmux sessions.

For merge/push/sync requests that finish accepted Claude worker work, do not
leave the completed `claude-cc*` tmux session open. After refs are verified,
run the completed-worker tmux cleanup for the affected `cc*` workers before the
final answer, unless the user explicitly asks to keep the worker window.

User standing preference for `/home/zhanxp/projects/tg-agent-gateway`: when the
user says `merge` for accepted worker work, treat it as approval to continue the
full post-merge lane without waiting for separate `sync master` or `push`
messages. After a successful merge into `master`, automatically:

1. Run final verification in `master`.
2. Fast-forward clean active worker/planner/reviewer branches to `master`.
3. Build/restart the local gateway/WebApp when runtime code or frontend assets
   changed.
4. Push `master` and the active branch set with ordinary fast-forward push.
5. Fetch/prune and audit that local/remote counts are `0 0`.
6. Close completed accepted Claude worker tmux sessions.

This standing preference does not permit force push, branch deletion, resetting
dirty worktrees, overwriting user work, or pushing refs that diverged remotely.
If any post-merge step is blocked by dirty state, conflicts, failed
verification, or non-fast-forward remote refs, stop and report the blocker with
the already-completed steps.

## Quick Start

Always preview first:

```bash
bash /home/zhanxp/projects/myagent/skills/skills-local/worktree-merge/scripts/merge_ready_worktrees.sh --dry-run
```

For a read-only branch/worktree audit:

```bash
bash /home/zhanxp/projects/myagent/skills/skills-local/worktree-merge/scripts/audit_worker_refs.sh
```

Apply only after reading the dry-run report:

```bash
bash /home/zhanxp/projects/myagent/skills/skills-local/worktree-merge/scripts/merge_ready_worktrees.sh --apply
```

The default target repo is:

```text
/home/zhanxp/projects/tg-agent-gateway
```

Default worker scan order:

```text
cc2 cc3 cc4 cc5 cc6 cc7 cc8
```

Default active branch set for sync/audit:

```text
master wt/cc1 wt/cc2 wt/cc3 wt/cc4 wt/cc5 wt/cc6 wt/cc7 wt/cc8 wt/cx1 wt/cx2
```

## Safety Rules

The script only marks a worker ready when:

- the worktree exists and is a Git worktree
- the worktree has no uncommitted changes
- no local process has cwd inside the worktree, unless `--include-active` is set
- the worker branch is ahead of `master`
- the worker branch is not behind `master`

It skips dirty, active, unchanged, behind, diverged, missing, or invalid worktrees and reports why.

## Accepted Patch Lane

Use this lane when the user says `merge` after a `codex-plan-claude-exec-review`
run where Codex reviewed a `cc*` worker diff, applied the accepted patch into
`/home/zhanxp/projects/tg-agent-gateway`, and intentionally left the worker
worktree dirty plus the `claude-cc*` tmux session open until final disposition.

Do not treat the dirty main checkout as an automatic blocker if the dirty files
are the accepted worker patch. First prove the provenance and scope:

```bash
git -C /home/zhanxp/projects/tg-agent-gateway status --short
git -C /home/zhanxp/projects/tg-agent-gateway diff --stat
git -C /home/zhanxp/worktrees/tg-agent-gateway/cc2 status --short
git -C /home/zhanxp/worktrees/tg-agent-gateway/cc2 diff --stat
```

Then finish the merge flow:

1. Inspect the main diff and the source worker diff. Commit only the accepted
   files in the main checkout; leave unrelated dirty or untracked files alone.
2. Run final verification in the main checkout before committing when possible.
   At minimum use the focused build/check commands that proved the patch.
3. Create a Lore-format commit on `master` for the accepted main-checkout
   patch.
4. Preserve the worker's duplicate dirty diff before cleaning it:
   ```bash
   ts=$(date +%Y%m%d-%H%M%S)
   worker=cc2
   git -C /home/zhanxp/worktrees/tg-agent-gateway/$worker diff --binary \
     > /tmp/tg-agent-gateway-$worker-accepted-before-ff-$ts.patch
   git -C /home/zhanxp/worktrees/tg-agent-gateway/$worker stash push -u \
     -m "backup $worker accepted duplicate before ff master $ts"
   git -C /home/zhanxp/worktrees/tg-agent-gateway/$worker merge --ff-only master
   ```
   The stash is a backup of already-accepted work; do not pop it back unless
   investigating a regression.
5. Continue the normal post-merge flow: verify active refs, push ordinary
   fast-forward refs when this is the standing post-`merge` path, restart the
   runtime if needed, and close the completed worker tmux session only after
   the worker worktree is clean and the branch contains `master`.

If the main diff contains unrelated tracked edits that cannot be cleanly
separated from the accepted worker patch, stop and report the blocker. If the
worker diff is not represented by the new `master` commit, keep the tmux session
open and do not clean or reuse that worker.

## Sync Lane

Use this lane when `master` already contains the accepted work and the user asks to "同步所有分支", "处理所有分支", "push worker branches", or "现在所有分支是不是统一".

1. Run the audit script.
2. For dirty checked-out worker worktrees, inspect whether the diff is already represented in `master`.
3. If the dirty work is duplicate/accepted, preserve it first:

```bash
ts=$(date +%Y%m%d-%H%M%S)
git -C /home/zhanxp/worktrees/tg-agent-gateway/cc2 diff --binary > /tmp/tg-agent-gateway-cc2-before-ff-$ts.patch
git -C /home/zhanxp/worktrees/tg-agent-gateway/cc2 stash push -u -m "backup cc2 before ff master $ts"
git -C /home/zhanxp/worktrees/tg-agent-gateway/cc2 merge --ff-only master
```

4. For clean branches that only lag `master`, use `git merge --ff-only master` inside the checked-out worktree.
5. For a local worker branch that diverged but is superseded by `master`, create a backup branch first, then align locally only when the user asked to handle that worker:

```bash
ts=$(date +%Y%m%d-%H%M%S)
git branch backup/wt-cc7-before-align-master-$ts wt/cc7
git -C /home/zhanxp/worktrees/tg-agent-gateway/cc7 reset --hard master
```

6. Verify with the audit script and `npm run verify`.
7. If the user asks to push worker refs, or the task is the user's standing
   post-`merge` flow for this repo, push only the active branch set and verify
   local/remote counts are `0 0`.
8. Close completed Claude worker tmux sessions for any synced `cc*` worker whose work is accepted:

```bash
   bash /home/zhanxp/projects/myagent/skills/skills-local/worktree-merge/scripts/cleanup_completed_worker_tmux.sh --workers "cc2 cc3" --apply
```

Use a dry-run first when the affected worker set is unclear:

```bash
   bash /home/zhanxp/projects/myagent/skills/skills-local/worktree-merge/scripts/cleanup_completed_worker_tmux.sh --workers "cc2 cc3"
```

### Pushing Worker Refs

Push fast-forward or new worker refs directly:

```bash
git push origin wt/cc1:wt/cc1 wt/cc2:wt/cc2 wt/cc3:wt/cc3 wt/cc4:wt/cc4 wt/cc5:wt/cc5 wt/cc6:wt/cc6 wt/cc7:wt/cc7 wt/cc8:wt/cc8 wt/cx1:wt/cx1 wt/cx2:wt/cx2
```

If a remote worker branch diverged, do not silently force push. Only after the user explicitly asks to handle that branch, use an exact-SHA lease:

```bash
git push --force-with-lease=refs/heads/wt/cc7:<old-remote-sha> origin wt/cc7:wt/cc7
```

Keep a local backup branch for the overwritten remote worker commit.

### What Counts As Unified

When answering whether branches are unified, distinguish:

- **Active work pool**: `master`, `wt/cc1`-`wt/cc8`, `wt/cx1`, `wt/cx2`.
- **Historical branches**: `backup/*`, old `origin/wt/bdcc*`, old `origin/wt/hm5`, review branches, and ad hoc experiment branches.

It is acceptable for historical branches to differ from `master`; do not rewrite or delete them unless the user explicitly asks.

## Historical Remote Cleanup Lane

Use this lane only when the user explicitly says old/historical remote branches are no longer needed.

1. List remote refs and identify non-active refs:

```bash
git branch -r --format='%(refname:short) %(objectname:short)' | sort
```

2. For each deletion candidate, verify its commit is contained by `master` before deleting the remote ref:

```bash
for r in origin/review/task-menu-refactor-20260513 origin/worktree-graceful-crunching-deer origin/wt/bdcc1 origin/wt/bdcc2 origin/wt/hm5; do
  echo "== $r =="
  git show -s --format='%H %s' "$r"
  git branch --contains "$r" --format='%(refname:short)' | sort
  git branch -r --contains "$r" --format='%(refname:short)' | sort
done
```

3. Delete exact remote refs only after containment is confirmed:

```bash
git push origin --delete review/task-menu-refactor-20260513 worktree-graceful-crunching-deer wt/bdcc1 wt/bdcc2 wt/hm5
git fetch origin --prune
```

4. Re-run the audit script. `Origin Heads Not At origin/master` should be empty except for deliberately retained branches.

Do not delete active refs (`origin/master`, `origin/wt/cc1`-`origin/wt/cc8`, `origin/wt/cx1`, `origin/wt/cx2`) as part of historical cleanup.

## Close Completed Worker Tmux Sessions

Use this lane when the user asks to close completed windows, tmux panes, or worker terminals after all relevant work has been merged and synced. Also use it automatically after merge/push/sync tasks that accepted Claude worker work, because stale completed `claude-cc*` panes make those workers look busy to the next "arrange cc" run.

1. Confirm active refs are synced and worker worktrees are clean:

```bash
bash /home/zhanxp/projects/myagent/skills/skills-local/worktree-merge/scripts/audit_worker_refs.sh
git worktree list --porcelain
```

2. Prefer the guarded cleanup script. It is dry-run by default and only closes sessions with `--apply`:

```bash
bash /home/zhanxp/projects/myagent/skills/skills-local/worktree-merge/scripts/cleanup_completed_worker_tmux.sh --workers "cc2 cc3"
bash /home/zhanxp/projects/myagent/skills/skills-local/worktree-merge/scripts/cleanup_completed_worker_tmux.sh --workers "cc2 cc3" --apply
```

The script only considers `claude-*` sessions whose pane cwd is inside the worker worktree, skips dirty worktrees, skips workers whose branch is not contained in `master`, skips workers with active/planned DB rows, and skips panes that do not look like a completed Claude final report.

3. If manual inspection is needed, list tmux sessions/panes and map them to worker worktree paths:

```bash
tmux list-sessions -F '#{session_name} #{session_windows} #{session_attached}' 2>/dev/null || true
tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} pid=#{pane_pid} cwd=#{pane_current_path} cmd=#{pane_current_command} title=#{pane_title}' 2>/dev/null || true
```

4. Close only worker-task sessions whose pane cwd is under `/home/zhanxp/worktrees/tg-agent-gateway/<worker>` and whose work has been merged/synced:

```bash
for s in claude-cc2-webapp-sidebar-swipe-gesture claude-cc5-add-webapp-attachments; do
  tmux kill-session -t "$s" 2>/dev/null || true
done
```

5. Verify no process cwd remains under the worker worktrees:

```bash
for d in /home/zhanxp/worktrees/tg-agent-gateway/cc{1..8} /home/zhanxp/worktrees/tg-agent-gateway/cx1 /home/zhanxp/worktrees/tg-agent-gateway/cx2; do
  printf '\n== %s ==\n' "$d"
  for p in /proc/[0-9]*; do
    cwd=$(readlink "$p/cwd" 2>/dev/null || true)
    case "$cwd" in "$d"*) ps -p "${p##*/}" -o pid=,ppid=,stat=,comm=,args= ;; esac
  done
done
```

Do not close service or operator sessions such as `tg-agent-gateway`, `tg-webapp-dev`, `tg-webapp-tunnel`, main `codex*`, or unrelated `claude*` sessions unless the user names them.

## Apply Behavior

`--apply` does not merge workers directly into `master` first. It:

1. checks that the main repo is on `master` and clean
2. creates a temporary integration branch and worktree from `master`
3. merges ready worker branches into that integration worktree in scan order
4. runs verification, default `npm run verify`
5. fast-forwards `master` to the verified integration branch
6. removes the temporary worktree and deletes the temporary branch on success

If a merge conflicts or verification fails, the script stops, keeps the integration worktree for inspection, and leaves `master` unchanged.

## Common Options

```bash
# Target a different repo.
bash scripts/merge_ready_worktrees.sh --repo /path/to/repo --dry-run

# Skip verification only for diagnostic or disposable runs.
bash scripts/merge_ready_worktrees.sh --apply --no-verify

# Use a custom verification command.
bash scripts/merge_ready_worktrees.sh --apply --verify "npm run type-check && npm run test:unit"

# Include worktrees with active local shell/process cwd.
bash scripts/merge_ready_worktrees.sh --dry-run --include-active
```

## Forbidden Defaults

Do not use destructive shortcuts for this workflow:

- no `git reset --hard`
- no `git clean`
- no force push
- no overwriting or stashing unrelated user work during merge
- no automatic push, except the user's standing post-`merge` flow for
  `/home/zhanxp/projects/tg-agent-gateway`, where ordinary fast-forward push of
  `master` plus active refs is explicitly requested

Exceptions must be explicit and narrow:

- Stashing a worker's duplicate accepted diff is allowed in the Accepted Patch
  Lane only after saving a patch backup and committing the same accepted work to
  `master`.
- `git reset --hard master` is allowed only for a specific worker branch after duplicate/superseded work has been backed up and the user asked to handle that branch.
- `git push --force-with-lease` is allowed only for a named remote worker branch with an exact old remote SHA and a local backup branch.

## Runtime Plan Files

`plans/*/<date>/...__plan.md` files can be referenced by `data/gateway.sqlite`. Do not move or delete untracked plan files just to clean `git status`; first check the DB `plan_path`. Prefer local `.git/info/exclude` entries for runtime plan artifacts that should stay on disk but not enter Git.

## Reporting

Final responses should include:

- ready workers merged or ready to merge
- skipped workers with reasons
- verification command and result
- master HEAD before and after apply
- integration worktree path if the run stopped for conflict or verification failure

For sync/audit tasks, also include:

- active branch set checked
- local/remote ahead-behind counts
- backup patch/stash/branch paths created
- remote refs pushed or intentionally skipped
- whether historical branches were excluded from "all current" claims
