# Graphify Pilot

Date: 2026-05-25
Scope: `myagent`

## Artifacts

Generated files are intentionally ignored by git:

- `graphify-out/graph.json`
- `graphify-out/graph.html`
- `graphify-out/GRAPH_REPORT.md`
- `graphify-out/GRAPH_TREE.html`
- `graphify-out/myagent-callflow.html`

The input boundary is controlled by `.graphifyignore`. Runtime snapshots, downloaded third-party skills, Playwright captures, generated heartbeat output, and Claude/Codex runtime backups are excluded because they drown out the source-of-truth project structure.

## Commands

```bash
uvx --from graphifyy graphify update /home/zhanxp/projects/myagent --no-cluster
uvx --from graphifyy graphify cluster-only /home/zhanxp/projects/myagent
uvx --from graphifyy graphify tree --graph graphify-out/graph.json --output graphify-out/GRAPH_TREE.html --root /home/zhanxp/projects/myagent --label myagent
uvx --from graphifyy graphify export callflow-html
uvx --from graphifyy graphify benchmark graphify-out/graph.json
```

## Results

Final scoped graph:

- 114 extracted files
- 1,360 nodes
- 2,184 clustered edges
- 103 communities
- benchmark estimate: 68,000 words / 90,666 naive tokens, about 1,707 tokens per graph query, reported 53.1x fewer tokens per query

The first unscoped run produced 6,525 nodes and noisy answers because it indexed runtime snapshots and downloaded skill copies. The scoped run is much more usable.

## What Worked

- `graphify explain "sync_shared_skills.sh"` immediately found the sync script and its function surface: `sync_from_codex()`, `sync_from_claude()`, `write_wrapper()`, `configs_validate()`, backup/restore helpers, and validation helpers.
- `graphify explain "sync_from_codex()"` gave the local call neighborhood without scanning the whole shell script.
- `GRAPH_REPORT.md` surfaced useful communities for `wsl-windows-chrome`, config sync, `sync-shared-skills`, heartbeat, disable-MCP cleanup, and selected local skills.
- `GRAPH_TREE.html` is the best quick navigation artifact; it is smaller and less visually noisy than the force graph.
- `myagent-callflow.html` is useful as a browsable architecture page, but it is secondary to `explain` and `tree` for daily agent work.

## What Did Not Work

- Broad natural-language queries such as "how do skills sync across codex claude and hermes" still matched generic nodes like `codex()` before the actual sync skill. For this repo, Graphify works better when seeded with exact file/function names.
- The no-API-key path is AST/document-structure oriented. It is good for localizing files and call surfaces, but it does not replace reading `SKILL.md` or shell script logic before editing.
- The graph is only as good as `.graphifyignore`. Without strict ignores it amplifies duplicated runtime backups instead of reducing context.

## Verdict

Graphify is worth keeping as an on-demand project map, not as a mandatory hook yet.

Use it before broad repo exploration when the task mentions an unfamiliar skill, script, or config surface. It can reduce repeated scanning by giving candidate files, nearby functions, and communities first. Continue using `rg` and direct file reads for exact behavior, especially for shell scripts and policy docs.

Do not run `graphify codex install`, `graphify claude install`, or git hooks until the same scoped workflow has been tested on `tg-agent-gateway`.

## Next Trial

For `tg-agent-gateway`, create a repo-specific `.graphifyignore` that includes only source, tests, scripts, docs, and config examples, while excluding `data/`, runtime plans, databases, backups, build output, and worktree artifacts. The acceptance bar should be higher there: Graphify should help answer "which service/handler owns this Telegram workflow?" faster than repeated `rg` plus manual context explanation.
