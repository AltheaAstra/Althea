"""Create editable Word documents for Document Studio drafts."""

from __future__ import annotations

import re
import xml.etree.ElementTree as ET
from decimal import Decimal, InvalidOperation
from io import BytesIO
from zipfile import ZIP_DEFLATED, ZipFile


_W_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
_R_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
_PKG_REL_NS = "http://schemas.openxmlformats.org/package/2006/relationships"
_CONTENT_NS = "http://schemas.openxmlformats.org/package/2006/content-types"
ET.register_namespace("w", _W_NS)
ET.register_namespace("r", _R_NS)


def _w(name: str) -> str:
    return f"{{{_W_NS}}}{name}"


def _set_font(run_properties: ET.Element, size: int, *, bold: bool = False, color: str | None = None) -> None:
    fonts = ET.SubElement(run_properties, _w("rFonts"))
    for name in ("ascii", "hAnsi", "eastAsia", "cs"):
        fonts.set(_w(name), "TH Sarabun New")
    if bold:
        ET.SubElement(run_properties, _w("b"))
        ET.SubElement(run_properties, _w("bCs"))
    if color:
        ET.SubElement(run_properties, _w("color")).set(_w("val"), color)
    ET.SubElement(run_properties, _w("sz")).set(_w("val"), str(size))
    ET.SubElement(run_properties, _w("szCs")).set(_w("val"), str(size))


def _run(paragraph: ET.Element, text: object, *, size: int = 22, bold: bool = False,
         color: str | None = None) -> None:
    run = ET.SubElement(paragraph, _w("r"))
    properties = ET.SubElement(run, _w("rPr"))
    _set_font(properties, size, bold=bold, color=color)
    content = str(text if text is not None else "")
    content = "".join(
        char for char in content
        if char in "\t\n\r" or 0x20 <= ord(char) <= 0xD7FF
        or 0xE000 <= ord(char) <= 0xFFFD or 0x10000 <= ord(char) <= 0x10FFFF
    )
    lines = content.splitlines() or [""]
    for index, line in enumerate(lines):
        if index:
            ET.SubElement(run, _w("br"))
        node = ET.SubElement(run, _w("t"))
        node.set("{http://www.w3.org/XML/1998/namespace}space", "preserve")
        node.text = line


def _paragraph(parent: ET.Element, text: object = "", *, size: int = 22, bold: bool = False,
               color: str | None = None, alignment: str | None = None,
               before: int = 0, after: int = 100) -> ET.Element:
    paragraph = ET.SubElement(parent, _w("p"))
    properties = ET.SubElement(paragraph, _w("pPr"))
    spacing = ET.SubElement(properties, _w("spacing"))
    spacing.set(_w("before"), str(before))
    spacing.set(_w("after"), str(after))
    if alignment:
        ET.SubElement(properties, _w("jc")).set(_w("val"), alignment)
    _run(paragraph, text, size=size, bold=bold, color=color)
    return paragraph


def _label_value(parent: ET.Element, label: str, value: object) -> None:
    paragraph = ET.SubElement(parent, _w("p"))
    properties = ET.SubElement(paragraph, _w("pPr"))
    ET.SubElement(properties, _w("spacing")).set(_w("after"), "45")
    _run(paragraph, f"{label}: ", bold=True)
    _run(paragraph, value if value not in (None, "") else "—")


def _cell(row: ET.Element, text: object, width: int, *, header: bool = False,
          align: str | None = None) -> None:
    cell = ET.SubElement(row, _w("tc"))
    properties = ET.SubElement(cell, _w("tcPr"))
    ET.SubElement(properties, _w("tcW"), {_w("w"): str(width), _w("type"): "dxa"})
    if header:
        ET.SubElement(properties, _w("shd"), {_w("fill"): "E8F2EC", _w("val"): "clear"})
    paragraph = ET.SubElement(cell, _w("p"))
    paragraph_properties = ET.SubElement(paragraph, _w("pPr"))
    ET.SubElement(paragraph_properties, _w("spacing")).set(_w("after"), "35")
    if align:
        ET.SubElement(paragraph_properties, _w("jc")).set(_w("val"), align)
    _run(paragraph, text, size=20, bold=header)


def _table(parent: ET.Element, headers: list[str], rows: list[list[object]]) -> None:
    widths = [4200, 900, 1000, 1600, 1900]
    table = ET.SubElement(parent, _w("tbl"))
    properties = ET.SubElement(table, _w("tblPr"))
    ET.SubElement(properties, _w("tblW"), {_w("w"): "9600", _w("type"): "dxa"})
    borders = ET.SubElement(properties, _w("tblBorders"))
    for edge in ("top", "left", "bottom", "right", "insideH", "insideV"):
        ET.SubElement(borders, _w(edge), {_w("val"): "single", _w("sz"): "4", _w("space"): "0", _w("color"): "B9C9BF"})
    grid = ET.SubElement(table, _w("tblGrid"))
    for width in widths:
        ET.SubElement(grid, _w("gridCol")).set(_w("w"), str(width))

    header_row = ET.SubElement(table, _w("tr"))
    ET.SubElement(ET.SubElement(header_row, _w("trPr")), _w("tblHeader"))
    for index, header in enumerate(headers):
        _cell(header_row, header, widths[index], header=True,
              align="center" if index else None)
    for values in rows:
        row = ET.SubElement(table, _w("tr"))
        for index, value in enumerate(values):
            _cell(row, value, widths[index], align="right" if index > 0 else None)


