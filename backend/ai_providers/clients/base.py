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


# Read timeouts (seconds). Every SDK client is built with DEFAULT_TIMEOUT, so a hung provider fails over in about
# a minute. A non-streamed answer must arrive within the read timeout, so a large one gets more time per request.
# Streams keep the default: it applies between chunks.
DEFAULT_TIMEOUT = 60
LONG_TIMEOUT = 300
LONG_ABOVE_TOKENS = 4000


def request_timeout(max_tokens: int) -> int:
    """The read timeout in seconds for a non-streamed request allowed `max_tokens` output tokens."""
    return LONG_TIMEOUT if max_tokens > LONG_ABOVE_TOKENS else DEFAULT_TIMEOUT


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
