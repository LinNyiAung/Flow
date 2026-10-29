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


@dataclass
class Completion:
    text: str
    input_tokens: int
    output_tokens: int
    finish: str   # "stop" | "length" | "filtered" | "refusal"
