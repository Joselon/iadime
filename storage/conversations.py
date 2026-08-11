from dataclasses import dataclass, field
from datetime import datetime, timezone
import json
import math
import os
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from config import CHAT_ROOT, DEFAULT_SYSTEM_PROMPT, GEMINI_MODEL, OPENAI_MODEL


MODEL_PRICING_EUR_PER_1M_TOKENS = {
    "openai": {
        "gpt-4.1-mini": {"input": 0.15, "output": 0.60},
        "gpt-4.1": {"input": 2.00, "output": 8.00},
        "gpt-4o-mini": {"input": 0.15, "output": 0.60},
        "gpt-4o": {"input": 5.00, "output": 15.00},
    },
    "gemini": {
        "gemini-2.0-flash": {"input": 0.10, "output": 0.40},
        "gemini-2.0-flash-lite": {"input": 0.05, "output": 0.20},
        "gemini-1.5-pro": {"input": 1.25, "output": 5.00},
    },
}


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def estimate_tokens(text: str) -> int:
    cleaned = str(text or "")
    if not cleaned:
        return 0
    return max(1, math.ceil(len(cleaned) / 4))


def _format_currency_eur(amount: float) -> str:
    return f"{amount:.4f} €"


def _parse_currency_eur(value: str) -> float:
    cleaned = str(value or "").replace("€", "").replace(" ", "").replace(",", ".")
    try:
        return float(cleaned)
    except ValueError:
        return 0.0


def _pricing_for(provider: str, model: str) -> Dict[str, float]:
    provider_name = (provider or "").lower()
    model_name = (model or "").lower()
    provider_rates = MODEL_PRICING_EUR_PER_1M_TOKENS.get(provider_name, {})
    if model_name in provider_rates:
        return provider_rates[model_name]
    if provider_rates:
        return next(iter(provider_rates.values()))
    return {"input": 0.0, "output": 0.0}


def estimate_turn_usage(provider: str, model: str, prompt: str, answer: str) -> Dict[str, Any]:
    input_tokens = estimate_tokens(prompt)
    output_tokens = estimate_tokens(answer)
    rates = _pricing_for(provider, model)
    estimated_cost = (input_tokens * rates.get("input", 0.0) + output_tokens * rates.get("output", 0.0)) / 1_000_000
    return {
        "estimated_input_tokens": input_tokens,
        "estimated_output_tokens": output_tokens,
        "estimated_tokens": input_tokens + output_tokens,
        "estimated_cost_eur": estimated_cost,
    }


def _normalize_history_entry(entry: Dict[str, Any]) -> Dict[str, Any]:
    normalized = dict(entry or {})
    normalized["role"] = str(normalized.get("role", "user"))
    normalized["content"] = str(normalized.get("content", ""))
    if "estimated_tokens" in normalized:
        try:
            normalized["estimated_tokens"] = int(float(normalized["estimated_tokens"]))
        except (TypeError, ValueError):
            normalized["estimated_tokens"] = 0
    if "estimated_cost_eur" in normalized:
        normalized["estimated_cost_eur"] = float(normalized.get("estimated_cost_eur") or 0.0)
    if "estimated_input_tokens" in normalized:
        try:
            normalized["estimated_input_tokens"] = int(float(normalized["estimated_input_tokens"]))
        except (TypeError, ValueError):
            normalized["estimated_input_tokens"] = 0
    if "estimated_output_tokens" in normalized:
        try:
            normalized["estimated_output_tokens"] = int(float(normalized["estimated_output_tokens"]))
        except (TypeError, ValueError):
            normalized["estimated_output_tokens"] = 0
    if "turn_cost_eur" in normalized:
        normalized["turn_cost_eur"] = float(normalized.get("turn_cost_eur") or 0.0)
    if "turn_tokens" in normalized:
        try:
            normalized["turn_tokens"] = int(float(normalized["turn_tokens"]))
        except (TypeError, ValueError):
            normalized["turn_tokens"] = 0
    return normalized


def _render_message_metadata(entry: Dict[str, Any]) -> List[str]:
    provider = str(entry.get("provider", "") or "").strip()
    model = str(entry.get("model", "") or "").strip()
    estimated_tokens = int(entry.get("estimated_tokens") or 0)
    estimated_cost_eur = float(entry.get("estimated_cost_eur") or 0.0)
    provider_label = provider.upper() if provider else "-"
    if not any([provider, model, estimated_tokens, estimated_cost_eur]):
        return []
    return [
        f"> Proveedor: {provider_label}",
        f"> Modelo: {model or '-'}",
        f"> Tokens estimados: {estimated_tokens}",
        f"> Coste estimado: {_format_currency_eur(estimated_cost_eur)}",
        "",
    ]


