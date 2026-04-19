#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
MANAGED_MARKER="Managed by sync-shared-skills"

SOURCE_SIDE="auto"
DRY_RUN=0
VERBOSE=0

CODEX_ROOT="${CODEX_HOME:-$HOME/.codex}/skills"
CLAUDE_ROOT="${CLAUDE_SKILLS_HOME:-$HOME/.claude/skills}"

CREATED=0
UPDATED=0
UNCHANGED=0
SKIPPED=0
CONFLICTS=0

usage() {
  cat <<'EOF'
Usage:
  sync_shared_skills.sh --source <codex|claude> [--dry-run] [--verbose]

Options:
  --source   Required. Select which side is the source.
  --dry-run  Print planned changes without modifying files.
  --verbose  Print per-skill decisions.
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      [[ $# -ge 2 ]] || die "--source requires a value"
      SOURCE_SIDE="$2"
      shift 2
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

case "$SOURCE_SIDE" in
  codex)
    SOURCE_ROOT="$CODEX_ROOT"
    TARGET_ROOT="$CLAUDE_ROOT"
    ;;
  claude)
    SOURCE_ROOT="$CLAUDE_ROOT"
    TARGET_ROOT="$CODEX_ROOT"
    ;;
  *)
    die "--source must be codex or claude"
    ;;
esac

[[ -d "$SOURCE_ROOT" ]] || die "Source root does not exist: $SOURCE_ROOT"
ensure_dir "$TARGET_ROOT"

log "Source: $SOURCE_ROOT"
log "Target: $TARGET_ROOT"

if [[ "$SOURCE_SIDE" == "codex" ]]; then
  sync_from_codex "$SOURCE_ROOT" "$TARGET_ROOT"
else
  sync_from_claude "$SOURCE_ROOT" "$TARGET_ROOT"
fi

log "Summary: created=$CREATED updated=$UPDATED unchanged=$UNCHANGED skipped=$SKIPPED conflicts=$CONFLICTS"
