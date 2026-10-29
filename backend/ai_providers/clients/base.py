"""The interface every provider client implements, and one shared instance per provider."""
from typing import AsyncIterator, Protocol

from ..types import Completion, Prompt


class ProviderClient(Protocol):
    name: str

    def configured(self) -> bool:
        """True when the provider's API key is present in the environment (checked at call time)."""

    async def complete(self, model: str, prompt: Prompt, *, effort: str | None = None) -> Completion: ...

    def stream(self, model: str, prompt: Prompt, *, effort: str | None = None) -> AsyncIterator[str | Completion]:
        """Yields text chunks, then exactly one Completion (text="", usage, finish)."""

    async def transcribe(self, model: str, audio: bytes, filename: str, language: str | None) -> Completion:
        """Speech to text. Claude raises NotImplementedError."""

    async def ping(self, model: str) -> None:
        """A tiny request (max_tokens about 16). Raises whatever the SDK raises."""


_clients: dict[str, ProviderClient] = {}


def get_client(provider: str) -> ProviderClient:
    """The one client instance for `provider` ("openai", "gemini" or "claude"). KeyError for anything else."""
    client = _clients.get(provider)
    if client is None:
        # Imported here so that a client module can import from this one.
        if provider == "openai":
            from .openai_client import OpenAIClient as cls
        elif provider == "gemini":
            from .gemini_client import GeminiClient as cls
        elif provider == "claude":
            from .claude_client import ClaudeClient as cls
        else:
            raise KeyError(f"unknown AI provider: {provider!r}")
        client = _clients[provider] = cls()
    return client
