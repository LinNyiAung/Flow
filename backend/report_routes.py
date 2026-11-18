import asyncio
from datetime import date, datetime, timedelta, tzinfo, UTC
from typing import Optional

from fastapi import APIRouter, HTTPException, status, Depends, Query
from fastapi.responses import StreamingResponse

from families.book import Book, get_book
from plans import quota
from pdf_generator import generate_financial_report_pdf
from report_models import (
    CategoryBreakdown, CurrencyReport, FinancialReport, GoalProgress, 
    MultiCurrencyFinancialReport, ReportPeriod, ReportRequest
)
from models import Currency
from tz_utils import as_calendar_date, day_bounds, local_today
from user_zones import user_zone

from sql import transactions as transactions_db
from sql import goals as goals_db

router = APIRouter(prefix="/api/reports", tags=["transactions"])


def calculate_report_dates(
    period: ReportPeriod,
    start_date: Optional[date],
    end_date: Optional[date],
    tz: tzinfo,
    now: Optional[datetime] = None,
):
    """
    Calculate start and end dates based on period, as naive wall-clock bounds of whole days (transaction dates are
    local date-times with no timezone, so they compare directly).

    Week/month/year are the ones containing today in `tz`, the person's zone (user_zones.user_zone), at the instant
    `now` (default: now). Custom dates are calendar dates, first and last day included.
    """
    today = local_today(tz, now)

    if period == ReportPeriod.WEEK:
        monday = today - timedelta(days=today.weekday())
        start, end = day_bounds(monday, monday + timedelta(days=6))
    elif period == ReportPeriod.MONTH:
        next_month = date(today.year + (today.month == 12), today.month % 12 + 1, 1)
        start, end = day_bounds(today.replace(day=1), next_month - timedelta(days=1))
    elif period == ReportPeriod.YEAR:
        start, end = day_bounds(date(today.year, 1, 1), date(today.year, 12, 31))
    else:  # CUSTOM
        if not start_date or not end_date:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Start date and end date are required for custom period"
            )
        start, end = day_bounds(as_calendar_date(start_date), as_calendar_date(end_date))
        if end < start:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="End date must be on or after start date"
            )

    return start, end


def generate_currency_report(transactions, currency, start_date, end_date):
    """Generate report for a specific currency"""
    inflows = [t for t in transactions if t["type"] == "inflow"]
    outflows = [t for t in transactions if t["type"] == "outflow"]

    total_inflow = sum(t["amount"] for t in inflows)
    total_outflow = sum(t["amount"] for t in outflows)

    # Calculate category breakdowns for inflows - CHANGED to use sub_category
    inflow_categories = {}
    for t in inflows:
        # Use format "Main Category -> Sub Category"
        cat_key = f"{t['main_category']} > {t['sub_category']}"
        if cat_key not in inflow_categories:
            inflow_categories[cat_key] = {
                "amount": 0, 
                "count": 0,
                "main_category": t['main_category']
            }
        inflow_categories[cat_key]["amount"] += t["amount"]
        inflow_categories[cat_key]["count"] += 1

    inflow_by_category = [
        CategoryBreakdown(
            category=cat,
            main_category=data["main_category"],  # NEW
            amount=data["amount"],
            percentage=(data["amount"] / total_inflow * 100) if total_inflow > 0 else 0,
            transaction_count=data["count"]
        )
        for cat, data in inflow_categories.items()
    ]
    inflow_by_category.sort(key=lambda x: x.amount, reverse=True)

    # Calculate category breakdowns for outflows - CHANGED to use sub_category
    outflow_categories = {}
    for t in outflows:
        # Use format "Main Category -> Sub Category"
        cat_key = f"{t['main_category']} > {t['sub_category']}"
        if cat_key not in outflow_categories:
            outflow_categories[cat_key] = {
                "amount": 0, 
                "count": 0,
                "main_category": t['main_category']
            }
        outflow_categories[cat_key]["amount"] += t["amount"]
        outflow_categories[cat_key]["count"] += 1

    outflow_by_category = [
        CategoryBreakdown(
            category=cat,
            main_category=data["main_category"],  # NEW
            amount=data["amount"],
            percentage=(data["amount"] / total_outflow * 100) if total_outflow > 0 else 0,
            transaction_count=data["count"]
        )
        for cat, data in outflow_categories.items()
    ]
    outflow_by_category.sort(key=lambda x: x.amount, reverse=True)

    # Calculate daily averages
    days_in_period = (end_date - start_date).days + 1
    avg_daily_inflow = total_inflow / days_in_period if days_in_period > 0 else 0
    avg_daily_outflow = total_outflow / days_in_period if days_in_period > 0 else 0

    return CurrencyReport(
        currency=currency,
        total_inflow=total_inflow,
        total_outflow=total_outflow,
        net_balance=total_inflow - total_outflow,
        inflow_by_category=inflow_by_category,
        outflow_by_category=outflow_by_category,
        total_transactions=len(transactions),
        inflow_count=len(inflows),
        outflow_count=len(outflows),
        average_daily_inflow=avg_daily_inflow,
        average_daily_outflow=avg_daily_outflow
    )


