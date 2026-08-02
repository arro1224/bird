from __future__ import annotations

import base64
import html
from pathlib import Path

from docx import Document
from docx.oxml.ns import qn
from docx.table import Table
from docx.text.paragraph import Paragraph


ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent.parent
DOCX_PATH = REPO / "outputs" / "merge_handoff_20260801" / "birdpart2_项目合并实施书_2026-08-01.docx"
OUT_DIR = REPO / "qa" / "merge_handoff_20260801" / "docx_fallback"
HTML_PATH = OUT_DIR / "birdpart2_项目合并实施书_2026-08-01.html"


def iter_block_items(document):
    parent = document.element.body
    for child in parent.iterchildren():
        if child.tag == qn("w:p"):
            yield Paragraph(child, document)
        elif child.tag == qn("w:tbl"):
            yield Table(child, document)


def paragraph_has_page_break(paragraph: Paragraph) -> bool:
    return bool(paragraph._p.xpath('.//w:br[@w:type="page"]'))


def paragraph_images(paragraph: Paragraph, document: Document) -> list[str]:
    images = []
    for blip in paragraph._p.xpath(".//a:blip"):
        rid = blip.get(qn("r:embed"))
        if not rid:
            continue
        part = document.part.related_parts.get(rid)
        if part is None:
            continue
        content_type = getattr(part, "content_type", "image/png")
        encoded = base64.b64encode(part.blob).decode("ascii")
        images.append(f"data:{content_type};base64,{encoded}")
    return images


def paragraph_html(paragraph: Paragraph, document: Document) -> str:
    parts = []
    if paragraph_has_page_break(paragraph):
        parts.append('<div class="page-break"></div>')
    images = paragraph_images(paragraph, document)
    if images:
        for src in images:
            parts.append(f'<div class="figure"><img src="{src}" alt="embedded document figure"></div>')
        if not paragraph.text.strip():
            return "".join(parts)

    text = html.escape(paragraph.text.strip())
    if not text:
        return "".join(parts)
    style = paragraph.style.name if paragraph.style else "Normal"
    if style == "Title":
        tag, cls = "h1", "cover-title"
    elif style == "Subtitle":
        tag, cls = "p", "subtitle"
    elif style.startswith("Heading 1"):
        tag, cls = "h1", ""
    elif style.startswith("Heading 2"):
        tag, cls = "h2", ""
    elif style.startswith("Heading 3"):
        tag, cls = "h3", ""
    elif "List Bullet" in style:
        tag, cls = "p", "list bullet"
        text = f"• {text}"
    elif "List Number" in style:
        tag, cls = "p", "list number"
    elif "Caption" in style:
        tag, cls = "p", "caption"
    else:
        tag, cls = "p", ""
    class_attr = f' class="{cls}"' if cls else ""
    parts.append(f"<{tag}{class_attr}>{text}</{tag}>")
    return "".join(parts)


def table_cell_text(cell) -> str:
    chunks = []
    for p in cell.paragraphs:
        if p.text.strip():
            chunks.append(html.escape(p.text.strip()))
    return "<br>".join(chunks)


def table_html(table: Table) -> str:
    rows = []
    if not table.rows:
        return ""
    header_cells = "".join(f"<th>{table_cell_text(c)}</th>" for c in table.rows[0].cells)
    rows.append(f"<thead><tr>{header_cells}</tr></thead>")
    body_rows = []
    for row in table.rows[1:]:
        cells = "".join(f"<td>{table_cell_text(c)}</td>" for c in row.cells)
        body_rows.append(f"<tr>{cells}</tr>")
    rows.append(f"<tbody>{''.join(body_rows)}</tbody>")
    return f"<table>{''.join(rows)}</table>"


def build_html() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    document = Document(DOCX_PATH)
    blocks = []
    for item in iter_block_items(document):
        if isinstance(item, Paragraph):
            blocks.append(paragraph_html(item, document))
        else:
            blocks.append(table_html(item))

    styles = """
    @page { size: Letter; margin: 1in; }
    * { box-sizing: border-box; }
    body { margin: 0; color: #202124; font-family: "Microsoft YaHei", "Noto Sans CJK SC", sans-serif; font-size: 11pt; line-height: 1.10; }
    h1 { color: #2E74B5; font-size: 16pt; margin: 16pt 0 8pt; break-after: avoid; page-break-after: avoid; }
    h2 { color: #2E74B5; font-size: 13pt; margin: 12pt 0 6pt; break-after: avoid; page-break-after: avoid; }
    h3 { color: #1F4D78; font-size: 12pt; margin: 8pt 0 4pt; break-after: avoid; page-break-after: avoid; }
    p { margin: 0 0 6pt; orphans: 3; widows: 3; }
    .cover-title { color: #17365D; font-size: 24pt; margin-top: 8pt; }
    .subtitle { color: #5F6B76; font-size: 12pt; margin-bottom: 12pt; }
    .list { margin-left: .25in; text-indent: -.18in; margin-bottom: 8pt; line-height: 1.167; }
    .caption { color: #5F6B76; font-size: 9pt; text-align: center; margin: 3pt 0 9pt; }
    .page-break { break-before: page; page-break-before: always; height: 0; }
    table { width: 100%; border-collapse: collapse; table-layout: fixed; margin: 4pt 0 8pt; font-size: 8.2pt; line-height: 1.02; }
    thead { display: table-header-group; }
    tr { break-inside: avoid; page-break-inside: avoid; }
    th, td { border: 1px solid #B7C3D0; padding: 4pt 5pt; vertical-align: middle; overflow-wrap: anywhere; }
    th { background: #17365D; color: white; font-weight: 700; text-align: center; }
    tbody tr:nth-child(even) td { background: #F8FAFC; }
    .figure { text-align: center; break-inside: avoid; page-break-inside: avoid; margin: 4pt 0 3pt; }
    img { max-width: 100%; height: auto; }
    """
    payload = f"<!doctype html><html lang='zh-CN'><head><meta charset='utf-8'><title>birdpart2 实施书 QA</title><style>{styles}</style></head><body>{''.join(blocks)}</body></html>"
    HTML_PATH.write_text(payload, encoding="utf-8")
    print(HTML_PATH)


if __name__ == "__main__":
    build_html()
