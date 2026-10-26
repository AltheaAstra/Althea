from dataclasses import dataclass
from zipfile import BadZipFile, ZipFile


@dataclass(frozen=True)
class ExtractionResult:
    text: str | None
    status: str
    message: str | None = None


def validate_office_archive(content: bytes, required_entry: str) -> bool:
    try:
        with ZipFile(__import__("io").BytesIO(content)) as archive:
            entries = archive.infolist()
            if len(entries) > 10000:
                return False
            expanded_size = sum(entry.file_size for entry in entries)
            if expanded_size > 100 * 1024 * 1024:
                return False
            if any(entry.file_size > 50 * 1024 * 1024 or (entry.compress_size > 0 and entry.file_size / entry.compress_size > 250) for entry in entries):
                return False
            names = {entry.filename for entry in entries}
            return "[Content_Types].xml" in names and required_entry in names
    except (BadZipFile, OSError):
        return False
