from typing import Any, Dict, Optional, Protocol, Union, runtime_checkable

from config import DEFAULT_SYSTEM_PROMPT


@runtime_checkable
class ConversationLike(Protocol):
    history: list[dict[str, str]]
    model: str
    provider: str
    system_prompt: str

    def reset(self) -> None: ...

    def update_settings(
        self,
        *,
        provider: Optional[str] = None,
        model: Optional[str] = None,
        system_prompt: Optional[str] = None,
    ) -> None: ...


StateLike = Union[Dict[str, Any], ConversationLike]


def dispatch_command(command: str, state: StateLike) -> Dict[str, Any]:
    text = (command or "").strip()
    if not text.startswith(":"):
        return {"ok": False, "message": "No es un comando"}

    if isinstance(state, ConversationLike):
        target: Dict[str, Any] = {
            "history": state.history,
            "model": state.model,
            "provider": state.provider,
            "system_prompt": state.system_prompt,
        }
    else:
        target = state

    if text == ":reset":
        target["history"] = []
        if isinstance(state, ConversationLike):
            state.reset()
        return {"ok": True, "message": "Contexto reiniciado"}

    if text == ":help":
        return {
            "ok": True,
            "message": "Comandos disponibles:\n"
            " :help => Muestra esta ayuda rápida.\n"
            " :model <nombre> => Cambia el modelo utilizado para la conversación.\n"
            " :reglas => Muestra las reglas actuales de la conversación.\n"
            " :reglas <texto> => Define nuevas reglas o instrucciones para el asistente.\n"
            " :reglas-reset => Restaura las reglas a: 'Eres un asistente útil. Responde siempre en español.'.\n"
            " :reset => Borra el contexto actual y reinicia la conversación.\n",
        }

    if text.startswith(":model "):
        new_model = text[len(":model "):].strip()
        if new_model:
            target["model"] = new_model
            if isinstance(state, ConversationLike):
                state.update_settings(model=new_model)
            return {"ok": True, "message": f"Modelo actualizado a {new_model}"}
        return {"ok": False, "message": "Uso: :model <nombre>"}

    if text == ":reglas":
        current_rules = str(target.get("system_prompt") or DEFAULT_SYSTEM_PROMPT)
        return {"ok": True, "message": f"Reglas actuales:\n{current_rules}"}

    if text.startswith(":reglas "):
        new_rules = text[len(":reglas "):].strip()
        if new_rules:
            target["system_prompt"] = new_rules
            if isinstance(state, ConversationLike):
                state.update_settings(system_prompt=new_rules)
            return {"ok": True, "message": "Reglas actualizadas"}
        return {"ok": False, "message": "Uso: :reglas <texto>"}

    if text == ":reglas-reset":
        target["system_prompt"] = DEFAULT_SYSTEM_PROMPT
        if isinstance(state, ConversationLike):
            state.update_settings(system_prompt=DEFAULT_SYSTEM_PROMPT)
        return {"ok": True, "message": "Reglas reiniciadas"}

    return {"ok": False, "message": "Comando desconocido"}
