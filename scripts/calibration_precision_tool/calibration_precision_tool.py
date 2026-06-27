#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Windows desktop tool for checking 27x27 calibration point precision."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation, ROUND_DOWN, getcontext
from pathlib import Path
from typing import Iterable


GRID_SIZE = 27
TOTAL_POINTS = GRID_SIZE * GRID_SIZE
SPAN = Decimal("225")
START = Decimal("-112.5")
THEORY_PLACES = Decimal("0.0001")
MODE_LABELS = {
    "both": "X或Y超限",
    "x": "只看X",
    "y": "只看Y",
}

getcontext().prec = 40


@dataclass(frozen=True)
class Point:
    index: int
    x: Decimal
    y: Decimal


@dataclass(frozen=True)
class AnalysisRow:
    index: int
    theory_x: Decimal
    theory_y: Decimal
    actual_x: Decimal
    actual_y: Decimal
    delta_x: Decimal
    delta_y: Decimal
    result: str


@dataclass(frozen=True)
class AnalysisResult:
    rows: list[AnalysisRow]
    total: int
    ok_count: int
    ng_count: int
    pass_rate: Decimal
    max_abs_delta_x: Decimal
    max_abs_delta_y: Decimal
    mode: str


class CalibrationFileError(ValueError):
    pass


def format_ng_indexes(rows: Iterable[AnalysisRow], limit: int = 80) -> str:
    indexes = [row.index for row in rows if row.result == "NG"]
    if not indexes:
        return "无"
    if len(indexes) <= limit:
        return compact_ranges(indexes)
    shown = compact_ranges(indexes[:limit])
    return f"{shown} ...（共 {len(indexes)} 个）"


def truncate_theory(value: Decimal) -> Decimal:
    result = value.quantize(THEORY_PLACES, rounding=ROUND_DOWN)
    if result == Decimal("-0.0000"):
        return Decimal("0.0000")
    return result


def format_decimal(value: Decimal, places: int = 4) -> str:
    quantum = Decimal("1").scaleb(-places)
    result = value.quantize(quantum)
    if result == Decimal("-0." + "0" * places):
        result = Decimal("0." + "0" * places)
    return f"{result:.{places}f}"


def generate_theory_points() -> dict[int, Point]:
    step = SPAN / Decimal(GRID_SIZE - 1)
    points: dict[int, Point] = {}

    for row in range(GRID_SIZE):
        y = truncate_theory(START + Decimal(row) * step)
        for col in range(GRID_SIZE):
            x = truncate_theory(START + Decimal(col) * step)
            index = row * GRID_SIZE + col + 1
            points[index] = Point(index=index, x=x, y=y)

    return points


def decode_text(path: Path) -> str:
    data = path.read_bytes()
    errors: list[str] = []

    for encoding in ("utf-8-sig", "utf-8", "gbk", "gb18030"):
        try:
            return data.decode(encoding)
        except UnicodeDecodeError as exc:
            errors.append(f"{encoding}: {exc}")

    raise CalibrationFileError("文件编码无法识别；已尝试 utf-8-sig、utf-8、gbk、gb18030。")


def compact_ranges(values: Iterable[int]) -> str:
    sorted_values = sorted(values)
    if not sorted_values:
        return ""

    ranges: list[str] = []
    start = prev = sorted_values[0]
    for value in sorted_values[1:]:
        if value == prev + 1:
            prev = value
            continue
        ranges.append(f"{start}-{prev}" if start != prev else str(start))
        start = prev = value
    ranges.append(f"{start}-{prev}" if start != prev else str(start))
    return ", ".join(ranges)


