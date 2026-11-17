#!/usr/bin/env python3
"""Render agy's JSON status telemetry without network requests or dependencies."""
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import unicodedata


def clean(value):
    return re.sub(r"[\x00-\x1f\x7f-\x9f]", "", str(value or "")).strip()


def obj(value):
    return value if isinstance(value, dict) else {}


def number(value):
    if isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value):
        return value
    return None


def shorten(text, width):
    result = ""
    used = 0
    for char in text:
        size = 0 if unicodedata.combining(char) else 2 if unicodedata.east_asian_width(char) in "WF" else 1
        if used + size > width:
            return result[:-1] + "…" if result else ""
        result += char
        used += size
    return result


def git_branch(cwd):
    try:
        def git(*args):
            return subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True,
                                  timeout=0.5, env={**os.environ, "GIT_OPTIONAL_LOCKS": "0"}).stdout.strip()
        branch = clean(git("branch", "--show-current")) or clean(git("rev-parse", "--short", "HEAD"))
        return branch or ""
    except (OSError, subprocess.TimeoutExpired):
        return ""


def quota_text(label, value):
    value = obj(value)
    remaining = number(value.get("remaining_fraction"))
    if remaining is None:
        return f"{label} --"
    result = f"{label}余{max(0, min(100, round(remaining * 100)))}%"
    seconds = number(value.get("reset_in_seconds"))
    if seconds is not None and seconds > 0:
        hours, minutes = divmod(math.ceil(seconds / 60), 60)
        if hours >= 24:
            days, hours = divmod(hours, 24)
            reset = f"{days}d{hours}h"
        else:
            reset = f"{hours}h{minutes:02d}m" if hours else f"{minutes}m"
        result += f"↻{reset}"
    return result


def render(data):
    data = obj(data)
    model = obj(data.get("model"))
    context = obj(data.get("context_window"))
    quota = obj(data.get("quota"))
    workspace = obj(data.get("workspace"))
    width = number(data.get("terminal_width")) or 100
    width = max(20, min(int(width), 500))
    name = clean(model.get("display_name") or model.get("id")) or "AGY"
    effort = clean(model.get("effort"))
    if effort and effort.lower() not in name.lower():
        name += f" ({effort})"
    used = number(context.get("used_percentage"))
    ctx = f"上下文{max(0, min(100, round(used)))}%" if used is not None else "上下文 --"
    identity = (str(model.get("id", "")) + " " + name).lower()
    third_party = any(word in identity for word in ("claude", "anthropic", "gpt", "openai"))
    prefix = "3p" if third_party else "gemini"
    weekly_key = "gemini-argon-wtu-weekly" if "argon" in identity and "gemini-argon-wtu-weekly" in quota else prefix + "-weekly"
    first = " · ".join([shorten(name, max(12, width - 20)), ctx])
    second = " · ".join([quota_text("5h", quota.get(prefix + "-5h")), quota_text("周", quota.get(weekly_key))])
    cwd = clean(workspace.get("current_dir") or data.get("cwd") or os.getcwd())
    home = str(Path.home())
    directory = "~" + cwd[len(home):] if cwd == home or cwd.startswith(home + "/") else cwd
    branch = git_branch(cwd)
    state = clean(data.get("agent_state"))
    mode = clean(data.get("cycle_mode"))
    details = [directory]
    if branch:
        details.append(branch)
    if state:
        details.append(state)
    if mode:
        details.append(mode)
    # Keep quota visible even on narrower terminals by giving it its own row.
    rows = [first + " · " + second, " · ".join(details)]
    if shorten(rows[0], width) != rows[0]:
        rows = [first, second, rows[1]]
    rows = [shorten(row, width) for row in rows]
    if "NO_COLOR" not in os.environ:
        colors = ["36", "32", "90"] if len(rows) == 3 else ["36", "90"]
        rows = [f"\033[{color}m{row}\033[0m" for color, row in zip(colors, rows)]
    return "\n".join(rows)


def main():
    try:
        data = json.load(sys.stdin)
    except (ValueError, OSError):
        data = {}
    print(render(data))


if __name__ == "__main__":
    main()
