#!/usr/bin/env python3
"""Update Claude-to-IM Telegram config and optionally restart the daemon."""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import stat
import subprocess
import tempfile
import urllib.error
import urllib.request


CONFIG_PATH = pathlib.Path.home() / ".claude-to-im" / "config.env"
CLAUDE_TO_IM_ROOT = pathlib.Path("/home/zhanxp/projects/myagent/skills/claude-to-im")
DAEMON_SCRIPT = CLAUDE_TO_IM_ROOT / "scripts" / "daemon.sh"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--token", required=True, help="Telegram bot token")
    parser.add_argument("--chat-id", required=True, help="Telegram chat id")
    parser.add_argument("--allowed-users", default="", help="Comma-separated Telegram user ids")
    parser.add_argument("--restart", action="store_true", help="Restart claude-to-im after config update")
    parser.add_argument("--config", default=str(CONFIG_PATH), help="Path to config.env")
    return parser.parse_args()


def validate_token(token: str) -> dict:
    url = f"https://api.telegram.org/bot{token}/getMe"
    try:
        with urllib.request.urlopen(url, timeout=15) as response:
            payload = response.read().decode("utf-8")
    except urllib.error.URLError as exc:
        raise SystemExit(f"Telegram validation failed: {exc}") from exc

    data = json.loads(payload)
    if not data.get("ok"):
        raise SystemExit("Telegram validation failed: getMe returned ok=false")
    return data["result"]


def mask_token(token: str) -> str:
    if len(token) <= 8:
        return "*" * len(token)
    return f"{token[:4]}...{token[-4:]}"


def update_enabled_channels(existing: str) -> str:
    parts = [part.strip() for part in existing.split(",") if part.strip()]
    if "telegram" not in parts:
        parts.append("telegram")
    return ",".join(parts) if parts else "telegram"


def rewrite_config(path: pathlib.Path, token: str, chat_id: str, allowed_users: str) -> None:
    if not path.exists():
        raise SystemExit(f"Config file not found: {path}")

    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    replacements = {
        "CTI_TG_BOT_TOKEN": token,
        "CTI_TG_CHAT_ID": chat_id,
    }
    if allowed_users:
        replacements["CTI_TG_ALLOWED_USERS"] = allowed_users

    seen: set[str] = set()
    new_lines: list[str] = []
    for line in lines:
        stripped = line.strip()
        if "=" not in line or stripped.startswith("#"):
            new_lines.append(line)
            continue

        key, _, value = line.partition("=")
        key = key.strip()
        if key == "CTI_ENABLED_CHANNELS":
            new_lines.append(f"CTI_ENABLED_CHANNELS={update_enabled_channels(value.strip())}")
            seen.add(key)
            continue
        if key in replacements:
            new_lines.append(f"{key}={replacements[key]}")
            seen.add(key)
            continue
        new_lines.append(line)

    if "CTI_ENABLED_CHANNELS" not in seen:
        new_lines.append("CTI_ENABLED_CHANNELS=telegram")
    for key, value in replacements.items():
        if key not in seen:
            new_lines.append(f"{key}={value}")

    with tempfile.NamedTemporaryFile("w", delete=False, encoding="utf-8") as tmp:
        tmp.write("\n".join(new_lines) + "\n")
        tmp_path = pathlib.Path(tmp.name)

    tmp_path.replace(path)
    path.chmod(stat.S_IRUSR | stat.S_IWUSR)


def restart_bridge() -> None:
    if not DAEMON_SCRIPT.exists():
        raise SystemExit(f"Daemon script not found: {DAEMON_SCRIPT}")
    subprocess.run(["bash", str(DAEMON_SCRIPT), "stop"], check=False)
    subprocess.run(["bash", str(DAEMON_SCRIPT), "start"], check=True)


def main() -> None:
    args = parse_args()
    config_path = pathlib.Path(os.path.expanduser(args.config))
    bot_info = validate_token(args.token)
    rewrite_config(config_path, args.token, args.chat_id, args.allowed_users)
    if args.restart:
        restart_bridge()

    username = bot_info.get("username", "<unknown>")
    print(f"Updated Telegram bridge config: {config_path}")
    print(f"Bot username: @{username}")
    print(f"Bot token: {mask_token(args.token)}")
    print(f"Chat ID: {args.chat_id}")
    if args.allowed_users:
        print(f"Allowed users: {args.allowed_users}")
    print(f"Restarted bridge: {'yes' if args.restart else 'no'}")


if __name__ == "__main__":
    main()
