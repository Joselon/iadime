import json
import os
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

    def chat(
        self,
        messages: List[Dict[str, str]],
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
            contents.append({"role": role_name, "parts": [{"text": item.get("content", "")} ]})
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
