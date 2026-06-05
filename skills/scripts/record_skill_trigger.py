#!/usr/bin/env python3
"""Record local myagent skill trigger counts.

Skills call this script from their SKILL.md instructions after they trigger.
The counter lives in user runtime state by default so ordinary skill use does
not dirty the myagent repository.
"""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_STATS_PATH = (
    Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state"))
    / "myagent"
    / "skill-trigger-stats.json"
)


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def load_stats(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {"version": 1, "skills": {}}

    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)

    if not isinstance(data, dict):
        raise ValueError(f"stats file root must be an object: {path}")

    skills = data.get("skills")
    if not isinstance(skills, dict):
        data["skills"] = {}

    version = data.get("version")
    if not isinstance(version, int):
        data["version"] = 1

    return data


def save_stats(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = path.with_suffix(path.suffix + ".tmp")
    with tmp_path.open("w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")
    tmp_path.replace(path)


def record_trigger(path: Path, skill_name: str) -> dict[str, Any]:
    path.parent.mkdir(parents=True, exist_ok=True)
    lock_path = path.with_suffix(path.suffix + ".lock")
    with lock_path.open("a+", encoding="utf-8") as lock_handle:
        fcntl.flock(lock_handle, fcntl.LOCK_EX)
        stats = load_stats(path)
        now = utc_now()
        now_iso = now.isoformat()
        today = now.date().isoformat()

        skills = stats.setdefault("skills", {})
        skill = skills.setdefault(
            skill_name,
            {
                "total": 0,
                "first_triggered_at": now_iso,
                "last_triggered_at": None,
                "by_date": {},
            },
        )

        total = skill.get("total")
        skill["total"] = (total if isinstance(total, int) else 0) + 1
        if not isinstance(skill.get("first_triggered_at"), str):
            skill["first_triggered_at"] = now_iso
        skill["last_triggered_at"] = now_iso

        by_date = skill.setdefault("by_date", {})
        if not isinstance(by_date, dict):
            by_date = {}
            skill["by_date"] = by_date
        daily_total = by_date.get(today)
        by_date[today] = (daily_total if isinstance(daily_total, int) else 0) + 1

        stats["updated_at"] = now_iso
        save_stats(path, stats)
        return skill


def print_report(path: Path) -> int:
    if not path.exists():
        print(f"no stats file: {path}")
        return 0

    stats = load_stats(path)
    skills = stats.get("skills", {})
    if not isinstance(skills, dict) or not skills:
        print(f"no skill trigger stats: {path}")
        return 0

    rows: list[tuple[int, str, str]] = []
    for name, raw in skills.items():
        if not isinstance(raw, dict):
            continue
        total = raw.get("total")
        last = raw.get("last_triggered_at")
        rows.append(
            (
                total if isinstance(total, int) else 0,
                str(name),
                last if isinstance(last, str) else "-",
            )
        )

    for total, name, last in sorted(rows, key=lambda row: (-row[0], row[1])):
        print(f"{total:5d}  {name}  last={last}")
    return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Record myagent skill triggers")
    parser.add_argument("skill", nargs="?", help="skill name to record")
    parser.add_argument(
        "--stats-file",
        default=str(DEFAULT_STATS_PATH),
        help=f"stats JSON path (default: {DEFAULT_STATS_PATH})",
    )
    parser.add_argument(
        "--report",
        action="store_true",
        help="print current trigger counts instead of recording a trigger",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    stats_path = Path(args.stats_file).expanduser()

    if args.report:
        return print_report(stats_path)

    skill = args.skill
    if not skill:
        print("missing skill name", file=sys.stderr)
        return 2

    record = record_trigger(stats_path, skill)
    print(f"recorded {skill}: total={record['total']} stats={stats_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
