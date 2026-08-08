#!/usr/bin/env python3
import base64
import json
import os
import sys
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from mimetypes import guess_type
from pathlib import Path
from typing import List, Dict, Any, Optional
# from utils.markdown import render_markdown_to_html
ROOT = Path(__file__).resolve().parent
WEB_ROOT = ROOT / "web"
CHAT_ROOT = ROOT / "chats"


def list_saved_conversations() -> List[str]:
    CHAT_ROOT.mkdir(parents=True, exist_ok=True)
    conversations = []
    for path in sorted(CHAT_ROOT.glob("*.md")):
        conversations.append(path.stem)
    return conversations


class ProviderError(RuntimeError):
    pass


class BaseProvider:
    def __init__(self, name: str, default_model: str) -> None:
        self.name = name
        self.default_model = default_model
        self.default_models: List[str] = []
        self._cached_models: Optional[List[str]] = None

    def chat(self, messages: List[Dict[str, str]], model: Optional[str] = None, temperature: float = 0.7, max_tokens: int = 1200) -> str:
        raise NotImplementedError

    def image(self, prompt: str, model: Optional[str] = None) -> str:
        raise NotImplementedError

    def fetch_models(self) -> List[str]:
        return self.default_models

    def list_models(self) -> List[str]:
        if self._cached_models is not None:
            return self._cached_models
        try:
            self._cached_models = self.fetch_models()
        except Exception:
            self._cached_models = self.default_models
        return self._cached_models


class OpenAIProvider(BaseProvider):
    def __init__(self) -> None:
        super().__init__("openai", os.getenv("OPENAI_MODEL", "gpt-4.1-mini"))
        self.api_key = os.getenv("OPENAI_API_KEY") or os.getenv("API_KEY")
        self.base_url = "https://api.openai.com/v1"
        self.default_models = [
            "gpt-4.1-mini",
            "gpt-4.1",
            "gpt-4o-mini",
            "gpt-4o",
        ]

    def _request_json(self, url: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        if not self.api_key:
            raise ProviderError("OPENAI_API_KEY no configurada")
        body = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            url,
            data=body,
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {self.api_key}",
            },
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=60) as response:
            return json.loads(response.read().decode("utf-8"))

    def chat(self, messages: List[Dict[str, str]], model: Optional[str] = None, temperature: float = 0.7, max_tokens: int = 1200) -> str:
        payload = {
            "model": model or self.default_model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens,
        }
        data = self._request_json(f"{self.base_url}/chat/completions", payload)
        content = data.get("choices", [{}])[0].get("message", {}).get("content", "")
        if isinstance(content, list):
            return "\n".join(part.get("text", "") for part in content if isinstance(part, dict))
        return str(content)

    def image(self, prompt: str, model: Optional[str] = None) -> str:
        payload = {
            "model": model or "gpt-image-1",
            "prompt": prompt,
            "size": "1024x1024",
        }
        data = self._request_json(f"{self.base_url}/images/generations", payload)
        b64 = data.get("data", [{}])[0].get("b64_json", "")
        if not b64:
            raise ProviderError("No se recibió imagen desde OpenAI")
        return f"data:image/png;base64,{b64}"

    def fetch_models(self) -> List[str]:
        if not self.api_key:
            return self.default_models
        req = urllib.request.Request(
            f"{self.base_url}/models",
            headers={"Authorization": f"Bearer {self.api_key}"},
        )
        with urllib.request.urlopen(req, timeout=20) as response:
            payload = json.loads(response.read().decode("utf-8"))
        models = parse_model_list(payload, "openai")
        return models or self.default_models


