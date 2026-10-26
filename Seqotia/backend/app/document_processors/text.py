from .base import ExtractionResult


def extract_txt(content: bytes) -> ExtractionResult:
    try:
        text = content.decode("utf-8-sig").replace("\x00", "").strip()
    except UnicodeDecodeError:
        return ExtractionResult(None, "needs_review", "The text file is not valid UTF-8.")
    if not text:
        return ExtractionResult(None, "needs_review", "The file contains no readable text.")
    return ExtractionResult(text, "completed")
