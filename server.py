#!/usr/bin/env python3
import base64
import json
import os
import signal
import socket
import sys
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from mimetypes import guess_type
from pathlib import Path
from typing import List, Dict, Any, Optional

import config
from commands.parser import dispatch_command
from providers import BaseProvider, GeminiProvider, OpenAIProvider, ProviderError, parse_model_list, select_provider
from storage.conversations import Conversation, list_saved_conversations as storage_list_saved_conversations, normalize_messages
from storage.sessions import SessionStore
from utils.logging import configure_logger

# from utils.markdown import render_markdown_to_html
ROOT = config.ROOT
WEB_ROOT = config.WEB_ROOT
FAVICON_ROOT = config.FAVICON_ROOT
CHAT_ROOT = config.CHAT_ROOT
DEFAULT_SYSTEM_PROMPT = config.DEFAULT_SYSTEM_PROMPT
LOGGER = configure_logger()


def list_saved_conversations() -> List[str]:
    return storage_list_saved_conversations(CHAT_ROOT)


class IadimeHTTPServer(ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True

    def server_bind(self) -> None:
        self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        super().server_bind()

    def __init__(self, server_address: tuple, handler_cls: type[BaseHTTPRequestHandler]) -> None:
        super().__init__(server_address, handler_cls)
        self.session_store = SessionStore()

    def get_conversation(self, session_id: str, payload: Optional[Dict[str, Any]] = None) -> Conversation:
        return self.session_store.get(session_id, payload)

    @property
    def sessions(self) -> Dict[str, Conversation]:
        return self.session_store.as_dict()


class IadimeHandler(BaseHTTPRequestHandler):
    server_version = "iadime-web/1.0"

    def _log_request_start(self) -> None:
        method = getattr(self, "command", "UNKNOWN")
        path = getattr(self, "path", "<sin-ruta>")
        client_address = getattr(self, "client_address", ("local",))
        client_host = client_address[0] if client_address else "local"
        LOGGER.info("%s %s from %s", method, path, client_host)

    def do_GET(self) -> None:  # noqa: N802
        self._log_request_start()
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if self._serve_static_asset(path):
            return

        if path in {"/", "/index.html"}:
            self._serve_file(WEB_ROOT / "index.html", "text/html; charset=utf-8")
            return
        if path == "/style.css":
            self._serve_file(WEB_ROOT / "style.css", "text/css; charset=utf-8")
            return
        if path == "/app.js":
            self._serve_file(WEB_ROOT / "app.js", "application/javascript; charset=utf-8")
            return
        if path in {"/chat", "/api/chat"}:
            self._send_json(405, {"error": "Use POST for chat"})
            return
        if path in {"/models", "/api/models"}:
            try:
                provider_name = self._get_provider_name(parsed)
                provider = select_provider(provider_name)
                self._send_json(200, {"models": provider.list_models(), "provider": provider.name})
            except ProviderError as exc:
                self._send_json(500, {"error": str(exc)})
            return
        if path in {"/history", "/api/history"}:
            session_id = self._get_session_id(parsed)
            conversation = self.server.get_conversation(session_id)
            self._send_json(200, {
                "session_id": session_id,
                "history": conversation.history,
                "conversation": conversation.to_payload(),
            })
            return
        if path in {"/export", "/api/export"}:
            self._send_json(405, {"error": "Use POST for export"})
            return
        if path in {"/import", "/api/import"}:
            self._send_json(405, {"error": "Use POST for import"})
            return
        if path in {"/conversations", "/api/conversations"}:
            self._send_json(200, {"conversations": list_saved_conversations()})
            return
        self._send_json(404, {"error": "Not found"})

    def _serve_static_asset(self, path: str) -> bool:
        asset_map = {
            "/favicon.ico": FAVICON_ROOT / "favicon.ico",
            "/apple-touch-icon.png": FAVICON_ROOT / "apple-touch-icon.png",
            "/site.webmanifest": WEB_ROOT / "site.webmanifest",
        }

        if path in asset_map:
            self._serve_file(asset_map[path])
            return True

        if path.startswith("/favicon/"):
            relative_path = path.removeprefix("/favicon/")
            self._serve_file(FAVICON_ROOT / relative_path)
            return True

        return False

    def do_POST(self) -> None:  # noqa: N802
        self._log_request_start()
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length) if length else b"{}"

        try:
            payload = json.loads(body.decode("utf-8")) if body else {}
        except json.JSONDecodeError:
            self._send_json(400, {"error": "JSON inválido"})
            return

        if path in {"/chat", "/api/chat"}:
            self._handle_chat(payload)
            return
        if path in {"/image", "/api/image"}:
            self._handle_image(payload)
            return
        if path in {"/export", "/api/export"}:
            self._handle_export(payload)
            return
        if path in {"/import", "/api/import"}:
            self._handle_import(payload)
            return
        self._send_json(404, {"error": "Not found"})

    def _handle_chat(self, payload: Dict[str, Any]) -> None:
        prompt = payload.get("prompt") or payload.get("message") or payload.get("content") or ""
        if not prompt:
            self._send_json(400, {"error": "Falta prompt"})
            return

        session_id = payload.get("session_id") or "default"
        conversation = self.server.get_conversation(session_id, payload)

        if payload.get("history") and not conversation.history:
            conversation.replace_history(payload.get("history"))

        conversation.update_settings(
            provider=payload.get("provider"),
            model=payload.get("model"),
            system_prompt=payload.get("system_prompt"),
        )

        if prompt.startswith(":"):
            result = dispatch_command(prompt, conversation)
            if result.get("ok"):
                LOGGER.info("Command handled for session=%s command=%s", session_id, prompt)
                self._send_json(200, {
                    "answer": result["message"],
                    "command": True,
                    "session_id": session_id,
                    "conversation": conversation.to_payload(),
                })
                return
            self._send_json(400, {"error": result["message"]})
            return

        normalized_history = conversation.history.copy()
        if payload.get("history"):
            normalized_history = payload.get("history", [])

        messages = conversation.to_messages(prompt, history=normalized_history)
        model = conversation.model
        provider_name = conversation.provider
        max_tokens = payload.get("max_tokens")
        if max_tokens is None:
            max_tokens = int(os.getenv("MAX_TOKENS", str(config.MAX_TOKENS)))
        temperature = payload.get("temperature")
        if temperature is None:
            temperature = float(os.getenv("TEMPERATURE", str(config.TEMPERATURE)))
        try:
            provider = select_provider(provider_name)
            answer = provider.chat(messages, model=model, temperature=temperature, max_tokens=max_tokens)
        except ProviderError as exc:
            LOGGER.exception("Chat provider error for session=%s provider=%s", session_id, provider_name)
            self._send_json(500, {"error": str(exc)})
            return

        conversation.add_user(prompt)
        conversation.add_assistant(answer)
        conversation.update_settings(provider=provider.name, model=model or provider.default_model)
        LOGGER.info(
            "Chat answered session=%s provider=%s model=%s messages=%d history=%d",
            session_id,
            provider.name,
            model or provider.default_model,
            len(messages),
            len(conversation.history),
        )
        self._send_json(200, {
            "answer": answer,
            "provider": provider.name,
            "model": model or provider.default_model,
            "session_id": session_id,
            "conversation": conversation.to_payload(),
        })

    def _handle_image(self, payload: Dict[str, Any]) -> None:
        prompt = payload.get("prompt") or payload.get("message") or payload.get("content") or ""
        if not prompt:
            self._send_json(400, {"error": "Falta prompt de imagen"})
            return
        provider_name = payload.get("provider")
        try:
            provider = select_provider(provider_name)
            image_data = provider.image(prompt)
        except ProviderError as exc:
            LOGGER.exception("Image provider error provider=%s", provider_name)
            self._send_json(500, {"error": str(exc)})
            return
        LOGGER.info("Image generated provider=%s prompt_length=%d", provider.name, len(prompt))
        self._send_json(200, {"image": image_data, "provider": provider.name})

    def _handle_export(self, payload: Dict[str, Any]) -> None:
        name = (payload.get("name") or "conversacion").strip()
        session_id = payload.get("session_id") or "default"
        conversation = self.server.get_conversation(session_id, payload)
        if payload.get("history"):
            conversation.replace_history(payload.get("history"))
        export_path = conversation.save(CHAT_ROOT, name)
        LOGGER.info("Conversation exported session=%s file=%s entries=%d", session_id, export_path.name, len(conversation.history))
        self._send_json(200, {"message": f"Conversación guardada en {export_path.name}", "conversations": list_saved_conversations()})

    def _handle_import(self, payload: Dict[str, Any]) -> None:
        name = (payload.get("name") or "conversacion").strip()
        session_id = payload.get("session_id") or "default"
        import_path = CHAT_ROOT / f"{name}.md"
        if not import_path.exists():
            self._send_json(404, {"error": f"No existe {import_path.name}"})
            return
        current = self.server.get_conversation(session_id, payload)
        conversation = Conversation.load(
            session_id,
            import_path,
            provider=current.provider,
            model=current.model,
            system_prompt=current.system_prompt,
        )
        self.server.session_store.replace(session_id, conversation)
        LOGGER.info("Conversation imported session=%s file=%s entries=%d", session_id, import_path.name, len(conversation.history))
        self._send_json(200, {
            "message": f"Conversación cargada desde {import_path.name}",
            "history": conversation.history,
            "conversation": conversation.to_payload(),
            "conversations": list_saved_conversations(),
        })

    def _serve_file(self, file_path: Path, content_type: Optional[str] = None) -> None:
        if not file_path.exists():
            self._send_json(404, {"error": "Not found"})
            return
        data = file_path.read_bytes()
        resolved_content_type = content_type or guess_type(str(file_path))[0] or "application/octet-stream"
        self.send_response(200)
        self.send_header("Content-Type", resolved_content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
        LOGGER.info("%s %s -> 200 file=%s bytes=%d", self.command, self.path, file_path.name, len(data))

    def _send_json(self, status: int, payload: Dict[str, Any]) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        LOGGER.info("%s %s -> %d json_bytes=%d", self.command, self.path, status, len(body))

    def _get_provider_name(self, parsed) -> Optional[str]:
        query = urllib.parse.parse_qs(parsed.query)
        provider_name = query.get("provider", [None])[0]
        return provider_name

    def _get_session_id(self, parsed) -> str:
        query = urllib.parse.parse_qs(parsed.query)
        return query.get("session_id", ["default"])[0]

    def log_message(self, format: str, *args: Any) -> None:  # noqa: A003
        return


class ServerController:
    def __init__(self, host: str = "0.0.0.0", port: int = 8080) -> None:
        self.host = host
        self.port = port
        self.httpd: Optional[IadimeHTTPServer] = None

    def _setup_signals(self) -> None:
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)

    def _signal_handler(self, signum: int, frame: Any) -> None:
        LOGGER.info("Señal %s recibida. Deteniendo servidor.", signum)
        if self.httpd:
            self.httpd.shutdown()
        LOGGER.info("Servidor detenido correctamente.")
        sys.exit(0)

    def start(self) -> None:
        self._setup_signals()
        try:
            self.httpd = IadimeHTTPServer((self.host, self.port), IadimeHandler)
            LOGGER.info("Servidor iniciado en http://%s:%s", self.host, self.port)
            self.httpd.serve_forever()
        except OSError as err:
            LOGGER.exception("No se pudo vincular al puerto %s: %s", self.port, err)
            sys.exit(1)
        finally:
            if self.httpd is not None:
                self.httpd.server_close()
                LOGGER.info("Socket del servidor cerrado.")


def main() -> None:
    host = os.getenv("HOST", config.HOST)
    port = int(os.getenv("PORT", str(config.PORT)))
    controller = ServerController(host=host, port=port)
    controller.start()


if __name__ == "__main__":
    main()