class GeminiProvider(BaseProvider):
    def __init__(self) -> None:
        super().__init__("gemini", os.getenv("GEMINI_MODEL", "gemini-2.0-flash"))
        self.api_key = os.getenv("GEMINI_API_KEY") or os.getenv("API_KEY")
        self.base_url = "https://generativelanguage.googleapis.com/v1beta"
        self.default_models = [
            "gemini-2.0-flash",
            "gemini-2.0-flash-lite",
            "gemini-1.5-pro",
        ]

    def _request_json(self, url: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        if not self.api_key:
            raise ProviderError("GEMINI_API_KEY no configurada")
        body = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"}, method="POST")
        with urllib.request.urlopen(req, timeout=60) as response:
            return json.loads(response.read().decode("utf-8"))

    def chat(self, messages: List[Dict[str, str]], model: Optional[str] = None, temperature: float = 0.7, max_tokens: int = 1200) -> str:
        model_name = model or self.default_model
        contents = []
        for item in messages:
            role = item.get("role", "user")
            if role == "assistant":
                role_name = "model"
            elif role == "system":
                role_name = "user"
            else:
                role_name = "user"
            contents.append({"role": role_name, "parts": [{"text": item.get("content", "")}]})
        payload = {
            "contents": contents,
            "generationConfig": {"temperature": temperature, "maxOutputTokens": max_tokens},
        }
        data = self._request_json(f"{self.base_url}/models/{model_name}:generateContent?key={self.api_key}", payload)
        parts = data.get("candidates", [{}])[0].get("content", {}).get("parts", [])
        if not parts:
            raise ProviderError("Gemini no devolvió contenido")
        return "".join(part.get("text", "") for part in parts if isinstance(part, dict))

    def image(self, prompt: str, model: Optional[str] = None) -> str:
        payload = {
            "instances": [{"prompt": prompt}],
            "parameters": {"sampleCount": 1},
        }
        data = self._request_json(f"{self.base_url}/models/{model or 'imagen-4.0-generate-001'}:predict?key={self.api_key}", payload)
        predictions = data.get("predictions", [])
        if not predictions:
            raise ProviderError("No se pudo generar la imagen con Gemini")
        b64 = predictions[0].get("bytesBase64Encoded", "")
        if not b64:
            raise ProviderError("No se recibió imagen desde Gemini")
        return f"data:image/png;base64,{b64}"

    def fetch_models(self) -> List[str]:
        if not self.api_key:
            return self.default_models
        req = urllib.request.Request(
            f"{self.base_url}/models?key={self.api_key}",
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=20) as response:
            payload = json.loads(response.read().decode("utf-8"))
        models = parse_model_list(payload, "gemini")
        return models or self.default_models


def select_provider(provider_name: Optional[str] = None) -> BaseProvider:
    provider_name = (provider_name or os.getenv("PROVIDER", "openai") or "openai").lower()
    if provider_name == "gemini":
        return GeminiProvider()
    return OpenAIProvider()


def parse_model_list(payload: Dict[str, Any], provider_name: str) -> List[str]:
    provider_name = (provider_name or "").lower()
    if provider_name == "gemini":
        models = []
        for item in payload.get("models", []) or []:
            name = item.get("name", "")
            if not name:
                continue
            if name.startswith("models/"):
                name = name.split("/", 1)[1]
            models.append(name)
        return models

    if provider_name == "openai":
        return [item.get("id", "") for item in payload.get("data", []) or [] if item.get("id")]

    return []


def normalize_messages(history: Optional[List[Dict[str, str]]], prompt: str, system_prompt: Optional[str] = None) -> List[Dict[str, str]]:
    messages: List[Dict[str, str]] = []
    if system_prompt:
        messages.append({"role": "system", "content": str(system_prompt)})
    if history:
        for entry in history:
            role = entry.get("role", "user")
            if role == "assistant":
                role_name = "assistant"
            elif role == "system":
                role_name = "system"
            else:
                role_name = "user"
            messages.append({"role": role_name, "content": str(entry.get("content", ""))})
    messages.append({"role": "user", "content": prompt})
    return messages


def dispatch_command(command: str, state: Dict[str, Any]) -> Dict[str, Any]:
    text = (command or "").strip()
    if not text.startswith(":"):
        return {"ok": False, "message": "No es un comando"}

    if text == ":reset":
        state["history"] = []
        return {"ok": True, "message": "Contexto reiniciado"}

    if text == ":help":
        return {
            "ok": True,
            "message": "Comandos disponibles:\n" \
            " :help => Muestra esta ayuda rápida.\n" \
            " :model <nombre> => Cambia el modelo utilizado para la conversación.\n" \
            " :reglas <texto> => Define nuevas reglas o instrucciones para el asistente.\n" \
            " :reglas-reset => Restaura las reglas a: 'Eres un asistente útil. Responde siempre en español.'\n" \
            " :reset => Borra el contexto actual y reinicia la conversación.\n"
        }

    if text.startswith(":model "):
        new_model = text[len(":model "):].strip()
        if new_model:
            state["model"] = new_model
            return {"ok": True, "message": f"Modelo actualizado a {new_model}"}
        return {"ok": False, "message": "Uso: :model <nombre>"}

    if text.startswith(":reglas "):
        new_rules = text[len(":reglas "):].strip()
        if new_rules:
            state["system_prompt"] = new_rules
            return {"ok": True, "message": "Reglas actualizadas"}
        return {"ok": False, "message": "Uso: :reglas <texto>"}

    if text == ":reglas-reset":
        state["system_prompt"] = "Eres un asistente útil. Responde siempre en español."
        return {"ok": True, "message": "Reglas reiniciadas"}

    return {"ok": False, "message": "Comando desconocido"}


class IadimeHTTPServer(ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True

    def __init__(self, server_address: tuple, handler_cls: type[BaseHTTPRequestHandler]) -> None:
        super().__init__(server_address, handler_cls)
        self.conversations: Dict[str, List[Dict[str, str]]] = {}
        self.session_states: Dict[str, Dict[str, Any]] = {}


class IadimeHandler(BaseHTTPRequestHandler):
    server_version = "iadime-web/1.0"

    def do_GET(self) -> None:  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

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
            history = self.server.conversations.get(session_id, [])
            self._send_json(200, {"history": history, "session_id": session_id})
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

    def do_POST(self) -> None:  # noqa: N802
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
        history = self.server.conversations.setdefault(session_id, [])
        state = self.server.session_states.setdefault(session_id, {
            "history": history,
            "model": payload.get("model") or os.getenv("OPENAI_MODEL", "gpt-4.1-mini"),
            "provider": payload.get("provider") or os.getenv("PROVIDER", "openai"),
            "system_prompt": payload.get("system_prompt") or "Eres un asistente útil. Responde siempre en español.",
        })
        if isinstance(state.get("history"), list):
            history[:] = state["history"]

        if prompt.startswith(":"):
            result = dispatch_command(prompt, state)
            if result.get("ok"):
                if isinstance(state.get("history"), list):
                    history[:] = state["history"]
                self._send_json(200, {"answer": result["message"], "command": True, "session_id": session_id})
                return
            self._send_json(400, {"error": result["message"]})
            return
        normalized_history = history.copy()
        if payload.get("history"):
            normalized_history = payload.get("history", [])

        messages = normalize_messages(normalized_history, prompt, system_prompt=state.get("system_prompt"))
        model = payload.get("model") or state.get("model")
        provider_name = payload.get("provider") or state.get("provider")
        max_tokens = payload.get("max_tokens")
        if max_tokens is None:
            max_tokens = int(os.getenv("MAX_TOKENS", "4000"))
        temperature = payload.get("temperature")
        if temperature is None:
            temperature = float(os.getenv("TEMPERATURE", "0.7"))
        try:
            provider = select_provider(provider_name)
            answer = provider.chat(messages, model=model, temperature=temperature, max_tokens=max_tokens)
        except ProviderError as exc:
            self._send_json(500, {"error": str(exc)})
            return

        history.append({"role": "user", "content": prompt})
        history.append({"role": "assistant", "content": answer})
        state["history"] = history
        state["model"] = model
        state["provider"] = provider_name
        self._send_json(200, {"answer": answer, "provider": provider.name, "model": model or provider.default_model, "session_id": session_id})

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
            self._send_json(500, {"error": str(exc)})
            return
        self._send_json(200, {"image": image_data, "provider": provider.name})

    def _handle_export(self, payload: Dict[str, Any]) -> None:
        name = (payload.get("name") or "conversacion").strip()
        session_id = payload.get("session_id") or "default"
        history = payload.get("history") or self.server.conversations.get(session_id, [])
        CHAT_ROOT.mkdir(parents=True, exist_ok=True)
        export_path = CHAT_ROOT / f"{name}.md"
        lines: List[str] = []
        for entry in history:
            role = entry.get("role", "user")
            content = str(entry.get("content", ""))
            if role == "assistant":
                lines.append(f"## IA\n{content}\n")
            else:
                lines.append(f"## Usuario\n{content}\n")
        export_path.write_text("\n".join(lines), encoding="utf-8")
        self._send_json(200, {"message": f"Conversación guardada en {export_path.name}", "conversations": list_saved_conversations()})

    def _handle_import(self, payload: Dict[str, Any]) -> None:
        name = (payload.get("name") or "conversacion").strip()
        session_id = payload.get("session_id") or "default"
        import_path = CHAT_ROOT / f"{name}.md"
        if not import_path.exists():
            self._send_json(404, {"error": f"No existe {import_path.name}"})
            return
        text = import_path.read_text(encoding="utf-8")
        history = []
        for block in text.split("## "):
            if not block.strip():
                continue
            if block.startswith("Usuario"):
                body = block[len("Usuario"):].strip()
                if body:
                    history.append({"role": "user", "content": body})
            elif block.startswith("IA"):
                body = block[len("IA"):].strip()
                if body:
                    history.append({"role": "assistant", "content": body})
        self.server.conversations[session_id] = history
        self._send_json(200, {"message": f"Conversación cargada desde {import_path.name}", "history": history, "conversations": list_saved_conversations()})

    def _serve_file(self, file_path: Path, content_type: str) -> None:
        if not file_path.exists():
            self._send_json(404, {"error": "Not found"})
            return
        data = file_path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _send_json(self, status: int, payload: Dict[str, Any]) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _get_provider_name(self, parsed) -> Optional[str]:
        query = urllib.parse.parse_qs(parsed.query)
        provider_name = query.get("provider", [None])[0]
        return provider_name

    def _get_session_id(self, parsed) -> str:
        query = urllib.parse.parse_qs(parsed.query)
        return query.get("session_id", ["default"])[0]

    def log_message(self, format: str, *args: Any) -> None:  # noqa: A003
        return


def main() -> None:
    import signal

    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", "8080"))
    server = IadimeHTTPServer((host, port), IadimeHandler)

    def stop_server(signum: int, frame: Any) -> None:
        print("\nServidor detenido")
        server.shutdown()

    signal.signal(signal.SIGINT, stop_server)
    signal.signal(signal.SIGTERM, stop_server)

    print(f"Servidor iniciado en http://{host}:{port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nServidor detenido")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