def _money(value: object) -> str:
    try:
        return f"{Decimal(str(value or '0')):,.2f}"
    except (InvalidOperation, ValueError):
        return str(value or "0.00")


def _item_rows(metadata: dict) -> list[list[object]]:
    rows: list[list[object]] = []
    for item in metadata.get("items", []):
        if not isinstance(item, dict):
            continue
        quantity = item.get("quantity", "")
        unit_price = _money(item.get("unit_price", "0"))
        line_total = _money(item.get("line_total", "0"))
        rows.append([
            item.get("name", ""),
            quantity,
            item.get("unit", ""),
            unit_price,
            line_total,
        ])
    return rows


def _signature_lines(body: ET.Element, labels: list[str]) -> None:
    _paragraph(body, "", after=180)
    for label in labels:
        _paragraph(body, f"ลงชื่อ ____________________________________     {label}", alignment="center", after=160)


def render_draft_docx(document: dict) -> tuple[bytes, str]:
    """Return an editable DOCX payload and a safe download filename."""
    category = document.get("category")
    metadata = document.get("metadata") or {}
    title, english_title = {
        "po": ("ใบสั่งซื้อ", "PURCHASE ORDER"),
        "pr": ("ใบขอซื้อ", "PURCHASE REQUISITION"),
        "repair": ("ใบแจ้งซ่อมอุปกรณ์", "DEVICE REPAIR REQUEST"),
    }[category]

    root = ET.Element(_w("document"))
    body = ET.SubElement(root, _w("body"))
    _paragraph(body, title, size=36, bold=True, color="176B49", alignment="center", after=0)
    _paragraph(body, english_title, size=24, bold=True, color="52685B", alignment="center", after=150)
    _paragraph(body, "เอกสารฉบับร่าง · กรุณาตรวจสอบข้อมูลก่อนนำไปใช้งาน", size=20,
               color="8A641B", alignment="center", after=220)

    if category == "po":
        _label_value(body, "เลขที่ PO", metadata.get("po_number"))
        _label_value(body, "วันที่เอกสาร", metadata.get("document_date"))
        _label_value(body, "ผู้ขาย", metadata.get("vendor"))
        _label_value(body, "เลขที่อ้างอิง", metadata.get("reference"))
        _label_value(body, "เงื่อนไข", metadata.get("terms"))
        _paragraph(body, "รายการสินค้าและบริการ", size=24, bold=True, color="176B49", before=150)
        _table(body, ["รายการ", "จำนวน", "หน่วย", "ราคาต่อหน่วย", "รวม"], _item_rows(metadata))
        _paragraph(body, f"ยอดรวมทั้งสิ้น: {_money(metadata.get('total_amount'))} บาท",
                   size=24, bold=True, alignment="right", before=100)
        _label_value(body, "หมายเหตุ", metadata.get("notes"))
        _signature_lines(body, ["ผู้จัดทำ / ผู้ซื้อ", "ผู้มีอำนาจอนุมัติ"])
    elif category == "pr":
        _label_value(body, "เลขที่ PR", metadata.get("pr_number"))
        _label_value(body, "วันที่ขอซื้อ", metadata.get("request_date"))
        _label_value(body, "ผู้ขอซื้อ", metadata.get("requester"))
        _label_value(body, "แผนก / หน่วยงาน", metadata.get("department"))
        _label_value(body, "วัตถุประสงค์", metadata.get("purpose"))
        _paragraph(body, "รายการที่ขอซื้อ", size=24, bold=True, color="176B49", before=150)
        _table(body, ["รายการ", "จำนวน", "หน่วย", "ราคาประมาณ", "รวมประมาณ"], _item_rows(metadata))
        _paragraph(body, f"ยอดรวมโดยประมาณ: {_money(metadata.get('estimated_total'))} บาท",
                   size=24, bold=True, alignment="right", before=100)
        _label_value(body, "เหตุผลความจำเป็น", metadata.get("justification"))
        _label_value(body, "ข้อมูลอ้างอิง", metadata.get("reference"))
        _signature_lines(body, ["ผู้ขอซื้อ", "ผู้อนุมัติ"])
    else:
        urgency = {"low": "ต่ำ", "normal": "ปกติ", "high": "เร่งด่วน"}.get(metadata.get("urgency"), "ปกติ")
        repair_status = {"reported": "รับแจ้งแล้ว", "in_progress": "กำลังซ่อม", "completed": "ซ่อมเสร็จแล้ว"}.get(metadata.get("repair_status"), "รับแจ้งแล้ว")
        _label_value(body, "เลขที่แจ้งซ่อม", metadata.get("request_number"))
        _label_value(body, "วันที่แจ้ง", metadata.get("report_date"))
        _label_value(body, "ระดับความเร่งด่วน", urgency)
        _label_value(body, "สถานะงานซ่อม", repair_status)
        _label_value(body, "ผู้แจ้ง", metadata.get("reporter"))
        _label_value(body, "อุปกรณ์", metadata.get("equipment_name"))
        _label_value(body, "หมายเลขทรัพย์สิน", metadata.get("asset_id"))
        _label_value(body, "สถานที่", metadata.get("location"))
        _paragraph(body, "รายละเอียดอาการ", size=24, bold=True, color="176B49", before=120)
        _paragraph(body, metadata.get("issue_description", ""), after=140)
        if metadata.get("technician_name"):
            _label_value(body, "ช่างผู้รับผิดชอบ", metadata.get("technician_name"))
        if metadata.get("completed_date"):
            _label_value(body, "วันที่ซ่อมเสร็จ", metadata.get("completed_date"))
        if metadata.get("diagnosis"):
            _paragraph(body, "สาเหตุ / ผลการตรวจสอบ", size=24, bold=True, color="176B49", before=120)
            _paragraph(body, metadata.get("diagnosis"), after=140)
        _paragraph(body, "งานที่ดำเนินการ", size=24, bold=True, color="176B49", before=120)
        if metadata.get("work_performed"):
            _paragraph(body, metadata.get("work_performed"), after=140)
        else:
            for _ in range(3):
                _paragraph(body, "________________________________________________________________________________", color="9AA99F", after=120)
        if metadata.get("parts_used"):
            _label_value(body, "อะไหล่ที่ใช้", metadata.get("parts_used"))
        if metadata.get("repair_cost"):
            _label_value(body, "ค่าใช้จ่ายรวม", f"{_money(metadata.get('repair_cost'))} บาท")
        _label_value(body, "หมายเหตุ", metadata.get("notes"))
        _signature_lines(body, ["ผู้แจ้ง", "ช่างผู้ดำเนินการ"])

    section = ET.SubElement(body, _w("sectPr"))
    ET.SubElement(section, _w("pgSz"), {_w("w"): "11906", _w("h"): "16838"})
    ET.SubElement(section, _w("pgMar"), {
        _w("top"): "850", _w("right"): "1134", _w("bottom"): "850", _w("left"): "1134",
        _w("header"): "425", _w("footer"): "425", _w("gutter"): "0",
    })

    styles = ET.Element(_w("styles"))
    normal = ET.SubElement(styles, _w("style"), {_w("type"): "paragraph", _w("default"): "1", _w("styleId"): "Normal"})
    properties = ET.SubElement(normal, _w("rPr"))
    _set_font(properties, 22)

    output = BytesIO()
    with ZipFile(output, "w", compression=ZIP_DEFLATED) as archive:
        content_types = ET.Element(f"{{{_CONTENT_NS}}}Types")
        ET.SubElement(content_types, f"{{{_CONTENT_NS}}}Default", {"Extension": "rels", "ContentType": "application/vnd.openxmlformats-package.relationships+xml"})
        ET.SubElement(content_types, f"{{{_CONTENT_NS}}}Default", {"Extension": "xml", "ContentType": "application/xml"})
        ET.SubElement(content_types, f"{{{_CONTENT_NS}}}Override", {"PartName": "/word/document.xml", "ContentType": "application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"})
        ET.SubElement(content_types, f"{{{_CONTENT_NS}}}Override", {"PartName": "/word/styles.xml", "ContentType": "application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"})
        archive.writestr("[Content_Types].xml", ET.tostring(content_types, encoding="utf-8", xml_declaration=True))

        relationships = ET.Element(f"{{{_PKG_REL_NS}}}Relationships")
        ET.SubElement(relationships, f"{{{_PKG_REL_NS}}}Relationship", {
            "Id": "rId1", "Type": "http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument", "Target": "word/document.xml",
        })
        archive.writestr("_rels/.rels", ET.tostring(relationships, encoding="utf-8", xml_declaration=True))

        document_relationships = ET.Element(f"{{{_PKG_REL_NS}}}Relationships")
        ET.SubElement(document_relationships, f"{{{_PKG_REL_NS}}}Relationship", {
            "Id": "rId1", "Type": "http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles", "Target": "styles.xml",
        })
        archive.writestr("word/_rels/document.xml.rels", ET.tostring(document_relationships, encoding="utf-8", xml_declaration=True))
        archive.writestr("word/document.xml", ET.tostring(root, encoding="utf-8", xml_declaration=True))
        archive.writestr("word/styles.xml", ET.tostring(styles, encoding="utf-8", xml_declaration=True))

    base_name = str(document.get("file_name") or english_title).strip()
    safe_name = re.sub(r'[\\/:*?"<>|\x00-\x1f]', "_", base_name).strip(" .") or english_title
    if not safe_name.lower().endswith(".docx"):
        safe_name += ".docx"
    return output.getvalue(), safe_name
