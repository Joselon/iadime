import json
import mimetypes
import os
import urllib.parse
import urllib.request
from typing import Any, Dict, List, Optional

from config import GEMINI_MODEL

from .base import BaseProvider, ProviderError, parse_model_list


class GeminiProvider(BaseProvider):
    def __init__(self) -> None:
        super().__init__("gemini", os.getenv("GEMINI_MODEL", GEMINI_MODEL))
        self.api_key = os.getenv("GEMINI_API_KEY") or os.getenv("API_KEY")
        self.base_url = "https://generativelanguage.googleapis.com/v1beta"
        self.default_models = [
            "gemini-2.5-flash",
            "gemini-2.5-flash-image-preview",
            "gemini-2.5-pro",
            "gemini-2.0-flash",
        ]

    def _request_json(self, url: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        if not self.api_key:
            raise ProviderError("GEMINI_API_KEY no configurada")
        body = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"}, method="POST")
        with urllib.request.urlopen(req, timeout=60) as response:
            return json.loads(response.read().decode("utf-8"))

    def _extract_image_from_part(self, part: Dict[str, Any]) -> Optional[str]:
        if not isinstance(part, dict):
            return None
        for key in ("inlineData", "inline_data"):
            payload = part.get(key)
            if isinstance(payload, dict):
                mime_type = payload.get("mimeType") or payload.get("mime_type") or "image/png"
                b64 = payload.get("data", "")
                if b64:
                    return f"data:{mime_type};base64,{b64}"
        for key in ("fileData", "file_data"):
            payload = part.get(key)
            if isinstance(payload, dict):
                file_uri = payload.get("fileUri") or payload.get("file_uri")
                if file_uri:
                    return file_uri
        return None

    def _build_parts(self, message: Dict[str, Any]) -> List[Dict[str, Any]]:
        content = message.get("content", "")
        parts: List[Dict[str, Any]] = []

        if isinstance(content, list):
            for item in content:
                if isinstance(item, dict):
                    if item.get("type") == "text":
                        text = item.get("text", "")
                        if text:
                            parts.append({"text": text})
                    elif item.get("type") == "image_url":
                        url = item.get("image_url", {}).get("url") if isinstance(item.get("image_url"), dict) else item.get("image_url")
                        if url:
                            parts.extend(self._build_image_parts(url))
                elif item:
                    parts.append({"text": str(item)})
        elif isinstance(content, str) and content.strip():
            parts.append({"text": content})

        for field in ("image_url", "data_url", "file_url", "image_data"):
            value = message.get(field)
            if value:
                parts.extend(self._build_image_parts(value))
        return parts

    def _build_image_parts(self, value: Any) -> List[Dict[str, Any]]:
        if value is None:
            return []
        if isinstance(value, dict):
            value = value.get("url") or value.get("data") or value.get("file_uri") or ""
        if not value:
            return []
        value_str = str(value)
        if value_str.startswith("data:"):
            meta, data = value_str.split(",", 1)
            mime_type = meta.split(":", 1)[1].split(";", 1)[0]
            return [{"inlineData": {"mimeType": mime_type, "data": data}}]
        if value_str.startswith("http://") or value_str.startswith("https://"):
            mime_type = mimetypes.guess_type(value_str)[0] or "image/png"
            return [{"fileData": {"mimeType": mime_type, "fileUri": value_str}}]
        return [{"text": value_str}]

    def chat(
        self,
        messages: List[Dict[str, Any]],
        model: Optional[str] = None,
        temperature: float = 0.7,
        max_tokens: int = 1200,
    ) -> str:
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
            parts = self._build_parts(item)
            if not parts:
                parts = [{"text": item.get("content", "") or ""}]
            contents.append({"role": role_name, "parts": parts})

        payload = {
            "contents": contents,
            "generationConfig": {"temperature": temperature, "maxOutputTokens": max_tokens},
        }
        data = self._request_json(f"{self.base_url}/models/{model_name}:generateContent?key={self.api_key}", payload)
        parts = data.get("candidates", [{}])[0].get("content", {}).get("parts", [])
        if not parts:
            raise ProviderError("Gemini no devolvió contenido")

        text_parts = []
        for part in parts:
            if not isinstance(part, dict):
                continue
            if "text" in part and part.get("text"):
                text_parts.append(str(part.get("text")))
            image_data = self._extract_image_from_part(part)
            if image_data and image_data.startswith("data:"):
                return image_data
        return "".join(text_parts)

    def image(self, prompt: str, model: Optional[str] = None) -> str:
        model_name = model or "gemini-2.5-flash-image-preview"
        payload = {
            "contents": [{"role": "user", "parts": [{"text": prompt}]}],
            "generationConfig": {"responseModalities": ["TEXT", "IMAGE"]},
        }
        data = self._request_json(f"{self.base_url}/models/{model_name}:generateContent?key={self.api_key}", payload)
        candidates = data.get("candidates", [])
        if not candidates:
            raise ProviderError("No se pudo generar la imagen con Gemini")
        parts = candidates[0].get("content", {}).get("parts", [])
        for part in parts:
            image_data = self._extract_image_from_part(part)
            if image_data:
                if image_data.startswith("data:"):
                    return image_data
                if image_data.startswith("http://") or image_data.startswith("https://"):
                    return image_data
        raise ProviderError("No se recibió imagen desde Gemini")

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
