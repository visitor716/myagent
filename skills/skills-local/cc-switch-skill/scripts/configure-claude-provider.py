#!/usr/bin/env python3
"""Configure a Claude cc-switch provider for one or more HOME directories.

This helper is intentionally non-interactive so provider secrets do not get
echoed by cc-switch's TTY prompts. Pass secrets through an environment variable,
a file, or stdin; the script only prints redacted summaries.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sqlite3
import stat
import subprocess
import sys
import time
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Upsert and activate a Claude provider in cc-switch for isolated HOME directories."
    )
    parser.add_argument("--home", action="append", required=True, help="Target HOME. Repeat for multiple homes.")
    parser.add_argument("--id", required=True, help="Provider id, for example baidu-qianfan.")
    parser.add_argument("--name", required=True, help="Provider display name.")
    parser.add_argument("--base-url", required=True, help="Anthropic-compatible base URL.")
    parser.add_argument("--api-key-env", help="Environment variable containing the provider API key.")
    parser.add_argument("--api-key-file", help="File containing the provider API key.")
    parser.add_argument("--api-key-stdin", action="store_true", help="Read provider API key from stdin.")
    parser.add_argument("--model", help="Optional model name; sets Claude model env vars when provided.")
    parser.add_argument("--category", default="custom", help="Provider category label.")
    parser.add_argument("--website-url", help="Provider website URL.")
    parser.add_argument("--notes", help="Provider notes.")
    parser.add_argument(
        "--sync-common-from-home",
        default=str(Path.home()),
        help="HOME to copy common_config_claude from; use an empty string to skip.",
    )
    parser.add_argument("--no-current", action="store_true", help="Do not mark this provider current.")
    parser.add_argument("--no-export-settings", action="store_true", help="Do not export .claude/settings.json.")
    return parser.parse_args()


def read_api_key(args: argparse.Namespace) -> str:
    sources = [bool(args.api_key_env), bool(args.api_key_file), args.api_key_stdin]
    if sum(sources) != 1:
        raise SystemExit("exactly one of --api-key-env, --api-key-file, or --api-key-stdin is required")

    if args.api_key_env:
        value = os.environ.get(args.api_key_env, "")
    elif args.api_key_file:
        value = Path(args.api_key_file).read_text(encoding="utf-8")
    else:
        value = sys.stdin.read()

    value = value.strip()
    if not value:
        raise SystemExit("api key is empty")
    return value


def run_cc_switch(home: Path, args: list[str], *, quiet: bool = False) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["HOME"] = str(home)
    result = subprocess.run(
        ["cc-switch", *args],
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        output = (result.stdout + result.stderr).strip()
        raise SystemExit(f"cc-switch failed for {home}: {output}")
    if not quiet and result.stdout.strip():
        print(result.stdout.strip())
    return result


def ensure_database(home: Path) -> Path:
    db = home / ".cc-switch" / "cc-switch.db"
    if not db.exists():
        home.mkdir(parents=True, exist_ok=True)
        run_cc_switch(home, ["config", "validate"], quiet=True)
    if not db.exists():
        raise SystemExit(f"cc-switch database was not created: {db}")
    return db


def backup_if_exists(path: Path, timestamp: str) -> None:
    if not path.exists():
        return
    if path.parent.name in {".cc-switch", ".claude"}:
        backup_dir = path.parent.parent / "backups"
    else:
        backup_dir = path.parent / "backups"
    backup_dir.mkdir(parents=True, exist_ok=True)
    backup_path = backup_dir / f"{path.name}.bak-cc-switch-provider-{timestamp}"
    shutil.copy2(path, backup_path)


def read_common_config(source_home: str) -> str | None:
    if not source_home:
        return None
    db = Path(source_home).expanduser() / ".cc-switch" / "cc-switch.db"
    if not db.exists():
        return None
    with sqlite3.connect(db) as conn:
        row = conn.execute("select value from settings where key='common_config_claude'").fetchone()
    return row[0] if row else None


def build_settings_config(args: argparse.Namespace, api_key: str) -> dict[str, object]:
    env = {
        "ANTHROPIC_AUTH_TOKEN": api_key,
        "ANTHROPIC_BASE_URL": args.base_url,
        "ENABLE_TOOL_SEARCH": "true",
    }
    if args.model:
        env.update(
            {
                "ANTHROPIC_MODEL": args.model,
                "ANTHROPIC_REASONING_MODEL": args.model,
                "ANTHROPIC_DEFAULT_HAIKU_MODEL": args.model,
                "ANTHROPIC_DEFAULT_SONNET_MODEL": args.model,
                "ANTHROPIC_DEFAULT_OPUS_MODEL": args.model,
            }
        )
    return {"env": env}


def upsert_provider(home: Path, args: argparse.Namespace, api_key: str, common_config: str | None) -> None:
    db = ensure_database(home)
    now = int(time.time() * 1000)
    settings_config = build_settings_config(args, api_key)
    meta = {
        "commonConfigEnabled": bool(common_config),
        "endpointAutoSelect": True,
        "apiFormat": "anthropic",
    }

    with sqlite3.connect(db) as conn:
        conn.execute("begin")
        if common_config:
            conn.execute("insert or replace into settings(key, value) values(?, ?)", ("common_config_claude", common_config))
            conn.execute("insert or replace into settings(key, value) values(?, ?)", ("common_config_legacy_migrated_v1", "true"))
            conn.execute("insert or replace into settings(key, value) values(?, ?)", ("official_providers_seeded", "true"))
        if not args.no_current:
            conn.execute("update providers set is_current=0 where app_type='claude'")
        conn.execute(
            """
            insert into providers (
              id, app_type, name, settings_config, website_url, category,
              created_at, sort_index, notes, icon, icon_color, meta,
              is_current, in_failover_queue, cost_multiplier, limit_daily_usd,
              limit_monthly_usd, provider_type
            ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            on conflict(id, app_type) do update set
              name=excluded.name,
              settings_config=excluded.settings_config,
              website_url=excluded.website_url,
              category=excluded.category,
              sort_index=excluded.sort_index,
              notes=excluded.notes,
              icon=excluded.icon,
              icon_color=excluded.icon_color,
              meta=excluded.meta,
              is_current=excluded.is_current,
              in_failover_queue=0,
              cost_multiplier=excluded.cost_multiplier,
              limit_daily_usd=excluded.limit_daily_usd,
              limit_monthly_usd=excluded.limit_monthly_usd,
              provider_type=excluded.provider_type
            """,
            (
                args.id,
                "claude",
                args.name,
                json.dumps(settings_config, separators=(",", ":")),
                args.website_url,
                args.category,
                now,
                0,
                args.notes,
                None,
                None,
                json.dumps(meta, separators=(",", ":")),
                0 if args.no_current else 1,
                0,
                "1.0",
                None,
                None,
                None,
            ),
        )
        conn.commit()


def export_settings(home: Path, provider_id: str) -> None:
    settings_path = home / ".claude" / "settings.json"
    settings_path.parent.mkdir(parents=True, exist_ok=True)
    run_cc_switch(home, ["--app", "claude", "provider", "export", provider_id, "-o", str(settings_path)], quiet=True)
    settings_path.chmod(stat.S_IRUSR | stat.S_IWUSR)


def verify(home: Path, provider_id: str) -> None:
    run_cc_switch(home, ["config", "validate"], quiet=True)
    current = run_cc_switch(home, ["--app", "claude", "provider", "current"], quiet=True)
    if provider_id not in current.stdout:
        raise SystemExit(f"provider {provider_id!r} is not current for {home}")


def main() -> None:
    args = parse_args()
    api_key = read_api_key(args)
    common_config = read_common_config(args.sync_common_from_home)
    timestamp = time.strftime("%Y%m%d-%H%M%S")

    for home_s in args.home:
        home = Path(home_s).expanduser()
        home.mkdir(parents=True, exist_ok=True)
        db = ensure_database(home)
        backup_if_exists(db, timestamp)
        backup_if_exists(home / ".claude" / "settings.json", timestamp)
        backup_if_exists(home / ".claude.json", timestamp)
        upsert_provider(home, args, api_key, common_config)
        if not args.no_export_settings:
            export_settings(home, args.id)
        verify(home, args.id)
        print(f"configured {home}: provider={args.id}, base_url={args.base_url}, api_key_set=true")


if __name__ == "__main__":
    main()
