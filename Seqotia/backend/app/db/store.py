import json
import mimetypes
import re
import sqlite3
import uuid
from contextlib import contextmanager
from datetime import date, datetime, timedelta
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from pathlib import Path
from typing import Any, Iterator
from zoneinfo import ZoneInfo

from ..ai.provider import SuggestionProvider, create_suggestion_provider
from ..document_processors import (
    ExtractionResult,
    extract_docx,
    extract_pdf,
    extract_pptx,
    extract_txt,
    extract_xlsx,
    validate_office_archive,
)
from ..document_processors.draft_export import render_draft_docx


class StoreError(Exception):
    def __init__(self, message: str, status_code: int = 400):
        super().__init__(message)
        self.status_code = status_code


ALLOWED_TYPES = {".pdf", ".docx", ".xlsx", ".pptx", ".txt"}
OFFICE_ENTRIES = {
    ".docx": "word/document.xml",
    ".xlsx": "xl/workbook.xml",
    ".pptx": "ppt/presentation.xml",
}
MIME_ALIASES = {
    ".pdf": {"application/pdf"},
    ".docx": {"application/vnd.openxmlformats-officedocument.wordprocessingml.document"},
    ".xlsx": {"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"},
    ".pptx": {"application/vnd.openxmlformats-officedocument.presentationml.presentation"},
    ".txt": {"text/plain"},
}
DOC_CATEGORIES = {"po": "Purchase Order", "pr": "Purchase Requisition", "repair": "Repair Request"}
TEMPLATES = [
    {"id": "po", "name": "ใบสั่งซื้อ", "category": "po", "description": "รายการสินค้า บัญชีราคา และเงื่อนไข", "fields": ["po_number", "document_date", "vendor", "items", "reference", "terms", "notes"]},
    {"id": "pr", "name": "ใบขอซื้อ", "category": "pr", "description": "ผู้ขอซื้อ วัตถุประสงค์ และรายการ", "fields": ["pr_number", "request_date", "requester", "department", "purpose", "items", "justification", "reference"]},
    {"id": "repair", "name": "ใบแจ้งซ่อม", "category": "repair", "description": "รายละเอียดอุปกรณ์ อาการ และสถานที่", "fields": ["request_number", "report_date", "reporter", "equipment_name", "asset_id", "location", "issue_description", "urgency", "notes"]},
]


def now_bangkok() -> datetime:
    return datetime.now(ZoneInfo("Asia/Bangkok")).replace(microsecond=0)


def timestamp() -> str:
    return now_bangkok().isoformat()


def _json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