def parse_point_file(path_text: str) -> dict[int, Point]:
    path = Path(path_text).expanduser()
    if not path.exists():
        raise CalibrationFileError(f"文件不存在：{path}")
    if not path.is_file():
        raise CalibrationFileError(f"不是有效文件：{path}")

    text = decode_text(path)
    points: dict[int, Point] = {}
    duplicate_indexes: list[int] = []

    for line_number, raw_line in enumerate(text.splitlines(), 1):
        line = raw_line.strip()
        if not line:
            continue

        parts = line.split()
        if len(parts) != 3:
            raise CalibrationFileError(
                f"第 {line_number} 行格式错误，应为：序号 x y；原文：{raw_line!r}"
            )

        try:
            index = int(parts[0])
            x = Decimal(parts[1])
            y = Decimal(parts[2])
        except (ValueError, InvalidOperation) as exc:
            raise CalibrationFileError(
                f"第 {line_number} 行数值无法解析；原文：{raw_line!r}"
            ) from exc

        if not 1 <= index <= TOTAL_POINTS:
            raise CalibrationFileError(
                f"第 {line_number} 行序号超出范围 1-{TOTAL_POINTS}：{index}"
            )

        if index in points:
            duplicate_indexes.append(index)
            continue

        points[index] = Point(index=index, x=x, y=y)

    if duplicate_indexes:
        raise CalibrationFileError(f"文件存在重复序号：{compact_ranges(duplicate_indexes)}")

    if len(points) != TOTAL_POINTS:
        missing = set(range(1, TOTAL_POINTS + 1)) - set(points)
        message = f"解析到 {len(points)} 个点，应为 {TOTAL_POINTS} 个点。"
        if missing:
            message += f" 缺失序号：{compact_ranges(missing)}"
        raise CalibrationFileError(message)

    return points


def parse_threshold(value: str) -> Decimal:
    try:
        threshold = Decimal(value.strip())
    except InvalidOperation as exc:
        raise CalibrationFileError("阈值必须是有效数字。") from exc

    if threshold < 0:
        raise CalibrationFileError("阈值不能小于 0。")
    return threshold


def parse_mode(value: str) -> str:
    mode = value.strip().lower()
    if mode not in MODE_LABELS:
        allowed = "|".join(MODE_LABELS)
        raise CalibrationFileError(f"判定模式必须是 {allowed}。")
    return mode


def is_ng(delta_x: Decimal, delta_y: Decimal, threshold: Decimal, mode: str) -> bool:
    if mode == "both":
        return abs(delta_x) > threshold or abs(delta_y) > threshold
    if mode == "x":
        return abs(delta_x) > threshold
    if mode == "y":
        return abs(delta_y) > threshold
    raise CalibrationFileError(f"未知判定模式：{mode}")


def analyze_points(
    actual_points: dict[int, Point], threshold: Decimal, mode: str = "both"
) -> AnalysisResult:
    mode = parse_mode(mode)
    theory_points = generate_theory_points()
    rows: list[AnalysisRow] = []

    for index in range(1, TOTAL_POINTS + 1):
        actual = actual_points[index]
        theory = theory_points[index]
        delta_x = actual.x - theory.x
        delta_y = actual.y - theory.y
        result = "NG" if is_ng(delta_x, delta_y, threshold, mode) else "OK"
        rows.append(
            AnalysisRow(
                index=index,
                theory_x=theory.x,
                theory_y=theory.y,
                actual_x=actual.x,
                actual_y=actual.y,
                delta_x=delta_x,
                delta_y=delta_y,
                result=result,
            )
        )

    ng_count = sum(1 for row in rows if row.result == "NG")
    ok_count = len(rows) - ng_count
    pass_rate = Decimal(ok_count) / Decimal(len(rows)) * Decimal("100")
    max_abs_delta_x = max(abs(row.delta_x) for row in rows)
    max_abs_delta_y = max(abs(row.delta_y) for row in rows)

    return AnalysisResult(
        rows=rows,
        total=len(rows),
        ok_count=ok_count,
        ng_count=ng_count,
        pass_rate=pass_rate,
        max_abs_delta_x=max_abs_delta_x,
        max_abs_delta_y=max_abs_delta_y,
        mode=mode,
    )


