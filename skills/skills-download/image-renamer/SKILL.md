---
name: image-renamer
description: 识别图片内容并提取关键字（时间、金额等）进行智能重命名
argument-hint: "<directory> | test"
---

# 图片智能重命名工具

## 功能说明

使用 OCR 识别图片中的文字，提取时间、金额等关键字，自动为图片重命名。

## 使用方法

### 重命名指定目录中的图片
```
/image-renamer /path/to/images
```

### 测试功能（使用示例图片）
```
/image-renamer test
```

## 工作原理

1. 使用 PaddleOCR 识别图片中的文字
2. 提取时间（日期/时间）、金额等关键字
3. 生成唯一的文件名格式：`YYYYMMDD_HHMMSS_金额.jpg`
4. 如果无法提取关键字，则使用哈希值

## 依赖

- Python 3.10+
- PaddleOCR
- PaddlePaddle
