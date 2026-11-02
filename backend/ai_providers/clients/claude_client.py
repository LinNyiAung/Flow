"""Claude through the official anthropic SDK (async, `client.beta.messages`).

SDK errors are deliberately not caught here: the runner classifies them.
Never send temperature, top_p or top_k (they return a 400; Prompt.temperature is ignored here), and do not send `thinking` (adaptive is the default
and Sonnet 5.5 / Opus 5.5 reject "disabled").
"""
import base64
import os
from typing import AsyncIterator

import anthropic

from ..types import Completion, Prompt
from .base import DEFAULT_TIMEOUT

# Models whose safety classifiers can decline a request: ask the API to re-run a declined request on its default
# fallback model instead of returning the refusal.
FALLBACK_MODELS = frozenset({"claude-sonnet-5-5", "claude-opus-5-5", "claude-fable-5-1"})
FALLBACK_BETA = "server-side-fallback-2026-07-01"

# Above this, a plain request can hit HTTP timeouts, so the SDK asks for a stream.
STREAM_ABOVE_TOKENS = 16000

# The SDK defaults are 600 s and 2 retries: a hung provider now costs about 60 s per attempt, with one retry.
# See base.py for what the timeout bounds.
TIMEOUT = DEFAULT_TIMEOUT  # seconds
MAX_RETRIES = 1


def map_finish(raw) -> str:
    return {"max_tokens": "length", "refusal": "refusal"}.get(raw, "stop")


def text_of(message) -> str:
    """The concatenated `text` blocks; thinking and fallback blocks are ignored; empty content gives ''."""
    return "".join(b.text for b in (getattr(message, "content", None) or []) if getattr(b, "type", None) == "text")


def strict_schema(schema):
    """A deep copy of `schema` with `additionalProperties: false` on every object node that does not set it
    (Claude structured outputs reject open objects). The caller's dict is not modified."""
    if isinstance(schema, list):
        return [strict_schema(x) for x in schema]
    if not isinstance(schema, dict):
        return schema
    out = {}
    for key, value in schema.items():
        if key in ("properties", "$defs", "definitions"):  # maps of name -> schema
            out[key] = {n: strict_schema(s) for n, s in value.items()} if isinstance(value, dict) else value
        elif key in ("items", "prefixItems", "anyOf", "oneOf", "allOf", "additionalProperties", "not"):
            out[key] = strict_schema(value)
        else:
            out[key] = value  # enum / const / default / required ...: data, not schemas
    kind = schema.get("type")
    if (kind == "object" or (isinstance(kind, list) and "object" in kind)) and "additionalProperties" not in out:
        out["additionalProperties"] = False
    return out


def _completion(message) -> Completion:
    usage = getattr(message, "usage", None)
    return Completion(text_of(message), getattr(usage, "input_tokens", 0) or 0, getattr(usage, "output_tokens", 0) or 0,
                      map_finish(getattr(message, "stop_reason", None)))


class ClaudeClient:
    name = "claude"

    def __init__(self):
        self._sdk = None  # (api key, AsyncAnthropic); created lazily, rebuilt if the key changes

    def configured(self) -> bool:
        return bool(os.getenv("ANTHROPIC_API_KEY"))

    def _messages(self):
        key = os.getenv("ANTHROPIC_API_KEY")
        if self._sdk is None or self._sdk[0] != key:
            self._sdk = (key, anthropic.AsyncAnthropic(api_key=key, timeout=TIMEOUT, max_retries=MAX_RETRIES))
        return self._sdk[1].beta.messages

    @staticmethod
    def _request(model: str, prompt: Prompt, effort: str | None) -> dict:
        content: list[dict] = []
        if prompt.image:
            content.append({"type": "image", "source": {
                "type": "base64", "media_type": prompt.image_mime or "image/jpeg",
                "data": base64.b64encode(prompt.image).decode("ascii")}})
        content.append({"type": "text", "text": prompt.user})
        kwargs: dict = {"model": model, "max_tokens": prompt.max_tokens,
                        "messages": [{"role": "user", "content": content}]}
        if prompt.system:
            kwargs["system"] = prompt.system
        output_config: dict = {}
        if prompt.json_schema is not None:
            output_config["format"] = {"type": "json_schema", "schema": strict_schema(prompt.json_schema)}
        if effort:
            output_config["effort"] = effort
        if output_config:
            kwargs["output_config"] = output_config
        if model in FALLBACK_MODELS:
            kwargs["betas"] = [FALLBACK_BETA]
            kwargs["fallbacks"] = "default"
        return kwargs

    async def complete(self, model: str, prompt: Prompt, *, effort: str | None = None,
                       timeout: int | None = None) -> Completion:
        kwargs = self._request(model, prompt, effort)
        if timeout is not None:
            kwargs["timeout"] = timeout  # seconds, this request only (create() and stream() both take it)
        if prompt.max_tokens > STREAM_ABOVE_TOKENS:
            async with self._messages().stream(**kwargs) as s:
                return _completion(await s.get_final_message())
        return _completion(await self._messages().create(**kwargs))

    async def stream(self, model: str, prompt: Prompt, *, effort: str | None = None) -> AsyncIterator[str | Completion]:
        async with self._messages().stream(**self._request(model, prompt, effort)) as s:
            async for text in s.text_stream:
                if text:
                    yield text
            final = await s.get_final_message()
        done = _completion(final)
        yield Completion("", done.input_tokens, done.output_tokens, done.finish)

    async def transcribe(self, model: str, audio: bytes, filename: str, language: str | None) -> Completion:
        raise NotImplementedError("Claude cannot transcribe audio")

    async def ping(self, model: str) -> None:
        await self._messages().create(**self._request(model, Prompt("", "ping", max_tokens=16), None))
