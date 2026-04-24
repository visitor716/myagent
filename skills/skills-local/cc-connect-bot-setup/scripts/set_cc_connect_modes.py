#!/usr/bin/env python3
"""Set cc-connect agent permission modes without touching secrets."""

from __future__ import annotations

import argparse
import os
import re
import shutil
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path


MODE_BY_AGENT = {
    "claudecode": "bypassPermissions",
    "codex": "full-auto",
}


@dataclass
class ProjectSummary:
    name: str
    agent_type: str
    old_mode: str
    new_mode: str
    changed: bool


def parse_quoted_assignment(line: str, key: str) -> str | None:
    match = re.match(rf'\s*{re.escape(key)}\s*=\s*"([^"]*)"', line)
    if not match:
        return None
    return match.group(1)


def mode_line(new_mode: str) -> str:
    return f'mode = "{new_mode}"\n'


def update_lines(lines: list[str]) -> tuple[list[str], list[ProjectSummary]]:
    output: list[str] = []
    summaries: list[ProjectSummary] = []

    current_project = ""
    current_agent = ""
    current_mode = ""
    in_agent_table = False
    in_options_table = False
    mode_seen = False

    def finalize_options() -> None:
        nonlocal current_mode, mode_seen
        desired = MODE_BY_AGENT.get(current_agent)
        if in_options_table and desired and not mode_seen:
            output.append(mode_line(desired))
            summaries.append(
                ProjectSummary(
                    name=current_project or "<unnamed>",
                    agent_type=current_agent,
                    old_mode="<missing>",
                    new_mode=desired,
                    changed=True,
                )
            )
            current_mode = desired
            mode_seen = True

    for line in lines:
        stripped = line.strip()

        if stripped.startswith("["):
            finalize_options()
            in_agent_table = stripped == "[projects.agent]"
            in_options_table = stripped == "[projects.agent.options]"
            mode_seen = False if in_options_table else mode_seen

            if stripped == "[[projects]]":
                current_project = ""
                current_agent = ""
                current_mode = ""
                mode_seen = False

        name_value = parse_quoted_assignment(line, "name")
        if name_value is not None and not in_agent_table and not in_options_table:
            current_project = name_value

        type_value = parse_quoted_assignment(line, "type")
        if type_value is not None and in_agent_table:
            current_agent = type_value

        if in_options_table:
            mode_value = parse_quoted_assignment(line, "mode")
            desired = MODE_BY_AGENT.get(current_agent)
            if mode_value is not None and desired:
                mode_seen = True
                current_mode = mode_value
                changed = mode_value != desired
                summaries.append(
                    ProjectSummary(
                        name=current_project or "<unnamed>",
                        agent_type=current_agent,
                        old_mode=mode_value,
                        new_mode=desired,
                        changed=changed,
                    )
                )
                if changed:
                    output.append(re.sub(r'(\s*mode\s*=\s*")[^"]*(".*)', rf"\1{desired}\2", line))
                    continue

        output.append(line)

    finalize_options()
    return output, summaries


def print_summary(summaries: list[ProjectSummary]) -> None:
    if not summaries:
        print("No claudecode/codex project modes found.")
        return

    print("Project | Agent | Old mode | New mode | Changed")
    print("--- | --- | --- | --- | ---")
    for item in summaries:
        print(
            f"{item.name} | {item.agent_type} | {item.old_mode} | "
            f"{item.new_mode} | {'yes' if item.changed else 'no'}"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description="Set cc-connect Claude Code/Codex modes to full-auto defaults.")
    parser.add_argument("--config", default="~/.cc-connect/config.toml", help="Path to cc-connect config.toml")
    parser.add_argument("--dry-run", action="store_true", help="Show summary without writing")
    args = parser.parse_args()

    config_path = Path(args.config).expanduser()
    if not config_path.exists():
        print(f"Config not found: {config_path}", file=sys.stderr)
        return 2

    original = config_path.read_text(encoding="utf-8").splitlines(keepends=True)
    updated, summaries = update_lines(original)
    print_summary(summaries)

    changed = updated != original
    if args.dry_run:
        print("Dry run: no files changed.")
        return 0
    if not changed:
        print("No changes needed.")
        return 0

    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_path = config_path.with_name(f"{config_path.name}.bak.fullauto.{timestamp}")
    shutil.copy2(config_path, backup_path)

    temp_path = config_path.with_name(f".{config_path.name}.tmp.{os.getpid()}")
    temp_path.write_text("".join(updated), encoding="utf-8")
    shutil.copymode(config_path, temp_path)
    temp_path.replace(config_path)

    print(f"Backup: {backup_path}")
    print(f"Updated: {config_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
