#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
MANAGED_MARKER="Managed by sync-shared-skills"

SOURCE_SIDE="auto"
TARGET_SIDE="auto"
DRY_RUN=0
VERBOSE=0
SYNC_CONFIGS=0

CODEX_ROOT="${CODEX_HOME:-$HOME/.codex}/skills"
CLAUDE_ROOT="${CLAUDE_SKILLS_HOME:-$HOME/.claude}/skills"
HERMES_ROOT="${HERMES_SKILLS_HOME:-$HOME/.hermes/skills}/myagent"
SKILLS_LOCAL_ROOT="/home/zhanxp/projects/myagent/skills/skills-local"
SKILLS_DOWNLOAD_ROOT="/home/zhanxp/projects/myagent/skills/skills-download"

MYAGENT_ROOT="/home/zhanxp/projects/myagent"
CLAUDE_SETTINGS_RUNTIME="$HOME/.claude/settings.json"
CLAUDE_SETTINGS_SOURCE="$MYAGENT_ROOT/configs/claude-code/settings.json"
CODEX_CONFIG_RUNTIME="$HOME/.codex/config.toml"
CODEX_CONFIG_SOURCE="$MYAGENT_ROOT/configs/codex/config.toml"
MYAGENT_CONFIG_SYNC="$MYAGENT_ROOT/configs/sync.sh"

CREATED=0
UPDATED=0
UNCHANGED=0
SKIPPED=0
CONFLICTS=0

usage() {
  cat <<'EOF'
Usage:
  sync_shared_skills.sh --source <codex|claude> [--target <codex|claude|hermes>] [--dry-run] [--verbose]
  sync_shared_skills.sh --configs <backup|restore|validate> [--dry-run]

Commands:
  Skills sync (default):
    --source   Required. Select which side is the source.
    --target   Optional. Defaults to claude for codex source and codex for claude source.
               Use hermes to install shared skills under ~/.hermes/skills/myagent.
               Use skills-local to install shared skills under ~/projects/myagent/skills/skills-local.
               Use skills-download to install shared skills under ~/projects/myagent/skills/skills-download.
    --dry-run  Print planned changes without modifying files.
    --verbose  Print per-skill decisions.

  Configs sync:
    --configs  Sync Claude Code / Codex configurations.
               Subcommands: backup, restore, validate, codex-runtime-backup
    --dry-run  Print planned changes without modifying files.

Examples:
  # Sync skills from Codex to Claude Code
  sync_shared_skills.sh --source codex --dry-run --verbose

  # Sync skills from Codex to Hermes
  sync_shared_skills.sh --source codex --target hermes --dry-run --verbose

  # Sync skills from Codex to skills-local
  sync_shared_skills.sh --source codex --target skills-local --dry-run --verbose

  # Sync skills from Codex to skills-download
  sync_shared_skills.sh --source codex --target skills-download --dry-run --verbose

  # Backup runtime configs to myagent
  sync_shared_skills.sh --configs backup

  # Restore configs from myagent to runtime
  sync_shared_skills.sh --configs restore

  # Validate config formats
  sync_shared_skills.sh --configs validate

  # Back up reusable Codex runtime experience into configs/codex/runtime
  sync_shared_skills.sh --configs codex-runtime-backup
EOF
}

log() {
  printf '%s\n' "$*"
}

vlog() {
  if [[ "$VERBOSE" -eq 1 ]]; then
    log "$@"
  fi
}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN'
    for arg in "$@"; do
      printf ' %q' "$arg"
    done
    printf '\n'
    return 0
  fi

  "$@"
}

ensure_dir() {
  local path="$1"

  if [[ -d "$path" ]]; then
    return 0
  fi

  run mkdir -p "$path"
}

realpath_safe() {
  local path="$1"

  if [[ ! -e "$path" && ! -L "$path" ]]; then
    return 1
  fi

  readlink -f "$path"
}

same_target() {
  local left="$1"
  local right="$2"
  local left_real
  local right_real

  left_real="$(realpath_safe "$left" 2>/dev/null || true)"
  right_real="$(realpath_safe "$right" 2>/dev/null || true)"

  [[ -n "$left_real" && -n "$right_real" && "$left_real" == "$right_real" ]]
}

# ============================================================
# Skills sync functions
# ============================================================

is_excluded_name() {
  local name="$1"

  case "$name" in
    .system|learned|imported)
      return 0
      ;;
    ask-claude|ask-gemini)
      return 0
      ;;
    autopilot|cancel|configure-notifications|deep-interview|doctor|help|hud|note|omx-setup)
      return 0
      ;;
    plan|ralph|ralplan|skill|team|trace|ultrawork|visual-verdict|web-clone|wiki|worker)
      return 0
      ;;
  esac

  return 1
}

