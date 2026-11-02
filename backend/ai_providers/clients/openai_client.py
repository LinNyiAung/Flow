"""OpenAI: chat completions (text, images, JSON mode, streaming) and Whisper transcription.

SDK errors are deliberately not caught here: the runner classifies them.
"""
import base64
import io
import os
import wave
from typing import AsyncIterator

import openai

from ..types import Completion, Prompt

_FINISH = {"length": "length", "content_filter": "filtered"}

# Explicit, so a hung provider fails over in about a minute (the SDK defaults are 600 s and 2 retries).
TIMEOUT = 60  # seconds
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

    async def complete(self, model: str, prompt: Prompt, *, effort: str | None = None) -> Completion:
        r = await self._client().chat.completions.create(**self._kwargs(model, prompt))
        choice = r.choices[0] if r.choices else None
        usage = getattr(r, "usage", None)
        return Completion(
            text=(choice.message.content or "") if choice else "",
            input_tokens=getattr(usage, "prompt_tokens", 0) or 0,
            output_tokens=getattr(usage, "completion_tokens", 0) or 0,
            finish=map_finish(choice.finish_reason if choice else None))

    async def stream(self, model: str, prompt: Prompt, *, effort: str | None = None) -> AsyncIterator[str | Completion]:
        resp = await self._client().chat.completions.create(
            **self._kwargs(model, prompt), stream=True, stream_options={"include_usage": True})
        finish, usage = None, None
        async for chunk in resp:
            if getattr(chunk, "usage", None) is not None:
                usage = chunk.usage
            for choice in chunk.choices or []:
                if choice.finish_reason:
                    finish = choice.finish_reason
                text = getattr(choice.delta, "content", None)
                if text:
                    yield text
        yield Completion("", getattr(usage, "prompt_tokens", 0) or 0, getattr(usage, "completion_tokens", 0) or 0,
                         map_finish(finish))

    async def transcribe(self, model: str, audio: bytes, filename: str, language: str | None) -> Completion:
        kwargs = {"model": model, "file": (filename, audio)}
        if language:
            kwargs["language"] = language  # omitted -> auto-detect
        r = await self._client().audio.transcriptions.create(**kwargs)
        text = r.text or ""
        tokens = len(text) // 4  # Whisper reports no usage: estimate, as before
        return Completion(text, tokens, tokens, "stop")

    async def ping(self, model: str) -> None:
        if model.startswith("whisper"):
            await self.transcribe(model, _silent_wav(), "ping.wav", None)
            return
        await self._client().chat.completions.create(
            model=model, messages=[{"role": "user", "content": "ping"}], max_completion_tokens=16)
