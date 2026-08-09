import os
from typing import Optional

from .base import BaseProvider
from .gemini import GeminiProvider
from .openai import OpenAIProvider


def select_provider(provider_name: Optional[str] = None) -> BaseProvider:
    provider_name = (provider_name or os.getenv("PROVIDER", "openai") or "openai").lower()
    if provider_name == "gemini":
        return GeminiProvider()
    return OpenAIProvider()
