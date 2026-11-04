"""The interface every provider client implements, and one shared instance per provider."""
from typing import AsyncIterator, Protocol

from ..types import Completion, Prompt


class ProviderClient(Protocol):
    name: str

    def configured(self) -> bool:
        """True when the provider's API key is present in the environment (checked at call time)."""

    async def complete(self, model: str, prompt: Prompt, *, effort: str | None = None,
                       timeout: int | None = None) -> Completion:
        """One non-streamed answer. `timeout` (seconds) overrides DEFAULT_TIMEOUT for this request."""

    def stream(self, model: str, prompt: Prompt, *, effort: str | None = None) -> AsyncIterator[str | Completion]:
        """Yields text chunks, then exactly one Completion (text="", usage, finish)."""

    async def transcribe(self, model: str, audio: bytes, filename: str, language: str | None) -> Completion:
        """Speech to text. Claude raises NotImplementedError."""

    async def ping(self, model: str) -> None:
        """A tiny request (max_tokens about 16). Raises whatever the SDK raises."""


# Timeouts in seconds. All three SDKs use httpx, where the timeout bounds each network operation: connecting, and
# each read (the wait for the next bytes of the response). A non-streamed answer arrives only when the model has
# finished, so its first read waits for the whole answer; a stream reads chunk by chunk. A hung provider costs
# about DEFAULT_TIMEOUT per attempt: OpenAI and Claude retry once (max_retries=1), Gemini does not retry.
# (google-genai would apply the timeout to the whole request if aiohttp were installed; it is not.)
DEFAULT_TIMEOUT = 60
LONG_TIMEOUT = 300
# Background jobs whose non-streamed answers are long: they get LONG_TIMEOUT. Every other feature (chat, transaction
# text/image/voice, budgets) gets DEFAULT_TIMEOUT.
LONG_TIMEOUT_FEATURES = frozenset({"insight_weekly", "insight_monthly", "insight_translation", "insight_custom"})


def request_timeout(feature: str | None) -> int:
    """The per-request timeout in seconds for a non-streamed call made for `feature`."""
    return LONG_TIMEOUT if feature in LONG_TIMEOUT_FEATURES else DEFAULT_TIMEOUT


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
