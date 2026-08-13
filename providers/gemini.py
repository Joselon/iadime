import json
import mimetypes
import os
import time
import urllib.error
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
            "gemini-2.5-flash-image",
            "gemini-2.5-pro",
            "veo-3.1-generate-preview",
            "veo-3.1-fast-generate-preview",
            "veo-3.1-lite-generate-preview",
            "lyria-3-clip-preview",
            "lyria-3-pro-preview",
            "deep-research-preview-04-2026",
            "deep-research-max-preview-04-2026",
        ]

    def _request_json(self, url: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        if not self.api_key:
            raise ProviderError("GEMINI_API_KEY no configurada")
        body = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"}, method="POST")
        with urllib.request.urlopen(req, timeout=60) as response:
            return json.loads(response.read().decode("utf-8"))

    def _request(self, url: str, method: str = "GET", payload: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        if not self.api_key:
            raise ProviderError("GEMINI_API_KEY no configurada")
        body = json.dumps(payload).encode("utf-8") if payload is not None else None
        separator = "&" if "?" in url else "?"
        request_url = f"{url}{separator}key={self.api_key}"
        headers = {"Content-Type": "application/json", "x-goog-api-key": self.api_key}
        req = urllib.request.Request(request_url, data=body, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=60) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            if exc.code == 400 and "content_blocked" in detail:
                raise ProviderError(
                    "Lyria bloqueó la petición por política de contenido. "
                    "Prueba una descripción de voz original y genérica, sin imitar a ninguna persona o artista."
                ) from exc
            raise ProviderError(f"Gemini API devolvió {exc.code}: {detail[:500]}") from exc

    def _poll(self, url: str, status_key: str = "done") -> Dict[str, Any]:
        for _ in range(72):
            result = self._request(url)
            if result.get(status_key) is True or result.get("status") in {"completed", "failed", "cancelled"}:
                if result.get("error"):
                    raise ProviderError(str(result["error"]))
                return result
            time.sleep(5)
        raise ProviderError("La operación de Gemini tardó demasiado")

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
        response = self.image_response(prompt, model)
        images = response.get("images", [])
        if not images:
            raise ProviderError("No se recibió imagen desde Gemini")
        return images[0]

    def image_response(
        self,
        prompt: str,
        model: Optional[str] = None,
        image_data_url: Optional[str] = None,
    ) -> Dict[str, Any]:
        model_name = model or "gemini-2.5-flash-image"
        parts: List[Dict[str, Any]] = [{"text": prompt}]
        if image_data_url:
            parts.extend(self._build_image_parts(image_data_url))
        payload = {
            "contents": [{"role": "user", "parts": parts}],
            "generationConfig": {"responseModalities": ["TEXT", "IMAGE"]},
        }
        data = self._request_json(f"{self.base_url}/models/{model_name}:generateContent?key={self.api_key}", payload)
        candidates = data.get("candidates", [])
        if not candidates:
            raise ProviderError("No se pudo generar la imagen con Gemini")
        parts = candidates[0].get("content", {}).get("parts", [])
        text_parts: List[str] = []
        images: List[str] = []
        for part in parts:
            if isinstance(part, dict) and part.get("text"):
                text_parts.append(str(part["text"]))
            image_data = self._extract_image_from_part(part)
            if image_data:
                images.append(image_data)
        return {"text": "".join(text_parts), "images": images}

    def video(self, prompt: str, model: Optional[str] = None, image_data_url: Optional[str] = None) -> str:
        model_name = model or "veo-3.1-generate-preview"
        instance: Dict[str, Any] = {"prompt": prompt}
        if image_data_url and image_data_url.startswith("data:"):
            meta, data = image_data_url.split(",", 1)
            instance["image"] = {
                "bytesBase64Encoded": data,
                "mimeType": meta.split(":", 1)[1].split(";", 1)[0],
            }
        payload = {
            "instances": [instance],
            "parameters": {"aspectRatio": "16:9", "durationSeconds": 8, "numberOfVideos": 1},
        }
        operation = self._request(
            f"{self.base_url}/models/{model_name}:predictLongRunning",
            method="POST",
            payload=payload,
        )
        operation_name = operation.get("name")
        if not operation_name:
            raise ProviderError("Gemini no devolvió la operación de vídeo")
        result = self._poll(f"{self.base_url}/{operation_name}")
        videos = result.get("response", {}).get("generateVideoResponse", {}).get("generatedSamples", [])
        if not videos:
            videos = result.get("response", {}).get("generatedVideos", [])
        video = videos[0].get("video", {}) if videos else {}
        uri = video.get("uri") or video.get("url")
        if not uri:
            raise ProviderError("Gemini no devolvió el vídeo generado")
        return uri

    def interaction(
        self,
        prompt: str,
        model: str,
        agent: bool = False,
        image_data_url: Optional[str] = None,
    ) -> Dict[str, Any]:
        interaction_input: Any = prompt
        if image_data_url and image_data_url.startswith("data:"):
            meta, data = image_data_url.split(",", 1)
            interaction_input = [
                {"type": "text", "text": prompt},
                {
                    "type": "image",
                    "mime_type": meta.split(":", 1)[1].split(";", 1)[0],
                    "data": data,
                },
            ]
        payload: Dict[str, Any] = {
            "input": interaction_input,
            "background": agent,
            "store": True,
        }
        if agent:
            payload["agent"] = model
            payload["agent_config"] = {"type": "deep-research", "visualization": "auto"}
        else:
            payload["model"] = model
        interaction = self._request(f"{self.base_url}/interactions", method="POST", payload=payload)
        interaction_id = interaction.get("id")
        if not interaction_id:
            raise ProviderError("Gemini no devolvió la interacción")
        return self._poll(f"{self.base_url}/interactions/{interaction_id}", status_key="status")

    def audio(self, prompt: str, model: Optional[str] = None, image_data_url: Optional[str] = None) -> Dict[str, Any]:
        safe_prompt = (
            "Create an original song with generic, non-imitative vocals. "
            "Do not imitate or resemble any real singer or artist. "
            "Keep the requested language, duration, style, instruments, and structure.\n\n"
            f"User request:\n{prompt}"
        )
        return self.interaction(safe_prompt, model or "lyria-3-clip-preview", image_data_url=image_data_url)

    def research(self, prompt: str, model: Optional[str] = None, image_data_url: Optional[str] = None) -> Dict[str, Any]:
        return self.interaction(prompt, model or "deep-research-preview-04-2026", agent=True, image_data_url=image_data_url)

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
        return list(dict.fromkeys(models + self.default_models))