def _ensure_closed_fenced_code_blocks(content: str) -> str:
    lines = str(content or "").splitlines()
    fence_count = sum(1 for line in lines if line.strip().startswith("```"))
    if fence_count % 2 == 0:
        return str(content or "")
    if content.endswith("\n"):
        return f"{content}```"
    return f"{content}\n```"


def _message_marker(entry: Dict[str, Any]) -> str:
    marker = {
        "role": str(entry.get("role", "user")),
        "provider": str(entry.get("provider", "") or ""),
        "model": str(entry.get("model", "") or ""),
        "estimated_tokens": int(entry.get("estimated_tokens") or 0),
        "estimated_cost_eur": float(entry.get("estimated_cost_eur") or 0.0),
    }
    return f"<!-- iadime-message {json.dumps(marker, ensure_ascii=False)} -->"


def _conversation_marker(conversation: "Conversation") -> str:
    marker = {
        "provider": str(conversation.provider or ""),
        "model": str(conversation.model or ""),
        "system_prompt": str(conversation.system_prompt or ""),
    }
    return f"<!-- iadime-conversation {json.dumps(marker, ensure_ascii=False)} -->"


def _parse_message_marker(line: str) -> Optional[Dict[str, Any]]:
    prefix = "<!-- iadime-message "
    suffix = " -->"
    if not line.startswith(prefix) or not line.endswith(suffix):
        return None
    payload = line[len(prefix):-len(suffix)].strip()
    try:
        marker = json.loads(payload)
    except json.JSONDecodeError:
        return None
    if not isinstance(marker, dict):
        return None
    return marker


def _parse_conversation_marker(text: str) -> Dict[str, Any]:
    for raw_line in text.splitlines():
        line = raw_line.strip()
        prefix = "<!-- iadime-conversation "
        suffix = " -->"
        if not line.startswith(prefix) or not line.endswith(suffix):
            continue
        payload = line[len(prefix):-len(suffix)].strip()
        try:
            marker = json.loads(payload)
        except json.JSONDecodeError:
            return {}
        if isinstance(marker, dict):
            return marker
        return {}
    return {}


def _parse_metadata_row(row: str) -> Optional[Tuple[str, str]]:
    cells = [cell.strip() for cell in row.strip().strip("|").split("|")]
    if len(cells) < 2:
        return None
    return cells[0], cells[1]


def _extract_message_block(section_lines: List[str]) -> Dict[str, Any]:
    lines = list(section_lines)
    metadata: Dict[str, Any] = {}
    while lines and not lines[0].strip():
        lines.pop(0)

    marker_index = next((index for index, line in enumerate(lines) if line.strip() == "| Campo | Valor |"), None)
    if marker_index is not None:
        content_lines = lines[:marker_index]
        table_lines = lines[marker_index:]
        if table_lines:
            table_lines.pop(0)
            if table_lines and table_lines[0].strip().startswith("| ---"):
                table_lines.pop(0)
            while table_lines and table_lines[0].strip().startswith("|"):
                row = table_lines.pop(0)
                parsed_row = _parse_metadata_row(row)
                if not parsed_row:
                    continue
                label, value = parsed_row
                normalized_label = label.lower()
                if normalized_label == "proveedor":
                    metadata["provider"] = value
                elif normalized_label == "modelo":
                    metadata["model"] = value
                elif normalized_label == "tokens estimados":
                    try:
                        metadata["estimated_tokens"] = int(float(value))
                    except ValueError:
                        metadata["estimated_tokens"] = 0
                elif normalized_label == "coste estimado":
                    metadata["estimated_cost_eur"] = _parse_currency_eur(value)
        content = "\n".join(content_lines).strip()
    else:
        content = "\n".join(lines).strip()
    return {"metadata": metadata, "content": content}


def _parse_marked_message_blocks(text: str) -> List[Dict[str, Any]]:
    history: List[Dict[str, Any]] = []
    lines = text.splitlines()
    index = 0
    while index < len(lines):
        line = lines[index].strip()
        marker = _parse_message_marker(line)
        if marker is None:
            index += 1
            continue

        index += 1
        content_lines: List[str] = []
        while index < len(lines):
            current_line = lines[index].strip()
            if current_line == "<!-- /iadime-message -->":
                index += 1
                break
            content_lines.append(lines[index])
            index += 1

        entry: Dict[str, Any] = {
            "role": marker.get("role", "user"),
            "content": "\n".join(content_lines).strip(),
        }
        entry.update(marker)
        if entry["content"]:
            history.append(_normalize_history_entry(entry))
    return history


