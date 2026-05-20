#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash scripts/cc-switch-run.sh doctor
  bash scripts/cc-switch-run.sh [--auto|--windows|--wsl|--home <path>] <cc-switch args...>

Modes:
  --auto     Prefer the home with the larger provider count
  --windows  Force /mnt/c/Users/<user> as HOME when available
  --wsl      Force the current WSL HOME
  --home     Force an explicit HOME, useful for isolated worker homes

Examples:
  bash scripts/cc-switch-run.sh doctor
  bash scripts/cc-switch-run.sh --windows provider list
  bash scripts/cc-switch-run.sh --windows --app codex provider current
  bash scripts/cc-switch-run.sh --home /home/zhanxp/.agents/bdcc1 --app claude provider current
EOF
}

linux_home="${HOME}"
windows_user="${CC_SWITCH_WINDOWS_USER:-${USER}}"
windows_home="/mnt/c/Users/${windows_user}"

is_wsl() {
  if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
    return 0
  fi

  grep -qiE 'microsoft|wsl' /proc/sys/kernel/osrelease 2>/dev/null
}

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
  local linux_count windows_count

  if ! is_wsl || [[ ! -d "$windows_home/.cc-switch" ]]; then
    echo "$linux_home"
    return
  fi

  linux_count="$(count_providers "$linux_home")"
  windows_count="$(count_providers "$windows_home")"

  if (( windows_count > linux_count )); then
    echo "$windows_home"
  else
    echo "$linux_home"
  fi
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
    target_label="windows"
  else
    target_label="wsl"
  fi

  cat <<EOF
WSL HOME:           $linux_home
WSL DB:             $(db_path "$linux_home")
WSL DB exists:      $(db_exists "$linux_home" && echo yes || echo no)
WSL provider total: $linux_count
Windows HOME:       $windows_home
Windows DB:         $(db_path "$windows_home")
Windows DB exists:  $(db_exists "$windows_home" && echo yes || echo no)
Windows providers:  $windows_count
Recommended mode:   $target_label

Hint:
  - Use --windows when the Windows cc-switch app is the source of truth.
  - Use --wsl when you intentionally manage the WSL-local cc-switch database.
EOF
}

mode="auto"
if [[ $# -gt 0 ]]; then
  case "$1" in
    --auto)
      mode="auto"
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
      echo "error: --windows is intended for WSL sessions." >&2
      exit 1
    fi
    if [[ ! -d "$windows_home/.cc-switch" ]]; then
      echo "error: Windows cc-switch home not found at $windows_home/.cc-switch" >&2
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

echo "info: using HOME=$target_home" >&2
HOME="$target_home" cc-switch "$@"