def run_gui() -> None:
    try:
        import tkinter as tk
        from tkinter import filedialog, messagebox, ttk
    except ModuleNotFoundError as exc:
        raise SystemExit(
            "当前 Python 环境缺少 tkinter。请在 Windows Python 中运行，或安装 tkinter 后再启动。"
        ) from exc

    root = tk.Tk()
    root.title("校正精度分析工具")
    root.geometry("1180x760")
    root.minsize(980, 620)

    file_path_var = tk.StringVar()
    threshold_var = tk.StringVar(value="0.1")
    mode_label_var = tk.StringVar(value=MODE_LABELS["both"])
    summary_var = tk.StringVar(value="请选择实际值文件并输入阈值。")
    ng_summary_var = tk.StringVar(value="NG序号：-")
    show_ng_only_var = tk.BooleanVar(value=False)
    current_result: AnalysisResult | None = None
    label_to_mode = {label: mode for mode, label in MODE_LABELS.items()}

    def choose_file() -> None:
        path = filedialog.askopenfilename(
            title="选择实际校正数据文件",
            filetypes=(("Text files", "*.txt"), ("All files", "*.*")),
        )
        if path:
            file_path_var.set(path)

    main = ttk.Frame(root, padding=12)
    main.pack(fill=tk.BOTH, expand=True)

    file_frame = ttk.Frame(main)
    file_frame.pack(fill=tk.X)

    ttk.Button(file_frame, text="选择实际值文件", command=choose_file).pack(side=tk.LEFT)
    file_entry = ttk.Entry(file_frame, textvariable=file_path_var)
    file_entry.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(8, 0))

    threshold_frame = ttk.Frame(main)
    threshold_frame.pack(fill=tk.X, pady=(10, 0))
    ttk.Label(threshold_frame, text="阈值：").pack(side=tk.LEFT)
    ttk.Entry(threshold_frame, textvariable=threshold_var, width=12).pack(side=tk.LEFT)
    ttk.Label(threshold_frame, text="判定模式：").pack(side=tk.LEFT, padx=(12, 0))
    ttk.Combobox(
        threshold_frame,
        textvariable=mode_label_var,
        values=tuple(MODE_LABELS.values()),
        state="readonly",
        width=12,
    ).pack(side=tk.LEFT)
    ttk.Checkbutton(threshold_frame, text="只显示NG点", variable=show_ng_only_var).pack(
        side=tk.LEFT, padx=(12, 0)
    )

    summary_label = ttk.Label(main, textvariable=summary_var, anchor=tk.W)
    summary_label.pack(fill=tk.X, pady=(10, 8))
    ng_summary_label = ttk.Label(main, textvariable=ng_summary_var, anchor=tk.W)
    ng_summary_label.pack(fill=tk.X, pady=(0, 8))

    columns = (
        "index",
        "theory_x",
        "theory_y",
        "actual_x",
        "actual_y",
        "delta_x",
        "delta_y",
        "result",
    )
    headings = {
        "index": "序号",
        "theory_x": "理论X",
        "theory_y": "理论Y",
        "actual_x": "实际X",
        "actual_y": "实际Y",
        "delta_x": "X偏差",
        "delta_y": "Y偏差",
        "result": "结果",
    }
    widths = {
        "index": 70,
        "theory_x": 120,
        "theory_y": 120,
        "actual_x": 120,
        "actual_y": 120,
        "delta_x": 120,
        "delta_y": 120,
        "result": 80,
    }

    table_frame = ttk.Frame(main)
    table_frame.pack(fill=tk.BOTH, expand=True)

    tree = ttk.Treeview(table_frame, columns=columns, show="headings", height=24)
    for column in columns:
        tree.heading(column, text=headings[column])
        tree.column(column, width=widths[column], anchor=tk.CENTER, stretch=True)

    y_scroll = ttk.Scrollbar(table_frame, orient=tk.VERTICAL, command=tree.yview)
    x_scroll = ttk.Scrollbar(table_frame, orient=tk.HORIZONTAL, command=tree.xview)
    tree.configure(yscrollcommand=y_scroll.set, xscrollcommand=x_scroll.set)

    tree.grid(row=0, column=0, sticky="nsew")
    y_scroll.grid(row=0, column=1, sticky="ns")
    x_scroll.grid(row=1, column=0, sticky="ew")
    table_frame.columnconfigure(0, weight=1)
    table_frame.rowconfigure(0, weight=1)

    tree.tag_configure("ng", background="#ffe4e6", foreground="#991b1b")
    tree.tag_configure("ok", background="#ffffff", foreground="#111827")

    def populate_table(result: AnalysisResult) -> None:
        tree.delete(*tree.get_children())
        visible_rows = (
            [row for row in result.rows if row.result == "NG"]
            if show_ng_only_var.get()
            else result.rows
        )
        for row in visible_rows:
            tag = "ng" if row.result == "NG" else "ok"
            tree.insert(
                "",
                tk.END,
                values=(
                    row.index,
                    format_decimal(row.theory_x),
                    format_decimal(row.theory_y),
                    format_decimal(row.actual_x),
                    format_decimal(row.actual_y),
                    format_decimal(row.delta_x),
                    format_decimal(row.delta_y),
                    row.result,
                ),
                tags=(tag,),
            )

    def analyze() -> None:
        nonlocal current_result
        try:
            if not file_path_var.get().strip():
                raise CalibrationFileError("请先选择实际值文件。")
            threshold = parse_threshold(threshold_var.get())
            mode = label_to_mode[mode_label_var.get()]
            actual_points = parse_point_file(file_path_var.get())
            result = analyze_points(actual_points, threshold, mode)
        except CalibrationFileError as exc:
            messagebox.showerror("无法分析", str(exc))
            return
        except OSError as exc:
            messagebox.showerror("无法读取文件", str(exc))
            return

        current_result = result
        populate_table(result)
        summary_var.set(
            "判定模式：{mode}    总点数：{total}    OK：{ok}    NG：{ng}    达标率：{rate}%    "
            "最大X偏差：{max_x}    最大Y偏差：{max_y}".format(
                mode=MODE_LABELS[result.mode],
                total=result.total,
                ok=result.ok_count,
                ng=result.ng_count,
                rate=format_decimal(result.pass_rate, 2),
                max_x=format_decimal(result.max_abs_delta_x),
                max_y=format_decimal(result.max_abs_delta_y),
            )
        )
        ng_summary_var.set(f"NG序号：{format_ng_indexes(result.rows)}")

    def refresh_filter() -> None:
        if current_result is not None:
            populate_table(current_result)

    ttk.Button(threshold_frame, text="开始分析", command=analyze).pack(side=tk.LEFT, padx=(12, 0))
    show_ng_only_var.trace_add("write", lambda *_args: refresh_filter())

    root.mainloop()


