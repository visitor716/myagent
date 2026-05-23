#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from collections import defaultdict
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Iterable


DEFAULT_REIMBURSABLE_MERCHANTS = (
    "扬州沁润居酒店管理有限公司",
    "扬州沁润局酒店管理有限公司",
)

INVESTMENT_CATEGORIES = {"投资理财"}


class BillParseError(RuntimeError):
    pass


@dataclass(frozen=True)
class Transaction:
    source: str
    time: str
    category: str
    counterparty: str
    description: str
    direction: str
    amount: Decimal
    method: str
    status: str
    order_id: str

    @property
    def month(self) -> str:
        return self.time[:7]


def normalize_path(raw: str) -> Path:
    raw = raw.strip().strip('"').strip("'")
    match = re.match(r"^([A-Za-z]):[\\/](.*)$", raw)
    if match:
        drive = match.group(1).lower()
        rest = match.group(2).replace("\\", "/")
        return Path(f"/mnt/{drive}/{rest}")
    return Path(raw).expanduser()


def read_text(path: Path) -> tuple[str, str]:
    data = path.read_bytes()
    encodings = ("utf-8-sig", "utf-8", "gb18030", "gbk")
    for encoding in encodings:
        try:
            return data.decode(encoding), encoding
        except UnicodeDecodeError:
            continue
    raise BillParseError(f"无法识别文件编码: {path}")


def parse_money(value: str) -> Decimal:
    cleaned = (
        value.strip()
        .replace("￥", "")
        .replace("¥", "")
        .replace("元", "")
        .replace(",", "")
        .replace("\t", "")
    )
    if cleaned.startswith("(") and cleaned.endswith(")"):
        cleaned = "-" + cleaned[1:-1]
    cleaned = cleaned.strip()
    if cleaned in {"", "-", "/"}:
        cleaned = "0"
    try:
        return Decimal(cleaned)
    except InvalidOperation as exc:
        raise BillParseError(f"无法解析金额: {value!r}") from exc


def find_header(lines: list[str], required: Iterable[str]) -> int:
    required_set = set(required)
    for idx, line in enumerate(lines):
        fields = {field.strip() for field in line.split(",")}
        if required_set.issubset(fields):
            return idx
    raise BillParseError(f"找不到账单 CSV 表头，缺少字段: {', '.join(required_set)}")


def parse_alipay(path: Path) -> tuple[list[Transaction], dict[str, object], str]:
    text, encoding = read_text(path)
    lines = text.splitlines()
    header_idx = find_header(lines, ("交易时间", "交易分类", "交易对方", "收/支", "金额", "交易状态"))
    summary = parse_alipay_summary(lines[:header_idx])
    reader = csv.DictReader(lines[header_idx:])
    rows: list[Transaction] = []
    for row in reader:
        time = (row.get("交易时间") or "").strip()
        if not re.match(r"^\d{4}-\d{2}-\d{2} ", time):
            continue
        rows.append(
            Transaction(
                source=str(path),
                time=time,
                category=(row.get("交易分类") or "").strip(),
                counterparty=(row.get("交易对方") or "").strip(),
                description=(row.get("商品说明") or "").strip(),
                direction=(row.get("收/支") or "").strip(),
                amount=parse_money(row.get("金额") or "0"),
                method=(row.get("收/付款方式") or "").strip(),
                status=(row.get("交易状态") or "").strip(),
                order_id=(row.get("交易订单号") or "").strip(),
            )
        )
    if not rows:
        raise BillParseError(f"没有解析到交易明细: {path}")
    return rows, summary, encoding


def parse_alipay_summary(lines: list[str]) -> dict[str, object]:
    summary: dict[str, object] = {}
    for line in lines:
        match = re.search(r"支出：(\d+)笔\s+([0-9,.]+)元", line)
        if match:
            summary["expense_count"] = int(match.group(1))
            summary["expense_amount"] = parse_money(match.group(2))
        match = re.search(r"共(\d+)笔记录", line)
        if match:
            summary["record_count"] = int(match.group(1))
    return summary


def is_expense(tx: Transaction) -> bool:
    return tx.direction == "支出"


def is_consumption_refund(tx: Transaction) -> bool:
    text = f"{tx.category} {tx.description} {tx.status}"
    return tx.direction == "不计收支" and "退款" in text and tx.category not in INVESTMENT_CATEGORIES


def money(value: Decimal) -> str:
    return f"{value.quantize(Decimal('0.01')):,.2f}"


def summarize(transactions: list[Transaction], reimbursable_merchants: set[str]) -> dict[str, object]:
    months = defaultdict(
        lambda: {
            "expense_rows": 0,
            "raw_expense": Decimal("0"),
            "refund": Decimal("0"),
            "reimbursable_gross": Decimal("0"),
            "reimbursable_refund": Decimal("0"),
        }
    )
    category_totals = defaultdict(Decimal)
    merchant_totals = defaultdict(Decimal)
    reimbursable_rows: list[Transaction] = []

    for tx in transactions:
        month = tx.month
        if is_expense(tx):
            months[month]["expense_rows"] += 1
            months[month]["raw_expense"] += tx.amount
            if tx.counterparty in reimbursable_merchants and tx.status != "交易关闭":
                months[month]["reimbursable_gross"] += tx.amount
                reimbursable_rows.append(tx)
            elif tx.status != "交易关闭":
                category_totals[tx.category] += tx.amount
                merchant_totals[tx.counterparty] += tx.amount
        elif is_consumption_refund(tx):
            months[month]["refund"] += tx.amount
            if tx.counterparty in reimbursable_merchants:
                months[month]["reimbursable_refund"] += tx.amount
            else:
                category_totals[tx.category] -= tx.amount
                merchant_totals[tx.counterparty] -= tx.amount

    monthly_rows = []
    for month in sorted(months):
        data = months[month]
        actual = data["raw_expense"] - data["refund"]
        reimbursable = data["reimbursable_gross"] - data["reimbursable_refund"]
        personal = actual - reimbursable
        monthly_rows.append(
            {
                "month": month,
                "expense_rows": data["expense_rows"],
                "actual": actual,
                "reimbursable": reimbursable,
                "personal": personal,
            }
        )

    return {
        "monthly": monthly_rows,
        "reimbursable_rows": reimbursable_rows,
        "category_totals": dict(category_totals),
        "merchant_totals": dict(merchant_totals),
    }


