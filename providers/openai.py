import json
import os
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

    def chat(
        self,
        messages: List[Dict[str, str]],
        model: Optional[str] = None,
        temperature: float = 0.7,
        max_tokens: int = 1200,
    ) -> str:
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
