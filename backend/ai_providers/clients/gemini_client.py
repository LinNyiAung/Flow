"""Gemini through google-genai's true-async surface (client.aio.models).

SDK errors are deliberately not caught here: the runner classifies them.
"""
import os
from typing import AsyncIterator

from google import genai
from google.genai import types

from ..types import Completion, Prompt
from .base import DEFAULT_TIMEOUT

_FILTERED = {"SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST"}

# google-genai has no timeout by default. Every call here passes its own HttpOptions(timeout=...) (milliseconds;
# with httpx it bounds each read), and the client is built without one. A client-level timeout would make
# google-genai write "X-Server-Timeout" into the client's shared header dict on the first call that does not
# override it, and every later request (including a 300 s one) would inherit that value. Retries stay at the
# SDK default: none (retry_options unset), so a hung provider costs about 60 s.
TIMEOUT_MS = DEFAULT_TIMEOUT * 1000


def _http_options(timeout_s: int | None) -> types.HttpOptions:
    """Per-request options: a fresh timeout (DEFAULT_TIMEOUT when None), in milliseconds."""
    return types.HttpOptions(timeout=(DEFAULT_TIMEOUT if timeout_s is None else timeout_s) * 1000)

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


def _count(meta, name) -> int:
    v = getattr(meta, name, None) if meta else None
    return v if isinstance(v, int) else 0


def audio_tokens_of(meta) -> int | None:
    """AUDIO tokens in usage_metadata.prompt_tokens_details (a list of ModalityTokenCount: modality, token_count);
    None when the response has no breakdown."""
    details = getattr(meta, "prompt_tokens_details", None) if meta else None
    if not isinstance(details, list):
        return None
    total = 0
    for d in details:
        modality = getattr(d, "modality", None)
        name = str(getattr(modality, "value", None) or getattr(modality, "name", None) or modality or "").upper()
        if name == "AUDIO":
            total += _count(d, "token_count")
    return total


def completion_of(text: str, finish, meta, input_chars: int, served: str | None, *, audio: bool = False) -> Completion:
    """A Completion from usage_metadata (see usage_of): cached_content_token_count is part of prompt_token_count; for
    an audio request the AUDIO tokens of the modality breakdown (all input tokens when there is none) are priced as
    audio. Marked estimated when the token counts fell back to len // 4."""
    tokens_in, tokens_out = usage_of(meta, input_chars, text)
    # (an empty answer may omit candidates_token_count: that 0 is exact)
    estimated = not (meta and isinstance(getattr(meta, "prompt_token_count", None), int)
                     and (isinstance(getattr(meta, "candidates_token_count", None), int) or not text))
    audio_tokens = 0
    if audio:
        found = audio_tokens_of(meta)
        audio_tokens = tokens_in if found is None else min(found, tokens_in)
    return Completion(text, tokens_in, tokens_out, map_finish(finish), served_model=served,
                      cached_input_tokens=min(_count(meta, "cached_content_token_count"), tokens_in),
                      audio_input_tokens=audio_tokens, estimated=estimated)


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
            self._sdk = (key, genai.Client(api_key=key))  # no client-level timeout: see TIMEOUT_MS
        return self._sdk[1].aio.models

    def _request(self, model: str, prompt: Prompt, timeout_s: int | None = None) -> dict:
        """`timeout_s` (seconds) for this request; None means DEFAULT_TIMEOUT."""
        config = types.GenerateContentConfig(
            system_instruction=prompt.system or None,
            response_mime_type="application/json" if prompt.json_schema is not None else None,
            max_output_tokens=prompt.max_tokens,
            temperature=prompt.temperature,
            http_options=_http_options(timeout_s))
        contents = prompt.user
        if prompt.image:
            contents = [types.Part.from_bytes(data=prompt.image, mime_type=prompt.image_mime or "image/jpeg"),
                        prompt.user]
        return {"model": model, "contents": contents, "config": config}

    async def complete(self, model: str, prompt: Prompt, *, effort: str | None = None,
                       timeout: int | None = None) -> Completion:
        r = await self._models().generate_content(**self._request(model, prompt, timeout))
        return completion_of(r.text or "", _finish_of(r), getattr(r, "usage_metadata", None), _chars(prompt),
                             getattr(r, "model_version", None))

    async def stream(self, model: str, prompt: Prompt, *, effort: str | None = None) -> AsyncIterator[str | Completion]:
        resp = await self._models().generate_content_stream(**self._request(model, prompt))
        parts: list[str] = []
        meta, finish, served = None, None, None
        async for chunk in resp:
            if getattr(chunk, "usage_metadata", None):
                meta = chunk.usage_metadata
            served = getattr(chunk, "model_version", None) or served  # GenerateContentResponse.model_version
            reason = _finish_of(chunk)
            if reason is not None:
                finish = reason
            text = chunk.text
            if text:
                parts.append(text)
                yield text
        done = completion_of("".join(parts), finish, meta, _chars(prompt), served)
        done.text = ""
        yield done

    async def transcribe(self, model: str, audio: bytes, filename: str, language: str | None) -> Completion:
        mime = _AUDIO_MIME.get(os.path.splitext(filename or "")[1].lower(), "audio/mpeg")
        instruction = _TRANSCRIBE + (f" The spoken language is {_language_phrase(language)}." if language else "")
        r = await self._models().generate_content(
            model=model,
            contents=[types.Part.from_bytes(data=audio, mime_type=mime), instruction],
            config=types.GenerateContentConfig(http_options=_http_options(None)))
        return completion_of((r.text or "").strip(), _finish_of(r), getattr(r, "usage_metadata", None),
                             len(instruction), getattr(r, "model_version", None), audio=True)

    async def ping(self, model: str) -> None:
        await self._models().generate_content(
            model=model, contents="ping",
            config=types.GenerateContentConfig(max_output_tokens=16, http_options=_http_options(None)))
