#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash scripts/cc-switch-run.sh doctor
  bash scripts/cc-switch-run.sh [--auto|--gui|--windows|--wsl|--home <path>] <cc-switch args...>

Modes:
  --auto     Prefer the Windows GUI cc-switch home when available
  --gui      Force the Windows GUI cc-switch home when available
  --windows  Compatibility alias for --gui
  --wsl      Force the current WSL HOME
  --home     Force an explicit HOME, useful for isolated worker homes

Examples:
  bash scripts/cc-switch-run.sh doctor
  bash scripts/cc-switch-run.sh provider list
  bash scripts/cc-switch-run.sh --gui --app codex provider current
  bash scripts/cc-switch-run.sh --gui print-home
  bash scripts/cc-switch-run.sh --home /home/zhanxp/.agents/bdcc1 --app claude provider current
EOF
}

linux_home="${HOME}"
windows_user="${CC_SWITCH_WINDOWS_USER:-${USER}}"
windows_profile="/mnt/c/Users/${windows_user}"
windows_store_path="${windows_profile}/AppData/Roaming/com.ccswitch.desktop/app_paths.json"

is_wsl() {
  if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
    return 0
  fi

  grep -qiE 'microsoft|wsl' /proc/sys/kernel/osrelease 2>/dev/null
}

windows_path_to_wsl_home() {
  local raw_path="$1"

  python3 - "$raw_path" <<'PY'
import os
import re
import sys

path = sys.argv[1].strip().strip('"')
path = path.rstrip("\\/")

def config_dir_to_home(candidate: str) -> str:
    candidate = candidate.rstrip("/")
    if os.path.basename(candidate) == ".cc-switch":
        return os.path.dirname(candidate)
    return candidate

if not path:
    raise SystemExit(1)

drive_match = re.match(r"^([A-Za-z]):[\\/](.*)$", path)
if drive_match:
    drive = drive_match.group(1).lower()
    rest = drive_match.group(2).replace("\\", "/")
    print(config_dir_to_home(f"/mnt/{drive}/{rest}"))
    raise SystemExit(0)

unc_match = re.match(r"^\\\\(?:wsl\.localhost|wsl\$)\\[^\\]+\\(.+)$", path, flags=re.I)
if unc_match:
    print(config_dir_to_home("/" + unc_match.group(1).replace("\\", "/")))
    raise SystemExit(0)

if path.startswith("/"):
    print(config_dir_to_home(path))
    raise SystemExit(0)

raise SystemExit(1)
PY
}

detect_windows_gui_home() {
  local fallback="${windows_profile}"
  local override=""

  if [[ -f "$windows_store_path" ]]; then
    override="$(
      python3 - "$windows_store_path" <<'PY' 2>/dev/null || true
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    raise SystemExit(0)

value = data.get("app_config_dir_override")
if value:
    print(value)
PY
    )"
  fi

  if [[ -n "$override" ]]; then
    if windows_path_to_wsl_home "$override"; then
      return
    fi
  fi

  printf '%s\n' "$fallback"
}

windows_home="$(detect_windows_gui_home)"

db_path() {
  local target_home="$1"
  printf '%s/.cc-switch/cc-switch.db\n' "$target_home"
}

db_exists() {
  local target_home="$1"
  [[ -f "$(db_path "$target_home")" ]]
}

count_providers() {
  local target_home="$1"

  if ! db_exists "$target_home"; then
    echo 0
    return
  fi

  HOME="$target_home" cc-switch config validate 2>/dev/null |
    awk '
      /Claude providers:/ { sum += $NF }
      /Codex providers:/ { sum += $NF }
      /Gemini providers:/ { sum += $NF }
      END { print sum + 0 }
    '
}

recommended_home() {
  if ! is_wsl || [[ ! -d "$windows_home/.cc-switch" ]]; then
    echo "$linux_home"
    return
  fi

  echo "$windows_home"
}

doctor() {
  local linux_count windows_count recommended target_label

  linux_count="$(count_providers "$linux_home")"
  if [[ -d "$windows_home/.cc-switch" ]]; then
    windows_count="$(count_providers "$windows_home")"
  else
    windows_count=0
  fi

  recommended="$(recommended_home)"
  if [[ "$recommended" == "$windows_home" ]]; then
    target_label="gui"
  else
    target_label="wsl"
  fi

  cat <<EOF
WSL HOME:           $linux_home
WSL DB:             $(db_path "$linux_home")
WSL DB exists:      $(db_exists "$linux_home" && echo yes || echo no)
WSL provider total: $linux_count
Windows HOME:       $windows_home
Windows Store:      $windows_store_path
Windows DB:         $(db_path "$windows_home")
Windows DB exists:  $(db_exists "$windows_home" && echo yes || echo no)
Windows providers:  $windows_count
Recommended mode:   $target_label

Hint:
  - Default/--auto uses the Windows GUI cc-switch home when it exists.
  - Use --wsl only when you intentionally manage the WSL-local cc-switch database.
  - Use --home for isolated worker homes such as bdcc1/bdcc2.
EOF
}

mode="auto"
if [[ $# -gt 0 ]]; then
  case "$1" in
    --auto)
      mode="auto"
      shift
      ;;
    --gui)
      mode="windows"
      shift
      ;;
    --windows)
      mode="windows"
      shift
      ;;
    --wsl)
      mode="wsl"
      shift
      ;;
    --home)
      mode="home"
      shift
      if [[ $# -eq 0 ]]; then
        echo "error: --home requires a path" >&2
        exit 1
      fi
      explicit_home="$1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
  esac
fi

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

if [[ "$1" == "doctor" ]]; then
  doctor
  exit 0
fi

case "$mode" in
  auto)
    target_home="$(recommended_home)"
    ;;
  windows)
    if ! is_wsl; then
      echo "error: --gui/--windows is intended for WSL sessions." >&2
      exit 1
    fi
    if [[ ! -d "$windows_home/.cc-switch" ]]; then
      echo "error: Windows GUI cc-switch home not found at $windows_home/.cc-switch" >&2
      exit 1
    fi
    target_home="$windows_home"
    ;;
  wsl)
    target_home="$linux_home"
    ;;
  home)
    if [[ ! -d "${explicit_home:-}" ]]; then
      echo "error: explicit HOME not found at ${explicit_home:-}" >&2
      exit 1
    fi
    target_home="$explicit_home"
    ;;
  *)
    echo "error: unsupported mode $mode" >&2
    exit 1
    ;;
esac

if [[ "$1" == "print-home" ]]; then
  printf '%s\n' "$target_home"
  exit 0
fi

echo "info: using HOME=$target_home" >&2
HOME="$target_home" cc-switch "$@"