@router.post("/generate", response_model=FinancialReport)
async def generate_report(
    report_request: ReportRequest,
    book: Book = Depends(get_book)
):
    """Generate a financial report for a specific currency"""
    try:
        start_date, end_date = calculate_report_dates(
            report_request.period,
            report_request.start_date,
            report_request.end_date,
            user_zone(book.person),
        )

        # Determine currency - use requested or user's default
        currency = report_request.currency
        if currency is None:
            currency = Currency(book.person.get("default_currency", "usd"))

        # Totals and per-category sums are computed in the database (transfers left out: a currency with only
        # transfers in the window has no income or spending, so it reports as empty).
        window = dict(currency=currency.value, date_from=start_date, date_to=end_date)
        totals = [s for s in await transactions_db.currency_totals(book.id, **window) if s["count"]]
        categories = await transactions_db.category_totals(book.id, **window)
        result = [{
            "totals": [
                {"total_inflow": s["total_inflow"], "total_outflow": s["total_outflow"],
                 "inflow_count": s["inflow_count"], "outflow_count": s["outflow_count"], "total_count": s["count"]}
                for s in totals
            ],
            **{
                f"{kind}_categories": [
                    {"_id": {"main": c["main_category"], "sub": c["sub_category"]}, "amount": c["total"], "count": c["count"]}
                    for c in categories if c["type"] == kind
                ]
                for kind in ("inflow", "outflow")
            },
        }]

        # Handle empty result
        if not result or not result[0]["totals"]:
            # [FIX] Async find
            goals = await goals_db.list_goals(book.id, currency=currency.value)

            goals_progress = [
                GoalProgress(
                    goal_id=g["_id"],
                    name=g["name"],
                    target_amount=g["target_amount"],
                    current_amount=g["current_amount"],
                    progress_percentage=(g["current_amount"] / g["target_amount"] * 100) if g["target_amount"] > 0 else 0,
                    status=g["status"],
                    currency=currency
                )
                for g in goals
            ]

            total_allocated = sum(g["current_amount"] for g in goals)

            return FinancialReport(
                period=report_request.period,
                start_date=start_date,
                end_date=end_date,
                total_inflow=0,
                total_outflow=0,
                net_balance=0,
                inflow_by_category=[],
                outflow_by_category=[],
                goals=goals_progress,
                total_allocated_to_goals=total_allocated,
                total_transactions=0,
                inflow_count=0,
                outflow_count=0,
                top_income_category=None,
                top_expense_category=None,
                average_daily_inflow=0,
                average_daily_outflow=0,
                currency=currency,
                generated_at=datetime.now(UTC)
            )

        # Extract aggregated data
        data = result[0]
        totals = data["totals"][0]

        total_inflow = totals["total_inflow"]
        total_outflow = totals["total_outflow"]
        inflow_count = totals["inflow_count"]
        outflow_count = totals["outflow_count"]
        total_transactions = totals["total_count"]

        # Process inflow categories
        inflow_by_category = [
            CategoryBreakdown(
                category=f"{cat['_id']['main']} > {cat['_id']['sub']}",
                main_category=cat['_id']['main'],
                amount=cat['amount'],
                percentage=(cat['amount'] / total_inflow * 100) if total_inflow > 0 else 0,
                transaction_count=cat['count']
            )
            for cat in data["inflow_categories"]
        ]

        # Process outflow categories
        outflow_by_category = [
            CategoryBreakdown(
                category=f"{cat['_id']['main']} > {cat['_id']['sub']}",
                main_category=cat['_id']['main'],
                amount=cat['amount'],
                percentage=(cat['amount'] / total_outflow * 100) if total_outflow > 0 else 0,
                transaction_count=cat['count']
            )
            for cat in data["outflow_categories"]
        ]

        # Calculate daily averages
        days_in_period = (end_date - start_date).days + 1
        avg_daily_inflow = total_inflow / days_in_period if days_in_period > 0 else 0
        avg_daily_outflow = total_outflow / days_in_period if days_in_period > 0 else 0

        # [FIX] Async find for goals (second occurrence)
        goals = await goals_db.list_goals(book.id, currency=currency.value)

        goals_progress = [
            GoalProgress(
                goal_id=g["_id"],
                name=g["name"],
                target_amount=g["target_amount"],
                current_amount=g["current_amount"],
                progress_percentage=(g["current_amount"] / g["target_amount"] * 100) if g["target_amount"] > 0 else 0,
                status=g["status"],
                currency=currency
            )
            for g in goals
        ]

        total_allocated = sum(g["current_amount"] for g in goals)

        # Top categories
        top_income = inflow_by_category[0].category if inflow_by_category else None
        top_expense = outflow_by_category[0].category if outflow_by_category else None

        report = FinancialReport(
            period=report_request.period,
            start_date=start_date,
            end_date=end_date,
            total_inflow=total_inflow,
            total_outflow=total_outflow,
            net_balance=total_inflow - total_outflow,
            inflow_by_category=inflow_by_category,
            outflow_by_category=outflow_by_category,
            goals=goals_progress,
            total_allocated_to_goals=total_allocated,
            total_transactions=total_transactions,
            inflow_count=inflow_count,
            outflow_count=outflow_count,
            top_income_category=top_income,
            top_expense_category=top_expense,
            average_daily_inflow=avg_daily_inflow,
            average_daily_outflow=avg_daily_outflow,
            currency=currency,
            generated_at=datetime.now(UTC)
        )

        return report

    except HTTPException:
        raise
    except Exception as e:
        print(f"Error generating report: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to generate report: {str(e)}"
        )


