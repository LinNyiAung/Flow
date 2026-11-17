"""Budget line categories: one key and one display label for every reader.

A budget line stores its main category in `main_category` and its sub-category in `sub_category` (NULL for a
main-only line). This module is the only place that joins the two into the "Main - Sub" label or splits that label
back (the AI still answers in the label shape).
"""
from typing import Mapping, Optional, Tuple

SEPARATOR = " - "


def allocation_key(cat: Mapping) -> Tuple[str, Optional[str]]:
    """(main_category, sub_category or None) of a budget line (a line without a sub_category key is main-only)."""
    return cat["main_category"], cat.get("sub_category") or None


def allocation_label(cat: Mapping) -> str:
    """"Main - Sub" for a sub line, "Main" for a main-only line."""
    main, sub = allocation_key(cat)
    return f"{main}{SEPARATOR}{sub}" if sub else main


def split_legacy_label(text: str) -> Tuple[str, Optional[str]]:
    """Split a "Main - Sub" label on its first " - " -> (main, sub); a label without one -> (text, None)."""
    main, sep, sub = text.partition(SEPARATOR)
    return (main, sub) if sep else (text, None)
