# Custom Skill Migration Plan

## Goal

Move all user-managed custom skills out of OMX runtime directories and into a single durable source-of-truth directory:

- Source of truth: `/home/zhanxp/projects/myagent/skills/`

Runtime directories remain usable, but only as entrypoints:

- `~/.codex/skills/`
- `~/.claude/skills/`

This keeps custom assets independent from OMX install/uninstall behavior.

## Directory Layout

```text
/home/zhanxp/projects/myagent/
├── README.md
├── docs/
│   └── skill-migration-plan.md
└── skills/
    ├── README.md
    ├── <skill-name-1>/
    │   ├── SKILL.md
    │   └── .skill-source.json
    └── <skill-name-2>/
        ├── SKILL.md
        └── .skill-source.json
```

## Naming Rules

- Use one directory per custom skill under `skills/`.
- Directory names should be lowercase kebab-case.
- The directory name is the runtime mount name.
- Each skill must contain a `SKILL.md`.
- Each skill should contain a `.skill-source.json` metadata file.

Recommended metadata shape:

```json
{
  "name": "example-skill",
  "owner": "zhanxp",
  "managed_by": "manual-git",
  "source_of_truth": "/home/zhanxp/projects/myagent/skills/example-skill",
  "runtime_targets": [
    "/home/zhanxp/.codex/skills/example-skill",
    "/home/zhanxp/.claude/skills/example-skill"
  ],
  "sync_policy": "symlink-preferred",
  "notes": "User-managed custom skill. Do not treat runtime copies as primary data."
}
```

## Linking Strategy

Preferred strategy:

1. Keep the real files only under `/home/zhanxp/projects/myagent/skills/`.
2. Make `~/.codex/skills/<name>` a symlink to `/home/zhanxp/projects/myagent/skills/<name>`.
3. Make `~/.claude/skills/<name>` a symlink to `/home/zhanxp/projects/myagent/skills/<name>`.

Fallback strategy:

- If a runtime surface cannot use symlinks, use a controlled sync process from the repo to the runtime directory.
- Even in fallback mode, this repository remains the only editable location.

## Conflict Rules

- If `~/.codex/skills/<name>` or `~/.claude/skills/<name>` already exists and is not a symlink, inspect it before replacing it.
- If the target contains user-authored content, migrate or back it up before relinking.
- Never overwrite an unmanaged runtime directory without first checking whether it contains custom content.
- Do not treat OMX built-in skills as migration candidates unless they were explicitly customized by the user.

## Migration Procedure

### Phase 1: Inventory

Inspect these locations:

- `~/.codex/skills/`
- `~/.claude/skills/`
- Any previous custom-skill stash or repo path

Classify each directory into one of these groups:

- Built-in OMX-managed content
- User-managed custom skill
- Unknown or mixed content

### Phase 2: Normalize Source of Truth

For each user-managed skill:

1. Create `/home/zhanxp/projects/myagent/skills/<name>/`.
2. Move the canonical `SKILL.md` and supporting files there.
3. Add `.skill-source.json`.
4. Commit the result to git.

### Phase 3: Replace Runtime Copies

For each migrated skill:

1. Remove or rename the runtime copy only after its source is safely present in the repo.
2. Create symlinks from both runtime directories to the repo path.
3. Verify the symlink resolves correctly.

### Phase 4: Validate

Validation should confirm:

- The repo path exists.
- `SKILL.md` exists in the repo path.
- Runtime entrypoints resolve back to the repo path.
- No custom skill remains only inside a runtime directory.

## Uninstall Protection Rules

Before any OMX uninstall or cleanup, classify paths into three groups.

Safe to delete:

- OMX runtime state
- OMX hooks and caches
- Regenerable built-in install artifacts

Do not delete directly:

- `/home/zhanxp/projects/myagent/skills/`
- `~/.codex/skills/`
- `~/.claude/skills/`
- Any separate user-owned skill repository

Must inspect before action:

- Any custom skill mixed into an OMX-managed directory
- Any runtime skill directory that is not a symlink
- Any skill with missing metadata or unclear ownership

Hard stop conditions before uninstall:

- A custom skill exists only in `~/.codex/skills/` or `~/.claude/skills/`
- A custom skill target is a real directory instead of a symlink and has not been inventoried
- A runtime entry points to a path outside the approved source-of-truth repo without explicit acknowledgment

## Recovery Procedure

If runtime directories are deleted or OMX is reinstalled:

1. Restore or clone `/home/zhanxp/projects/myagent/`.
2. Recreate `~/.codex/skills/` and `~/.claude/skills/` if needed.
3. Recreate symlinks for each custom skill from the repo path.
4. Verify the runtime entrypoints resolve to the repo path.

Minimum recovery proof:

- `skills/<name>/SKILL.md` exists in the repo
- `~/.codex/skills/<name>` points to the repo copy
- `~/.claude/skills/<name>` points to the repo copy

## Operating Rules Going Forward

- All custom skill edits happen in `/home/zhanxp/projects/myagent/skills/`.
- Runtime directories are treated as disposable mount points.
- `sync-shared-skills` may remain in use as a distribution helper, but not as backup or the primary storage mechanism.
- New skills should be created in the repo first, then linked into runtime directories.

## Immediate Next Actions

1. Create the `skills/` directory in this repo.
2. Add one `README.md` under `skills/` stating that it is the canonical source-of-truth location.
3. Inventory existing custom skills under `~/.codex/skills/` and `~/.claude/skills/`.
4. Migrate each confirmed custom skill into this repo.
5. Replace runtime copies with symlinks.
6. Commit the migrated source-of-truth layout to git.
