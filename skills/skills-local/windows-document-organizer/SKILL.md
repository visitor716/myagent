---
name: windows-document-organizer
description: Safely organize Windows-mounted document folders from WSL with dry-run inventories, exact duplicate detection, content-assisted classification, reviewed move plans, traceable indexes, and non-destructive file moves. Use when the user asks to 整理资料, 整理目录, classify a D:\ or /mnt drive work folder, deduplicate documents, preserve existing curated subtrees, generate 00_资料索引 logs, or clean up mixed Office/PDF/image/project files without deleting originals.
---

# Windows Document Organizer

## Overview

Use this skill to organize messy Windows-mounted document folders from WSL without deleting data. The standard result is a reviewed move plan, thematic folders, `00_资料索引/` logs, exact duplicates separated into `99_重复文件`, and uncertain files kept in `98_待识别` until content inspection gives enough evidence.

## Workflow

1. Resolve the target path first. Convert Windows drive paths such as `D:\Work\资料` to `/mnt/d/Work/资料`; for UNC paths, verify the exact WSL mapping before touching files.
2. Run a non-destructive inventory:

```bash
python3 ~/.codex/skills/windows-document-organizer/scripts/document_organizer.py inventory /mnt/d/path/to/folder
```

3. Read the generated files under `00_资料索引/`:
   - `inventory-*.csv`: top-level file/directory inventory with size, mtime, and hash when available
   - `duplicates-*.csv`: exact duplicate groups by SHA-256
   - `index-*.md`: concise human-readable summary
   - `summary-*.json`: machine-readable counts and output paths
4. Preserve existing organized subtrees such as an existing `资料/` or a prior `00_资料索引/` unless the user explicitly includes them in scope. Treat them as context, not as files to reorganize.
5. Classify files from evidence, not filenames alone. For ambiguous Office/PDF/image files, inspect embedded text before leaving them in `98_待识别`:
   - PDFs: `pdftotext`, `pdfinfo`, OCR if text extraction is empty
   - DOCX/PPTX/XLSX/WPS-style zip files: unzip/inspect XML text and metadata
   - screenshots/scanned PDFs: OCR or image viewing
6. Write a move plan JSON in the target folder or `00_资料索引/`. Keep source paths relative to the root and do not use absolute targets:

```json
{
  "root": "/mnt/d/Work/资料",
  "moves": [
    {
      "source": "example.pdf",
      "target": "01_TCP项目/example.pdf",
      "reason": "PDF text mentions TCP project acceptance"
    },
    {
      "source": "example (1).pdf",
      "target": "99_重复文件/example (1).pdf",
      "reason": "Exact SHA-256 duplicate of example.pdf"
    }
  ]
}
```

7. Dry-run the plan and inspect conflicts before moving:

```bash
python3 ~/.codex/skills/windows-document-organizer/scripts/document_organizer.py apply-plan /mnt/d/Work/资料/00_资料索引/move-plan.json
```

8. Execute only after the dry-run validates cleanly:

```bash
python3 ~/.codex/skills/windows-document-organizer/scripts/document_organizer.py apply-plan /mnt/d/Work/资料/00_资料索引/move-plan.json --execute
```

9. Re-run `inventory` after moving and refresh the Markdown index. Final output should report:
   - target root and WSL path mapping
   - generated index/log paths
   - created category folders
   - duplicate count and where duplicates were moved
   - unresolved files remaining in `98_待识别`
   - any preserved subtrees

## Safety Rules

- Never delete files in this workflow. Move exact duplicates to `99_重复文件` instead.
- Do not overwrite an existing target path. Rename the planned target or keep the file in `98_待识别`.
- Do not reorganize an existing curated subtree unless the user explicitly expands scope.
- Do not classify a file only from a vague name such as `1.4.docx`; inspect embedded text or OCR first.
- Keep move logs in `00_资料索引/` so the operation is auditable.

## Folder Naming Pattern

Use stable, numbered folders only when the category is supported by file content. Adapt category names to the directory domain, but keep these reserved names:

- `00_资料索引`: inventories, Markdown index, JSON plans, CSV logs
- `98_待识别`: files still lacking enough evidence
- `99_重复文件`: exact duplicates moved out of the active corpus

For technical work folders, good category names include project/product names, equipment/software domains, electrical/PLC/servo topics, SOP/maintenance materials, training/templates, travel/reimbursement material, and personal/admin material.
