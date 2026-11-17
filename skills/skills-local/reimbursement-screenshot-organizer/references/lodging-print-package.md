# Lodging Payment Screenshot Print Package

## When to create

Create a print package Word document when the lodging directory has 2+ payment screenshots that need to be printed together for physical submission.

## Layout: 2×2 Grid

Use a 2-row × 2-column table in python-docx. Each cell holds one payment screenshot with a label below. Page fits up to 4 images per A4.

### Template

```python
from docx import Document
from docx.shared import Cm, Pt
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
import os

base = "/path/to/住宿费目录"
images = [
    ("住宿费_付款截图_2772.00_扬州沁润居酒店管理有限公司_2026-04-16.jpg", "扬州沁润居 ¥2,772.00  2026-04-16"),
    ("住宿费_付款截图_1980.00_扬州格林东方酒店_2026-05-10.jpg",    "扬州格林东方 ¥1,980.00  2026-05-10"),
]
total = 4752  # sum of all amounts

doc = Document()
for section in doc.sections:
    section.top_margin = Cm(1.0)
    section.bottom_margin = Cm(1.0)
    section.left_margin = Cm(1.0)
    section.right_margin = Cm(1.0)

title = doc.add_paragraph()
title.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = title.add_run("酒店付款截图打印包")
run.font.size = Pt(14)
run.bold = True
doc.add_paragraph()

table = doc.add_table(rows=2, cols=2)
table.alignment = WD_TABLE_ALIGNMENT.CENTER
img_width = Cm(7.5)

for i, (fname, label) in enumerate(images):
    row_idx = i // 2
    col_idx = i % 2
    cell = table.cell(row_idx, col_idx)
    cell.paragraphs[0].alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = cell.paragraphs[0].add_run()
    run.add_picture(os.path.join(base, fname), width=img_width)
    p = cell.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p.add_run(label)
    r.font.size = Pt(8)

doc.add_paragraph()

p_total = doc.add_paragraph()
p_total.alignment = WD_ALIGN_PARAGRAPH.CENTER
r_total = p_total.add_run(f"付款合计：¥{total}.00")
r_total.font.size = Pt(12)
r_total.bold = True

new_name = f"酒店付款截图打印包-{date}-{amount1}-{amount2}-总金额{total}.docx"
doc.save(os.path.join(base, new_name))
```

## Naming convention

```
酒店付款截图打印包-{YYYYMMDD}-{金额1}-{金额2}-总金额{合计}.docx
```

Example: `酒店付款截图打印包-20260629-2772.00-1980.00-总金额4752.00.docx`

## Image source preference

Use JPG originals (higher resolution), not PNG scaled-down copies. Embed directly at ~7.5 cm width — python-docx handles scaling and JPG originals produce crisper prints than pre-scaled PNGs.

## PNG/JPG duplicate handling

When both PNG and JPG of the same screenshot exist, the PNG is typically a scaled-down copy (e.g. 780px wide) while the JPG is the original (e.g. 1170px). Delete the PNG and use the JPG for the print package. If the PNG was previously embedded in an existing docx, rebuild the docx from the JPG.