sync_dir_skill() {
  local name="$1"
  local source_path="$2"
  local target_root="$3"
  local target_path="$target_root/$name"

  if [[ -e "$target_path" || -L "$target_path" ]]; then
    if same_target "$target_path" "$source_path"; then
      UNCHANGED=$((UNCHANGED + 1))
      vlog "same      $name"
      return 0
    fi

    CONFLICTS=$((CONFLICTS + 1))
    log "conflict  $name -> $target_path already exists and is unmanaged"
    return 0
  fi

  ensure_dir "$target_root"
  run ln -s "$source_path" "$target_path"
  CREATED=$((CREATED + 1))
  vlog "created   $name -> symlink"
}

wrapper_description() {
  local name="$1"
  printf 'Imported flat Claude Code skill from %s.md. Use when the task matches the workflow described below or the user asks for %s-related workflow help.' "$name" "$name"
}

write_wrapper() {
  local name="$1"
  local source_file="$2"
  local target_root="$3"
  local target_dir="$target_root/$name"
  local target_file="$target_dir/SKILL.md"
  local tmp_file
  local existed_before=0

  if [[ -e "$target_dir" || -L "$target_dir" ]]; then
    existed_before=1
  fi

  if [[ "$existed_before" -eq 1 ]]; then
    if [[ -d "$target_dir" && -f "$target_file" ]] && grep -q "$MANAGED_MARKER" "$target_file"; then
      :
    else
      CONFLICTS=$((CONFLICTS + 1))
      log "conflict  $name -> $target_dir already exists and is unmanaged"
      return 0
    fi
  fi

  tmp_file="$(mktemp)"
  {
    printf '%s\n' '---'
    printf 'name: %s\n' "$name"
    printf 'description: %s\n' "$(wrapper_description "$name")"
    printf '%s\n' '---'
    printf '\n'
    printf '<!-- %s. Source: %s -->\n\n' "$MANAGED_MARKER" "$source_file"
    cat "$source_file"
  } > "$tmp_file"

  if [[ -f "$target_file" ]] && cmp -s "$tmp_file" "$target_file"; then
    rm -f "$tmp_file"
    UNCHANGED=$((UNCHANGED + 1))
    vlog "same      $name"
    return 0
  fi

  ensure_dir "$target_dir"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY-RUN write wrapper $target_file from $source_file"
    rm -f "$tmp_file"
  else
    mv "$tmp_file" "$target_file"
  fi

  if [[ "$existed_before" -eq 1 ]]; then
    UPDATED=$((UPDATED + 1))
  else
    CREATED=$((CREATED + 1))
  fi

  vlog "wrapped   $name"
}