def print_markdown(
    paths: list[Path],
    encodings: list[str],
    transactions: list[Transaction],
    summary: dict[str, object],
    result: dict[str, object],
    reimbursable_merchants: set[str],
    top: int,
) -> None:
    monthly = result["monthly"]
    actual_total = sum((row["actual"] for row in monthly), Decimal("0"))
    reimbursable_total = sum((row["reimbursable"] for row in monthly), Decimal("0"))
    personal_total = sum((row["personal"] for row in monthly), Decimal("0"))
    month_count = len(monthly) or 1

    print("# 记账分析")
    print()
    print(f"- 来源文件: {', '.join(str(path) for path in paths)}")
    print(f"- 检测编码: {', '.join(encodings)}")
    print(f"- 交易明细: {len(transactions)} 笔")
    if reimbursable_merchants:
        print(f"- 可报销剔除商户: {', '.join(sorted(reimbursable_merchants))}")
    print()
    print("| 月份 | 原实际支出 | 可报销剔除 | 剔除后个人支出 |")
    print("|---|---:|---:|---:|")
    for row in monthly:
        print(
            f"| {row['month']} | {money(row['actual'])} | "
            f"{money(row['reimbursable'])} | {money(row['personal'])} |"
        )
    print(
        f"| 合计 | {money(actual_total)} | {money(reimbursable_total)} | "
        f"{money(personal_total)} |"
    )
    print()
    print(f"- 剔除后月均个人支出: {money(personal_total / month_count)}")

    official_amount = summary.get("expense_amount")
    if isinstance(official_amount, Decimal):
        diff = actual_total - official_amount
        status = "一致" if diff == Decimal("0") else f"相差 {money(diff)}"
        print(f"- 支付宝导出支出摘要: {money(official_amount)}，本次计算: {money(actual_total)}，校验: {status}")

    rows = result["reimbursable_rows"]
    if rows:
        print()
        print("## 已剔除可报销明细")
        print()
        print("| 时间 | 商户 | 分类 | 状态 | 金额 |")
        print("|---|---|---|---|---:|")
        for tx in rows:
            print(f"| {tx.time} | {tx.counterparty} | {tx.category} | {tx.status} | {money(tx.amount)} |")

    category_totals = {
        key: value
        for key, value in result["category_totals"].items()
        if value != Decimal("0")
    }
    if category_totals:
        print()
        print("## 个人支出分类 Top")
        print()
        print("| 分类 | 金额 |")
        print("|---|---:|")
        for category, amount in sorted(category_totals.items(), key=lambda item: (-item[1], item[0]))[:top]:
            print(f"| {category} | {money(amount)} |")


def decimal_default(value: object) -> object:
    if isinstance(value, Decimal):
        return str(value)
    if isinstance(value, Transaction):
        return value.__dict__
    raise TypeError(f"Object of type {type(value).__name__} is not JSON serializable")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Analyze personal bill CSV exports.")
    parser.add_argument("paths", nargs="+", help="CSV bill path(s). Windows D:\\ paths are accepted in WSL.")
    parser.add_argument("--exclude-merchant", action="append", default=[], help="Merchant to remove as reimbursable.")
    parser.add_argument("--no-default-exclusions", action="store_true", help="Do not remove the built-in reimbursable merchants.")
    parser.add_argument("--format", choices=("markdown", "json"), default="markdown")
    parser.add_argument("--top", type=int, default=10, help="Number of top categories to print.")
    args = parser.parse_args(argv)

    paths = [normalize_path(raw) for raw in args.paths]
    missing = [str(path) for path in paths if not path.exists()]
    if missing:
        raise BillParseError(f"文件不存在: {', '.join(missing)}")

    transactions: list[Transaction] = []
    encodings: list[str] = []
    combined_summary: dict[str, object] = {}
    for path in paths:
        parsed, summary, encoding = parse_alipay(path)
        transactions.extend(parsed)
        encodings.append(encoding)
        if len(paths) == 1:
            combined_summary = summary

    reimbursable_merchants = set(args.exclude_merchant)
    if not args.no_default_exclusions:
        reimbursable_merchants.update(DEFAULT_REIMBURSABLE_MERCHANTS)

    result = summarize(transactions, reimbursable_merchants)
    if args.format == "json":
        payload = {
            "paths": [str(path) for path in paths],
            "encodings": encodings,
            "summary": combined_summary,
            "result": result,
        }
        print(json.dumps(payload, ensure_ascii=False, indent=2, default=decimal_default))
    else:
        print_markdown(paths, encodings, transactions, combined_summary, result, reimbursable_merchants, args.top)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BillParseError as exc:
        print(f"bookkeeping: {exc}", file=sys.stderr)
        raise SystemExit(2)
