"""Plain data types shared by the AI provider package."""
from dataclasses import dataclass


@dataclass(frozen=True)
class Target:
    """One provider and one model, e.g. Target("claude", "claude-sonnet-5-5")."""
    provider: str
    model: str


@dataclass(frozen=True)
class FeatureSetting:
    """The resolved setting for one feature: a main target plus its backups."""
    main: Target
    backups: tuple[Target, ...] | None   # None = default backups, () = "no backups"
    source: str                          # "panel" | "server" | "default"


@dataclass
class Prompt:
    system: str
    user: str
    image: bytes | None = None
    image_mime: str | None = None
    json_schema: dict | None = None
    max_tokens: int = 2000
    temperature: float | None = None   # sent to OpenAI and Gemini when set; never sent to Claude


@dataclass
class Completion:
    """One answer and what it cost. Only the first four fields are required; the rest feed the cost estimate.

    input_tokens is every input token the provider billed: OpenAI's prompt_tokens and Gemini's prompt_token_count
    (both already include their cached tokens), Claude's input_tokens + cache reads + cache writes (Claude reports
    those separately). cached_input_tokens, cache_write_tokens and audio_input_tokens are parts of that total.
    """
    text: str
    input_tokens: int
    output_tokens: int
    finish: str   # "stop" | "length" | "filtered" | "refusal"
    audio_seconds: float | None = None   # length of the transcribed audio, when the provider reports it
    served_model: str | None = None      # the model the provider says answered (may differ from the one requested)
    cached_input_tokens: int = 0         # input tokens billed at the cached rate (Claude: cache reads)
    cache_write_tokens: int = 0          # Claude cache creation tokens
    audio_input_tokens: int = 0          # input tokens that were audio (priced at the audio input rate)
    estimated: bool = False              # tokens or duration estimated (len // 4 ...) rather than reported
    # An answer made of several provider requests (the translation's cut-off retry): each request, recorded as its
    # own usage row (so each is priced on its own, long-prompt rates included). The totals above are their sums.
    requests: tuple["Completion", ...] = ()
    outcome: str | None = None           # for one of `requests`: "rejected" when its text was not used
