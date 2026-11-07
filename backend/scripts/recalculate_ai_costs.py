"""Recalculate ai_usage.estimated_cost_usd for every row with the current prices (ai_usage_service.PRICING).

Run from the backend directory with DATABASE_URL set (as the backend has it):

    python -m scripts.recalculate_ai_costs            # dry run: prints what would change, writes nothing
    python -m scripts.recalculate_ai_costs --apply    # writes the new costs, in batches, each in its own transaction

Each row is priced from what it stored: provider, model_name, served_model, the token counts (and their cached /
cache-write / audio parts), audio_seconds and created_at (which picks dated prices). Rows from before those detail
columns existed fall back as follows:
  - Gemini voice input rows (transaction_audio_transcription) with no audio_input_tokens: all input tokens are priced
    as audio (the input is the recording plus a one-line instruction);
  - OpenAI speech-to-text rows with no audio_seconds: the audio length is estimated from the stored output tokens
    (characters // 4, about 5.5 characters per word, 150 spoken words per minute).
Running --apply twice changes nothing the second time. The plan cost caps read the new numbers at once.
"""
import argparse
import asyncio
from decimal import ROUND_HALF_UP, Decimal
from typing import Any, Callable

from sqlalchemy import bindparam, select, update

from ai_usage_service import calculate_cost
from sql.db import dispose_engine, fetch_all, transaction
from sql.tables import ai_usage

BATCH = 500
AUDIO_FEATURE = "transaction_audio_transcription"
_MICRO = Decimal("0.000001")
c = ai_usage.c


def _usd(value) -> Decimal:
    return Decimal(str(value or 0)).quantize(_MICRO, rounding=ROUND_HALF_UP)


def estimated_audio(row: dict[str, Any]) -> bool:
    """An OpenAI speech-to-text row with no stored duration: its audio length will be estimated."""
    return row["provider"] == "openai" and row["feature_type"] == AUDIO_FEATURE and row.get("audio_seconds") is None


def new_cost(row: dict[str, Any]) -> Decimal:
    audio_tokens = int(row.get("audio_input_tokens") or 0)
    all_audio = row["provider"] == "gemini" and row["feature_type"] == AUDIO_FEATURE and audio_tokens == 0
    return _usd(calculate_cost(
        row["provider"], row["model_name"], int(row["input_tokens"] or 0), int(row["output_tokens"] or 0),
        audio_seconds=row.get("audio_seconds"), audio_input=all_audio, audio_input_tokens=audio_tokens,
        cached_input_tokens=int(row.get("cached_input_tokens") or 0),
        cache_write_tokens=int(row.get("cache_write_tokens") or 0),
        served_model=row.get("served_model"), at=row["created_at"]))


async def recalculate(apply: bool = False, *, batch_size: int = BATCH, user_id: str | None = None,
                      out: Callable[[str], None] = print) -> dict[str, Any]:
    """Reprice every ai_usage row (only `user_id`'s when given: the tests use it). Returns the summary it prints:
    {"providers": {provider: {rows, old, new, changed}}, "total": {...}, "estimated_audio_rows": n, "applied": n}."""
    providers: dict[str, dict[str, Any]] = {}
    estimated_rows = applied = 0
    cols = (c.id, c.feature_type, c.provider, c.model_name, c.served_model, c.input_tokens, c.output_tokens,
            c.cached_input_tokens, c.cache_write_tokens, c.audio_input_tokens, c.audio_seconds, c.created_at,
            c.estimated_cost_usd)
    stmt_update = (update(ai_usage).where(c.id == bindparam("row_id"))
                   .values(estimated_cost_usd=bindparam("new_cost")))
    last_id = None
    while True:
        stmt = select(*cols).order_by(c.id).limit(batch_size)
        if last_id is not None:
            stmt = stmt.where(c.id > last_id)
        if user_id is not None:
            stmt = stmt.where(c.user_id == user_id)
        rows = await fetch_all(stmt)
        if not rows:
            break
        last_id = rows[-1]["id"]
        changes = []
        for row in rows:
            old, new = _usd(row["estimated_cost_usd"]), new_cost(row)
            p = providers.setdefault(row["provider"], {"rows": 0, "old": Decimal(0), "new": Decimal(0), "changed": 0})
            p["rows"] += 1
            p["old"] += old
            p["new"] += new
            estimated_rows += estimated_audio(row)
            if new != old:
                p["changed"] += 1
                changes.append({"row_id": row["id"], "new_cost": new})
        if apply and changes:
            async with transaction() as conn:
                await conn.execute(stmt_update, changes)
            applied += len(changes)

    total = {"rows": sum(p["rows"] for p in providers.values()), "old": sum((p["old"] for p in providers.values()), Decimal(0)),
             "new": sum((p["new"] for p in providers.values()), Decimal(0)),
             "changed": sum(p["changed"] for p in providers.values())}
    out("AI cost recalculation (" + ("APPLIED" if apply else "dry run: nothing written; add --apply to write") + ")")
    out(f"{'provider':<10} {'rows':>8} {'old cost USD':>14} {'new cost USD':>14} {'rows changed':>13}")
    for name in sorted(providers):
        p = providers[name]
        out(f"{name:<10} {p['rows']:>8} {p['old']:>14.6f} {p['new']:>14.6f} {p['changed']:>13}")
    out(f"{'total':<10} {total['rows']:>8} {total['old']:>14.6f} {total['new']:>14.6f} {total['changed']:>13}")
    if estimated_rows:
        out(f"Note: {estimated_rows} OpenAI voice input row(s) have no stored audio length; their duration was "
            "estimated from the transcript (about 5.5 characters per word, 150 words per minute).")
    if apply:
        out(f"Updated {applied} row(s).")
    return {"providers": providers, "total": total, "estimated_audio_rows": estimated_rows, "applied": applied}


async def _main(apply: bool, batch_size: int) -> None:
    try:
        await recalculate(apply, batch_size=batch_size)
    finally:
        await dispose_engine()


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description="Recalculate ai_usage.estimated_cost_usd with the current prices.")
    parser.add_argument("--apply", action="store_true", help="write the new costs (default: dry run)")
    parser.add_argument("--batch-size", type=int, default=BATCH, help=f"rows per batch/transaction (default {BATCH})")
    args = parser.parse_args(argv)
    from dotenv import load_dotenv
    load_dotenv()  # DATABASE_URL, as the backend reads it (config.py); nothing is printed
    asyncio.run(_main(args.apply, max(1, args.batch_size)))


if __name__ == "__main__":
    main()
