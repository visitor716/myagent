#!/usr/bin/env python3
"""Generate a local Codex heartbeat snapshot.

The heartbeat is intentionally non-invasive: it reads status, writes the latest
snapshot to docs/agent-memory/heartbeat.md, and never launches a fallback
browser or enables MCP.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parents[1]
MEMORY_DIR = ROOT / "docs" / "agent-memory"
HEARTBEAT_FILE = MEMORY_DIR / "heartbeat.md"
RUNTIME_MEMORY = Path.home() / ".codex" / "memories" / "codex-operating-memory.md"
SOURCE_MEMORY = MEMORY_DIR / "codex-operating-memory.md"
CHROME_STATUS_SCRIPT = (
    ROOT
    / "skills"
    / "skills-local"
    / "wsl-windows-chrome"
    / "scripts"
    / "attach_windows_logged_in_chrome.sh"
)


def run(command: list[str], timeout: int = 15, cwd: Path = ROOT) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            command,
            cwd=cwd,
            timeout=timeout,
            text=True,
            capture_output=True,
            check=False,
        )
    except FileNotFoundError as exc:
        return subprocess.CompletedProcess(command, 127, "", str(exc))
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout if isinstance(exc.stdout, str) else ""
        stderr = exc.stderr if isinstance(exc.stderr, str) else ""
        return subprocess.CompletedProcess(command, 124, stdout, stderr or f"timeout after {timeout}s")


def compact(text: str, max_lines: int = 40, max_chars: int = 4000) -> str:
    text = text.strip()
    if not text:
        return ""
    lines = text.splitlines()
    if len(lines) > max_lines:
        lines = lines[:max_lines] + [f"... truncated {len(text.splitlines()) - max_lines} lines"]
    compacted = "\n".join(lines)
    if len(compacted) > max_chars:
        compacted = compacted[:max_chars] + "\n... truncated chars"
    return compacted


def section(title: str, body: Iterable[str]) -> list[str]:
    lines = [f"## {title}", ""]
    lines.extend(body)
    lines.append("")
    return lines


def command_block(label: str, text: str) -> list[str]:
    if not text:
        return [f"- `{label}`: no output"]
    return [f"- `{label}`:", "", "```text", text, "```"]


def git_summary() -> list[str]:
    status = run(["git", "status", "--short"], timeout=10)
    branch = run(["git", "branch", "--show-current"], timeout=5)
    dirty = bool(status.stdout.strip())
    lines = [
        f"- Branch: `{branch.stdout.strip() or 'unknown'}`",
        f"- Working tree: {'dirty' if dirty else 'clean'}",
    ]
    lines.extend(command_block("git status --short", compact(status.stdout, max_lines=80)))
    return lines


def codex_summary() -> list[str]:
    version = run(["codex", "--version"], timeout=10)
    mcp = run(["codex", "mcp", "list"], timeout=10)
    features = run(["codex", "features", "list"], timeout=15)
    interesting = []
    for line in features.stdout.splitlines():
        name = line.split(maxsplit=1)[0] if line.strip() else ""
        if name in {"goals", "hooks", "memories", "prevent_idle_sleep", "remote_control"}:
            interesting.append(line)

    lines = [f"- Version: `{version.stdout.strip() or version.stderr.strip() or 'unknown'}`"]
    lines.extend(command_block("codex mcp list", compact(mcp.stdout or mcp.stderr, max_lines=20)))
    lines.extend(command_block("selected codex features", "\n".join(interesting)))
    return lines


def memory_summary() -> list[str]:
    if RUNTIME_MEMORY.is_symlink():
        target = os.readlink(RUNTIME_MEMORY)
        runtime_state = f"symlink -> `{target}`"
    elif RUNTIME_MEMORY.exists():
        runtime_state = "regular file"
    else:
        runtime_state = "missing"

    return [
        f"- Source memory: `{SOURCE_MEMORY}` {'present' if SOURCE_MEMORY.exists() else 'missing'}",
        f"- Runtime memory: `{RUNTIME_MEMORY}` {runtime_state}",
        f"- Open loops: `{MEMORY_DIR / 'open-loops.md'}`",
        f"- Decisions: `{MEMORY_DIR / 'decisions.md'}`",
    ]


def extract_json(text: str) -> dict[str, object] | None:
    start = text.find("{")
    end = text.rfind("}")
    if start == -1 or end == -1 or end <= start:
        return None
    try:
        return json.loads(text[start : end + 1])
    except json.JSONDecodeError:
        return None


def chrome_summary() -> list[str]:
    if not CHROME_STATUS_SCRIPT.exists():
        return [f"- Status script missing: `{CHROME_STATUS_SCRIPT}`"]

    result = run(["bash", str(CHROME_STATUS_SCRIPT), "--status", "--json"], timeout=20)
    payload = extract_json(result.stdout)
    if payload:
        ready_keys = [
            "local_cdp_ready",
            "gateway_cdp_ready",
            "relay_cdp_ready",
        ]
        ready = any(bool(payload.get(key)) for key in ready_keys)
        fields = [
            f"- Attach script: `{CHROME_STATUS_SCRIPT}`",
            f"- Dedicated Windows CDP ready: {ready}",
            f"- Requested port: `{payload.get('requested_cdp_port', 'unknown')}`",
            f"- Resolved port: `{payload.get('resolved_cdp_port', 'unknown')}`",
            f"- Preferred mode: `{payload.get('preferred_mode', 'unknown')}`",
        ]
        return fields

    output = compact("\n".join(part for part in [result.stdout, result.stderr] if part), max_lines=30)
    lines = [
        f"- Attach script: `{CHROME_STATUS_SCRIPT}`",
        f"- Dedicated Windows CDP ready: false",
        f"- Status command exit code: {result.returncode}",
    ]
    lines.extend(command_block("chrome status diagnostics", output))
    return lines


def render() -> str:
    now = datetime.now().astimezone().isoformat(timespec="seconds")
    lines = [
        "# Codex Heartbeat",
        "",
        f"Generated: {now}",
        "",
        "This file is generated by `scripts/codex_heartbeat.py`.",
        "",
    ]
    lines.extend(section("Git", git_summary()))
    lines.extend(section("Codex", codex_summary()))
    lines.extend(section("Memory", memory_summary()))
    lines.extend(section("Windows Chrome Skill", chrome_summary()))
    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate a local Codex heartbeat snapshot.")
    parser.add_argument("--quiet", action="store_true", help="Do not print the output path.")
    args = parser.parse_args()

    MEMORY_DIR.mkdir(parents=True, exist_ok=True)
    HEARTBEAT_FILE.write_text(render(), encoding="utf-8")

    if not args.quiet:
        print(HEARTBEAT_FILE)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
