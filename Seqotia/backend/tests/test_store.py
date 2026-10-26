import tempfile
import unittest
import zipfile
from io import BytesIO
from pathlib import Path

from backend.app.db.store import Store, StoreError


def sample_docx() -> bytes:
    output = BytesIO()
    with zipfile.ZipFile(output, "w") as archive:
        archive.writestr("[Content_Types].xml", "<Types xmlns='http://schemas.openxmlformats.org/package/2006/content-types'></Types>")
        archive.writestr(
            "word/document.xml",
            "<w:document xmlns:w='http://schemas.openxmlformats.org/wordprocessingml/2006/main'><w:body><w:p><w:r><w:t>Seqotia document text</w:t></w:r></w:p></w:body></w:document>",
        )
    return output.getvalue()


def sample_office_document(required_entry: str, content_entry: str, content: str) -> bytes:
    output = BytesIO()
    with zipfile.ZipFile(output, "w") as archive:
        archive.writestr("[Content_Types].xml", "<Types xmlns='http://schemas.openxmlformats.org/package/2006/content-types'></Types>")
        archive.writestr(required_entry, "<root></root>")
        archive.writestr(content_entry, content)
    return output.getvalue()


class StoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        root = Path(self.temporary.name)
        self.store = Store(root / "seqotia.sqlite3", root / "uploads", 1024 * 1024)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_dashboard_uses_real_empty_state_and_bangkok_time(self) -> None:
        result = self.store.dashboard_summary()
        self.assertEqual(result["total_documents"], 0)
        self.assertEqual(result["created_last_7_days"], 0)
        self.assertEqual(result["pending_approval"], 0)
        self.assertEqual(result["timezone"], "Asia/Bangkok")
        self.assertEqual(result["recent_documents"], [])

    def test_folder_cycle_is_rejected_and_contents_block_archive(self) -> None:
        parent = self.store.create_folder("Procurement")
        child = self.store.create_folder("Quarterly", parent["id"])
        with self.assertRaises(StoreError) as cycle:
            self.store.update_folder(parent["id"], {"parent_id": child["id"]})
        self.assertEqual(cycle.exception.status_code, 409)
        self.store.upload_document("brief.txt", "scope".encode(), "text/plain", child["id"])
        with self.assertRaises(StoreError):
            self.store.archive_folder(child["id"])

    def test_upload_sanitizes_filename_extracts_text_and_archives_softly(self) -> None:
        document = self.store.upload_document("..\\reports\\memo.txt", "บันทึกการจัดซื้อ".encode(), "text/plain")
        self.assertEqual(document["file_name"], "memo.txt")
        self.assertEqual(document["processing_status"], "completed")
        self.assertEqual(document["content_preview"], "บันทึกการจัดซื้อ")
        self.assertEqual(len(self.store.document_history(document["id"])), 1)
        self.store.archive_document(document["id"])
        self.assertEqual(self.store.list_documents(), [])

    def test_docx_processor_extracts_text_from_valid_office_archive(self) -> None:
        document = self.store.upload_document(
            "minutes.docx", sample_docx(),
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        )
        self.assertEqual(document["processing_status"], "completed")
        self.assertIn("Seqotia document text", document["content_preview"])

    def test_xlsx_and_pptx_processors_extract_text(self) -> None:
        xlsx = sample_office_document(
            "xl/workbook.xml", "xl/worksheets/sheet1.xml",
            "<worksheet xmlns='http://schemas.openxmlformats.org/spreadsheetml/2006/main'><sheetData><row><c r='A1' t='inlineStr'><is><t>Budget line</t></is></c></row></sheetData></worksheet>",
        )
        spreadsheet = self.store.upload_document(
            "budget.xlsx", xlsx,
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        )
        self.assertEqual(spreadsheet["processing_status"], "completed")
        self.assertIn("Budget line", spreadsheet["content_preview"])

        pptx = sample_office_document(
            "ppt/presentation.xml", "ppt/slides/slide1.xml",
            "<p:sld xmlns:p='http://schemas.openxmlformats.org/presentationml/2006/main' xmlns:a='http://schemas.openxmlformats.org/drawingml/2006/main'><a:t>Quarterly update</a:t></p:sld>",
        )
        presentation = self.store.upload_document(
            "update.pptx", pptx,
            "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        )
        self.assertEqual(presentation["processing_status"], "completed")
        self.assertIn("Quarterly update", presentation["content_preview"])

    def test_upload_rejects_mime_mismatch_unsupported_and_oversized(self) -> None:
        with self.assertRaises(StoreError) as mismatch:
            self.store.upload_document("report.txt", b"content", "application/pdf")
        self.assertEqual(mismatch.exception.status_code, 415)
        with self.assertRaises(StoreError) as unsupported:
            self.store.upload_document("archive.zip", b"PK", "application/zip")
        self.assertEqual(unsupported.exception.status_code, 415)
        small_store = Store(self.store.database_path.parent / "small.sqlite3", self.store.upload_dir, 3)
        with self.assertRaises(StoreError) as size:
            small_store.upload_document("large.txt", b"four", "text/plain")
        self.assertEqual(size.exception.status_code, 413)

    def test_po_draft_calculates_totals_and_validates_server_side(self) -> None:
        saved = self.store.create_draft({
            "category": "po", "metadata": {
                "vendor": "Vendor Co.",
                "items": [
                    {"name": "Paper", "quantity": "2", "unit": "ream", "unit_price": "10.25"},
                    {"name": "Folders", "quantity": "3", "unit": "box", "unit_price": "4.10"},
                ],
            },
        })
        self.assertEqual(saved["metadata"]["total_amount"], "32.80")
        self.assertEqual(saved["approval_status"], "draft")
        self.assertEqual(saved["file_type"], "seqotia")
        with self.assertRaises(StoreError):
            self.store.create_draft({"category": "po", "metadata": {"items": []}})

    def test_draft_date_and_repair_urgency_are_validated(self) -> None:
        with self.assertRaises(StoreError) as date_error:
            self.store.create_draft({
                "category": "repair",
                "metadata": {"reporter": "Nok", "equipment_name": "Printer", "issue_description": "Jam", "report_date": "17-10-2026"},
            })
        self.assertEqual(date_error.exception.status_code, 422)
        with self.assertRaises(StoreError) as urgency_error:
            self.store.create_draft({
                "category": "repair",
                "metadata": {"reporter": "Nok", "equipment_name": "Printer", "issue_description": "Jam", "urgency": "critical"},
            })
        self.assertEqual(urgency_error.exception.status_code, 422)

    def test_document_sorting_uses_allowlisted_ordering(self) -> None:
        self.store.upload_document("zeta.txt", b"last", "text/plain")
        self.store.upload_document("alpha.txt", b"first", "text/plain")
        documents = self.store.list_documents(sort="name_asc")
        self.assertEqual([item["file_name"] for item in documents], ["alpha.txt", "zeta.txt"])
        with self.assertRaises(StoreError):
            self.store.list_documents(sort="name; DROP TABLE documents")

    def test_ai_demo_is_explicit_and_feedback_is_recorded(self) -> None:
        suggestion = self.store.create_suggestion("repair", "issue_description", "")
        self.assertTrue(suggestion["is_mock"])
        self.assertEqual(suggestion["status"], "demo_mock")
        self.assertEqual(suggestion["sources"], [])
        self.store.save_feedback(suggestion["suggestion_id"], True)
        with self.store._connection() as connection:
            self.assertEqual(connection.execute("SELECT count(*) FROM ai_feedback").fetchone()[0], 1)


if __name__ == "__main__":
    unittest.main()
