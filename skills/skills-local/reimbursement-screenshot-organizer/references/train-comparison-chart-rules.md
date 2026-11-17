# Train Ticket Comparison Chart Rules (火车票比价图规则)

## Principle

Company HQ is in Wuhan. Reimbursable train fare is capped at the Wuhan-equivalent price. If the traveler's actual trip starts from or ends at Wuhan (武汉站 or 汉口站), the actual ticket price is directly comparable — no comparison chart needed. Otherwise, a comparison chart (比价图) must show what the same trip would cost if departing from / arriving at Wuhan.

## When a comparison chart is needed

For each **trip** (a same-day multi-segment journey treated as one itinerary, judged by the first origin and final destination):

- **Origin is 武汉站/汉口站** → NO comparison chart needed (already a Wuhan departure)
- **Destination is 武汉站/汉口站** → NO comparison chart needed (already a Wuhan arrival)
- **Origin is NOT Wuhan AND destination is NOT Wuhan** → comparison chart NEEDED
- **Passing through 汉口站/武汉站 mid-trip does NOT exempt** the trip — only origin/destination station matters

## What comparison chart to prepare

For a trip that needs a comparison chart, prepare **one** chart showing the Wuhan-equivalent price:

- Trip: 扬州东 → 广州白云 (origin not Wuhan, destination not Wuhan)
  → Prepare 比价图: **扬州东 → 武汉** (same departure station, Wuhan as destination)
- Trip: 广州南 → 扬州东 (origin not Wuhan, passes through 汉口)
  → Prepare 比价图: **武汉 → 扬州东** (Wuhan as origin, same destination station)

Rule of thumb: pick the direction that substitutes the non-Wuhan endpoint with Wuhan, keeping the trip's actual origin or destination as-is.

## How to group trips

Same-day consecutive train segments form one trip, even if the last segment is on a later date (overnight travel). Example:

```
2026-04-30  扬州东 → 苏州园区     117.00
2026-04-30  苏州园区 → 上海松江    58.00
2026-05-02  上海松江 → 广州白云    367.00
```
→ One trip: 扬州东 → 广州白云 (need 比价图: 扬州东 → 武汉)

```
2026-05-10  广州南 → 汉口         522.00
2026-05-10  汉口 → 扬州东         273.00
```
→ One trip: 广州南 → 扬州东. Origin 广州南 is NOT Wuhan → need 比价图: 武汉 → 扬州东

## Word document assembly

Place comparison charts into a 2-column table in a Word document. Each chart gets:
- The screenshot image embedded at ~7cm width, centered
- A label below: "行程N 比价图：XX→武汉" or "行程N 比价图：武汉→XX" in 10pt

```python
from docx import Document
from docx.shared import Cm, Pt
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()
title = doc.add_paragraph()
title.alignment = WD_ALIGN_PARAGRAPH.CENTER
title.add_run("火车票比价图汇总").font.size = Pt(14)

table = doc.add_table(rows=1, cols=2)
# ... embed images and labels per cell
doc.save("火车票比价图汇总-YYYYMMDD.docx")
```
