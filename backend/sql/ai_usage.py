"""AI usage records (tokens and estimated cost per AI call) and the admin statistics."""
from datetime import datetime
from typing import Any, Dict, Iterable, List, Optional

from sqlalchemy import case, distinct, func, insert, select

from sql.db import execute, fetch_all, fetch_one
from sql.docs import rows_to_docs
from sql.tables import ai_usage, users

c = ai_usage.c


def _window(stmt, start: Optional[datetime], end: Optional[datetime]):
    if start:
        stmt = stmt.where(c.created_at >= start)
    if end:
        stmt = stmt.where(c.created_at <= end)
    return stmt


def _count_if(condition):
    return func.count(case((condition, 1)))


def _sum_if(condition, column):
    return func.coalesce(func.sum(case((condition, column), else_=0)), 0)


def _f(row: Dict[str, Any]) -> Dict[str, Any]:
    """Decimal sums -> float; NULL sums -> 0."""
    return {k: (float(v) if hasattr(v, "is_finite") else (0 if v is None and k != "user_ids" else v)) for k, v in row.items()}


async def insert_usage(doc: Dict[str, Any]) -> None:
    await execute(insert(ai_usage).values(**{("id" if k == "_id" else k): v for k, v in doc.items()}))


async def overall_stats(start: Optional[datetime], end: Optional[datetime]) -> Dict[str, Any]:
    stmt = _window(select(
        func.count().label("total_requests"),
        func.coalesce(func.sum(c.total_tokens), 0).label("total_tokens"),
        func.coalesce(func.sum(c.estimated_cost_usd), 0).label("total_cost"),
        _sum_if(c.provider == "openai", c.estimated_cost_usd).label("openai_cost"),
        _sum_if(c.provider == "gemini", c.estimated_cost_usd).label("gemini_cost"),
        _count_if(c.feature_type == "weekly_insight").label("weekly_insights"),
        _count_if(c.feature_type == "monthly_insight").label("monthly_insights"),
        _count_if(c.feature_type == "chat").label("chat_requests"),
        _count_if(c.feature_type == "translation").label("translations"),
        func.count(distinct(c.user_id)).label("unique_users"),
    ), start, end)
    return _f(await fetch_one(stmt))


async def per_user_stats(start: Optional[datetime], end: Optional[datetime], sort_by: str,
                         skip: int, limit: int) -> List[Dict[str, Any]]:
    """One row per user (with name/e-mail), ordered by sort_by desc then user id."""
    metrics = {
        "total_requests": func.count().label("total_requests"),
        "total_tokens": func.coalesce(func.sum(c.total_tokens), 0).label("total_tokens"),
        "total_cost": func.coalesce(func.sum(c.estimated_cost_usd), 0).label("total_cost"),
    }
    stmt = _window(select(
        c.user_id, users.c.name.label("user_name"), users.c.email.label("user_email"),
        metrics["total_requests"],
        func.coalesce(func.sum(c.input_tokens), 0).label("total_input_tokens"),
        func.coalesce(func.sum(c.output_tokens), 0).label("total_output_tokens"),
        metrics["total_tokens"], metrics["total_cost"],
        _count_if(c.feature_type == "weekly_insight").label("weekly_insights"),
        _count_if(c.feature_type == "monthly_insight").label("monthly_insights"),
        _count_if(c.feature_type == "chat").label("chat_requests"),
        _count_if(c.feature_type == "translation").label("translations"),
        _sum_if(c.provider == "openai", c.estimated_cost_usd).label("openai_cost"),
        _sum_if(c.provider == "gemini", c.estimated_cost_usd).label("gemini_cost"),
    ).select_from(ai_usage.join(users, users.c.id == c.user_id)), start, end)
    stmt = (stmt.group_by(c.user_id, users.c.name, users.c.email)
            .order_by(metrics[sort_by].desc(), c.user_id).offset(skip).limit(limit))
    return [_f(r) for r in await fetch_all(stmt)]


async def user_detail(user_id: str, feature_type: Optional[str], limit: int) -> List[Dict[str, Any]]:
    stmt = select(ai_usage).where(c.user_id == user_id)
    if feature_type:
        stmt = stmt.where(c.feature_type == feature_type)
    return rows_to_docs(await fetch_all(stmt.order_by(c.created_at.desc(), c.id).limit(limit)))


async def feature_stats(features: Iterable[str], start: Optional[datetime], end: Optional[datetime]) -> List[Dict[str, Any]]:
    """Per feature type: requests, tokens, cost and the distinct user ids."""
    stmt = _window(select(
        c.feature_type,
        func.count().label("total_requests"),
        func.coalesce(func.sum(c.total_tokens), 0).label("total_tokens"),
        func.coalesce(func.sum(c.estimated_cost_usd), 0).label("total_cost"),
        func.array_agg(distinct(c.user_id)).label("user_ids"),
    ).where(c.feature_type.in_(list(features))), start, end).group_by(c.feature_type)
    return [_f(r) for r in await fetch_all(stmt)]