class Store:
    def __init__(self, database_path: Path, upload_dir: Path, max_upload_bytes: int,
                 suggestion_provider: SuggestionProvider | None = None):
        self.database_path = database_path
        self.upload_dir = upload_dir.resolve()
        self.max_upload_bytes = max_upload_bytes
        self.suggestion_provider = suggestion_provider or create_suggestion_provider()
        self.database_path.parent.mkdir(parents=True, exist_ok=True)
        self.upload_dir.mkdir(parents=True, exist_ok=True)
        self._migrate()

    @contextmanager
    def _connection(self) -> Iterator[sqlite3.Connection]:
        connection = sqlite3.connect(self.database_path, timeout=10)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys=ON")
        connection.execute("PRAGMA busy_timeout=10000")
        try:
            yield connection
            connection.commit()
        except Exception:
            connection.rollback()
            raise
        finally:
            connection.close()

    def _migrate(self) -> None:
        migration = Path(__file__).parents[2] / "migrations" / "001_initial.sql"
        with self._connection() as connection:
            version = int(connection.execute("PRAGMA user_version").fetchone()[0])
            if version > 1:
                raise RuntimeError("The local database version is newer than this backend supports.")
            if version == 0:
                connection.executescript(migration.read_text(encoding="utf-8"))
                connection.execute("PRAGMA user_version=1")

    def _folder_exists(self, connection: sqlite3.Connection, folder_id: int | None) -> bool:
        if folder_id is None:
            return True
        row = connection.execute("SELECT id FROM folders WHERE id=? AND archived_at IS NULL", (folder_id,)).fetchone()
        return row is not None

    def create_folder(self, name: str, parent_id: int | None = None) -> dict[str, Any]:
        name = name.strip()
        if not name or len(name) > 120:
            raise StoreError("Folder name must contain between 1 and 120 characters.", 422)
        if "/" in name or "\\" in name or any(ord(char) < 32 for char in name):
            raise StoreError("Folder name contains unsupported characters.", 422)
        now = timestamp()
        with self._connection() as connection:
            if not self._folder_exists(connection, parent_id):
                raise StoreError("Parent folder was not found.", 404)
            cursor = connection.execute(
                "INSERT INTO folders(name,parent_id,created_at,updated_at) VALUES(?,?,?,?)",
                (name, parent_id, now, now),
            )
            return self._folder(connection, int(cursor.lastrowid))

    def list_folders(self, search: str = "") -> list[dict[str, Any]]:
        with self._connection() as connection:
            return [dict(row) for row in connection.execute(
                """SELECT f.id,f.name,f.parent_id,f.created_at,f.updated_at,
                          (SELECT count(*) FROM documents d WHERE d.folder_id=f.id AND d.archived_at IS NULL) AS document_count
                   FROM folders f WHERE f.archived_at IS NULL AND f.name LIKE ? ORDER BY f.name COLLATE NOCASE""",
                (f"%{search}%",),
            )]

    def _folder(self, connection: sqlite3.Connection, folder_id: int) -> dict[str, Any]:
        row = connection.execute(
            """SELECT f.id,f.name,f.parent_id,f.created_at,f.updated_at,
                      (SELECT count(*) FROM documents d WHERE d.folder_id=f.id AND d.archived_at IS NULL) AS document_count
               FROM folders f WHERE f.id=? AND f.archived_at IS NULL""",
            (folder_id,),
        ).fetchone()
        if row is None:
            raise StoreError("Folder was not found.", 404)
        return dict(row)

    def update_folder(self, folder_id: int, changes: dict[str, Any]) -> dict[str, Any]:
        if not changes or set(changes) - {"name", "parent_id"}:
            raise StoreError("Only name and parent_id can be changed.", 422)
        with self._connection() as connection:
            current = self._folder(connection, folder_id)
            name = current["name"]
            parent_id = current["parent_id"]
            if "name" in changes:
                if not isinstance(changes["name"], str):
                    raise StoreError("Folder name must be text.", 422)
                name = changes["name"].strip()
                if not name or len(name) > 120 or "/" in name or "\\" in name or any(ord(char) < 32 for char in name):
                    raise StoreError("Folder name is invalid.", 422)
            if "parent_id" in changes:
                parent_id = changes["parent_id"]
                if parent_id is not None and (isinstance(parent_id, bool) or not isinstance(parent_id, int)):
                    raise StoreError("parent_id must be an integer or null.", 422)
                if parent_id == folder_id:
                    raise StoreError("A folder cannot be its own parent.", 409)
                if not self._folder_exists(connection, parent_id):
                    raise StoreError("Parent folder was not found.", 404)
                cursor = parent_id
                while cursor is not None:
                    if cursor == folder_id:
                        raise StoreError("A folder cannot be moved into one of its descendants.", 409)
                    row = connection.execute("SELECT parent_id FROM folders WHERE id=? AND archived_at IS NULL", (cursor,)).fetchone()
                    cursor = row["parent_id"] if row else None
            connection.execute("UPDATE folders SET name=?,parent_id=?,updated_at=? WHERE id=?", (name, parent_id, timestamp(), folder_id))
            return self._folder(connection, folder_id)

    def archive_folder(self, folder_id: int) -> None:
        with self._connection() as connection:
            self._folder(connection, folder_id)
            has_children = connection.execute("SELECT 1 FROM folders WHERE parent_id=? AND archived_at IS NULL LIMIT 1", (folder_id,)).fetchone()
            has_documents = connection.execute("SELECT 1 FROM documents WHERE folder_id=? AND archived_at IS NULL LIMIT 1", (folder_id,)).fetchone()
            if has_children or has_documents:
                raise StoreError("Move or archive the folder contents before archiving this folder.", 409)
            connection.execute("UPDATE folders SET archived_at=?,updated_at=? WHERE id=?", (timestamp(), timestamp(), folder_id))

    def _normalize_filename(self, filename: str) -> tuple[str, str]:
        name = filename.replace("\\", "/").split("/")[-1].strip()
        name = "".join(char for char in name if ord(char) >= 32 and char not in '<>:"|?*')
        if not name or len(name) > 255:
            raise StoreError("File name is invalid.", 422)
        extension = Path(name).suffix.lower()
        if extension not in ALLOWED_TYPES:
            raise StoreError("Supported file types are PDF, DOCX, XLSX, PPTX, and TXT.", 415)
        return name, extension

    def _validate_file(self, filename: str, content: bytes, content_type: str) -> tuple[str, str, ExtractionResult]:
        clean_name, extension = self._normalize_filename(filename)
        if not content:
            raise StoreError("The uploaded file is empty.", 422)
        if len(content) > self.max_upload_bytes:
            raise StoreError(f"File exceeds the {self.max_upload_bytes // (1024 * 1024)} MB upload limit.", 413)
        actual_type = (content_type or "application/octet-stream").split(";", 1)[0].strip().lower()
        if actual_type not in {"", "application/octet-stream", "binary/octet-stream", *MIME_ALIASES[extension]}:
            raise StoreError("The file type does not match its extension.", 415)
        if extension in OFFICE_ENTRIES and not validate_office_archive(content, OFFICE_ENTRIES[extension]):
            raise StoreError("The file is not a valid supported Office document.", 415)
        if extension == ".pdf" and not content.startswith(b"%PDF-"):
            raise StoreError("The file is not a valid PDF.", 415)
        if extension == ".txt":
            extracted = extract_txt(content)
        elif extension == ".docx":
            extracted = extract_docx(content)
        elif extension == ".xlsx":
            extracted = extract_xlsx(content)
        elif extension == ".pptx":
            extracted = extract_pptx(content)
        else:
            extracted = extract_pdf(content)
        return clean_name, extension, extracted

    def _write_upload(self, extension: str, content: bytes) -> tuple[str, Path]:
        now = now_bangkok()
        relative = Path("documents") / now.strftime("%Y") / now.strftime("%m") / f"{uuid.uuid4().hex}{extension}"
        destination = (self.upload_dir / relative).resolve()
        if self.upload_dir not in destination.parents:
            raise StoreError("Storage path is invalid.", 500)
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(content)
        return relative.as_posix(), destination

    def _insert_document(self, connection: sqlite3.Connection, *, doc_id: str, file_name: str,
                         original_file_name: str | None, file_type: str, file_size: int,
                         folder_id: int | None, category: str, processing_status: str,
                         extracted_status: str, storage_key: str | None, extracted_text: str | None,
                         metadata: dict[str, Any], approval_status: str = "draft") -> dict[str, Any]:
        now = timestamp()
        connection.execute(
            """INSERT INTO documents(id,file_name,original_file_name,file_type,file_size,folder_id,category,
               created_at,updated_at,processing_status,approval_status,current_version,extracted_text_status,
               storage_key,extracted_text,metadata_json) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (doc_id,file_name,original_file_name,file_type,file_size,folder_id,category,now,now,
             processing_status,approval_status,1,extracted_status,storage_key,extracted_text,_json(metadata)),
        )
        connection.execute(
            "INSERT INTO document_history(document_id,version,actor,action,details_json,created_at) VALUES(?,?,?,?,?,?)",
            (doc_id,1,"Local user","created",_json({"source": "upload" if storage_key else "document_studio"}),now),
        )
        return self._document(connection, doc_id)

    def upload_document(self, filename: str, content: bytes, content_type: str = "application/octet-stream",
                        folder_id: int | None = None) -> dict[str, Any]:
        clean_name, extension, extracted = self._validate_file(filename, content, content_type)
        if folder_id is not None and (isinstance(folder_id, bool) or not isinstance(folder_id, int)):
            raise StoreError("folder_id must be an integer or null.", 422)
        storage_key, destination = self._write_upload(extension, content)
        doc_id = str(uuid.uuid4())
        try:
            with self._connection() as connection:
                if not self._folder_exists(connection, folder_id):
                    raise StoreError("Folder was not found.", 404)
                result = self._insert_document(
                    connection, doc_id=doc_id, file_name=clean_name, original_file_name=clean_name,
                    file_type=extension.lstrip("."), file_size=len(content), folder_id=folder_id,
                    category="general", processing_status=extracted.status,
                    extracted_status="available" if extracted.text else "unavailable", storage_key=storage_key,
                    extracted_text=extracted.text, metadata={"processing_note": extracted.message} if extracted.message else {},
                )
        except Exception:
            destination.unlink(missing_ok=True)
            raise
        return result

    def _normalize_items(self, items: Any, required: bool) -> tuple[list[dict[str, str]], Decimal]:
        if not isinstance(items, list) or (required and not items) or len(items) > 100:
            raise StoreError("Add between 1 and 100 line items.", 422)
        normalized: list[dict[str, str]] = []
        total = Decimal("0")
        for index, item in enumerate(items):
            if not isinstance(item, dict):
                raise StoreError(f"Line item {index + 1} is invalid.", 422)
            name = str(item.get("name", "")).strip()
            unit = str(item.get("unit", "")).strip()
            if not name or len(name) > 200 or len(unit) > 40:
                raise StoreError(f"Line item {index + 1} needs a name and a valid unit.", 422)
            try:
                quantity_value = str(item.get("quantity", "")).strip()
                price_value = str(item.get("unit_price", "0") or "0").strip()
                if len(quantity_value) > 40 or len(price_value) > 40:
                    raise InvalidOperation
                quantity = Decimal(quantity_value)
                unit_price = Decimal(price_value)
                if (not quantity.is_finite() or not unit_price.is_finite() or quantity <= 0 or unit_price < 0
                        or quantity > Decimal("1000000000") or unit_price > Decimal("1000000000000")
                        or quantity.as_tuple().exponent < -6 or unit_price.as_tuple().exponent < -4):
                    raise InvalidOperation
            except (InvalidOperation, ValueError):
                raise StoreError(f"Line item {index + 1} has an invalid quantity or price.", 422) from None
            line_total = (quantity * unit_price).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
            total += line_total
            normalized.append({"name": name, "quantity": format(quantity.normalize(), "f"), "unit": unit,
                               "unit_price": format(unit_price.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP), "f"),
                               "line_total": format(line_total, "f")})
        return normalized, total.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)

    @staticmethod
    def _required_text(metadata: dict[str, Any], field: str, label: str) -> str:
        value = metadata.get(field)
        if not isinstance(value, str) or not value.strip() or len(value.strip()) > 2000:
            raise StoreError(f"{label} is required and must be at most 2,000 characters.", 422)
        return value.strip()

    @staticmethod
    def _optional_date(metadata: dict[str, Any], field: str, label: str) -> None:
        value = metadata.get(field)
        if value in (None, ""):
            return
        if not isinstance(value, str):
            raise StoreError(f"{label} must use YYYY-MM-DD.", 422)
        try:
            parsed = date.fromisoformat(value)
        except ValueError:
            raise StoreError(f"{label} must use YYYY-MM-DD.", 422) from None
        if parsed.isoformat() != value:
            raise StoreError(f"{label} must use YYYY-MM-DD.", 422)

    def _validate_draft_metadata(self, category: str, metadata: Any) -> dict[str, Any]:
        if category not in DOC_CATEGORIES:
            raise StoreError("category must be po, pr, or repair.", 422)
        if not isinstance(metadata, dict):
            raise StoreError("metadata must be an object.", 422)
        metadata = dict(metadata)
        if category == "po":
            self._required_text(metadata, "vendor", "Vendor")
            self._optional_date(metadata, "document_date", "Document date")
            metadata["items"], total = self._normalize_items(metadata.get("items"), True)
            metadata["total_amount"] = format(total, "f")
        elif category == "pr":
            self._required_text(metadata, "requester", "Requester")
            self._required_text(metadata, "department", "Department")
            self._required_text(metadata, "purpose", "Purpose")
            self._optional_date(metadata, "request_date", "Request date")
            metadata["items"], total = self._normalize_items(metadata.get("items"), True)
            metadata["estimated_total"] = format(total, "f")
        else:
            for field, label in (("reporter", "Reporter"), ("equipment_name", "Equipment"), ("issue_description", "Issue description")):
                self._required_text(metadata, field, label)
            self._optional_date(metadata, "report_date", "Report date")
            urgency = metadata.get("urgency", "normal")
            if not isinstance(urgency, str) or urgency not in {"low", "normal", "high"}:
                raise StoreError("Urgency must be low, normal, or high.", 422)
            repair_status = metadata.get("repair_status", "reported")
            if not isinstance(repair_status, str) or repair_status not in {"reported", "in_progress", "completed"}:
                raise StoreError("Repair status must be reported, in_progress, or completed.", 422)
            metadata["repair_status"] = repair_status
            for field, label in (
                ("technician_name", "Technician"),
                ("diagnosis", "Diagnosis"),
                ("work_performed", "Work performed"),
                ("parts_used", "Parts used"),
            ):
                value = metadata.get(field, "")
                if not isinstance(value, str) or len(value) > 2000:
                    raise StoreError(f"{label} must be text up to 2,000 characters.", 422)
                metadata[field] = value.strip()
            self._optional_date(metadata, "completed_date", "Completion date")
            if repair_status == "completed":
                self._required_text(metadata, "technician_name", "Technician")
                self._required_text(metadata, "work_performed", "Work performed")
                if not metadata.get("completed_date"):
                    raise StoreError("Completion date is required for completed repairs.", 422)
            repair_cost = metadata.get("repair_cost", "")
            if repair_cost not in (None, ""):
                try:
                    if not isinstance(repair_cost, str) or len(repair_cost) > 40:
                        raise InvalidOperation
                    amount = Decimal(repair_cost.strip())
                    if (not amount.is_finite() or amount < 0 or amount > Decimal("1000000000000")
                            or amount.as_tuple().exponent < -2):
                        raise InvalidOperation
                except (InvalidOperation, ValueError):
                    raise StoreError("Repair cost must be a non-negative amount with up to two decimals.", 422) from None
                metadata["repair_cost"] = format(amount.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP), "f")
            else:
                metadata["repair_cost"] = ""
            metadata.pop("items", None)
        return metadata

    def create_draft(self, payload: dict[str, Any]) -> dict[str, Any]:
        if set(payload) - {"category", "metadata", "title", "folder_id"}:
            raise StoreError("Draft request contains unsupported fields.", 422)
        category = payload.get("category")
        if not isinstance(category, str):
            raise StoreError("category must be po, pr, or repair.", 422)
        metadata = self._validate_draft_metadata(category, payload.get("metadata"))
        title = payload.get("title")
        title = str(title).strip() if isinstance(title, str) else ""
        if not title:
            title = f"{DOC_CATEGORIES[category]} draft"
        if len(title) > 255:
            raise StoreError("title is too long.", 422)
        folder_id = payload.get("folder_id")
        if folder_id is not None and (isinstance(folder_id, bool) or not isinstance(folder_id, int)):
            raise StoreError("folder_id must be an integer or null.", 422)
        with self._connection() as connection:
            if not self._folder_exists(connection, folder_id):
                raise StoreError("Folder was not found.", 404)
            return self._insert_document(
                connection, doc_id=str(uuid.uuid4()), file_name=title, original_file_name=None,
                file_type="seqotia", file_size=0, folder_id=folder_id, category=category,
                processing_status="completed", extracted_status="not_applicable", storage_key=None,
                extracted_text=None, metadata=metadata,
            )

    def update_draft(self, doc_id: str, changes: dict[str, Any]) -> dict[str, Any]:
        if not changes or set(changes) - {"metadata", "title"}:
            raise StoreError("Only title and metadata can be changed on a draft.", 422)
        with self._connection() as connection:
            current = self._document(connection, doc_id)
            category = current["category"]
            if current["file_type"] != "seqotia" or current["approval_status"] != "draft" or category not in DOC_CATEGORIES:
                raise StoreError("Only Studio drafts can be edited here.", 409)
            metadata = self._validate_draft_metadata(category, changes.get("metadata", current["metadata"]))
            title = changes.get("title", current["file_name"])
            if not isinstance(title, str):
                raise StoreError("title must be text.", 422)
            title = title.strip()
            if not title or len(title) > 255:
                raise StoreError("title must contain between 1 and 255 characters.", 422)
            now = timestamp()
            version = current["current_version"] + 1
            connection.execute(
                "UPDATE documents SET file_name=?,metadata_json=?,current_version=?,updated_at=? WHERE id=?",
                (title, _json(metadata), version, now, doc_id),
            )
            connection.execute(
                "INSERT INTO document_history(document_id,version,actor,action,details_json,created_at) VALUES(?,?,?,?,?,?)",
                (doc_id, version, "Local user", "draft_updated", _json({"fields": sorted(changes)}), now),
            )
            return self._document(connection, doc_id)

    def _document(self, connection: sqlite3.Connection, doc_id: str, include_archived: bool = False) -> dict[str, Any]:
        where = "id=?" if include_archived else "id=? AND archived_at IS NULL"
        row = connection.execute(f"SELECT * FROM documents WHERE {where}", (doc_id,)).fetchone()
        if row is None:
            raise StoreError("Document was not found.", 404)
        result = dict(row)
        result["tags"] = json.loads(result.pop("tags_json"))
        result["metadata"] = json.loads(result.pop("metadata_json"))
        extracted = result.pop("extracted_text")
        result["content_preview"] = extracted[:1200] if extracted else None
        return result

    def get_document(self, doc_id: str) -> dict[str, Any]:
        with self._connection() as connection:
            return self._document(connection, doc_id)

    def list_documents(self, *, search: str = "", folder_id: int | None = None,
                       category: str = "", approval_status: str = "", processing_status: str = "",
                       repair_status: str = "", sort: str = "updated_desc", limit: int = 100) -> list[dict[str, Any]]:
        conditions = ["d.archived_at IS NULL"]
        values: list[Any] = []
        if search.strip():
            conditions.append("(d.file_name LIKE ? OR d.original_file_name LIKE ? OR d.extracted_text LIKE ? OR d.metadata_json LIKE ?)")
            term = f"%{search.strip()}%"
            values.extend([term, term, term, term])
        if folder_id is not None:
            conditions.append("d.folder_id=?")
            values.append(folder_id)
        if category:
            conditions.append("d.category=?")
            values.append(category)
        if approval_status:
            conditions.append("d.approval_status=?")
            values.append(approval_status)
        if processing_status:
            conditions.append("d.processing_status=?")
            values.append(processing_status)
        if repair_status:
            if not isinstance(repair_status, str) or repair_status not in {"reported", "in_progress", "completed"}:
                raise StoreError("repair_status is not supported.", 422)
            conditions.append("d.category='repair'")
            if repair_status == "reported":
                conditions.append(
                    "(d.metadata_json LIKE ? OR (d.metadata_json NOT LIKE ? AND d.metadata_json NOT LIKE ?))"
                )
                values.extend([
                    '%"repair_status":"reported"%',
                    '%"repair_status":"in_progress"%',
                    '%"repair_status":"completed"%',
                ])
            else:
                conditions.append("d.metadata_json LIKE ?")
                values.append(f'%"repair_status":"{repair_status}"%')
        sort_columns = {
            "name_asc": "d.file_name COLLATE NOCASE ASC",
            "name_desc": "d.file_name COLLATE NOCASE DESC",
            "created_desc": "d.created_at DESC",
            "created_asc": "d.created_at ASC",
            "updated_asc": "d.updated_at ASC",
            "updated_desc": "d.updated_at DESC",
            "category_asc": "d.category COLLATE NOCASE ASC",
        }
        order_by = sort_columns.get(sort)
        if order_by is None:
            raise StoreError("sort is not supported.", 422)
        values.append(max(1, min(limit, 500)))
        with self._connection() as connection:
            rows = connection.execute(
                f"SELECT d.*,f.name AS folder_name FROM documents d LEFT JOIN folders f ON f.id=d.folder_id WHERE {' AND '.join(conditions)} ORDER BY {order_by} LIMIT ?",
                values,
            ).fetchall()
            result = []
            for row in rows:
                item = dict(row)
                item["tags"] = json.loads(item.pop("tags_json"))
                item["metadata"] = json.loads(item.pop("metadata_json"))
                extracted = item.pop("extracted_text")
                item["content_preview"] = extracted[:400] if extracted else None
                result.append(item)
            return result

    def update_document(self, doc_id: str, changes: dict[str, Any]) -> dict[str, Any]:
        allowed = {"folder_id", "tags"}
        if not changes or set(changes) - allowed:
            raise StoreError("Only folder_id and tags can be changed.", 422)
        with self._connection() as connection:
            self._document(connection, doc_id)
            if "folder_id" in changes:
                folder_id = changes["folder_id"]
                if folder_id is not None and (isinstance(folder_id, bool) or not isinstance(folder_id, int)):
                    raise StoreError("folder_id must be an integer or null.", 422)
                if not self._folder_exists(connection, folder_id):
                    raise StoreError("Folder was not found.", 404)
                connection.execute("UPDATE documents SET folder_id=?,updated_at=? WHERE id=?", (folder_id,timestamp(),doc_id))
            if "tags" in changes:
                tags = changes["tags"]
                if not isinstance(tags, list) or len(tags) > 30 or any(not isinstance(tag, str) or len(tag) > 40 for tag in tags):
                    raise StoreError("tags must be a list of up to 30 short strings.", 422)
                connection.execute("UPDATE documents SET tags_json=?,updated_at=? WHERE id=?", (_json(tags),timestamp(),doc_id))
            connection.execute(
                "INSERT INTO document_history(document_id,version,actor,action,details_json,created_at) VALUES(?,?,?,?,?,?)",
                (doc_id,1,"Local user","updated",_json({"fields": sorted(changes)}),timestamp()),
            )
            return self._document(connection, doc_id)

    def archive_document(self, doc_id: str) -> None:
        with self._connection() as connection:
            self._document(connection, doc_id)
            now = timestamp()
            connection.execute("UPDATE documents SET archived_at=?,updated_at=? WHERE id=?", (now,now,doc_id))
            connection.execute("INSERT INTO document_history(document_id,version,actor,action,details_json,created_at) VALUES(?,?,?,?,?,?)",
                               (doc_id,1,"Local user","archived","{}",now))

    def document_history(self, doc_id: str) -> list[dict[str, Any]]:
        with self._connection() as connection:
            self._document(connection, doc_id)
            rows = connection.execute("SELECT version,actor,action,details_json,created_at FROM document_history WHERE document_id=? ORDER BY id DESC", (doc_id,)).fetchall()
            return [{**dict(row), "details": json.loads(row["details_json"])} for row in rows]

    def download_path(self, doc_id: str) -> tuple[Path, str, str]:
        with self._connection() as connection:
            document = self._document(connection, doc_id)
            storage_key = document.get("storage_key")
            if not storage_key:
                raise StoreError("This document has no uploaded source file.", 409)
            path = (self.upload_dir / storage_key).resolve()
            if self.upload_dir not in path.parents or not path.is_file():
                raise StoreError("The source file is not available in local storage.", 404)
            mime = mimetypes.guess_type(document.get("original_file_name") or "")[0] or "application/octet-stream"
            return path, document.get("original_file_name") or document["file_name"], mime

    def export_document(self, doc_id: str) -> tuple[bytes, str, str]:
        with self._connection() as connection:
            document = self._document(connection, doc_id)
        if document["file_type"] != "seqotia" or document["category"] not in DOC_CATEGORIES:
            raise StoreError("Only Document Studio drafts can be exported as a Word document.", 409)
        content, filename = render_draft_docx(document)
        return content, filename, "application/vnd.openxmlformats-officedocument.wordprocessingml.document"

    def reprocess_document(self, doc_id: str) -> dict[str, Any]:
        path, filename, mime = self.download_path(doc_id)
        content = path.read_bytes()
        clean_name, extension, extracted = self._validate_file(filename, content, mime)
        with self._connection() as connection:
            connection.execute("UPDATE documents SET processing_status=?,extracted_text_status=?,extracted_text=?,updated_at=? WHERE id=?",
                               (extracted.status,"available" if extracted.text else "unavailable",extracted.text,timestamp(),doc_id))
            metadata_row = connection.execute("SELECT metadata_json FROM documents WHERE id=?", (doc_id,)).fetchone()
            metadata = json.loads(metadata_row["metadata_json"])
            if extracted.message:
                metadata["processing_note"] = extracted.message
            else:
                metadata.pop("processing_note", None)
            connection.execute("UPDATE documents SET metadata_json=? WHERE id=?", (_json(metadata),doc_id))
            connection.execute(
                "INSERT INTO document_history(document_id,version,actor,action,details_json,created_at) VALUES(?,?,?,?,?,?)",
                (doc_id,1,"Local user","reprocessed",_json({"status": extracted.status}),timestamp()),
            )
            return self._document(connection, doc_id)

    def dashboard_summary(self) -> dict[str, Any]:
        now = now_bangkok()
        recent_after = (now - timedelta(days=7)).isoformat()
        with self._connection() as connection:
            row = connection.execute(
                """SELECT count(*) AS total,
                          sum(CASE WHEN created_at>=? THEN 1 ELSE 0 END) AS created_recently,
                          sum(CASE WHEN approval_status='pending' THEN 1 ELSE 0 END) AS pending_approval,
                          sum(CASE WHEN processing_status IN ('processing','needs_review','failed') THEN 1 ELSE 0 END) AS needs_attention
                   FROM documents WHERE archived_at IS NULL""",
                (recent_after,),
            ).fetchone()
            repair_counts = connection.execute(
                """SELECT sum(CASE WHEN metadata_json LIKE '%"repair_status":"reported"%'
                                      OR (metadata_json NOT LIKE '%"repair_status":"in_progress"%'
                                          AND metadata_json NOT LIKE '%"repair_status":"completed"%')
                                     THEN 1 ELSE 0 END) AS reported,
                          sum(CASE WHEN metadata_json LIKE '%"repair_status":"in_progress"%' THEN 1 ELSE 0 END) AS in_progress,
                          sum(CASE WHEN metadata_json LIKE '%"repair_status":"completed"%' THEN 1 ELSE 0 END) AS completed
                   FROM documents WHERE archived_at IS NULL AND category='repair'"""
            ).fetchone()
            recent = connection.execute("SELECT id,file_name,category,updated_at,approval_status,processing_status FROM documents WHERE archived_at IS NULL ORDER BY updated_at DESC LIMIT 5").fetchall()
        return {"generated_at": now.isoformat(), "timezone": "Asia/Bangkok", "mode": "local_development",
                "total_documents": row["total"] or 0, "created_last_7_days": row["created_recently"] or 0,
                "pending_approval": row["pending_approval"] or 0, "needs_attention": row["needs_attention"] or 0,
                "repair_reported": repair_counts["reported"] or 0,
                "repair_in_progress": repair_counts["in_progress"] or 0,
                "repair_completed": repair_counts["completed"] or 0,
                "recent_documents": [dict(item) for item in recent]}

    def create_suggestion(self, document_type: str, field_name: str, text: str = "") -> dict[str, Any]:
        suggestions = self.suggestion_provider.suggest(document_type, field_name, text)
        suggestion_id = str(uuid.uuid4())
        with self._connection() as connection:
            connection.execute("INSERT INTO ai_suggestions(id,document_type,field_name,provider,created_at) VALUES(?,?,?,?,?)",
                               (suggestion_id,document_type[:40],field_name[:80],self.suggestion_provider.name,timestamp()))
        message = "ตัวอย่างข้อความจำลอง — โปรดตรวจสอบและยืนยันเอง" if self.suggestion_provider.is_mock else "ข้อความแนะนำจาก AI — โปรดตรวจสอบก่อนนำไปใช้"
        return {"suggestion_id": suggestion_id, "status": self.suggestion_provider.name, "is_mock": self.suggestion_provider.is_mock,
                "message": message, "sources": [],
                "suggestions": suggestions}

    def save_feedback(self, suggestion_id: str, accepted: bool, correction: str | None = None) -> None:
        if correction is not None and (not isinstance(correction, str) or len(correction) > 2000):
            raise StoreError("Correction must be at most 2,000 characters.", 422)
        with self._connection() as connection:
            exists = connection.execute("SELECT 1 FROM ai_suggestions WHERE id=?", (suggestion_id,)).fetchone()
            if not exists:
                raise StoreError("Suggestion was not found.", 404)
            connection.execute("INSERT INTO ai_feedback(suggestion_id,accepted,correction,created_at) VALUES(?,?,?,?)",
                               (suggestion_id,int(accepted),correction,timestamp()))

