"""Format-specific document extraction adapters."""

from .base import ExtractionResult, validate_office_archive
from .office import extract_docx, extract_pptx, extract_xlsx
from .pdf import extract_pdf
from .text import extract_txt

__all__ = [
    "ExtractionResult",
    "validate_office_archive",
    "extract_docx",
    "extract_pptx",
    "extract_xlsx",
    "extract_pdf",
    "extract_txt",
]
