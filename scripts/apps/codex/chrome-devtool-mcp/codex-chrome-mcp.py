# Codex Chrome DevTools MCP mode switcher for Windows.

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


MODE_TO_ARGS = {
    "auto": [
        "/c",
        "npx",
        "chrome-devtools-mcp@latest",
        "--autoConnect",
    ],
    "fixed": [
        "/c",
        "npx",
        "chrome-devtools-mcp@latest",
        "--browser-url=http://127.0.0.1:9222",
    ],
}

USAGE = (
    "Usage: codex-chrome-mcp.py [auto|fixed] [additional Codex args...]\n"
    "  auto  - let chrome-devtools-mcp auto-connect to an available Chrome target\n"
    "  fixed - attach to http://127.0.0.1:9222\n"
)


def build_config_override(mode: str) -> str:
    mcp_args = ",".join(f"'{arg}'" for arg in MODE_TO_ARGS[mode])
    return f"mcp_servers.chrome-devtools.args=[{mcp_args}]"


def resolve_codex_command() -> str | None:
    return shutil.which("codex")


def main(argv: list[str]) -> int:
    mode = "auto"
    passthrough_args = argv

    if argv:
        candidate = argv[0].lower()
        if candidate in MODE_TO_ARGS:
            mode = candidate
            passthrough_args = argv[1:]
        else:
            sys.stderr.write(USAGE)
            return 2

    codex_command = resolve_codex_command()
    if codex_command is None:
        sys.stderr.write("Error: 'codex' was not found in PATH.\n")
        return 127

    command = [
        codex_command,
        "-c",
        build_config_override(mode),
        *passthrough_args,
    ]

    completed = subprocess.run(command)
    return completed.returncode


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
