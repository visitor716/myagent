# OpenCLI Install Notes

Date: 2026-05-25
Package: `@jackwener/opencli@1.8.0`
Source: `jackwener/OpenCLI`

## Installed

- Global CLI: `opencli` from npm
- Repo-managed skills:
  - `skills/skills-local/opencli-usage`
  - `skills/skills-local/opencli-browser`
  - `skills/skills-local/opencli-adapter-author`
  - `skills/skills-local/opencli-autofix`
- Runtime skill symlinks:
  - `~/.codex/skills/opencli-*`
  - `~/.claude/skills/opencli-*`
  - `~/.hermes/skills/myagent/opencli-*`
- Browser Bridge extension package downloaded and unpacked:
  - `~/.opencli/extension/opencli-extension-v1.0.15.zip`
  - `~/.opencli/extension/opencli-extension-v1.0.15/`

## Verification

```bash
opencli --version
NODE_NO_WARNINGS=1 opencli list -f json
opencli hackernews top --limit 3 -f json
opencli doctor
bash configs/sync.sh validate
```

Observed results:

- `opencli --version` returns `1.8.0`.
- `opencli list -f json` returns 859 command entries.
- `opencli hackernews top --limit 3 -f json` returns public data successfully.
- Four OpenCLI skills pass `quick_validate.py`.
- Skill sync dry-run after installation reports `created=0 updated=0 unchanged=50 skipped=23 conflicts=0`.
- `bash configs/sync.sh validate` passes.

## Browser Bridge Status

`opencli doctor` currently reports:

- daemon running on port `19825`
- Browser Bridge extension not connected

The dedicated Windows Chrome automation profile is reachable through `wsl-windows-chrome` at `127.0.0.1:9222`, but `opencli browser` still requires the OpenCLI Browser Bridge extension. Setting `OPENCLI_CDP_ENDPOINT=http://127.0.0.1:9222` was not enough for `opencli browser` commands.

The Chrome Web Store page was opened in the dedicated automation profile and the install button entered the "processing product install" state, but the extension confirmation UI is browser-native rather than page DOM, so `playwright-cli` could not accept it programmatically. Do not assume browser-backed OpenCLI commands work until `opencli doctor` is green.

## Usage Guidance

Use OpenCLI now for public/local adapters and command discovery:

```bash
NODE_NO_WARNINGS=1 opencli list -f json
opencli <site> --help -f yaml
opencli hackernews top --limit 5 -f json
```

Use `wsl-windows-chrome` as the primary browser automation path until Browser Bridge is connected. Once the extension is connected, prefer OpenCLI for reusable adapters and structured browser primitives, but keep `wsl-windows-chrome` as the trusted logged-in Chrome attachment baseline.
