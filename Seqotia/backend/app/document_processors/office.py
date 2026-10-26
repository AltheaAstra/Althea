import re
from io import BytesIO
from zipfile import BadZipFile, ZipFile
from xml.etree import ElementTree as ET

from .base import ExtractionResult


WORD_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
SHEET_NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
SLIDE_NS = "http://schemas.openxmlformats.org/drawingml/2006/main"


def _texts(xml: bytes, namespace: str) -> list[str]:
    try:
        root = ET.fromstring(xml)
    except ET.ParseError as exc:
        raise ValueError("The document contains invalid XML.") from exc
    return [node.text or "" for node in root.iter(f"{{{namespace}}}t")]


def extract_docx(content: bytes) -> ExtractionResult:
    try:
        with ZipFile(BytesIO(content)) as archive:
            parts = _texts(archive.read("word/document.xml"), WORD_NS)
    except (BadZipFile, KeyError, OSError, ValueError):
        return ExtractionResult(None, "needs_review", "The DOCX content could not be read.")
    text = " ".join(part.strip() for part in parts if part.strip()).strip()
    return ExtractionResult(text or None, "completed" if text else "needs_review", None if text else "The document contains no readable text.")


def extract_xlsx(content: bytes) -> ExtractionResult:
    try:
        with ZipFile(BytesIO(content)) as archive:
            shared: list[str] = []
            if "xl/sharedStrings.xml" in archive.namelist():
                root = ET.fromstring(archive.read("xl/sharedStrings.xml"))
                shared = ["".join(node.text or "" for node in item.iter(f"{{{SHEET_NS}}}t")) for item in root.findall(f"{{{SHEET_NS}}}si")]
            sheet_names = sorted(
                (name for name in archive.namelist() if re.fullmatch(r"xl/worksheets/sheet\d+\.xml", name)),
                key=lambda name: int(re.search(r"sheet(\d+)", name).group(1)),
            )
            cells: list[str] = []
            for sheet_name in sheet_names:
                root = ET.fromstring(archive.read(sheet_name))
                for cell in root.iter(f"{{{SHEET_NS}}}c"):
                    value = cell.find(f"{{{SHEET_NS}}}v")
                    if value is None or value.text is None:
                        inline = cell.find(f"{{{SHEET_NS}}}is")
                        if inline is not None:
                            text = "".join(node.text or "" for node in inline.iter(f"{{{SHEET_NS}}}t"))
                            if text.strip():
                                cells.append(text.strip())
                        continue
                    raw = value.text.strip()
                    if cell.get("t") == "s":
                        try:
                            raw = shared[int(raw)]
                        except (ValueError, IndexError):
                            continue
                    if raw:
                        cells.append(raw)
    except (BadZipFile, KeyError, OSError, ET.ParseError, ValueError):
        return ExtractionResult(None, "needs_review", "The XLSX content could not be read.")
    text = " | ".join(cells)
    return ExtractionResult(text or None, "completed" if text else "needs_review", None if text else "The workbook contains no readable cells.")


def extract_pptx(content: bytes) -> ExtractionResult:
    try:
        with ZipFile(BytesIO(content)) as archive:
            slide_names = sorted(
                (name for name in archive.namelist() if re.fullmatch(r"ppt/slides/slide\d+\.xml", name)),
                key=lambda name: int(re.search(r"slide(\d+)", name).group(1)),
            )
            slides = [" ".join(part.strip() for part in _texts(archive.read(name), SLIDE_NS) if part.strip()) for name in slide_names]
    except (BadZipFile, KeyError, OSError, ValueError):
        return ExtractionResult(None, "needs_review", "The PPTX content could not be read.")
    text = "\n".join(slide for slide in slides if slide)
    return ExtractionResult(text or None, "completed" if text else "needs_review", None if text else "The presentation contains no readable text.")
