# Itinerary PDF Cropping And Word Merge

Use this reference when the user asks for `裁剪行程`, `合并行程单`, `行程单转 Word`, `把多个行程放到一个 Word`, or similar printable itinerary packaging.

## Command

```bash
python3 ~/.codex/skills/reimbursement-screenshot-organizer/scripts/expense_organizer.py merge-itineraries /path/to/报销目录/03-交通行程 -o /path/to/报销目录/03-交通行程/2026-05-20_滴滴行程报销单合并.docx
```

Optional filters:

```bash
python3 ~/.codex/skills/reimbursement-screenshot-organizer/scripts/expense_organizer.py merge-itineraries /path/to/03-交通行程 --glob '2026-05-20_交通行程_滴滴出行_*.pdf'
```

## Behavior

- Processes the first page of each matched PDF.
- Finds visible text blocks, ignores page-number text such as `页码` or `第 1 页`, and crops to the union of the remaining content with small padding.
- Keeps the itinerary title, route metadata, fare total, and detail table when they are present in the PDF text layer.
- Writes cropped PNGs under `裁剪图片` unless `--image-dir` is provided.
- Builds one DOCX with each cropped itinerary image on its own page.

## Verification

- Check the DOCX container with `file` and `zipfile.ZipFile(...).testzip()`.
- Parse `word/document.xml` and `word/_rels/document.xml.rels` if a structural check is needed.
- Visually inspect the generated PNGs when print layout matters; the crop should remove blank margins and page numbers without cutting off itinerary rows.

## Dependency Note

`merge-itineraries` requires PyMuPDF (`fitz`) at runtime. If system Python does not have it, use an existing PDF/OCR virtual environment that has `fitz`, or install `pymupdf` into the environment used for this command.
