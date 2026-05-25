#!/usr/bin/env python3
"""Safe inventory and reviewed move-plan helper for document folders."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import shutil
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable


INDEX_DIR_NAME = "00_资料索引"


@dataclass
class InventoryItem:
    relpath: str
    kind: str
    size_bytes: int
    mtime: str
    sha256: str
    duplicate_group: str


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Safely inventory and apply reviewed document-folder move plans.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    inventory_parser = subparsers.add_parser("inventory", help="Create non-destructive inventory and duplicate reports.")
    inventory_parser.add_argument("root", help="Folder to inspect. Windows drive paths are mapped to /mnt/<drive> on WSL.")
    inventory_parser.add_argument("--output-dir", default=INDEX_DIR_NAME, help="Output directory, relative to root by default.")
    inventory_parser.add_argument("--recursive", action="store_true", help="Inventory all descendants instead of top-level entries.")
    inventory_parser.add_argument("--include-hidden", action="store_true", help="Include dotfiles and hidden-looking entries.")
    inventory_parser.add_argument("--no-hash", action="store_true", help="Skip SHA-256 hashes and duplicate grouping.")
    inventory_parser.set_defaults(func=inventory_command)

    apply_parser = subparsers.add_parser("apply-plan", help="Validate or execute a reviewed JSON move plan.")
    apply_parser.add_argument("plan", help="Move plan JSON path.")
    apply_parser.add_argument("--execute", action="store_true", help="Actually move files. Without this, only dry-run.")
    apply_parser.set_defaults(func=apply_plan_command)

    args = parser.parse_args(argv)
    return args.func(args)


def inventory_command(args: argparse.Namespace) -> int:
    root = resolve_input_path(args.root)
    if not root.is_dir():
        raise SystemExit(f"Root is not a directory: {root}")

    output_dir = resolve_output_dir(root, args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    items = collect_inventory(
        root=root,
        output_dir=output_dir,
        recursive=args.recursive,
        include_hidden=args.include_hidden,
        hash_files=not args.no_hash,
    )
    assign_duplicate_groups(items)

    inventory_path = output_dir / f"inventory-{timestamp}.csv"
    duplicates_path = output_dir / f"duplicates-{timestamp}.csv"
    index_path = output_dir / f"index-{timestamp}.md"
    summary_path = output_dir / f"summary-{timestamp}.json"

    write_inventory_csv(inventory_path, items)
    duplicate_rows = write_duplicates_csv(duplicates_path, items)
    write_index(index_path, root, items, duplicate_rows, args.recursive)
    write_summary(summary_path, root, items, duplicate_rows, inventory_path, duplicates_path, index_path)

    print(f"Root: {root}")
    print(f"Inventory: {inventory_path}")
    print(f"Duplicates: {duplicates_path}")
    print(f"Index: {index_path}")
    print(f"Summary: {summary_path}")
    print(
        "Counts: "
        f"files={sum(1 for item in items if item.kind == 'file')} "
        f"dirs={sum(1 for item in items if item.kind == 'dir')} "
        f"duplicate_files={len(duplicate_rows)}"
    )
    return 0


def apply_plan_command(args: argparse.Namespace) -> int:
    plan_path = resolve_input_path(args.plan)
    if not plan_path.is_file():
        raise SystemExit(f"Plan is not a file: {plan_path}")

    with plan_path.open("r", encoding="utf-8") as handle:
        plan = json.load(handle)

    root_value = plan.get("root")
    if not isinstance(root_value, str) or not root_value.strip():
        raise SystemExit("Plan must contain a non-empty string field: root")
    root = resolve_input_path(root_value)
    if not root.is_dir():
        raise SystemExit(f"Plan root is not a directory: {root}")

    moves = plan.get("moves")
    if not isinstance(moves, list):
        raise SystemExit("Plan must contain a list field: moves")

    prepared = [prepare_move(root, raw_move, index) for index, raw_move in enumerate(moves, start=1)]
    validate_prepared_moves(prepared)

    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    log_dir = root / INDEX_DIR_NAME
    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / f"move-log-{timestamp}.csv"

    for move in prepared:
        if args.execute:
            move.target.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(move.source), str(move.target))
        action = "moved" if args.execute else "would-move"
        print(f"{action}: {move.source.relative_to(root)} -> {move.target.relative_to(root)}")

    write_move_log(log_path, prepared, executed=args.execute)
    print(f"Move log: {log_path}")
    print("Mode: execute" if args.execute else "Mode: dry-run")
    return 0


def resolve_input_path(value: str) -> Path:
    value = value.strip()
    match = re.match(r"^([A-Za-z]):[\\/](.*)$", value)
    if os.name != "nt" and match:
        drive = match.group(1).lower()
        rest = match.group(2).replace("\\", "/")
        return Path("/mnt") / drive / rest
    return Path(value).expanduser().resolve()


def resolve_output_dir(root: Path, value: str) -> Path:
    path = Path(value).expanduser()
    if path.is_absolute():
        return path
    return root / path


def collect_inventory(
    root: Path,
    output_dir: Path,
    recursive: bool,
    include_hidden: bool,
    hash_files: bool,
) -> list[InventoryItem]:
    output_dir_resolved = output_dir.resolve()
    paths: Iterable[Path]
    if recursive:
        paths = root.rglob("*")
    else:
        paths = root.iterdir()

    items: list[InventoryItem] = []
    for path in sorted(paths, key=lambda item: item.relative_to(root).as_posix().lower()):
        if path.resolve() == output_dir_resolved or output_dir_resolved in path.resolve().parents:
            continue
        relpath = path.relative_to(root).as_posix()
        if not include_hidden and any(part.startswith(".") for part in Path(relpath).parts):
            continue
        try:
            stat = path.stat()
        except OSError:
            continue
        kind = "dir" if path.is_dir() else "file" if path.is_file() else "other"
        digest = sha256_file(path) if hash_files and path.is_file() else ""
        items.append(
            InventoryItem(
                relpath=relpath,
                kind=kind,
                size_bytes=stat.st_size if path.is_file() else 0,
                mtime=datetime.fromtimestamp(stat.st_mtime).isoformat(timespec="seconds"),
                sha256=digest,
                duplicate_group="",
            )
        )
    return items


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def assign_duplicate_groups(items: list[InventoryItem]) -> None:
    groups: dict[tuple[str, int], list[InventoryItem]] = {}
    for item in items:
        if item.kind == "file" and item.sha256:
            groups.setdefault((item.sha256, item.size_bytes), []).append(item)
    group_index = 1
    for _, group_items in sorted(groups.items(), key=lambda entry: (entry[0][1], entry[0][0])):
        if len(group_items) < 2:
            continue
        group_id = f"D{group_index:03d}"
        group_index += 1
        for item in sorted(group_items, key=lambda entry: entry.relpath.lower()):
            item.duplicate_group = group_id


def write_inventory_csv(path: Path, items: list[InventoryItem]) -> None:
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["relpath", "kind", "size_bytes", "mtime", "sha256", "duplicate_group"])
        for item in items:
            writer.writerow([item.relpath, item.kind, item.size_bytes, item.mtime, item.sha256, item.duplicate_group])


def write_duplicates_csv(path: Path, items: list[InventoryItem]) -> list[InventoryItem]:
    duplicates = [item for item in items if item.duplicate_group]
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["duplicate_group", "relpath", "size_bytes", "sha256", "keep_candidate"])
        for group_id in sorted({item.duplicate_group for item in duplicates}):
            group_items = sorted((item for item in duplicates if item.duplicate_group == group_id), key=lambda item: item.relpath.lower())
            for index, item in enumerate(group_items):
                writer.writerow([item.duplicate_group, item.relpath, item.size_bytes, item.sha256, "yes" if index == 0 else "no"])
    return duplicates


def write_index(path: Path, root: Path, items: list[InventoryItem], duplicates: list[InventoryItem], recursive: bool) -> None:
    files = [item for item in items if item.kind == "file"]
    dirs = [item for item in items if item.kind == "dir"]
    duplicate_groups = sorted({item.duplicate_group for item in duplicates})
    top_extensions: dict[str, int] = {}
    for item in files:
        suffix = Path(item.relpath).suffix.lower() or "(no extension)"
        top_extensions[suffix] = top_extensions.get(suffix, 0) + 1

    lines = [
        "# 资料索引",
        "",
        f"- Root: `{root}`",
        f"- Scope: {'recursive' if recursive else 'top-level'}",
        f"- Files: {len(files)}",
        f"- Directories: {len(dirs)}",
        f"- Duplicate groups: {len(duplicate_groups)}",
        f"- Duplicate files: {len(duplicates)}",
        "",
        "## Extensions",
        "",
    ]
    for suffix, count in sorted(top_extensions.items(), key=lambda entry: (-entry[1], entry[0]))[:20]:
        lines.append(f"- `{suffix}`: {count}")
    if duplicate_groups:
        lines.extend(["", "## Duplicate Groups", ""])
        for group_id in duplicate_groups[:50]:
            group_items = [item for item in duplicates if item.duplicate_group == group_id]
            lines.append(f"- {group_id}:")
            for item in group_items:
                lines.append(f"  - `{item.relpath}`")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_summary(
    path: Path,
    root: Path,
    items: list[InventoryItem],
    duplicates: list[InventoryItem],
    inventory_path: Path,
    duplicates_path: Path,
    index_path: Path,
) -> None:
    summary = {
        "root": str(root),
        "files": sum(1 for item in items if item.kind == "file"),
        "directories": sum(1 for item in items if item.kind == "dir"),
        "duplicate_files": len(duplicates),
        "duplicate_groups": len({item.duplicate_group for item in duplicates}),
        "outputs": {
            "inventory_csv": str(inventory_path),
            "duplicates_csv": str(duplicates_path),
            "index_md": str(index_path),
        },
    }
    path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


@dataclass
class PreparedMove:
    source: Path
    target: Path
    reason: str


def prepare_move(root: Path, raw_move: Any, index: int) -> PreparedMove:
    if not isinstance(raw_move, dict):
        raise SystemExit(f"Move #{index} must be an object")
    source_value = raw_move.get("source")
    target_value = raw_move.get("target")
    reason = str(raw_move.get("reason") or "")
    if not isinstance(source_value, str) or not source_value.strip():
        raise SystemExit(f"Move #{index} has invalid source")
    if not isinstance(target_value, str) or not target_value.strip():
        raise SystemExit(f"Move #{index} has invalid target")
    source = safe_child_path(root, source_value, f"Move #{index} source")
    target = safe_child_path(root, target_value, f"Move #{index} target")
    if source == target:
        raise SystemExit(f"Move #{index} source and target are the same: {source_value}")
    if not source.exists():
        raise SystemExit(f"Move #{index} source does not exist: {source}")
    if target.exists():
        raise SystemExit(f"Move #{index} target already exists: {target}")
    return PreparedMove(source=source, target=target, reason=reason)


def safe_child_path(root: Path, value: str, label: str) -> Path:
    raw = Path(value)
    if raw.is_absolute():
        raise SystemExit(f"{label} must be relative to root: {value}")
    candidate = (root / raw).resolve()
    try:
        candidate.relative_to(root)
    except ValueError as exc:
        raise SystemExit(f"{label} escapes root: {value}") from exc
    return candidate


def validate_prepared_moves(moves: list[PreparedMove]) -> None:
    targets: set[Path] = set()
    sources: set[Path] = set()
    for move in moves:
        if move.source in sources:
            raise SystemExit(f"Duplicate source in move plan: {move.source}")
        sources.add(move.source)
        if move.target in targets:
            raise SystemExit(f"Duplicate target in move plan: {move.target}")
        targets.add(move.target)


def write_move_log(path: Path, moves: list[PreparedMove], executed: bool) -> None:
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["status", "source", "target", "reason"])
        status = "moved" if executed else "would-move"
        for move in moves:
            writer.writerow([status, str(move.source), str(move.target), move.reason])


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BrokenPipeError:
        raise SystemExit(1)
