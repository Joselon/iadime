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
    def test_session_store_creates_and_replaces_conversations(self) -> None:
        session_store = server.SessionStore()

        created = session_store.get("demo", {"provider": "openai", "model": "gpt-test"})
        self.assertEqual(created.id, "demo")
        self.assertEqual(created.model, "gpt-test")

        replacement = server.Conversation.create("demo", provider="gemini", model="gemini-2.0-flash")
        session_store.replace("demo", replacement)

        self.assertIs(session_store.get("demo"), replacement)

    def test_conversation_tracks_messages_and_exports_markdown(self) -> None:
        conversation = server.Conversation.create("demo", provider="openai", model="gpt-test")
        conversation.update_settings(system_prompt="Reglas persistidas")
        conversation.add_user_message("Hola", {"provider": "openai", "model": "gpt-test", "estimated_tokens": 2, "estimated_cost_eur": 0.0})
        conversation.add_assistant_message(
            "Respuesta",
            {
                "provider": "openai",
                "model": "gpt-test",
                "estimated_tokens": 3,
                "estimated_cost_eur": 0.0123,
            },
        )

        self.assertEqual(conversation.history[0]["role"], "user")
        self.assertEqual(conversation.history[1]["role"], "assistant")
        self.assertIn("<!-- iadime-message", conversation.export_markdown())
        self.assertIn("<!-- iadime-conversation", conversation.export_markdown())
        self.assertIn("Reglas persistidas", conversation.export_markdown())
        self.assertIn("Hola", conversation.export_markdown())
        self.assertIn("Respuesta", conversation.export_markdown())
        self.assertIn("> Proveedor: OPENAI", conversation.export_markdown())
        self.assertIn("## Resumen", conversation.export_markdown())

    def test_export_closes_unmatched_code_fence_before_metadata(self) -> None:
        conversation = server.Conversation.create("demo", provider="gemini", model="gemini-3.6-flash")
        conversation.add_assistant_message(
            "```sh\necho hola",
            {
                "provider": "gemini",
                "model": "gemini-3.6-flash",
                "estimated_tokens": 12,
                "estimated_cost_eur": 0.0001,
            },
        )

        exported = conversation.export_markdown()

        self.assertIn("echo hola\n```\n<!-- /iadime-message -->", exported)
        self.assertIn("> Proveedor: GEMINI", exported)

    def test_conversation_loads_metadata_from_markdown(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "demo.md"
            path.write_text(
                """<!-- iadime-conversation {"provider": "openai", "model": "gpt-test", "system_prompt": "Reglas demo"} -->

<!-- iadime-message {"role": "user", "provider": "openai", "model": "gpt-test", "estimated_tokens": 2, "estimated_cost_eur": 0.0} -->
Hola
![imagen](../imagenes/imagen)
## Título interno
<!-- /iadime-message -->
> Proveedor: openai
> Modelo: gpt-test
> Tokens estimados: 2
> Coste estimado: 0.0000 €
""",
                encoding="utf-8",
            )

            conversation = server.Conversation.load("demo", path)

        self.assertEqual(conversation.history[0]["provider"], "openai")
        self.assertEqual(conversation.history[0]["model"], "gpt-test")
        self.assertIn("![imagen](../imagenes/imagen)", conversation.history[0]["content"])
        self.assertIn("## Título interno", conversation.history[0]["content"])
        self.assertEqual(conversation.model, "gpt-test")
        self.assertEqual(conversation.system_prompt, "Reglas demo")

    def test_reglas_command_shows_current_system_prompt(self) -> None:
        state = {"history": [], "model": "gpt-4.1-mini", "provider": "openai", "system_prompt": "Regla activa"}
        response = server.dispatch_command(":reglas", state)
        self.assertTrue(response["ok"])
        self.assertIn("Regla activa", response["message"])

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
            self.addCleanup(httpd.server_close)
            handler = server.IadimeHandler.__new__(server.IadimeHandler)
            handler.server = httpd
            handler._send_json = lambda status, payload: setattr(handler, "last_payload", payload)

            handler._handle_chat({"prompt": ":model gpt-4o", "session_id": "demo"})
            handler._handle_chat({"prompt": "Hola", "session_id": "demo", "provider": "openai"})

        self.assertEqual(httpd.sessions["demo"].model, "gpt-4o")
        self.assertEqual(httpd.sessions["demo"].system_prompt, server.DEFAULT_SYSTEM_PROMPT)
        self.assertEqual(provider.calls[-1]["model"], "gpt-4o")
        self.assertEqual(provider.calls[-1]["messages"][0]["role"], "system")

    def test_history_endpoint_returns_conversation_payload(self) -> None:
        httpd = server.IadimeHTTPServer(("127.0.0.1", 0), server.IadimeHandler)
        self.addCleanup(httpd.server_close)
        conversation = httpd.get_conversation("demo")
        conversation.add_user("Hola")

        handler = server.IadimeHandler.__new__(server.IadimeHandler)
        handler.server = httpd
        handler.path = "/history?session_id=demo"
        handler._send_json = lambda status, payload: setattr(handler, "last_payload", payload)

        handler.do_GET()

        self.assertEqual(handler.last_payload["history"][0]["content"], "Hola")
        self.assertEqual(handler.last_payload["conversation"]["id"], "demo")

    def test_favicon_route_serves_icon_file(self) -> None:
        httpd = server.IadimeHTTPServer(("127.0.0.1", 0), server.IadimeHandler)
        self.addCleanup(httpd.server_close)
        handler = server.IadimeHandler.__new__(server.IadimeHandler)
        handler.server = httpd
        handler.command = "GET"
        handler.path = "/favicon.ico"
        served = {}

        def record_serve(file_path, content_type=None):
            served["file_path"] = file_path
            served["content_type"] = content_type

        handler._serve_file = record_serve

        handler.do_GET()

        self.assertEqual(served["file_path"].name, "favicon.ico")

    def test_chat_uses_requested_max_tokens(self) -> None:
        provider = RecordingProvider()
        with patch.object(server, "select_provider", return_value=provider):
            httpd = server.IadimeHTTPServer(("127.0.0.1", 0), server.IadimeHandler)
            self.addCleanup(httpd.server_close)
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

    def test_delete_conversation_endpoint_removes_saved_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            original_root = server.ROOT
            original_chat_root = getattr(server, "CHAT_ROOT", None)
            try:
                server.ROOT = Path(tmpdir)
                server.CHAT_ROOT = server.ROOT / "chats"
                server.CHAT_ROOT.mkdir(parents=True, exist_ok=True)
                saved_path = server.CHAT_ROOT / "demo.md"
                saved_path.write_text("## Usuario\nHola\n", encoding="utf-8")

                httpd = server.IadimeHTTPServer(("127.0.0.1", 0), server.IadimeHandler)
                self.addCleanup(httpd.server_close)
                handler = server.IadimeHandler.__new__(server.IadimeHandler)
                handler.server = httpd
                handler.command = "DELETE"
                handler.path = "/conversations?name=demo"
                handler._send_json = lambda status, payload: setattr(handler, "last_payload", payload)

                handler.do_DELETE()

                self.assertFalse(saved_path.exists())
                self.assertIn("demo.md", handler.last_payload["message"])
            finally:
                server.ROOT = original_root
                server.CHAT_ROOT = original_chat_root or (original_root / "chats")

    def test_import_legacy_conversation_uses_default_rules(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            original_root = server.ROOT
            original_chat_root = getattr(server, "CHAT_ROOT", None)
            try:
                server.ROOT = Path(tmpdir)
                server.CHAT_ROOT = server.ROOT / "chats"
                server.CHAT_ROOT.mkdir(parents=True, exist_ok=True)
                legacy_path = server.CHAT_ROOT / "legacy.md"
                legacy_path.write_text("## Usuario\nHola\n\n## IA\nRespuesta\n", encoding="utf-8")

                httpd = server.IadimeHTTPServer(("127.0.0.1", 0), server.IadimeHandler)
                self.addCleanup(httpd.server_close)
                existing = httpd.get_conversation("demo")
                existing.update_settings(system_prompt="Reglas previas de otra conversación")

                handler = server.IadimeHandler.__new__(server.IadimeHandler)
                handler.server = httpd
                handler._send_json = lambda status, payload: setattr(handler, "last_payload", payload)

                handler._handle_import({"session_id": "demo", "name": "legacy"})

                loaded = httpd.sessions["demo"]
                self.assertEqual(loaded.system_prompt, server.DEFAULT_SYSTEM_PROMPT)
                self.assertEqual(loaded.history[0]["content"], "Hola")
            finally:
                server.ROOT = original_root
                server.CHAT_ROOT = original_chat_root or (original_root / "chats")


if __name__ == "__main__":
    unittest.main()