def run_cli(args: argparse.Namespace) -> int:
    threshold = parse_threshold(args.threshold)
    mode = parse_mode(args.mode)
    actual_points = parse_point_file(args.analyze)
    result = analyze_points(actual_points, threshold, mode)

    print(f"判定模式: {MODE_LABELS[result.mode]}")
    print(f"总点数: {result.total}")
    print(f"OK: {result.ok_count}")
    print(f"NG: {result.ng_count}")
    print(f"达标率: {format_decimal(result.pass_rate, 2)}%")
    print(f"最大X偏差: {format_decimal(result.max_abs_delta_x)}")
    print(f"最大Y偏差: {format_decimal(result.max_abs_delta_y)}")
    print(f"NG序号: {format_ng_indexes(result.rows, limit=args.limit)}")

    if args.show_ng:
        print("序号 理论X 理论Y 实际X 实际Y X偏差 Y偏差")
        for row in result.rows:
            if row.result != "NG":
                continue
            print(
                row.index,
                format_decimal(row.theory_x),
                format_decimal(row.theory_y),
                format_decimal(row.actual_x),
                format_decimal(row.actual_y),
                format_decimal(row.delta_x),
                format_decimal(row.delta_y),
            )

    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="校正精度分析工具")
    parser.add_argument("--analyze", help="实际校正数据 txt 文件；省略时启动 Windows 桌面界面")
    parser.add_argument("--threshold", default="0.1", help="管控阈值，默认 0.1")
    parser.add_argument(
        "--mode",
        choices=tuple(MODE_LABELS),
        default="both",
        help="判定模式：both=X或Y超限，x=只看X，y=只看Y；默认 both",
    )
    parser.add_argument("--show-ng", action="store_true", help="命令行输出 NG 点明细")
    parser.add_argument("--limit", type=int, default=80, help="NG 序号摘要最多显示多少个点")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        if args.analyze:
            return run_cli(args)
        run_gui()
        return 0
    except CalibrationFileError as exc:
        parser.exit(2, f"错误: {exc}\n")


if __name__ == "__main__":
    raise SystemExit(main())