@router.post("/generate-multi-currency", response_model=MultiCurrencyFinancialReport)
async def generate_multi_currency_report(
    report_request: ReportRequest,
    book: Book = Depends(get_book)
):
    """Generate a financial report with all currencies"""
    try:
        start_date, end_date = calculate_report_dates(
            report_request.period,
            report_request.start_date,
            report_request.end_date,
            user_zone(book.person),
        )

        all_transactions = await transactions_db.find_transactions(
            book.id, date_from=start_date, date_to=end_date, include_transfers=False
        )

        # Group by currency
        transactions_by_currency = {}
        for t in all_transactions:
            currency = t.get("currency", "usd")
            if currency not in transactions_by_currency:
                transactions_by_currency[currency] = []
            transactions_by_currency[currency].append(t)

        # Generate report for each currency
        currency_reports = []
        for currency_str, transactions in transactions_by_currency.items():
            try:
                currency = Currency(currency_str)
            except ValueError:
                print(f"⚠️ Report: skipping transactions with unknown currency {currency_str!r}")
                continue
            report = generate_currency_report(transactions, currency, start_date, end_date)
            currency_reports.append(report)

        # [FIX] Async fetch all goals
        all_goals = await goals_db.list_goals(book.id)

        goals_progress = [
            GoalProgress(
                goal_id=g["_id"],
                name=g["name"],
                target_amount=g["target_amount"],
                current_amount=g["current_amount"],
                progress_percentage=(g["current_amount"] / g["target_amount"] * 100) if g["target_amount"] > 0 else 0,
                status=g["status"],
                currency=Currency(g.get("currency", "usd"))
            )
            for g in all_goals
        ]

        report = MultiCurrencyFinancialReport(
            period=report_request.period,
            start_date=start_date,
            end_date=end_date,
            currency_reports=currency_reports,
            goals=goals_progress,
            total_transactions=len(all_transactions),
            generated_at=datetime.now(UTC)
        )

        return report

    except HTTPException:
        raise
    except Exception as e:
        print(f"Error generating multi-currency report: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to generate report: {str(e)}"
        )


