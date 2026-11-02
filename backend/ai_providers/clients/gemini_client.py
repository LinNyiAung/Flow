"""Gemini through google-genai's true-async surface (client.aio.models).

SDK errors are deliberately not caught here: the runner classifies them.
"""
import os
from typing import AsyncIterator

from google import genai
from google.genai import types

from ..types import Completion, Prompt
from .base import DEFAULT_TIMEOUT, request_timeout

_FILTERED = {"SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST"}

# Explicit, so a hung provider fails over in about a minute (by default google-genai has no timeout).
# HttpOptions.timeout is in milliseconds. Retries stay at the SDK default (none: retry_options unset).
TIMEOUT_MS = DEFAULT_TIMEOUT * 1000

_AUDIO_MIME = {
    ".mp3": "audio/mpeg", ".wav": "audio/wav", ".m4a": "audio/mp4", ".mp4": "audio/mp4", ".aac": "audio/aac",
    ".ogg": "audio/ogg", ".oga": "audio/ogg", ".opus": "audio/ogg", ".flac": "audio/flac", ".webm": "audio/webm",
    ".aiff": "audio/aiff", ".aif": "audio/aiff", ".3gp": "audio/3gpp", ".amr": "audio/amr",
}
# Callers pass ISO 639-1 codes; the model needs a language name ("my" would read as English "my").
_LANGUAGES = {"en": "English", "my": "Burmese (Myanmar)", "th": "Thai", "zh": "Chinese", "ja": "Japanese",
              "ko": "Korean", "vi": "Vietnamese", "id": "Indonesian", "ms": "Malay", "hi": "Hindi",
              "es": "Spanish", "fr": "French", "de": "German", "pt": "Portuguese", "ru": "Russian", "ar": "Arabic"}


def _language_phrase(code: str) -> str:
    code = code.strip()
    name = _LANGUAGES.get(code.lower().split("-")[0])
    return name or f"the language with ISO 639-1 code '{code}'"


_TRANSCRIBE = "Transcribe this audio exactly. Reply with only the transcript."


def map_finish(raw) -> str:
    """`raw` is a FinishReason enum member, its name, or None."""
    name = getattr(raw, "name", raw)
    if name == "MAX_TOKENS":
        return "length"
    if name in _FILTERED:
        return "filtered"
    return "stop"


def usage_of(meta, input_chars: int, text: str) -> tuple[int, int]:
    """(input, output) tokens from usage_metadata; len // 4 of the prompt and the answer when it is missing."""
    def value(name, fallback):
        v = getattr(meta, name, None) if meta else None
        return v if isinstance(v, int) else fallback

    thoughts = value("thoughts_token_count", 0)  # thinking is billed as output
    return value("prompt_token_count", input_chars // 4), value("candidates_token_count", len(text) // 4) + thoughts


def _chars(prompt: Prompt) -> int:
    return len(prompt.system) + len(prompt.user)


def _finish_of(response):
    cands = getattr(response, "candidates", None)
    return getattr(cands[0], "finish_reason", None) if cands else None


class GeminiClient:
    name = "gemini"

    def __init__(self):
        self._sdk = None  # (api key, genai.Client); created lazily, rebuilt if the key changes

    def configured(self) -> bool:
        return bool(os.getenv("GOOGLE_API_KEY"))

    def _models(self):
        key = os.getenv("GOOGLE_API_KEY")
        if self._sdk is None or self._sdk[0] != key:
            self._sdk = (key, genai.Client(api_key=key, http_options=types.HttpOptions(timeout=TIMEOUT_MS)))
        return self._sdk[1].aio.models

    def _request(self, model: str, prompt: Prompt, timeout_s: int | None = None) -> dict:
        """`timeout_s` (seconds) overrides the client's timeout for this request; None keeps the client default."""
        config = types.GenerateContentConfig(
            system_instruction=prompt.system or None,
            response_mime_type="application/json" if prompt.json_schema is not None else None,
            max_output_tokens=prompt.max_tokens,
            temperature=prompt.temperature,
            http_options=None if timeout_s is None else types.HttpOptions(timeout=timeout_s * 1000))  # milliseconds
        contents = prompt.user
        if prompt.image:
            contents = [types.Part.from_bytes(data=prompt.image, mime_type=prompt.image_mime or "image/jpeg"),
                        prompt.user]
        return {"model": model, "contents": contents, "config": config}

    async def complete(self, model: str, prompt: Prompt, *, effort: str | None = None) -> Completion:
        # Per-request read timeout: a large non-streamed answer gets longer than the client default.
        r = await self._models().generate_content(**self._request(model, prompt, request_timeout(prompt.max_tokens)))
        text = r.text or ""
        tokens_in, tokens_out = usage_of(getattr(r, "usage_metadata", None), _chars(prompt), text)
        return Completion(text, tokens_in, tokens_out, map_finish(_finish_of(r)))

    async def stream(self, model: str, prompt: Prompt, *, effort: str | None = None) -> AsyncIterator[str | Completion]:
        resp = await self._models().generate_content_stream(**self._request(model, prompt))
        parts: list[str] = []
        meta, finish = None, None
        async for chunk in resp:
            if getattr(chunk, "usage_metadata", None):
                meta = chunk.usage_metadata
            reason = _finish_of(chunk)
            if reason is not None:
                finish = reason
            text = chunk.text
            if text:
                parts.append(text)
                yield text
        tokens_in, tokens_out = usage_of(meta, _chars(prompt), "".join(parts))
        yield Completion("", tokens_in, tokens_out, map_finish(finish))

    async def transcribe(self, model: str, audio: bytes, filename: str, language: str | None) -> Completion:
        mime = _AUDIO_MIME.get(os.path.splitext(filename or "")[1].lower(), "audio/mpeg")
        instruction = _TRANSCRIBE + (f" The spoken language is {_language_phrase(language)}." if language else "")
        r = await self._models().generate_content(
            model=model,
            contents=[types.Part.from_bytes(data=audio, mime_type=mime), instruction])
        text = (r.text or "").strip()
        tokens_in, tokens_out = usage_of(getattr(r, "usage_metadata", None), len(instruction), text)
        return Completion(text, tokens_in, tokens_out, map_finish(_finish_of(r)))

    async def ping(self, model: str) -> None:
        await self._models().generate_content(
            model=model, contents="ping", config=types.GenerateContentConfig(max_output_tokens=16))
