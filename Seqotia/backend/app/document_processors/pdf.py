from .base import ExtractionResult


def extract_pdf(content: bytes) -> ExtractionResult:
    if not content.startswith(b"%PDF-"):
        return ExtractionResult(None, "needs_review", "The file does not have a valid PDF header.")
    try:
        import fitz  # type: ignore[import-not-found]
    except ImportError:
        return ExtractionResult(None, "needs_review", "PDF text extraction is unavailable. Install the optional PyMuPDF dependency.")
    try:
        with fitz.open(stream=content, filetype="pdf") as document:
            text = "\n".join(page.get_text("text") for page in document).strip()
    except Exception:
        return ExtractionResult(None, "needs_review", "The PDF could not be read. It may be damaged, encrypted, or scanned.")
    if not text:
        return ExtractionResult(None, "needs_review", "No selectable PDF text was found. Scanned-file OCR is not configured.")
    return ExtractionResult(text, "completed")
