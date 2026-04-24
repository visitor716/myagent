#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
图片智能重命名工具 - 使用 ChatOCR 的 OCR 引擎
"""

import os
import sys
import re
import hashlib
import shutil
from datetime import datetime
from pathlib import Path
from typing import Optional, Tuple

# 添加 ChatOCR 后端到 Python 路径
CHATOCR_BACKEND = "/home/zhanxp/projects/ChatOCR/backend"
sys.path.insert(0, CHATOCR_BACKEND)

# 导入 ChatOCR 的 OCR 引擎
try:
    from ocr_engine import OcrEngine
    OCR_ENGINE_AVAILABLE = True
    print("✓ 成功加载 ChatOCR OCR 引擎")
except ImportError as e:
    print(f"⚠ 无法加载 ChatOCR OCR 引擎: {e}")
    OCR_ENGINE_AVAILABLE = False


class ImageRenamer:
    """图片重命名器"""

    def __init__(self):
        self.ocr_engine = None
        if OCR_ENGINE_AVAILABLE:
            try:
                self.ocr_engine = OcrEngine()
                print("✓ OCR 引擎初始化完成")
            except Exception as e:
                print(f"⚠ OCR 引擎初始化失败: {e}")
                self.ocr_engine = None

    def get_file_hash(self, filepath: str) -> str:
        """获取文件的 MD5 哈希值"""
        hash_md5 = hashlib.md5()
        with open(filepath, "rb") as f:
            for chunk in iter(lambda: f.read(4096), b""):
                hash_md5.update(chunk)
        return hash_md5.hexdigest()[:8]  # 只取前8位

    def extract_date(self, text: str) -> Optional[str]:
        """从文本中提取日期时间"""
        # 日期格式: 2024-01-15, 2024/01/15, 2024年01月15日, 24-01-15, 01/15/2024
        date_patterns = [
            r'(\d{4})[-/年](\d{1,2})[-/月](\d{1,2})',  # 2024-01-15, 2024/01/15, 2024年01月15日
            r'(\d{2})[-/](\d{1,2})[-/](\d{2})',  # 24-01-15, 01/15/24
        ]

        for pattern in date_patterns:
            matches = re.findall(pattern, text)
            for match in matches:
                if len(match) == 3:
                    year, month, day = match
                    # 处理两位年份
                    if len(year) == 2:
                        year = '20' + year if int(year) < 50 else '19' + year
                    try:
                        # 验证日期有效性
                        dt = datetime(int(year), int(month), int(day))
                        return dt.strftime('%Y%m%d')
                    except ValueError:
                        continue
        return None

    def extract_time(self, text: str) -> Optional[str]:
        """从文本中提取时间"""
        # 时间格式: 14:30, 14:30:45, 2:30 PM
        time_patterns = [
            r'(\d{1,2}):(\d{2})(?::(\d{2}))?',  # 14:30, 14:30:45
        ]

        for pattern in time_patterns:
            matches = re.findall(pattern, text)
            for match in matches:
                if len(match) >= 2:
                    hour, minute = match[0], match[1]
                    second = match[2] if len(match) > 2 and match[2] else '00'
                    try:
                        # 验证时间有效性
                        hour_int = int(hour)
                        minute_int = int(minute)
                        second_int = int(second)
                        if 0 <= hour_int < 24 and 0 <= minute_int < 60 and 0 <= second_int < 60:
                            return f"{hour_int:02d}{minute_int:02d}{second_int:02d}"
                    except ValueError:
                        continue
        return None

    def extract_amount(self, text: str) -> Optional[str]:
        """从文本中提取金额"""
        # 金额格式: ¥123.45, ￥123.45, $123.45, 123.45元, 123元
        amount_patterns = [
            r'[¥￥$](\d+(?:\.\d{1,2})?)',  # ¥123.45, ￥123.45, $123.45
            r'(\d+(?:\.\d{1,2})?)[元块钱]',  # 123.45元, 123元
            r'金额[:：]?\s*[¥￥$]?(\d+(?:\.\d{1,2})?)',  # 金额: 123.45
            r'合计[:：]?\s*[¥￥$]?(\d+(?:\.\d{1,2})?)',  # 合计: 123.45
            r'小计[:：]?\s*[¥￥$]?(\d+(?:\.\d{1,2})?)',  # 小计: 123.45
        ]

        for pattern in amount_patterns:
            matches = re.findall(pattern, text)
            for match in matches:
                if match:
                    # 格式化金额，保留两位小数
                    try:
                        amount = float(match)
                        return f"{amount:.2f}".replace('.', '')
                    except ValueError:
                        continue
        return None

    def ocr_image(self, image_path: str) -> str:
        """使用 OCR 识别图片文字"""
        if not self.ocr_engine:
            return ""

        try:
            print(f"  正在识别: {os.path.basename(image_path)}")
            text, confidence, text_blocks = self.ocr_engine.recognize(image_path, use_cache=False)
            return text
        except Exception as e:
            print(f"  OCR 识别错误: {e}")
            return ""

    def generate_new_name(self, image_path: str) -> str:
        """生成新的文件名"""
        # 获取原文件扩展名
        ext = Path(image_path).suffix.lower()

        # 尝试 OCR 识别
        ocr_text = ""
        if self.ocr_engine:
            ocr_text = self.ocr_image(image_path)

        # 提取关键字
        date_str = self.extract_date(ocr_text)
        time_str = self.extract_time(ocr_text)
        amount_str = self.extract_amount(ocr_text)

        # 构建文件名
        name_parts = []

        if date_str:
            name_parts.append(date_str)
            if time_str:
                name_parts.append(time_str)

        if amount_str:
            name_parts.append(amount_str)

        # 如果没有提取到关键字，使用文件哈希
        if not name_parts:
            file_hash = self.get_file_hash(image_path)
            name_parts.append(file_hash)

        # 组合文件名
        new_name = "_".join(name_parts) + ext

        return new_name

    def rename_image(self, image_path: str, dry_run: bool = False) -> Tuple[str, str, bool]:
        """
        重命名图片

        Args:
            image_path: 图片路径
            dry_run: 是否只是预览不实际重命名

        Returns:
            (原路径, 新路径, 是否成功)
        """
        if not os.path.exists(image_path):
            print(f"文件不存在: {image_path}")
            return image_path, "", False

        # 生成新文件名
        new_name = self.generate_new_name(image_path)
        dir_path = os.path.dirname(image_path)
        new_path = os.path.join(dir_path, new_name)

        # 如果新文件名已存在，添加序号
        counter = 1
        base_name = os.path.splitext(new_name)[0]
        ext = os.path.splitext(new_name)[1]
        while os.path.exists(new_path):
            new_name = f"{base_name}_{counter}{ext}"
            new_path = os.path.join(dir_path, new_name)
            counter += 1

        # 实际重命名
        if not dry_run:
            try:
                shutil.move(image_path, new_path)
                print(f"✓ 重命名: {os.path.basename(image_path)} -> {new_name}")
                return image_path, new_path, True
            except Exception as e:
                print(f"✗ 重命名失败: {e}")
                return image_path, new_path, False
        else:
            print(f"  预览: {os.path.basename(image_path)} -> {new_name}")
            return image_path, new_path, True

    def process_directory(self, dir_path: str, dry_run: bool = False) -> list:
        """
        处理目录中的所有图片

        Args:
            dir_path: 目录路径
            dry_run: 是否只是预览不实际重命名

        Returns:
            处理结果列表
        """
        if not os.path.isdir(dir_path):
            print(f"目录不存在: {dir_path}")
            return []

        # 支持的图片格式
        image_exts = {'.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'}

        # 收集图片文件
        image_files = []
        for filename in os.listdir(dir_path):
            ext = os.path.splitext(filename)[1].lower()
            if ext in image_exts:
                image_files.append(os.path.join(dir_path, filename))

        if not image_files:
            print(f"目录中没有找到图片: {dir_path}")
            return []

        print(f"找到 {len(image_files)} 张图片")

        # 处理图片
        results = []
        for image_path in sorted(image_files):
            result = self.rename_image(image_path, dry_run=dry_run)
            results.append(result)

        return results


def main():
    """主函数"""
    if len(sys.argv) < 2:
        print("用法:")
        print("  python rename_with_chatocr.py <目录路径> [--dry-run]")
        print("  python rename_with_chatocr.py --test")
        return

    arg1 = sys.argv[1]

    if arg1 == "--test":
        # 测试模式 - 使用当前目录
        test_dir = os.getcwd()
        print(f"测试模式: {test_dir}")
        renamer = ImageRenamer()
        renamer.process_directory(test_dir, dry_run=True)
        return

    dir_path = arg1
    dry_run = "--dry-run" in sys.argv

    if not os.path.isdir(dir_path):
        print(f"错误: 目录不存在 - {dir_path}")
        return

    renamer = ImageRenamer()

    print("=" * 60)
    if dry_run:
        print("预览模式 - 不会实际重命名文件")
    else:
        print("实际重命名模式")
    print("=" * 60)

    results = renamer.process_directory(dir_path, dry_run=dry_run)

    # 统计结果
    success_count = sum(1 for r in results if r[2])
    print("=" * 60)
    print(f"处理完成: 共 {len(results)} 张，成功 {success_count} 张")


if __name__ == "__main__":
    main()