@router.post("/download")
async def download_report_pdf(
    report_request: ReportRequest,
    book: Book = Depends(get_book)
):
    """Generate and download a financial report as PDF (single currency only for now).

    Needs "reports" unlocked on the user's plan (Free: 403 plan_feature_locked). That is the only gate: the PDF is not
    an AI action, so nothing is counted and the hidden AI cost cap does not apply.
    """
    quota.require_unlocked(book.person, "reports")
    return await _download_report_pdf(report_request, book)


async def _download_report_pdf(report_request: ReportRequest, book: Book):
    try:
        # Determine currency
        currency = report_request.currency
        if currency is None:
            currency = Currency(book.person.get("default_currency", "usd"))

        # Generate the report (reuse the generate_report logic)
        start_date, end_date = calculate_report_dates(
            report_request.period,
            report_request.start_date,
            report_request.end_date,
            user_zone(book.person),
        )

        transactions = await transactions_db.find_transactions(
            book.id, currency=currency.value, date_from=start_date, date_to=end_date, include_transfers=False
        )

        currency_report = generate_currency_report(transactions, currency, start_date, end_date)

        # [FIX] Async fetch goals
        goals = await goals_db.list_goals(book.id, currency=currency.value)

        goals_progress = [
            GoalProgress(
                goal_id=g["_id"],
                name=g["name"],
                target_amount=g["target_amount"],
                current_amount=g["current_amount"],
                progress_percentage=(g["current_amount"] / g["target_amount"] * 100) if g["target_amount"] > 0 else 0,
                status=g["status"],
                currency=currency
            )
            for g in goals
        ]

        total_allocated = sum(g["current_amount"] for g in goals)

        top_income = currency_report.inflow_by_category[0].category if currency_report.inflow_by_category else None
        top_expense = currency_report.outflow_by_category[0].category if currency_report.outflow_by_category else None

        report = FinancialReport(
            period=report_request.period,
            start_date=start_date,
            end_date=end_date,
            total_inflow=currency_report.total_inflow,
            total_outflow=currency_report.total_outflow,
            net_balance=currency_report.net_balance,
            inflow_by_category=currency_report.inflow_by_category,
            outflow_by_category=currency_report.outflow_by_category,
            goals=goals_progress,
            total_allocated_to_goals=total_allocated,
            total_transactions=currency_report.total_transactions,
            inflow_count=currency_report.inflow_count,
            outflow_count=currency_report.outflow_count,
            top_income_category=top_income,
            top_expense_category=top_expense,
            average_daily_inflow=currency_report.average_daily_inflow,
            average_daily_outflow=currency_report.average_daily_outflow,
            currency=currency,
            generated_at=datetime.now(UTC)
        )

        # Generate PDF with its times in the person's zone
        # "Generated For": the family's name for the family book, else the person's.
        generated_for = (book.family or {}).get("name", "") if book.is_family else book.person.get("name", "")
        pdf_buffer = await asyncio.to_thread(
            generate_financial_report_pdf,
            report,
            generated_for,
            user_zone(book.person),
            currency
        )

        # Create filename with currency
        period_name = report_request.period.value
        filename = f"financial_report_{currency.value}_{period_name}_{start_date.strftime('%Y%m%d')}_{end_date.strftime('%Y%m%d')}.pdf"

        return StreamingResponse(
            pdf_buffer,
            media_type="application/pdf",
            headers={"Content-Disposition": f"attachment; filename={filename}"}
        )

    except HTTPException:
        raise
    except Exception as e:
        print(f"Error generating PDF: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to generate PDF: {str(e)}"
        )