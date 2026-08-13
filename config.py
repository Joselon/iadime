from pathlib import Path

ROOT = Path(__file__).resolve().parent
WEB_ROOT = ROOT / "web"
FAVICON_ROOT = WEB_ROOT / "favicon"
CHAT_ROOT = ROOT / "chats"
OUTPUT_ROOT = ROOT / "output"
IMAGES_ROOT = ROOT / "imagenes"
DEFAULT_SYSTEM_PROMPT = "Eres un asistente útil. Responde siempre en español."
HOST = "127.0.0.1"
PORT = 8080
OPENAI_MODEL = "gpt-4.1-mini"
GEMINI_MODEL = "gemini-2.5-flash"
TEMPERATURE = 0.7
MAX_TOKENS = 4000
