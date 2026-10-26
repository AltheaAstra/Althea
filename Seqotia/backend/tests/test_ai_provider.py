import json
import os
import unittest
from io import BytesIO
from urllib.error import HTTPError
from unittest.mock import patch

from backend.app.ai.provider import (
    DemoSuggestionProvider,
    OpenAISuggestionProvider,
    SuggestionProviderError,
    create_suggestion_provider,
)


class OpenAISuggestionProviderTests(unittest.TestCase):
    def setUp(self) -> None:
        self.output_text = json.dumps({
            "suggestions": [
                {"text": "เพื่อสนับสนุนการปฏิบัติงานตามข้อมูลที่ผู้ใช้ระบุ", "style": "formal"},
                {"text": "โปรดเพิ่มรายละเอียดตามความจำเป็น", "style": "concise"},
            ],
        }, ensure_ascii=False)
        self.response = json.dumps({
            "status": "completed",
            "output": [{"type": "message", "content": [{"type": "output_text", "text": self.output_text}]}],
        }, ensure_ascii=False).encode("utf-8")

    def test_sends_input_to_responses_api_and_validates_output(self) -> None:
        provider = OpenAISuggestionProvider("test-secret", "gpt-test", timeout_seconds=7)
        with patch("backend.app.ai.provider.urlopen", return_value=BytesIO(self.response)) as mocked_urlopen:
            suggestions = provider.suggest("pr", "purpose", "ข้อความภาษาไทย")

        self.assertEqual(suggestions[0]["style"], "formal")
        self.assertEqual(len(suggestions), 2)
        request = mocked_urlopen.call_args.args[0]
        self.assertEqual(request.full_url, "https://api.openai.com/v1/responses")
        self.assertEqual(request.get_header("Authorization"), "Bearer test-secret")
        self.assertEqual(mocked_urlopen.call_args.kwargs["timeout"], 7)
        body = json.loads(request.data.decode("utf-8"))
        self.assertEqual(body["model"], "gpt-test")
        self.assertFalse(body["store"])
        self.assertEqual(body["text"]["format"]["type"], "json_object")
        self.assertEqual(json.loads(body["input"])["current_text"], "ข้อความภาษาไทย")

    def test_rejects_provider_http_errors_without_leaking_response_body(self) -> None:
        provider = OpenAISuggestionProvider("test-secret")
        error = HTTPError("https://api.openai.com/v1/responses", 401, "unauthorized", {}, BytesIO(b"test-secret"))
        with patch("backend.app.ai.provider.urlopen", side_effect=error):
            with self.assertRaises(SuggestionProviderError) as raised:
                provider.suggest("po", "notes", "")
        self.assertIn("401", str(raised.exception))
        self.assertNotIn("test-secret", str(raised.exception))

    def test_rejects_unusable_or_oversized_model_suggestions(self) -> None:
        provider = OpenAISuggestionProvider("test-secret")
        malformed = json.dumps({"output": [{"type": "message", "content": [{"type": "output_text", "text": "not-json"}]}]}).encode()
        with patch("backend.app.ai.provider.urlopen", return_value=BytesIO(malformed)):
            with self.assertRaises(SuggestionProviderError):
                provider.suggest("repair", "issue_description", "")

        oversized_text = "x" * 601
        output = json.dumps({"suggestions": [{"text": oversized_text, "style": "formal"}]}).encode()
        response = json.dumps({"status": "completed", "output": [{"type": "message", "content": [{"type": "output_text", "text": output.decode()}]}]}).encode()
        with patch("backend.app.ai.provider.urlopen", return_value=BytesIO(response)):
            with self.assertRaises(SuggestionProviderError):
                provider.suggest("repair", "issue_description", "")

    def test_provider_factory_defaults_to_demo_and_requires_a_key_for_openai(self) -> None:
        with patch.dict(os.environ, {"AI_PROVIDER": "demo_mock"}, clear=True):
            self.assertIsInstance(create_suggestion_provider(), DemoSuggestionProvider)

        with patch.dict(os.environ, {"AI_PROVIDER": "openai"}, clear=True):
            with self.assertRaisesRegex(ValueError, "OPENAI_API_KEY"):
                create_suggestion_provider()

    def test_provider_factory_reads_openai_configuration_from_environment(self) -> None:
        with patch.dict(os.environ, {
            "AI_PROVIDER": "openai",
            "OPENAI_API_KEY": "local-secret",
            "OPENAI_MODEL": "gpt-test",
            "OPENAI_TIMEOUT_SECONDS": "12",
        }, clear=True):
            provider = create_suggestion_provider()
        self.assertIsInstance(provider, OpenAISuggestionProvider)
        self.assertEqual(provider.model, "gpt-test")
        self.assertEqual(provider.timeout_seconds, 12)


if __name__ == "__main__":
    unittest.main()
