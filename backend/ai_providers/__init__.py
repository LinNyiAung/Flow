"""Per-feature AI provider switching (openai / gemini / claude) with fallback.

Later tasks add the runner (run, run_stream) and its errors to these exports.
"""
from .types import Completion, FeatureSetting, Prompt, Target

__all__ = ["Completion", "FeatureSetting", "Prompt", "Target"]