def _parse_saved_history(text: str) -> List[Dict[str, Any]]:
    marked_history = _parse_marked_message_blocks(text)
    if marked_history:
        return marked_history

    history: List[Dict[str, Any]] = []
    lines = text.splitlines()
    index = 0
    while index < len(lines):
        line = lines[index].strip()
        if not line.startswith("## "):
            index += 1
            continue
        header = line[3:].strip().lower()
        if header.startswith("usuario"):
            role = "user"
        elif header.startswith("ia"):
            role = "assistant"
        else:
            role = None
        index += 1
        section_lines: List[str] = []
        while index < len(lines) and not lines[index].strip().startswith("## "):
            section_lines.append(lines[index])
            index += 1
        if role is None:
            continue
        parsed_block = _extract_message_block(section_lines)
        content = parsed_block["content"]
        if not content:
            continue
        entry: Dict[str, Any] = {"role": role, "content": content}
        entry.update(parsed_block["metadata"])
        history.append(_normalize_history_entry(entry))
    return history


def list_saved_conversations(directory: Optional[Path] = None) -> List[str]:
    chat_root = directory or CHAT_ROOT
    chat_root.mkdir(parents=True, exist_ok=True)
    conversations = []
    for path in sorted(chat_root.glob("*.md")):
        conversations.append(path.stem)
    return conversations


def normalize_messages(
    history: Optional[List[Dict[str, Any]]],
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
    history: List[Dict[str, Any]] = field(default_factory=list)
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

    def add_user_message(self, content: str, metadata: Optional[Dict[str, Any]] = None) -> None:
        entry = {"role": "user", "content": content}
        if metadata:
            entry.update(metadata)
        self.history.append(_normalize_history_entry(entry))
        self.touch()

    def add_assistant_message(self, content: str, metadata: Optional[Dict[str, Any]] = None) -> None:
        entry = {"role": "assistant", "content": content}
        if metadata:
            entry.update(metadata)
        self.history.append(_normalize_history_entry(entry))
        self.touch()

    def reset(self) -> None:
        self.history.clear()
        self.touch()

    def replace_history(self, history: Optional[List[Dict[str, str]]]) -> None:
        self.history = [_normalize_history_entry(entry) for entry in (history or [])]
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
        lines: List[str] = [_conversation_marker(self), ""]
        for entry in self.history:
            content = _ensure_closed_fenced_code_blocks(str(entry.get("content", "")))
            lines.append(_message_marker(entry))
            lines.append(content)
            lines.append("<!-- /iadime-message -->")
            metadata_lines = _render_message_metadata(entry)
            if metadata_lines:
                lines.extend(metadata_lines)
        summary = self.summary()
        if summary["estimated_tokens"] or summary["estimated_cost_eur"]:
            lines.append("## Resumen\n")
            lines.extend([
                "| Campo | Valor |",
                "| --- | --- |",
                f"| Tokens estimados totales | {summary['estimated_tokens']} |",
                f"| Coste estimado total | {_format_currency_eur(summary['estimated_cost_eur'])} |",
                "",
            ])
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
        conversation_meta = _parse_conversation_marker(text)
        history = _parse_saved_history(text)
        resolved_provider = provider or conversation_meta.get("provider")
        resolved_model = model or conversation_meta.get("model")
        resolved_system_prompt = system_prompt or conversation_meta.get("system_prompt")
        conversation = cls.create(
            session_id,
            provider=resolved_provider,
            model=resolved_model,
            system_prompt=resolved_system_prompt,
        )
        conversation.replace_history(history)
        if history:
            first_entry = history[0]
            conversation.update_settings(
                provider=resolved_provider or first_entry.get("provider"),
                model=resolved_model or first_entry.get("model"),
            )
        return conversation

    def summary(self) -> Dict[str, Any]:
        estimated_tokens = 0
        estimated_cost_eur = 0.0
        for entry in self.history:
            estimated_tokens += int(entry.get("estimated_tokens") or 0)
            estimated_cost_eur += float(entry.get("estimated_cost_eur") or 0.0)
        return {
            "estimated_tokens": estimated_tokens,
            "estimated_cost_eur": estimated_cost_eur,
        }

    def to_payload(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "provider": self.provider,
            "model": self.model,
            "system_prompt": self.system_prompt,
            "history": self.history,
            "summary": self.summary(),
            "created": self.created.isoformat(),
            "updated": self.updated.isoformat(),
        }
