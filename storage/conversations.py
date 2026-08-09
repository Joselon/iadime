from dataclasses import dataclass, field
from datetime import datetime, timezone
import os
from pathlib import Path
from typing import Any, Dict, List, Optional

from config import CHAT_ROOT, DEFAULT_SYSTEM_PROMPT, GEMINI_MODEL, OPENAI_MODEL


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def list_saved_conversations(directory: Optional[Path] = None) -> List[str]:
    chat_root = directory or CHAT_ROOT
    chat_root.mkdir(parents=True, exist_ok=True)
    conversations = []
    for path in sorted(chat_root.glob("*.md")):
        conversations.append(path.stem)
    return conversations


def normalize_messages(
    history: Optional[List[Dict[str, str]]],
    prompt: str,
    system_prompt: Optional[str] = None,
) -> List[Dict[str, str]]:
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


@dataclass
class Conversation:
    id: str
    provider: str
    model: str
    system_prompt: str = DEFAULT_SYSTEM_PROMPT
    history: List[Dict[str, str]] = field(default_factory=list)
    created: datetime = field(default_factory=utc_now)
    updated: datetime = field(default_factory=utc_now)

    def touch(self) -> None:
        self.updated = utc_now()

    def add_user(self, content: str) -> None:
        self.history.append({"role": "user", "content": content})
        self.touch()

    def add_assistant(self, content: str) -> None:
        self.history.append({"role": "assistant", "content": content})
        self.touch()

    def reset(self) -> None:
        self.history.clear()
        self.touch()

    def replace_history(self, history: Optional[List[Dict[str, str]]]) -> None:
        self.history = [
            {"role": str(entry.get("role", "user")), "content": str(entry.get("content", ""))}
            for entry in (history or [])
        ]
        self.touch()

    def update_settings(
        self,
        *,
        provider: Optional[str] = None,
        model: Optional[str] = None,
        system_prompt: Optional[str] = None,
    ) -> None:
        changed = False
        if provider:
            self.provider = provider
            changed = True
        if model:
            self.model = model
            changed = True
        if system_prompt:
            self.system_prompt = system_prompt
            changed = True
        if changed:
            self.touch()

    def to_messages(self, prompt: str, history: Optional[List[Dict[str, str]]] = None) -> List[Dict[str, str]]:
        return normalize_messages(history if history is not None else self.history, prompt, self.system_prompt)

    def export_markdown(self) -> str:
        lines: List[str] = []
        for entry in self.history:
            role = entry.get("role", "user")
            content = str(entry.get("content", ""))
            if role == "assistant":
                lines.append(f"## IA\n{content}\n")
            else:
                lines.append(f"## Usuario\n{content}\n")
        return "\n".join(lines)

    def save(self, directory: Path, name: str) -> Path:
        directory.mkdir(parents=True, exist_ok=True)
        export_path = directory / f"{name}.md"
        export_path.write_text(self.export_markdown(), encoding="utf-8")
        self.touch()
        return export_path

    @classmethod
    def create(
        cls,
        session_id: str,
        provider: Optional[str] = None,
        model: Optional[str] = None,
        system_prompt: Optional[str] = None,
    ) -> "Conversation":
        resolved_provider = provider or os.getenv("PROVIDER", "openai")
        if model:
            resolved_model = model
        elif resolved_provider == "gemini":
            resolved_model = os.getenv("GEMINI_MODEL", GEMINI_MODEL)
        else:
            resolved_model = os.getenv("OPENAI_MODEL", OPENAI_MODEL)
        return cls(
            id=session_id,
            provider=resolved_provider,
            model=resolved_model,
            system_prompt=system_prompt or DEFAULT_SYSTEM_PROMPT,
        )

    @classmethod
    def load(
        cls,
        session_id: str,
        path: Path,
        provider: Optional[str] = None,
        model: Optional[str] = None,
        system_prompt: Optional[str] = None,
    ) -> "Conversation":
        text = path.read_text(encoding="utf-8")
        history: List[Dict[str, str]] = []
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
        conversation = cls.create(session_id, provider=provider, model=model, system_prompt=system_prompt)
        conversation.replace_history(history)
        return conversation

    def to_payload(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "provider": self.provider,
            "model": self.model,
            "system_prompt": self.system_prompt,
            "history": self.history,
            "created": self.created.isoformat(),
            "updated": self.updated.isoformat(),
        }
