#!/usr/bin/env python3
"""Inventory reimbursement images and safely apply rename/classification plans."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import sys
from collections import defaultdict
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any
from zipfile import ZipFile


IMAGE_EXTENSIONS = {
    ".bmp",
    ".gif",
    ".heic",
    ".heif",
    ".jpeg",
    ".jpg",
    ".png",
    ".tif",
    ".tiff",
    ".webp",
}

EVIDENCE_EXTENSIONS = IMAGE_EXTENSIONS | {".pdf"}

CATEGORY_FOLDERS = {
    "invoice": "01-发票",
    "发票": "01-发票",
    "payment": "02-支付凭证",
    "支付": "02-支付凭证",
    "支付凭证": "02-支付凭证",
    "付款截图": "02-支付凭证",
    "transport": "03-交通行程",
    "traffic": "03-交通行程",
    "travel": "03-交通行程",
    "交通": "03-交通行程",
    "交通行程": "03-交通行程",
    "lodging": "04-住宿",
    "hotel": "04-住宿",
    "住宿": "04-住宿",
    "meal": "05-餐饮",
    "food": "05-餐饮",
    "餐饮": "05-餐饮",
    "purchase": "06-办公采购",
    "office": "06-办公采购",
    "办公采购": "06-办公采购",
    "express": "06-办公采购",
    "快递": "06-办公采购",
    "快递费": "06-办公采购",
    "other": "07-其他票据",
    "其他": "07-其他票据",
    "其他票据": "07-其他票据",
    "uncertain": "99-待确认",
    "unknown": "99-待确认",
    "待确认": "99-待确认",
}

COMPANY_TITLE = "武汉帝尔激光科技股份有限公司"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    inventory_parser = subparsers.add_parser("inventory", help="Create an evidence-file inventory JSON file.")
    inventory_parser.add_argument("root", help="Directory containing reimbursement images or PDFs.")
    inventory_parser.add_argument(
        "-o",
        "--output",
        help="Inventory JSON output path. Defaults to <root>/expense-inventory.json.",
    )

    unpack_parser = subparsers.add_parser("unpack", help="Safely unpack downloaded reimbursement ZIP archives.")
    unpack_parser.add_argument("path", help="ZIP file or directory containing ZIP files.")
    unpack_parser.add_argument(
        "-o",
        "--output",
        help="Output directory. Defaults to the ZIP directory, creating <zip-stem>-clean folders.",
    )
    unpack_parser.add_argument(
        "--filename-encoding",
        default="gbk",
        help="Encoding for legacy ZIP filenames decoded as CP437 by Python. Default: gbk.",
    )

    apply_parser = subparsers.add_parser("apply", help="Dry-run or execute a rename/classification plan.")
    apply_parser.add_argument("plan", help="Plan JSON path.")
    apply_parser.add_argument("--execute", action="store_true", help="Actually move or copy files.")
    apply_parser.add_argument(
        "--mode",
        choices=("move", "copy"),
        default="move",
        help="Use move or copy when --execute is set. Default: move.",
    )
    apply_parser.add_argument(
        "--manifest",
        help="Manifest output path. Defaults to <root>/expense-organization-manifest.json.",
    )

    check_parser = subparsers.add_parser("check", help="Check a plan against reimbursement rules.")
    check_parser.add_argument("plan", help="Plan JSON path.")
    check_parser.add_argument(
        "--report",
        help="Compliance report JSON output path. Defaults to <root>/expense-compliance-report.json.",
    )

    args = parser.parse_args()
    if args.command == "inventory":
        return run_inventory(args)
    if args.command == "unpack":
        return run_unpack(args)
    if args.command == "apply":
        return run_apply(args)
    if args.command == "check":
        return run_check(args)
    parser.error("unknown command")
    return 2


def run_inventory(args: argparse.Namespace) -> int:
    root = Path(args.root).expanduser().resolve()
    if not root.is_dir():
        raise SystemExit(f"Not a directory: {root}")

    output = Path(args.output).expanduser().resolve() if args.output else root / "expense-inventory.json"
    files = [path for path in sorted(root.rglob("*")) if path.is_file() and path.suffix.lower() in EVIDENCE_EXTENSIONS]
    items = [inventory_item(root, path) for path in files]
    data = {
        "root": str(root),
        "created_at": now_iso(),
        "evidence_count": len(items),
        "image_count": len(items),
        "items": items,
    }
    output.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote inventory: {output}")
    print(f"Evidence files found: {len(items)}")
    for item in items:
        dimensions = item.get("dimensions") or {}
        size_label = ""
        if dimensions:
            size_label = f" {dimensions.get('width')}x{dimensions.get('height')}"
        print(f"- {item['source']} ({item['sha256_12']}{size_label})")
    return 0


def run_unpack(args: argparse.Namespace) -> int:
    source_path = Path(args.path).expanduser().resolve()
    if source_path.is_file():
        zip_paths = [source_path]
    elif source_path.is_dir():
        zip_paths = sorted(path for path in source_path.glob("*.zip") if path.is_file())
    else:
        raise SystemExit(f"ZIP path not found: {source_path}")

    if not zip_paths:
        raise SystemExit(f"No ZIP files found: {source_path}")

    output_base = Path(args.output).expanduser().resolve() if args.output else None
    operations = []
    for zip_path in zip_paths:
        if output_base and len(zip_paths) == 1 and source_path.is_file():
            target_dir = output_base
        else:
            target_dir = (output_base or zip_path.parent) / f"{zip_path.stem}-clean"
        target_dir.mkdir(parents=True, exist_ok=True)
        operations.extend(unpack_zip(zip_path, target_dir, args.filename_encoding))

    print(f"Unpacked ZIP files: {len(zip_paths)}")
    print(f"Extracted files: {len(operations)}")
    for operation in operations:
        print(f"- {operation['zip']}:{operation['member']} -> {operation['destination']}")
    return 0


def run_apply(args: argparse.Namespace) -> int:
    plan_path = Path(args.plan).expanduser().resolve()
    if not plan_path.is_file():
        raise SystemExit(f"Plan not found: {plan_path}")
    plan = json.loads(plan_path.read_text(encoding="utf-8"))

    root_value = plan.get("root") or str(plan_path.parent)
    root = Path(root_value).expanduser().resolve()
    if not root.is_dir():
        raise SystemExit(f"Plan root is not a directory: {root}")

    raw_items = plan.get("items")
    if not isinstance(raw_items, list):
        raise SystemExit("Plan must contain an items list.")

    operations = []
    for index, item in enumerate(raw_items, start=1):
        if not isinstance(item, dict):
            raise SystemExit(f"Item {index} must be an object.")
        operations.append(build_operation(root, item, index))

    errors = [op for op in operations if op.get("error")]
    if errors:
        for op in errors:
            print(f"ERROR item {op['index']}: {op['error']}", file=sys.stderr)
        return 1

    if args.execute:
        for op in operations:
            dest = Path(op["destination_abs"])
            dest.parent.mkdir(parents=True, exist_ok=True)
            source = Path(op["source_abs"])
            if args.mode == "copy":
                shutil.copy2(source, dest)
            else:
                shutil.move(str(source), str(dest))

    manifest = {
        "root": str(root),
        "created_at": now_iso(),
        "dry_run": not args.execute,
        "mode": args.mode,
        "count": len(operations),
        "print_reminders": [
            {
                "source": op["source"],
                "destination": op["destination"],
                "print_note": op.get("print_note"),
            }
            for op in operations
            if op.get("requires_extra_print")
        ],
        "operations": [
            {
                "source": op["source"],
                "destination": op["destination"],
                "category": op["category"],
                "claim_id": op.get("claim_id"),
                "expense_kind": op.get("expense_kind"),
                "evidence_type": op.get("evidence_type"),
                "evidence_types": op.get("evidence_types"),
                "requires_extra_print": op.get("requires_extra_print", False),
                "print_note": op.get("print_note"),
                "confidence": op.get("confidence"),
                "notes": op.get("notes"),
            }
            for op in operations
        ],
    }
    manifest_path = Path(args.manifest).expanduser().resolve() if args.manifest else root / "expense-organization-manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    prefix = "APPLY" if args.execute else "DRY-RUN"
    for op in operations:
        print_suffix = " [需额外打印]" if op.get("requires_extra_print") else ""
        print(f"{prefix}: {op['source']} -> {op['destination']}{print_suffix}")
    print(f"Wrote manifest: {manifest_path}")
    if not args.execute:
        print("No files changed. Re-run with --execute to apply.")
    return 0


def run_check(args: argparse.Namespace) -> int:
    plan_path = Path(args.plan).expanduser().resolve()
    if not plan_path.is_file():
        raise SystemExit(f"Plan not found: {plan_path}")
    plan = json.loads(plan_path.read_text(encoding="utf-8"))

    root_value = plan.get("root") or str(plan_path.parent)
    root = Path(root_value).expanduser().resolve()
    raw_items = plan.get("items")
    if not isinstance(raw_items, list):
        raise SystemExit("Plan must contain an items list.")

    findings = check_plan_timing(plan)
    groups: dict[str, list[tuple[int, dict[str, Any]]]] = defaultdict(list)
    for index, item in enumerate(raw_items, start=1):
        if not isinstance(item, dict):
            findings.append(finding("error", "plan.item", f"Item {index} must be an object.", target=f"item-{index}"))
            continue
        source = str(item.get("source") or "").strip()
        target = source or f"item-{index}"
        findings.extend(check_item(root, item, index))
        claim_id = str(item.get("claim_id") or "").strip() or f"item-{index}"
        groups[claim_id].append((index, item))

    for claim_id, group_items in groups.items():
        findings.extend(check_claim_group(claim_id, group_items))

    if raw_items and not any(infer_evidence_types(item) & {"reimbursement_cover", "expense_form"} for item in raw_items):
        findings.append(
            finding(
                "warning",
                "oa.cover",
                "Plan does not include reimbursement cover/form evidence; final paper package still needs a complete OA computer-printed cover.",
                target="plan",
            )
        )

    summary = summarize_findings(findings)
    report = {
        "root": str(root),
        "created_at": now_iso(),
        "count": len(raw_items),
        "summary": summary,
        "findings": findings,
    }
    report_path = Path(args.report).expanduser().resolve() if args.report else root / "expense-compliance-report.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"Checked items: {len(raw_items)}")
    print(f"Findings: errors={summary['error']} warnings={summary['warning']} info={summary['info']}")
    for item in findings:
        print(f"{item['level'].upper()}: {item['rule']} {item.get('target') or ''} - {item['message']}")
    print(f"Wrote report: {report_path}")
    return 1 if summary["error"] else 0


def inventory_item(root: Path, path: Path) -> dict[str, Any]:
    stat = path.stat()
    item: dict[str, Any] = {
        "source": path.relative_to(root).as_posix(),
        "bytes": stat.st_size,
        "mtime": datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc).isoformat(),
        "sha256_12": sha256_prefix(path),
    }
    dimensions = image_dimensions(path)
    if dimensions:
        item["dimensions"] = dimensions
    return item


def unpack_zip(zip_path: Path, target_dir: Path, filename_encoding: str) -> list[dict[str, str]]:
    operations: list[dict[str, str]] = []
    with ZipFile(zip_path) as archive:
        for info in archive.infolist():
            if info.is_dir():
                continue
            decoded_name = decode_zip_member_name(info, filename_encoding)
            relative_path = safe_zip_relative_path(decoded_name)
            if relative_path is None:
                print(f"WARNING: skipping unsafe ZIP member {info.filename!r}", file=sys.stderr)
                continue
            destination = unique_destination(target_dir / relative_path.parent, relative_path.name)
            destination.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(info) as source, destination.open("wb") as target:
                shutil.copyfileobj(source, target)
            operations.append(
                {
                    "zip": zip_path.name,
                    "member": decoded_name,
                    "destination": destination.as_posix(),
                }
            )
    return operations


def decode_zip_member_name(info: Any, filename_encoding: str) -> str:
    raw_name = str(info.filename)
    try:
        decoded_name = raw_name.encode("cp437").decode(filename_encoding)
        if decoded_name != raw_name:
            return decoded_name
    except Exception:
        pass
    return raw_name


def safe_zip_relative_path(name: str) -> Path | None:
    normalized = name.replace("\\", "/").strip("/")
    parts = []
    for part in normalized.split("/"):
        if not part or part in {".", ".."}:
            continue
        if ":" in part:
            return None
        parts.append(part)
    if not parts:
        return None
    sanitized_parts = [sanitize_path_part(part, "目录") for part in parts[:-1]]
    sanitized_parts.append(sanitize_filename(parts[-1]))
    return Path(*sanitized_parts)


def build_operation(root: Path, item: dict[str, Any], index: int) -> dict[str, Any]:
    source_value = str(item.get("source") or "").strip()
    if not source_value:
        return {"index": index, "error": "missing source"}
    if Path(source_value).is_absolute():
        return {"index": index, "source": source_value, "error": "source must be relative to root"}

    source = (root / source_value).resolve()
    if not is_relative_to(source, root):
        return {"index": index, "source": source_value, "error": "source escapes root"}
    if not source.is_file():
        return {"index": index, "source": source_value, "error": "source file not found"}

    category = normalize_category(item.get("category"))
    filename = str(item.get("new_name") or "").strip()
    if filename:
        filename = sanitize_filename(filename)
        if not Path(filename).suffix:
            filename += source.suffix.lower()
    else:
        filename = build_filename(item, category, source.suffix.lower())

    destination = unique_destination(root / category, filename)
    print_requirement = infer_print_requirement(item)
    return {
        "index": index,
        "source": source_value,
        "source_abs": str(source),
        "destination": destination.relative_to(root).as_posix(),
        "destination_abs": str(destination),
        "category": category,
        "claim_id": item.get("claim_id"),
        "expense_kind": infer_expense_kind(item),
        "evidence_type": infer_evidence_type(item),
        "evidence_types": sorted(infer_evidence_types(item)),
        "requires_extra_print": print_requirement["requires_extra_print"],
        "print_note": print_requirement["print_note"],
        "confidence": item.get("confidence"),
        "notes": item.get("notes"),
    }


def check_item(root: Path, item: dict[str, Any], index: int) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    source = str(item.get("source") or "").strip()
    target = source or f"item-{index}"
    if not source:
        results.append(finding("error", "source.missing", "Missing source file path.", target=target))
    elif Path(source).is_absolute():
        results.append(finding("error", "source.absolute", "Source must be relative to plan root.", target=target))
    else:
        source_path = (root / source).resolve()
        if root.exists() and (not is_relative_to(source_path, root) or not source_path.is_file()):
            results.append(finding("warning", "source.not_found", "Source file was not found under plan root.", target=target))

    confidence = str(item.get("confidence") or "").strip().lower()
    if confidence == "low":
        results.append(finding("warning", "confidence.low", "Low-confidence OCR/visual result; manually verify before submission.", target=target))

    print_requirement = infer_print_requirement(item)
    if print_requirement["requires_extra_print"]:
        results.append(
            finding(
                "info",
                "print.extra_copy",
                print_requirement["print_note"] or "This invoice requires one extra printed copy.",
                target=target,
            )
        )

    if is_electronic_invoice(item):
        if not str(item.get("invoice_code") or "").strip() or not str(item.get("invoice_number") or "").strip():
            results.append(
                finding(
                    "warning",
                    "invoice.electronic_code_number",
                    "Electronic invoice should have invoice_code and invoice_number filled in order; do not swap them.",
                    target=target,
                )
            )

    buyer_name = first_present(item, "buyer_name", "invoice_title", "purchaser_name", "company_name")
    if buyer_name and buyer_name != COMPANY_TITLE:
        level = "error" if ("帝尔" in buyer_name or "武汉" in buyer_name) else "warning"
        results.append(
            finding(
                level,
                "invoice.title",
                f"Invoice title should be exactly {COMPANY_TITLE}; visible title is {buyer_name}.",
                target=target,
            )
        )
    return results


def check_claim_group(claim_id: str, group_items: list[tuple[int, dict[str, Any]]]) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    items = [item for _, item in group_items]
    evidence = set().union(*(infer_evidence_types(item) for item in items))
    kind = infer_group_expense_kind(items)
    target = f"claim:{claim_id}"

    if kind == "transport":
        if "invoice" not in evidence and "taxi_machine_receipt" not in evidence:
            results.append(finding("warning", "transport.invoice", "Transportation claim should include invoice or machine-printed ticket.", target=target))
        if not ({"itinerary", "self_made_itinerary"} & evidence):
            results.append(finding("warning", "transport.itinerary", "Transportation claim should include electronic itinerary or printed self-made itinerary.", target=target))
        if "taxi_machine_receipt" in evidence and "self_made_itinerary" not in evidence:
            results.append(finding("warning", "transport.taxi_itinerary", "Machine-printed taxi ticket needs a printed self-made itinerary table.", target=target))

    if kind == "lodging":
        required = {
            "invoice": "hotel invoice",
            "lodging_detail": "lodging detail bill from hotel front desk",
            "order_screenshot": "online order screenshot",
            "payment_proof": "payment/preorder proof",
        }
        for evidence_type, label in required.items():
            if evidence_type not in evidence:
                results.append(finding("error", f"lodging.{evidence_type}", f"Lodging claim is missing {label}.", target=target))
        results.extend(check_lodging_amounts(target, items))

    if kind == "purchase":
        required = {
            "invoice": "invoice",
            "order_screenshot": "order screenshot",
            "payment_proof": "payment screenshot",
        }
        for evidence_type, label in required.items():
            if evidence_type not in evidence:
                results.append(finding("warning", f"purchase.{evidence_type}", f"Purchase claim should include {label}.", target=target))
        if group_text(items, ["document_type", "notes", "merchant", "project_name"]).find("备件") >= 0 or group_text(
            items, ["document_type", "notes", "merchant", "project_name"]
        ).find("物料") >= 0:
            if "warehouse_slip" not in evidence:
                results.append(finding("error", "purchase.warehouse_slip", "Spare-part/material purchase needs assistant-provided warehouse in/out slip photo.", target=target))

    if kind == "express":
        text = group_text(items, ["purpose", "document_type", "notes"])
        business_type = first_group_present(items, "business_type", "travel_type", "reimbursement_scope")
        fee_type = first_group_present(items, "fee_type", "oa_type", "expense_category")
        if "机票" in text:
            if business_type and "差旅" not in business_type:
                results.append(finding("warning", "express.travel", "Express for mailing flight tickets should be treated as travel-related express cost.", target=target))
        elif business_type and "非差旅" not in business_type:
            results.append(finding("warning", "express.non_travel", "Express reimbursement is normally 非差旅.", target=target))
        if ("备件" in text or "物料" in text) and fee_type and "修理费" not in fee_type:
            results.append(finding("warning", "express.repair_fee", "Mailing spare parts/materials should use 修理费.", target=target))
        if "文件" in text and fee_type and "办公费" not in fee_type:
            results.append(finding("warning", "express.office_fee", "Mailing documents should use 办公费.", target=target))

    return results


def check_plan_timing(plan: dict[str, Any]) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    expense_date = parse_date_value(first_present(plan, "expense_date", "occurred_date"))
    finance_date = parse_date_value(first_present(plan, "finance_received_date", "finance_arrival_date"))
    returned_date = parse_date_value(first_present(plan, "returned_to_company_date", "return_date"))
    submitted_date = parse_date_value(first_present(plan, "submitted_date", "submission_date"))

    if expense_date and finance_date and days_between(expense_date, finance_date) > 92:
        results.append(finding("error", "timing.three_months", "Expense-to-Finance interval is greater than 3 months and is not reimbursable.", target="plan"))
    if returned_date and submitted_date and (submitted_date - returned_date).days > 3:
        results.append(finding("warning", "timing.return_3_days", "Travel reimbursement should be submitted within 3 days after returning to company.", target="plan"))

    long_term = parse_optional_bool(plan.get("long_term_outside"))
    unreimbursed_total = parse_amount_value(plan.get("unreimbursed_total"))
    if submitted_date and (long_term or (unreimbursed_total is not None and unreimbursed_total > 1000)):
        if submitted_date.day > 20:
            results.append(finding("warning", "timing.current_month_20", "Long-term outside travel or accumulated unreimbursed amount over 1000 yuan should be submitted before the 20th.", target="plan"))

    special_delay = parse_optional_bool(plan.get("special_delay"))
    if special_delay and expense_date and submitted_date:
        deadline = next_month_20(expense_date)
        if submitted_date > deadline:
            results.append(finding("warning", "timing.next_month_20", "Special-delay or accumulated small-amount reimbursement should be submitted by the 20th of the next month.", target="plan"))
    return results


def check_lodging_amounts(target: str, items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    invoice_amount = first_group_amount(items, "invoice_amount", "amount")
    paid_amount = first_group_amount(items, "paid_amount", "payment_amount")
    reimbursement_amount = first_group_amount(items, "reimbursement_amount", "claim_amount")
    if invoice_amount is None or paid_amount is None or reimbursement_amount is None:
        return []
    expected = min(invoice_amount, paid_amount)
    if abs(reimbursement_amount - expected) > 0.005:
        return [
            finding(
                "error",
                "lodging.amount",
                f"Lodging reimbursement should be min(invoice_amount, paid_amount) without rounding: expected {expected:.2f}, got {reimbursement_amount:.2f}.",
                target=target,
            )
        ]
    return []


def normalize_category(value: Any) -> str:
    raw = str(value or "uncertain").strip()
    if re.match(r"^\d{2}-[^/\\]+$", raw):
        return sanitize_path_part(raw, "99-待确认")
    return CATEGORY_FOLDERS.get(raw.lower(), CATEGORY_FOLDERS.get(raw, "99-待确认"))


def build_filename(item: dict[str, Any], category: str, extension: str) -> str:
    date = normalize_date(item.get("date"))
    category_name = re.sub(r"^\d{2}-", "", category)
    merchant = sanitize_path_part(first_present(item, "merchant", "payee", "issuer"), "商户未知")
    amount = normalize_amount(first_present(item, "amount", "total", "paid_amount"))
    doc_type = sanitize_path_part(first_present(item, "document_type", "type"), "截图")
    parts = [
        sanitize_path_part(date, "日期未知"),
        sanitize_path_part(category_name, "待确认"),
        merchant,
        sanitize_path_part(amount, "金额未知"),
        doc_type,
    ]
    return sanitize_filename("_".join(parts) + extension)


def infer_print_requirement(item: dict[str, Any]) -> dict[str, Any]:
    explicit = item.get("requires_extra_print")
    explicit_bool = parse_optional_bool(explicit)
    explicit_note = str(item.get("print_note") or "").strip()
    if explicit_bool is not None:
        return {
            "requires_extra_print": explicit_bool,
            "print_note": explicit_note if explicit_bool else None,
        }

    fields = [
        "category",
        "document_type",
        "invoice_type",
        "project_name",
        "item_name",
        "goods_name",
        "service_name",
        "merchant",
        "notes",
    ]
    text = " ".join(str(item.get(field) or "") for field in fields)
    if "专用发票" in text or "增值税专票" in text or "专票" in text:
        return {
            "requires_extra_print": True,
            "print_note": explicit_note or "增值税专用发票，报销需额外打印一份",
        }
    has_toll_item = "通行费" in text
    has_ordinary_invoice = "普通发票" in text or "电子普通发票" in text or "普票" in text
    if has_toll_item and has_ordinary_invoice:
        return {
            "requires_extra_print": True,
            "print_note": explicit_note or "公路通行费普通发票，项目名称含通行费，报销需额外打印一份",
        }
    return {"requires_extra_print": False, "print_note": explicit_note or None}


def infer_evidence_type(item: dict[str, Any]) -> str:
    raw = first_present(item, "evidence_type", "attachment_type", "document_role")
    normalized = raw.strip().lower()
    aliases = {
        "invoice": "invoice",
        "发票": "invoice",
        "itinerary": "itinerary",
        "行程单": "itinerary",
        "self_made_itinerary": "self_made_itinerary",
        "自拟行程单": "self_made_itinerary",
        "payment": "payment_proof",
        "payment_proof": "payment_proof",
        "付款截图": "payment_proof",
        "支付凭证": "payment_proof",
        "order": "order_screenshot",
        "order_screenshot": "order_screenshot",
        "订单截图": "order_screenshot",
        "lodging_detail": "lodging_detail",
        "住宿明细": "lodging_detail",
        "warehouse_slip": "warehouse_slip",
        "出入库单": "warehouse_slip",
        "reimbursement_cover": "reimbursement_cover",
        "报销单封面": "reimbursement_cover",
        "expense_form": "expense_form",
        "报销单": "expense_form",
        "taxi_machine_receipt": "taxi_machine_receipt",
        "机打车票": "taxi_machine_receipt",
    }
    if normalized in aliases:
        return aliases[normalized]
    if raw in aliases:
        return aliases[raw]

    text = " ".join(
        str(item.get(field) or "")
        for field in ("category", "document_type", "invoice_type", "project_name", "merchant", "notes")
    )
    if "报销单封面" in text:
        return "reimbursement_cover"
    if "报销单" in text:
        return "expense_form"
    if "出入库" in text:
        return "warehouse_slip"
    if "住宿明细" in text or "明细账单" in text:
        return "lodging_detail"
    if "自拟行程" in text:
        return "self_made_itinerary"
    if "行程单" in text:
        return "itinerary"
    if "机打" in text and ("车票" in text or "出租车" in text):
        return "taxi_machine_receipt"
    if "付款" in text or "支付" in text or "转账" in text:
        return "payment_proof"
    if "订单" in text or "预定" in text or "预订" in text:
        return "order_screenshot"
    if "发票" in text or normalize_category(item.get("category")) == "01-发票":
        return "invoice"
    return "unknown"


def infer_evidence_types(item: dict[str, Any]) -> set[str]:
    raw_values: list[Any] = []
    for key in ("evidence_types", "attachment_types", "document_roles"):
        value = item.get(key)
        if isinstance(value, list):
            raw_values.extend(value)
        elif value is not None and str(value).strip():
            raw_values.extend(re.split(r"[,，、/]+", str(value)))

    single = first_present(item, "evidence_type", "attachment_type", "document_role")
    if single:
        raw_values.append(single)

    normalized: set[str] = set()
    for value in raw_values:
        value_text = str(value).strip()
        if not value_text:
            continue
        clone = dict(item)
        clone["evidence_type"] = value_text
        normalized_type = infer_evidence_type(clone)
        if normalized_type != "unknown":
            normalized.add(normalized_type)

    if normalized:
        return normalized
    return {infer_evidence_type(item)}


def infer_expense_kind(item: dict[str, Any]) -> str:
    raw = first_present(item, "expense_kind", "expense_type", "business_kind", "claim_type")
    normalized = raw.strip().lower()
    aliases = {
        "transport": "transport",
        "traffic": "transport",
        "travel": "transport",
        "交通": "transport",
        "交通费": "transport",
        "汽车费": "transport",
        "lodging": "lodging",
        "hotel": "lodging",
        "住宿": "lodging",
        "purchase": "purchase",
        "office": "purchase",
        "办公采购": "purchase",
        "express": "express",
        "快递": "express",
        "快递费": "express",
        "meal": "meal",
        "food": "meal",
        "餐饮": "meal",
    }
    if normalized in aliases:
        return aliases[normalized]
    if raw in aliases:
        return aliases[raw]

    text = " ".join(
        str(item.get(field) or "")
        for field in ("category", "document_type", "merchant", "project_name", "notes", "purpose")
    )
    if any(word in text for word in ("快递", "顺丰", "寄件", "邮寄")):
        return "express"
    if any(word in text for word in ("酒店", "住宿", "宾馆")):
        return "lodging"
    if any(word in text for word in ("滴滴", "高德", "出租车", "火车", "飞机", "客运", "车票", "通行费", "停车", "加油")):
        return "transport"
    if any(word in text for word in ("备件", "物料", "办公", "耗材", "软件", "打印")):
        return "purchase"
    if any(word in text for word in ("餐饮", "餐厅", "外卖", "咖啡")):
        return "meal"
    return "other"


def infer_group_expense_kind(items: list[dict[str, Any]]) -> str:
    kinds = [infer_expense_kind(item) for item in items]
    for preferred in ("lodging", "transport", "purchase", "express", "meal"):
        if preferred in kinds:
            return preferred
    return kinds[0] if kinds else "other"


def is_electronic_invoice(item: dict[str, Any]) -> bool:
    text = " ".join(str(item.get(field) or "") for field in ("document_type", "invoice_type", "notes"))
    return "电子" in text and "发票" in text


def finding(level: str, rule: str, message: str, target: str | None = None) -> dict[str, Any]:
    result: dict[str, Any] = {"level": level, "rule": rule, "message": message}
    if target:
        result["target"] = target
    return result


def summarize_findings(findings: list[dict[str, Any]]) -> dict[str, int]:
    summary = {"error": 0, "warning": 0, "info": 0}
    for item in findings:
        level = str(item.get("level") or "info")
        summary[level] = summary.get(level, 0) + 1
    return summary


def group_text(items: list[dict[str, Any]], fields: list[str]) -> str:
    return " ".join(str(item.get(field) or "") for item in items for field in fields)


def first_group_present(items: list[dict[str, Any]], *keys: str) -> str:
    for item in items:
        value = first_present(item, *keys)
        if value:
            return value
    return ""


def first_group_amount(items: list[dict[str, Any]], *keys: str) -> float | None:
    for item in items:
        for key in keys:
            amount = parse_amount_value(item.get(key))
            if amount is not None:
                return amount
    return None


def parse_amount_value(value: Any) -> float | None:
    raw = str(value or "").strip().replace(",", "")
    if not raw:
        return None
    match = re.search(r"(\d+(?:\.\d{1,2})?)", raw)
    if not match:
        return None
    return float(match.group(1))


def parse_date_value(value: Any) -> date | None:
    raw = str(value or "").strip()
    if not raw:
        return None
    match = re.search(r"(20\d{2})[-/.年](\d{1,2})[-/.月](\d{1,2})", raw)
    if match:
        year, month, day = match.groups()
        return date(int(year), int(month), int(day))
    match = re.search(r"\b(20\d{2})(\d{2})(\d{2})\b", raw)
    if match:
        year, month, day = match.groups()
        return date(int(year), int(month), int(day))
    return None


def days_between(start: date, end: date) -> int:
    if end < start:
        return 0
    return (end - start).days


def next_month_20(value: date) -> date:
    if value.month == 12:
        return date(value.year + 1, 1, 20)
    return date(value.year, value.month + 1, 20)


def parse_optional_bool(value: Any) -> bool | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return value
    normalized = str(value).strip().lower()
    if normalized in {"1", "true", "yes", "y", "是", "需要"}:
        return True
    if normalized in {"0", "false", "no", "n", "否", "不需要"}:
        return False
    return None


def first_present(item: dict[str, Any], *keys: str) -> str:
    for key in keys:
        value = item.get(key)
        if value is not None and str(value).strip():
            return str(value).strip()
    return ""


def normalize_date(value: Any) -> str:
    raw = str(value or "").strip()
    if not raw:
        return "日期未知"
    match = re.search(r"(20\d{2})[-/.年](\d{1,2})[-/.月](\d{1,2})", raw)
    if match:
        year, month, day = match.groups()
        return f"{year}-{int(month):02d}-{int(day):02d}"
    match = re.search(r"\b(20\d{2})(\d{2})(\d{2})\b", raw)
    if match:
        year, month, day = match.groups()
        return f"{year}-{month}-{day}"
    return "日期未知"


def normalize_amount(value: Any) -> str:
    raw = str(value or "").strip()
    if not raw:
        return "金额未知"
    raw = raw.replace(",", "")
    match = re.search(r"(\d+(?:\.\d{1,2})?)", raw)
    if not match:
        return "金额未知"
    amount = float(match.group(1))
    return f"{amount:.2f}"


def sanitize_filename(value: str) -> str:
    value = Path(value).name
    stem = sanitize_path_part(Path(value).stem, "未命名")
    suffix = Path(value).suffix.lower()
    suffix = re.sub(r"[^.A-Za-z0-9]", "", suffix)[:12]
    return stem + suffix


def sanitize_path_part(value: Any, fallback: str, limit: int = 60) -> str:
    text = str(value or "").strip()
    if not text:
        text = fallback
    text = re.sub(r"\s+", "", text)
    text = re.sub(r'[<>:"/\\|?*\x00-\x1f]', "-", text)
    text = text.strip(".-_ ")
    return (text or fallback)[:limit]


def unique_destination(directory: Path, filename: str) -> Path:
    candidate = directory / filename
    if not candidate.exists():
        return candidate
    stem = candidate.stem
    suffix = candidate.suffix
    for number in range(2, 1000):
        next_candidate = directory / f"{stem}_{number:02d}{suffix}"
        if not next_candidate.exists():
            return next_candidate
    raise SystemExit(f"Could not find available filename for {candidate}")


def sha256_prefix(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()[:12]


def image_dimensions(path: Path) -> dict[str, int] | None:
    try:
        from PIL import Image  # type: ignore
    except Exception:
        return None
    try:
        with Image.open(path) as image:
            width, height = image.size
    except Exception:
        return None
    return {"width": int(width), "height": int(height)}


def is_relative_to(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


if __name__ == "__main__":
    raise SystemExit(main())
