"""OpenAI: chat completions (text, images, JSON mode, streaming) and Whisper transcription.

SDK errors are deliberately not caught here: the runner classifies them.
"""
import base64
import io
import os
import wave
from typing import AsyncIterator

import openai

from ..features import is_openai_audio_model
from ..types import Completion, Prompt
from .base import DEFAULT_TIMEOUT

_FINISH = {"length": "length", "content_filter": "filtered"}

# The SDK defaults are 600 s and 2 retries: a hung provider now costs about 60 s per attempt, with one retry.
# See base.py for what the timeout bounds.
TIMEOUT = DEFAULT_TIMEOUT  # seconds
MAX_RETRIES = 1


def map_finish(raw) -> str:
    return _FINISH.get(raw, "stop")


def _messages(prompt: Prompt) -> list[dict]:
    user: str | list = prompt.user
    if prompt.image:
        b64 = base64.b64encode(prompt.image).decode("ascii")
        mime = prompt.image_mime or "image/jpeg"
        user = [{"type": "text", "text": prompt.user},
                {"type": "image_url", "image_url": {"url": f"data:{mime};base64,{b64}"}}]
    messages = [{"role": "system", "content": prompt.system}] if prompt.system else []
    return messages + [{"role": "user", "content": user}]


def _with_usage(text: str, finish: str, usage, served: str | None, prompt: Prompt) -> Completion:
    """A Completion from CompletionUsage: prompt_tokens (which include prompt_tokens_details.cached_tokens) and
    completion_tokens; len // 4 of the prompt text and the answer (marked estimated) when the response has none."""
    if usage is None:
        return Completion(text, (len(prompt.system) + len(prompt.user)) // 4, len(text) // 4, finish,
                          served_model=served, estimated=True)
    details = getattr(usage, "prompt_tokens_details", None)
    cached = getattr(details, "cached_tokens", 0) if details is not None else 0
    return Completion(text, getattr(usage, "prompt_tokens", 0) or 0, getattr(usage, "completion_tokens", 0) or 0,
                      finish, served_model=served, cached_input_tokens=cached if isinstance(cached, int) else 0)


def audio_seconds_of(response) -> float | None:
    """The transcribed audio's length from a transcription response: `usage` of type "duration" (whisper-1;
    openai.types.audio.Transcription.usage is UsageTokens | UsageDuration), else a verbose_json `duration`.
    None when the response carries neither (the gpt-4o*-transcribe models report token usage instead)."""
    usage = getattr(response, "usage", None)
    if usage is not None and getattr(usage, "type", None) == "duration":
        seconds = getattr(usage, "seconds", None)
        if isinstance(seconds, (int, float)):
            return float(seconds)
    duration = getattr(response, "duration", None)
    return float(duration) if isinstance(duration, (int, float)) else None


def _silent_wav() -> bytes:
    """Half a second of silence: the smallest thing Whisper accepts for a ping."""
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(16000)
        w.writeframes(b"\x00\x00" * 8000)
    return buf.getvalue()


class OpenAIClient:
    name = "openai"

    def __init__(self):
        self._sdk = None  # (api key, AsyncOpenAI); created lazily, rebuilt if the key changes

    def configured(self) -> bool:
        return bool(os.getenv("OPENAI_API_KEY"))

    def _client(self):
        key = os.getenv("OPENAI_API_KEY")
        if self._sdk is None or self._sdk[0] != key:
            self._sdk = (key, openai.AsyncOpenAI(api_key=key, timeout=TIMEOUT, max_retries=MAX_RETRIES))
        return self._sdk[1]

    def _kwargs(self, model: str, prompt: Prompt) -> dict:
        # max_completion_tokens, not the deprecated max_tokens: gpt-4o accepts both, reasoning models only this one.
        kwargs = {"model": model, "messages": _messages(prompt), "max_completion_tokens": prompt.max_tokens}
        if prompt.temperature is not None:
            kwargs["temperature"] = prompt.temperature
        if prompt.json_schema is not None:
            kwargs["response_format"] = {"type": "json_object"}
        return kwargs

    async def complete(self, model: str, prompt: Prompt, *, effort: str | None = None,
                       timeout: int | None = None) -> Completion:
        kwargs = self._kwargs(model, prompt)
        if timeout is not None:
            kwargs["timeout"] = timeout  # seconds, this request only (the SDK's per-request override)
        r = await self._client().chat.completions.create(**kwargs)
        choice = r.choices[0] if r.choices else None
        text = (choice.message.content or "") if choice else ""
        return _with_usage(text, map_finish(choice.finish_reason if choice else None), getattr(r, "usage", None),
                           getattr(r, "model", None), prompt)

    async def stream(self, model: str, prompt: Prompt, *, effort: str | None = None) -> AsyncIterator[str | Completion]:
        resp = await self._client().chat.completions.create(
            **self._kwargs(model, prompt), stream=True, stream_options={"include_usage": True})
        finish, usage, served = None, None, None
        parts: list[str] = []
        async for chunk in resp:
            if getattr(chunk, "usage", None) is not None:
                usage = chunk.usage
            served = getattr(chunk, "model", None) or served  # every chunk names the model (ChatCompletionChunk.model)
            for choice in chunk.choices or []:
                if choice.finish_reason:
                    finish = choice.finish_reason
                text = getattr(choice.delta, "content", None)
                if text:
                    parts.append(text)
                    yield text
        done = _with_usage("".join(parts), map_finish(finish), usage, served, prompt)
        done.text = ""
        yield done

    async def transcribe(self, model: str, audio: bytes, filename: str, language: str | None) -> Completion:
        kwargs = {"model": model, "file": (filename, audio)}
        if language:
            kwargs["language"] = language  # omitted -> auto-detect
        r = await self._client().audio.transcriptions.create(**kwargs)
        text = r.text or ""
        tokens = len(text) // 4  # the token columns stay an estimate (speech-to-text is billed per minute)
        seconds = audio_seconds_of(r)
        return Completion(text, tokens, tokens, "stop", audio_seconds=seconds, served_model=getattr(r, "model", None),
                          estimated=seconds is None)

    async def ping(self, model: str) -> None:
        if is_openai_audio_model(model):
            await self.transcribe(model, _silent_wav(), "ping.wav", None)
            return
        await self._client().chat.completions.create(
            model=model, messages=[{"role": "user", "content": "ping"}], max_completion_tokens=16)
