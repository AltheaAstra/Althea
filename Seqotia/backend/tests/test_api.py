import json
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from backend.app.db.store import Store
from backend.app.main import create_handler


class ApiSmokeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        root = Path(self.temporary.name)
        store = Store(root / "seqotia.sqlite3", root / "uploads", 1024 * 1024)
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), create_handler(store))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base_url = f"http://127.0.0.1:{self.server.server_port}"

    def tearDown(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)
        self.temporary.cleanup()

    def _json(self, path: str, method: str = "GET", value=None):
        body = json.dumps(value, ensure_ascii=False).encode("utf-8") if value is not None else None
        request = Request(self.base_url + path, data=body, method=method, headers={"Content-Type": "application/json"} if body is not None else {})
        with urlopen(request, timeout=2) as response:
            return response.status, json.loads(response.read().decode("utf-8"))

    def test_health_summary_folder_and_document_draft_routes(self) -> None:
        status, health = self._json("/health")
        self.assertEqual(status, 200)
        self.assertEqual(health["authentication"], "not_configured")

        status, folder = self._json("/api/folders", "POST", {"name": "Operations"})
        self.assertEqual(status, 201)
        self.assertEqual(folder["name"], "Operations")

        status, draft = self._json("/api/documents", "POST", {
            "category": "repair",
            "metadata": {"reporter": "Nok", "equipment_name": "Printer", "issue_description": "Paper jam"},
        })
        self.assertEqual(status, 201)
        self.assertEqual(draft["approval_status"], "draft")

        status, summary = self._json("/api/dashboard/summary")
        self.assertEqual(status, 200)
        self.assertEqual(summary["total_documents"], 1)

    def test_multipart_upload_route_returns_extracted_text(self) -> None:
        boundary = "seqotia-test-boundary"
        body = (
            f"--{boundary}\r\n"
            'Content-Disposition: form-data; name="file"; filename="notes.txt"\r\n'
            "Content-Type: text/plain\r\n\r\n"
        ).encode() + "ข้อความทดสอบ".encode() + f"\r\n--{boundary}--\r\n".encode()
        request = Request(
            self.base_url + "/api/documents/upload",
            data=body,
            method="POST",
            headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
        )
        with urlopen(request, timeout=2) as response:
            self.assertEqual(response.status, 201)
            result = json.loads(response.read().decode("utf-8"))
        self.assertEqual(result["processing_status"], "completed")
        self.assertEqual(result["content_preview"], "ข้อความทดสอบ")

    def test_bad_draft_returns_structured_validation_error(self) -> None:
        request = Request(
            self.base_url + "/api/documents",
            data=json.dumps({"category": "po", "metadata": {"items": []}}).encode(),
            method="POST",
            headers={"Content-Type": "application/json"},
        )
        with self.assertRaises(HTTPError) as response:
            urlopen(request, timeout=2)
        self.assertEqual(response.exception.code, 422)
        self.assertIn("error", json.loads(response.exception.read().decode("utf-8")))


if __name__ == "__main__":
    unittest.main()
