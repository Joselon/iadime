import json
import mimetypes
import os
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Dict, List, Optional

from config import OPENAI_MODEL

from .base import BaseProvider, ProviderError, parse_model_list


class OpenAIProvider(BaseProvider):
    def __init__(self) -> None:
        super().__init__("openai", os.getenv("OPENAI_MODEL", OPENAI_MODEL))
        self.api_key = os.getenv("OPENAI_API_KEY") or os.getenv("API_KEY")
        self.base_url = "https://api.openai.com/v1"
        self.default_models = [
            "gpt-4.1",
            "gpt-4.1-mini",
            "gpt-4o",
            "gpt-4o-mini",
            "gpt-image-1",
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
        try:
            with urllib.request.urlopen(req, timeout=60) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            detail = ""
            if exc.fp:
                raw = exc.fp.read().decode("utf-8", errors="replace")
                try:
                    parsed = json.loads(raw)
                    detail = (
                        parsed.get("error", {}).get("message")
                        or parsed.get("message")
                        or raw
                    )
                except json.JSONDecodeError:
                    detail = raw
            message = detail.strip() if detail else str(exc)
            raise ProviderError(f"OpenAI API error ({exc.code}): {message}") from exc
        except urllib.error.URLError as exc:
            raise ProviderError(f"Error de conexión con OpenAI: {exc.reason}") from exc

    def _normalize_message_content(self, message: Dict[str, Any]) -> Any:
        content = message.get("content", "")
        parts: List[Dict[str, Any]] = []

        if isinstance(content, list):
            parts.extend(content)
        elif isinstance(content, str) and content:
            parts.append({"type": "text", "text": content})
        elif content is not None:
            parts.append({"type": "text", "text": str(content)})

        for field in ("image_url", "data_url", "file_url"):
            value = message.get(field)
            if not value:
                continue
            image_url = self._extract_image_url(value)
            if image_url:
                parts.append({"type": "image_url", "image_url": {"url": image_url}})

        if not parts:
            return ""
        if len(parts) == 1 and parts[0].get("type") == "text":
            return parts[0].get("text", "")
        return parts

    def _extract_image_url(self, value: Any) -> Optional[str]:
        if isinstance(value, dict):
            value = value.get("url") or value.get("data")
        if not value:
            return None
        value_str = str(value).strip()
        if not value_str:
            return None
        if value_str.startswith("data:image/"):
            return value_str
        if value_str.startswith(("http://", "https://", "/")):
            parsed = urllib.parse.urlparse(value_str)
            path = parsed.path or value_str
            mime_type = mimetypes.guess_type(path)[0] or ""
            if mime_type.startswith("image/"):
                return value_str
        return None

    def _prepare_messages(self, messages: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        prepared: List[Dict[str, Any]] = []
        for message in messages:
            prepared_message = {"role": message.get("role", "user")}
            content = self._normalize_message_content(message)
            prepared_message["content"] = content
            prepared.append(prepared_message)
        return prepared

    def chat(
        self,
        messages: List[Dict[str, Any]],
        model: Optional[str] = None,
        temperature: float = 0.7,
        max_tokens: int = 1200,
    ) -> str:
        payload = {
            "model": model or self.default_model,
            "messages": self._prepare_messages(messages),
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