sync_from_codex() {
  local source_root="$1"
  local target_root="$2"
  local path
  local name

  for path in "$source_root"/*; do
    [[ -d "$path" ]] || continue
    [[ -f "$path/SKILL.md" ]] || continue

    name="$(basename "$path")"

    if is_excluded_name "$name"; then
      SKIPPED=$((SKIPPED + 1))
      vlog "skipped   $name"
      continue
    fi

    sync_dir_skill "$name" "$path" "$target_root"
  done
}

sync_from_claude() {
  local source_root="$1"
  local target_root="$2"
  local path
  local name

  for path in "$source_root"/*; do
    [[ -e "$path" ]] || continue

    if [[ -d "$path" && -f "$path/SKILL.md" ]]; then
      name="$(basename "$path")"

      if is_excluded_name "$name"; then
        SKIPPED=$((SKIPPED + 1))
        vlog "skipped   $name"
        continue
      fi

      sync_dir_skill "$name" "$path" "$target_root"
      continue
    fi

    if [[ -f "$path" && "$path" == *.md ]]; then
      name="$(basename "$path" .md)"

      if [[ "$name" == "SKILL" ]] || is_excluded_name "$name"; then
        SKIPPED=$((SKIPPED + 1))
        vlog "skipped   $name"
        continue
      fi

      write_wrapper "$name" "$path" "$target_root"
    fi
  done
}

# ============================================================
# Configs sync functions
# ============================================================

validate_json() {
  local file="$1"
  if command -v jq &> /dev/null; then
    jq empty "$file" 2>/dev/null && return 0 || return 1
  else
    [[ $(head -c 1 "$file") == "{" ]] && return 0 || return 1
  fi
}

validate_toml() {
  local file="$1"
  grep -qE '^[a-zA-Z_]+\s*=|^\[' "$file" && return 0 || return 1
}

configs_validate() {
  log "Validating config formats..."
  local has_error=0

  if [[ -f "$CLAUDE_SETTINGS_SOURCE" ]]; then
    if validate_json "$CLAUDE_SETTINGS_SOURCE"; then
      log "  [OK] Claude Code settings.json"
    else
      log "  [ERROR] Claude Code settings.json format invalid"
      has_error=1
    fi
  else
    log "  [WARN] Claude Code settings.json not found: $CLAUDE_SETTINGS_SOURCE"
  fi

  if [[ -f "$CODEX_CONFIG_SOURCE" ]]; then
    if validate_toml "$CODEX_CONFIG_SOURCE"; then
      log "  [OK] Codex config.toml"
    else
      log "  [ERROR] Codex config.toml format invalid"
      has_error=1
    fi
  else
    log "  [WARN] Codex config.toml not found: $CODEX_CONFIG_SOURCE"
  fi

  if [[ $has_error -eq 0 ]]; then
    log "All validations passed."
    return 0
  else
    return 1
  fi
}

configs_backup() {
  log "Backing up runtime configs to myagent..."

  ensure_dir "$(dirname "$CLAUDE_SETTINGS_SOURCE")"
  ensure_dir "$(dirname "$CODEX_CONFIG_SOURCE")"

  if [[ -f "$CLAUDE_SETTINGS_RUNTIME" ]]; then
    run cp "$CLAUDE_SETTINGS_RUNTIME" "$CLAUDE_SETTINGS_SOURCE"
    log "  [OK] Claude Code config backed up to $CLAUDE_SETTINGS_SOURCE"
    log "  [WARN] Please review and sanitize sensitive data before committing"
  else
    log "  [WARN] Claude Code runtime config not found: $CLAUDE_SETTINGS_RUNTIME"
  fi

  if [[ -f "$CODEX_CONFIG_RUNTIME" ]]; then
    run cp "$CODEX_CONFIG_RUNTIME" "$CODEX_CONFIG_SOURCE"
    log "  [OK] Codex config backed up to $CODEX_CONFIG_SOURCE"
  else
    log "  [WARN] Codex runtime config not found: $CODEX_CONFIG_RUNTIME"
  fi
}

configs_restore() {
  log "Restoring configs from myagent to runtime directories..."

  if [[ -f "$CLAUDE_SETTINGS_SOURCE" ]]; then
    if [[ -f "$CLAUDE_SETTINGS_RUNTIME" ]]; then
      run cp "$CLAUDE_SETTINGS_RUNTIME" "$CLAUDE_SETTINGS_RUNTIME.bak.$(date +%Y%m%d_%H%M%S)"
      log "  [OK] Claude Code runtime config backed up"
    fi
    run cp "$CLAUDE_SETTINGS_SOURCE" "$CLAUDE_SETTINGS_RUNTIME"
    log "  [OK] Claude Code config restored to $CLAUDE_SETTINGS_RUNTIME"
  else
    log "  [ERROR] Source config not found: $CLAUDE_SETTINGS_SOURCE"
    return 1
  fi

  if [[ -f "$CODEX_CONFIG_SOURCE" ]]; then
    if [[ -f "$CODEX_CONFIG_RUNTIME" ]]; then
      run cp "$CODEX_CONFIG_RUNTIME" "$CODEX_CONFIG_RUNTIME.bak.$(date +%Y%m%d_%H%M%S)"
      log "  [OK] Codex runtime config backed up"
    fi
    run cp "$CODEX_CONFIG_SOURCE" "$CODEX_CONFIG_RUNTIME"
    log "  [OK] Codex config restored to $CODEX_CONFIG_RUNTIME"
  else
    log "  [ERROR] Source config not found: $CODEX_CONFIG_SOURCE"
    return 1
  fi
}

configs_codex_runtime_backup() {
  log "Backing up reusable Codex runtime experience to myagent..."

  if [[ ! -x "$MYAGENT_CONFIG_SYNC" ]]; then
    die "Config sync script not found or not executable: $MYAGENT_CONFIG_SYNC"
  fi

  run bash "$MYAGENT_CONFIG_SYNC" codex-backup-runtime
}

configs_sync() {
  local subcmd="${1:-validate}"

  case "$subcmd" in
    validate)
      configs_validate
      ;;
    backup)
      configs_backup
      ;;
    restore)
      configs_restore
      ;;
    codex-runtime-backup|codex-backup-runtime|runtime-backup)
      configs_codex_runtime_backup
      ;;
    *)
      die "Unknown configs subcommand: $subcmd. Use: backup, restore, validate, codex-runtime-backup"
      ;;
  esac
}

# ============================================================
# Main
# ============================================================

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      [[ $# -ge 2 ]] || die "--source requires a value"
      SOURCE_SIDE="$2"
      shift 2
      ;;
    --target)
      [[ $# -ge 2 ]] || die "--target requires a value"
      TARGET_SIDE="$2"
      shift 2
      ;;
    --configs)
      SYNC_CONFIGS=1
      if [[ $# -ge 2 && ! "$2" =~ ^-- ]]; then
        CONFIGS_CMD="$2"
        shift 2
      else
        CONFIGS_CMD="validate"
        shift
      fi
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --verbose)
      VERBOSE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "Unknown argument: $1"
      ;;
  esac
done

# Configs sync mode
if [[ "$SYNC_CONFIGS" -eq 1 ]]; then
  configs_sync "${CONFIGS_CMD:-validate}"
  exit 0
fi

# Skills sync mode
case "$SOURCE_SIDE" in
  codex)
    SOURCE_ROOT="$CODEX_ROOT"
    if [[ "$TARGET_SIDE" == "auto" ]]; then
      TARGET_SIDE="claude"
    fi
    ;;
  claude)
    SOURCE_ROOT="$CLAUDE_ROOT"
    if [[ "$TARGET_SIDE" == "auto" ]]; then
      TARGET_SIDE="codex"
    fi
    ;;
  skills-local)
    SOURCE_ROOT="$SKILLS_LOCAL_ROOT"
    if [[ "$TARGET_SIDE" == "auto" ]]; then
      TARGET_SIDE="all"
    fi
    ;;
  skills-download)
    SOURCE_ROOT="$SKILLS_DOWNLOAD_ROOT"
    if [[ "$TARGET_SIDE" == "auto" ]]; then
      TARGET_SIDE="all"
    fi
    ;;
  *)
    die "--source must be codex, claude, skills-local, or skills-download"
    ;;
esac

case "$TARGET_SIDE" in
  codex)
    TARGET_ROOT="$CODEX_ROOT"
    ;;
  claude)
    TARGET_ROOT="$CLAUDE_ROOT"
    ;;
  hermes)
    TARGET_ROOT="$HERMES_ROOT"
    ;;
  skills-local)
    TARGET_ROOT="$SKILLS_LOCAL_ROOT"
    ;;
  skills-download)
    TARGET_ROOT="$SKILLS_DOWNLOAD_ROOT"
    ;;
  all)
    :
    ;;
  *)
    die "--target must be codex, claude, hermes, skills-local, skills-download, or all"
    ;;
esac

if [[ "$SOURCE_SIDE" == "$TARGET_SIDE" ]]; then
  die "--source and --target cannot be the same side"
fi

if [[ "$TARGET_SIDE" == "all" ]]; then
  [[ -d "$SOURCE_ROOT" ]] || die "Source root does not exist: $SOURCE_ROOT"

  local_targets=()
  for candidate in codex claude hermes skills-local skills-download; do
    [[ "$candidate" != "$SOURCE_SIDE" ]] || continue
    # skills-local and skills-download are independent source pools; do not cross-sync
    [[ "$SOURCE_SIDE" == "skills-local" && "$candidate" == "skills-download" ]] && continue
    [[ "$SOURCE_SIDE" == "skills-download" && "$candidate" == "skills-local" ]] && continue
    local_targets+=("$candidate")
  done

  for target in "${local_targets[@]}"; do
    echo ""
    log "=== Sync $SOURCE_SIDE -> $target ==="
    bash "$0" --source "$SOURCE_SIDE" --target "$target" ${DRY_RUN:+--dry-run} ${VERBOSE:+--verbose}
  done
  exit 0
fi

[[ -d "$SOURCE_ROOT" ]] || die "Source root does not exist: $SOURCE_ROOT"
ensure_dir "$TARGET_ROOT"

log "Source ($SOURCE_SIDE): $SOURCE_ROOT"
log "Target ($TARGET_SIDE): $TARGET_ROOT"

if [[ "$SOURCE_SIDE" == "codex" ]]; then
  sync_from_codex "$SOURCE_ROOT" "$TARGET_ROOT"
else
  sync_from_claude "$SOURCE_ROOT" "$TARGET_ROOT"
fi

log "Summary: created=$CREATED updated=$UPDATED unchanged=$UNCHANGED skipped=$SKIPPED conflicts=$CONFLICTS"

if [[ "$TARGET_SIDE" == "hermes" ]]; then
  log "Hermes note: restart Hermes or clear its skill prompt cache if an existing session does not see new skills."
fi
