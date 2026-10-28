"""The only provider entry point: bounded requests and an atomic reservation."""
import os
from pathlib import Path
from openai import OpenAI
from safety import FirestoreGuard, ServiceError

VISION_MODEL = "gpt-4o-2024-08-06"
CHAT_MODEL = "gpt-4o-mini-2024-07-18"
OUTPUT_LIMITS = {"upload": 2200, "chat": 350}
INPUT_BYTE_LIMITS = {"upload": 24_000, "chat": 16_000}
guard = FirestoreGuard()
_client = None


def api_key():
    # Production must mount a Secret Manager secret; never load a source .env.
    secret_file = os.environ.get("OPENAI_API_KEY_FILE")
    if secret_file:
        try:
            return Path(secret_file).read_text().strip()
        except OSError:
            return None
    if not os.environ.get("K_SERVICE"):
        return os.environ.get("OPENAI_API_KEY")
    return None


def complete(endpoint, actor, messages):
    global _client
    key = api_key()
    if not key:
        raise ServiceError("ai_unavailable", "Analysis is temporarily unavailable.")
    text_bytes = 0
    for message in messages:
        content = message["content"]
        if isinstance(content, str):
            text_bytes += len(content.encode("utf-8"))
        else:
            text_bytes += sum(len(part.get("text", "").encode("utf-8")) for part in content)
    if text_bytes > INPUT_BYTE_LIMITS[endpoint]:
        raise ServiceError("invalid_request", "This request is too long.", 400)
    if _client is None:
        _client = OpenAI(api_key=key, timeout=40.0, max_retries=0)
    # This is deliberately immediately before the one provider attempt. Failure
    # or ambiguous timeouts retain the entire reservation; never refund/retry.
    guard.reserve(actor, endpoint)
    kwargs = {"model": VISION_MODEL if endpoint == "upload" else CHAT_MODEL,
              "messages": messages, "max_tokens": OUTPUT_LIMITS[endpoint],
              "temperature": 0 if endpoint == "upload" else 0.4,
              "store": False}
    if endpoint == "upload":
        kwargs["response_format"] = {"type": "json_object"}
    try:
        response = _client.chat.completions.create(**kwargs)
        choice = response.choices[0]
        if choice.finish_reason != "stop" or not choice.message.content:
            raise ValueError("Incomplete or refused response")
        return choice.message.content
    except Exception:
        # No raw provider messages, keys, images, or upstream response bodies.
        raise ServiceError("analysis_failed", "Analysis couldn't be completed. Please try again.", 502) from None
