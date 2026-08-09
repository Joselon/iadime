from typing import Any, Dict, List, Optional


class ProviderError(RuntimeError):
    pass


class BaseProvider:
    def __init__(self, name: str, default_model: str) -> None:
        self.name = name
        self.default_model = default_model
        self.default_models: List[str] = []
        self._cached_models: Optional[List[str]] = None

    def chat(
        self,
        messages: List[Dict[str, str]],
        model: Optional[str] = None,
        temperature: float = 0.7,
        max_tokens: int = 1200,
    ) -> str:
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
