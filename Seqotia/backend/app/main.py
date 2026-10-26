"""Dependency-free HTTP API for the Seqotia local development workspace."""

import ipaddress
import json
from email.parser import BytesParser
from email.policy import default as email_policy
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, quote, unquote, urlsplit

from .core.config import get_settings
from .db.store import Store, StoreError, TEMPLATES


MAX_JSON_BYTES = 1024 * 1024


def _positive_int(value: str | None, name: str) -> int | None:
    if value is None or value == "":
        return None
    try:
        result = int(value)
    except ValueError:
        raise StoreError(f"{name} must be an integer.", 422) from None
    if result < 1:
        raise StoreError(f"{name} must be a positive integer.", 422)
    return result


def create_handler(store: Store) -> type[BaseHTTPRequestHandler]:
    class Handler(BaseHTTPRequestHandler):
        server_version = "SeqotiaLocal/0.1"
        sys_version = ""

        def log_message(self, _format: str, *_args: object) -> None:
            # Document names and search terms can be sensitive; do not log request URLs.
            return

        def end_headers(self) -> None:
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, PATCH, DELETE, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "Content-Type")
            self.send_header("X-Content-Type-Options", "nosniff")
            super().end_headers()

        def _json_response(self, status: int, value: object) -> None:
            data = json.dumps(value, ensure_ascii=False).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def _error(self, status: int, message: str) -> None:
            self._json_response(status, {"error": {"status": status, "message": message}})

        def _body(self, max_bytes: int) -> bytes:
            try:
                length = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                raise StoreError("Content-Length is invalid.", 400) from None
            if length < 0 or length > max_bytes:
                raise StoreError("Request body exceeds the allowed size.", 413)
            body = self.rfile.read(length)
            if len(body) != length:
                raise StoreError("Request body ended unexpectedly.", 400)
            return body

        def _read_json(self) -> dict:
            content_type = self.headers.get("Content-Type", "").split(";", 1)[0].strip().lower()
            if content_type != "application/json":
                raise StoreError("Content-Type must be application/json.", 415)
            try:
                value = json.loads(self._body(MAX_JSON_BYTES))
            except (UnicodeDecodeError, json.JSONDecodeError):
                raise StoreError("Request body must contain valid JSON.", 400) from None
            if not isinstance(value, dict):
                raise StoreError("Request body must be a JSON object.", 422)
            return value

        def _read_upload(self) -> tuple[str, bytes, str, int | None]:
            content_type = self.headers.get("Content-Type", "")
            if not content_type.lower().startswith("multipart/form-data;"):
                raise StoreError("Upload must use multipart/form-data.", 415)
            raw = self._body(store.max_upload_bytes + MAX_JSON_BYTES)
            message = BytesParser(policy=email_policy).parsebytes(
                f"Content-Type: {content_type}\r\nMIME-Version: 1.0\r\n\r\n".encode("latin-1") + raw
            )
            if not message.is_multipart():
                raise StoreError("Upload form is malformed.", 400)
            file_part = None
            folder_raw = None
            for part in message.iter_parts():
                disposition = part.get_content_disposition()
                name = part.get_param("name", header="content-disposition")
                if disposition == "form-data" and name == "file":
                    file_part = part
                elif disposition == "form-data" and name == "folder_id":
                    try:
                        folder_raw = part.get_payload(decode=True).decode("utf-8", errors="strict").strip()
                    except UnicodeDecodeError:
                        raise StoreError("folder_id is invalid.", 422) from None
            if file_part is None or not file_part.get_filename():
                raise StoreError("Choose a file to upload.", 422)
            try:
                folder_id = _positive_int(folder_raw, "folder_id")
            except UnicodeDecodeError:
                raise StoreError("folder_id is invalid.", 422) from None
            return file_part.get_filename(), file_part.get_payload(decode=True) or b"", file_part.get_content_type(), folder_id

        def _route_parts(self) -> tuple[list[str], dict[str, list[str]]]:
            parsed = urlsplit(self.path)
            parts = [unquote(part) for part in parsed.path.strip("/").split("/") if part]
            return parts, parse_qs(parsed.query, keep_blank_values=False)

        def _dispatch(self, method: str) -> None:
            parts, query = self._route_parts()
            if method == "GET":
                if parts == ["health"]:
                    return self._json_response(200, {"status": "ok", "mode": "local_development", "ai_provider": "demo_mock", "authentication": "not_configured"})
                if parts == ["api", "dashboard", "summary"]:
                    return self._json_response(200, store.dashboard_summary())
                if parts == ["api", "templates"]:
                    return self._json_response(200, TEMPLATES)
                if parts == ["api", "folders"]:
                    return self._json_response(200, store.list_folders(query.get("q", [""])[0]))
                if parts == ["api", "documents"]:
                    folder_id = _positive_int(query.get("folder_id", [None])[0], "folder_id")
                    limit = _positive_int(query.get("limit", ["100"])[0], "limit") or 100
                    return self._json_response(200, store.list_documents(
                        search=query.get("q", [""])[0], folder_id=folder_id,
                        category=query.get("category", [""])[0],
                        approval_status=query.get("approval_status", [""])[0], limit=limit,
                        processing_status=query.get("processing_status", [""])[0],
                        sort=query.get("sort", ["updated_desc"])[0],
                    ))
                if len(parts) == 4 and parts[:2] == ["api", "documents"] and parts[3] == "history":
                    return self._json_response(200, store.document_history(parts[2]))
                if len(parts) == 4 and parts[:2] == ["api", "documents"] and parts[3] == "download":
                    path, filename, mime = store.download_path(parts[2])
                    data = path.read_bytes()
                    self.send_response(200)
                    self.send_header("Content-Type", mime)
                    self.send_header("Content-Length", str(len(data)))
                    self.send_header("Content-Disposition", f"attachment; filename*=UTF-8''{quote(filename)}")
                    self.end_headers()
                    self.wfile.write(data)
                    return
                if len(parts) == 3 and parts[:2] == ["api", "documents"]:
                    return self._json_response(200, store.get_document(parts[2]))
                return self._error(404, "Route was not found.")

            if method == "POST":
                if parts == ["api", "documents", "upload"]:
                    filename, content, mime, folder_id = self._read_upload()
                    return self._json_response(201, store.upload_document(filename, content, mime, folder_id))
                if parts == ["api", "documents"]:
                    return self._json_response(201, store.create_draft(self._read_json()))
                if parts == ["api", "folders"]:
                    payload = self._read_json()
                    unknown = set(payload) - {"name", "parent_id"}
                    if unknown or not isinstance(payload.get("name"), str):
                        raise StoreError("Provide a folder name and optional parent_id.", 422)
                    parent_id = payload.get("parent_id")
                    if parent_id is not None and (isinstance(parent_id, bool) or not isinstance(parent_id, int)):
                        raise StoreError("parent_id must be an integer or null.", 422)
                    return self._json_response(201, store.create_folder(payload["name"], parent_id))
                if parts == ["api", "ai", "suggestions"]:
                    payload = self._read_json()
                    document_type = payload.get("document_type", "general")
                    field_name = payload.get("field_name", "default")
                    text = payload.get("text", "")
                    if any(not isinstance(value, str) or len(value) > 2000 for value in (document_type, field_name, text)):
                        raise StoreError("Suggestion context is invalid.", 422)
                    return self._json_response(200, store.create_suggestion(document_type, field_name, text))
                if parts == ["api", "ai", "feedback"]:
                    payload = self._read_json()
                    suggestion_id = payload.get("suggestion_id")
                    accepted = payload.get("accepted")
                    if not isinstance(suggestion_id, str) or not isinstance(accepted, bool):
                        raise StoreError("suggestion_id and accepted are required.", 422)
                    store.save_feedback(suggestion_id, accepted, payload.get("correction"))
                    return self._json_response(201, {"status": "recorded"})
                if len(parts) == 4 and parts[:2] == ["api", "documents"] and parts[3] == "reprocess":
                    return self._json_response(200, store.reprocess_document(parts[2]))
                return self._error(404, "Route was not found.")

            if method == "PATCH":
                if len(parts) == 3 and parts[:2] == ["api", "folders"]:
                    payload = self._read_json()
                    return self._json_response(200, store.update_folder(_positive_int(parts[2], "folder_id"), payload))
                if len(parts) == 3 and parts[:2] == ["api", "documents"]:
                    return self._json_response(200, store.update_document(parts[2], self._read_json()))
                return self._error(404, "Route was not found.")

            if method == "DELETE":
                if len(parts) == 3 and parts[:2] == ["api", "folders"]:
                    store.archive_folder(_positive_int(parts[2], "folder_id"))
                    return self._json_response(200, {"status": "archived"})
                if len(parts) == 3 and parts[:2] == ["api", "documents"]:
                    store.archive_document(parts[2])
                    return self._json_response(200, {"status": "archived"})
                return self._error(404, "Route was not found.")

            return self._error(405, "Method is not supported.")

        def _handle(self, method: str) -> None:
            try:
                self._dispatch(method)
            except StoreError as exc:
                self._error(exc.status_code, str(exc))
            except (ValueError, TypeError):
                self._error(422, "Request values are invalid.")
            except Exception:
                # Deliberately do not return stack traces, paths, or document contents.
                self._error(500, "The local service could not complete this request.")

        def do_GET(self) -> None:
            self._handle("GET")

        def do_POST(self) -> None:
            self._handle("POST")

        def do_PATCH(self) -> None:
            self._handle("PATCH")

        def do_DELETE(self) -> None:
            self._handle("DELETE")

        def do_OPTIONS(self) -> None:
            self.send_response(204)
            self.send_header("Content-Length", "0")
            self.end_headers()

    return Handler


def main() -> None:
    settings = get_settings()
    try:
        is_loopback = settings.host.lower() == "localhost" or ipaddress.ip_address(settings.host).is_loopback
    except ValueError:
        is_loopback = False
    if not is_loopback and not settings.allow_remote:
        raise SystemExit("Refusing to bind beyond loopback without SEQOTIA_ALLOW_REMOTE=1. This development API has no authentication.")
    store = Store(settings.database_path, settings.upload_dir, settings.max_upload_bytes)
    server = ThreadingHTTPServer((settings.host, settings.port), create_handler(store))
    server.daemon_threads = True
    print(f"Seqotia local API listening at http://{settings.host}:{settings.port} (SQLite; demo AI mode)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping Seqotia local API.")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
