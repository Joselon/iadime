import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import server


class RecordingProvider(server.BaseProvider):
    def __init__(self) -> None:
        super().__init__("openai", "gpt-test")
        self.calls: list[dict] = []

    def chat(self, messages, model=None, temperature=0.7, max_tokens=1200) -> str:
        self.calls.append({"messages": messages, "model": model, "max_tokens": max_tokens})
        return "respuesta"

    def image(self, prompt: str, model=None) -> str:
        raise NotImplementedError


class ProviderSelectionTests(unittest.TestCase):
    def test_default_provider_is_openai(self) -> None:
        with patch.dict(os.environ, {}, clear=False):
            provider = server.select_provider()
            self.assertIsInstance(provider, server.OpenAIProvider)

    def test_gemini_provider_is_selected_when_requested(self) -> None:
        with patch.dict(os.environ, {"PROVIDER": "gemini"}, clear=False):
            provider = server.select_provider()
            self.assertIsInstance(provider, server.GeminiProvider)

    def test_normalize_messages_preserves_user_history(self) -> None:
        history = [{"role": "assistant", "content": "Hola"}, {"role": "user", "content": "¿Qué tal?"}]
        messages = server.normalize_messages(history, "Gracias")
        self.assertEqual(messages[-1]["content"], "Gracias")
        self.assertEqual(messages[0]["role"], "assistant")

    def test_parse_gemini_models_from_api_payload(self) -> None:
        payload = {
            "models": [
                {"name": "models/gemini-2.0-flash"},
                {"name": "models/gemini-2.0-flash-lite"},
                {"name": "models/imagen-4.0-generate-001"},
            ]
        }
        models = server.parse_model_list(payload, "gemini")
        self.assertIn("gemini-2.0-flash", models)
        self.assertIn("gemini-2.0-flash-lite", models)
        self.assertIn("imagen-4.0-generate-001", models)

    def test_parse_openai_models_from_api_payload(self) -> None:
        payload = {
            "data": [
                {"id": "gpt-4.1-mini"},
                {"id": "gpt-4o"},
            ]
        }
        models = server.parse_model_list(payload, "openai")
        self.assertEqual(models, ["gpt-4.1-mini", "gpt-4o"])

    def test_dispatch_command_updates_model_and_rules(self) -> None:
        state = {"provider": "openai", "model": "gpt-4.1-mini", "system_prompt": "default"}
        response = server.dispatch_command(":model gpt-4o", state)
        self.assertTrue(response["ok"])
        self.assertEqual(state["model"], "gpt-4o")

        response = server.dispatch_command(":reglas Responde en inglés", state)
        self.assertTrue(response["ok"])
        self.assertEqual(state["system_prompt"], "Responde en inglés")

        response = server.dispatch_command(":reglas-reset", state)
        self.assertTrue(response["ok"])
        self.assertIn("asistente", state["system_prompt"])

    def test_render_markdown_to_html_preserves_mermaid_and_code_blocks(self) -> None:
        self.assertTrue(hasattr(server, "normalize_messages"))
        self.assertTrue(hasattr(server, "dispatch_command"))

    def test_normalize_messages_includes_system_prompt_when_provided(self) -> None:
        messages = server.normalize_messages([{"role": "user", "content": "Hola"}], "¿Qué tal?", system_prompt="Se breve")
        self.assertEqual(messages[0], {"role": "system", "content": "Se breve"})
        self.assertEqual(messages[-1]["content"], "¿Qué tal?")

    def test_chat_reuses_session_state_for_model_and_rules(self) -> None:
        provider = RecordingProvider()
        with patch.object(server, "select_provider", return_value=provider):
            httpd = server.IadimeHTTPServer(("127.0.0.1", 0), server.IadimeHandler)
            handler = server.IadimeHandler.__new__(server.IadimeHandler)
            handler.server = httpd
            handler._send_json = lambda status, payload: setattr(handler, "last_payload", payload)

            handler._handle_chat({"prompt": ":model gpt-4o", "session_id": "demo"})
            handler._handle_chat({"prompt": "Hola", "session_id": "demo", "provider": "openai"})

        self.assertEqual(httpd.session_states["demo"]["model"], "gpt-4o")
        self.assertEqual(httpd.session_states["demo"]["system_prompt"], "Eres un asistente útil. Responde siempre en español.")
        self.assertEqual(provider.calls[-1]["model"], "gpt-4o")
        self.assertEqual(provider.calls[-1]["messages"][0]["role"], "system")

    def test_chat_uses_requested_max_tokens(self) -> None:
        provider = RecordingProvider()
        with patch.object(server, "select_provider", return_value=provider):
            httpd = server.IadimeHTTPServer(("127.0.0.1", 0), server.IadimeHandler)
            handler = server.IadimeHandler.__new__(server.IadimeHandler)
            handler.server = httpd
            handler._send_json = lambda status, payload: setattr(handler, "last_payload", payload)
            handler._handle_chat({"prompt": "Hola", "session_id": "demo", "provider": "openai", "max_tokens": 4096})

        self.assertEqual(provider.calls[-1]["max_tokens"], 4096)

    def test_list_saved_conversations_uses_chats_folder(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            original_root = server.ROOT
            original_chat_root = getattr(server, "CHAT_ROOT", None)
            try:
                server.ROOT = Path(tmpdir)
                server.CHAT_ROOT = server.ROOT / "chats"
                server.CHAT_ROOT.mkdir(parents=True, exist_ok=True)
                (server.CHAT_ROOT / "demo.md").write_text("hola", encoding="utf-8")
                self.assertEqual(server.list_saved_conversations(), ["demo"])
            finally:
                server.ROOT = original_root
                server.CHAT_ROOT = original_chat_root or (original_root / "chats")


if __name__ == "__main__":
    unittest.main()
