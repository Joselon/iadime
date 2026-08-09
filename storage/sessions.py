from typing import Any, Dict, Optional

from .conversations import Conversation


class SessionStore:
    def __init__(self) -> None:
        self._sessions: Dict[str, Conversation] = {}

    def get(self, session_id: str, payload: Optional[Dict[str, Any]] = None) -> Conversation:
        conversation = self._sessions.get(session_id)
        if conversation is None:
            payload = payload or {}
            conversation = Conversation.create(
                session_id,
                provider=payload.get("provider"),
                model=payload.get("model"),
                system_prompt=payload.get("system_prompt"),
            )
            self._sessions[session_id] = conversation
        return conversation

    def replace(self, session_id: str, conversation: Conversation) -> Conversation:
        self._sessions[session_id] = conversation
        return conversation

    def remove(self, session_id: str) -> Optional[Conversation]:
        return self._sessions.pop(session_id, None)

    def as_dict(self) -> Dict[str, Conversation]:
        return self._sessions