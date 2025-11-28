from datetime import datetime, timedelta, UTC
from typing import Optional

from fastapi import APIRouter, HTTPException, status, Depends
from fastapi.responses import StreamingResponse

from utils import get_current_user, require_premium
from pdf_generator import generate_financial_report_pdf
from report_models import CategoryBreakdown, FinancialReport, GoalProgress, ReportPeriod, ReportRequest


from database import (
    transactions_collection, goals_collection
)


router = APIRouter(prefix="/api/reports", tags=["transactions"])

# ==================== FINANCIAL REPORTS ====================

def calculate_report_dates(period: ReportPeriod, start_date: Optional[datetime] = None, end_date: Optional[datetime] = None):
    """Calculate start and end dates based on period"""
    now = datetime.now(UTC)
    
    if period == ReportPeriod.WEEK:
        start = now - timedelta(days=now.weekday())
        start = start.replace(hour=0, minute=0, second=0, microsecond=0)
        end = start + timedelta(days=6, hours=23, minutes=59, seconds=59)
    elif period == ReportPeriod.MONTH:
        start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        if now.month == 12:
            end = now.replace(month=12, day=31, hour=23, minute=59, second=59)
        else:
            end = (now.replace(month=now.month + 1, day=1) - timedelta(days=1)).replace(hour=23, minute=59, second=59)
    elif period == ReportPeriod.YEAR:
        start = now.replace(month=1, day=1, hour=0, minute=0, second=0, microsecond=0)
        end = now.replace(month=12, day=31, hour=23, minute=59, second=59)
    else:  # CUSTOM
        if not start_date or not end_date:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Start date and end date are required for custom period"
            )
        # Ensure dates are in UTC
        if start_date.tzinfo is None:
            start = start_date.replace(tzinfo=UTC, hour=0, minute=0, second=0, microsecond=0)
        else:
            start = start_date.astimezone(UTC).replace(hour=0, minute=0, second=0, microsecond=0)
            
        if end_date.tzinfo is None:
            end = end_date.replace(tzinfo=UTC, hour=23, minute=59, second=59, microsecond=999999)
        else:
            end = end_date.astimezone(UTC).replace(hour=23, minute=59, second=59, microsecond=999999)
    
    return start, end


@router.post("/generate", response_model=FinancialReport)
async def generate_report(
    report_request: ReportRequest,
    current_user: dict = Depends(get_current_user)
):
    """Generate a financial report for the specified period"""
    try:
        start_date, end_date = calculate_report_dates(
            report_request.period,
            report_request.start_date,
            report_request.end_date
        )
        
        # Fetch all transactions in the period
        transactions = list(transactions_collection.find({
            "user_id": current_user["_id"],
            "date": {"$gte": start_date, "$lte": end_date}
        }))
        
        # Calculate metrics
        inflows = [t for t in transactions if t["type"] == "inflow"]
        outflows = [t for t in transactions if t["type"] == "outflow"]
        
        total_inflow = sum(t["amount"] for t in inflows)
        total_outflow = sum(t["amount"] for t in outflows)
        net_balance = total_inflow - total_outflow
        
        # Calculate category breakdowns for inflows
        inflow_categories = {}
        for t in inflows:
            cat = t["main_category"]
            if cat not in inflow_categories:
                inflow_categories[cat] = {"amount": 0, "count": 0}
            inflow_categories[cat]["amount"] += t["amount"]
            inflow_categories[cat]["count"] += 1
        
        inflow_by_category = [
            CategoryBreakdown(
                category=cat,
                amount=data["amount"],
                percentage=(data["amount"] / total_inflow * 100) if total_inflow > 0 else 0,
                transaction_count=data["count"]
            )
            for cat, data in inflow_categories.items()
        ]
        inflow_by_category.sort(key=lambda x: x.amount, reverse=True)
        
        # Calculate category breakdowns for outflows
        outflow_categories = {}
        for t in outflows:
            cat = t["main_category"]
            if cat not in outflow_categories:
                outflow_categories[cat] = {"amount": 0, "count": 0}
            outflow_categories[cat]["amount"] += t["amount"]
            outflow_categories[cat]["count"] += 1
        
        outflow_by_category = [
            CategoryBreakdown(
                category=cat,
                amount=data["amount"],
                percentage=(data["amount"] / total_outflow * 100) if total_outflow > 0 else 0,
                transaction_count=data["count"]
            )
            for cat, data in outflow_categories.items()
        ]
        outflow_by_category.sort(key=lambda x: x.amount, reverse=True)
        
        # Get goals data
        goals = list(goals_collection.find({"user_id": current_user["_id"]}))
        goals_progress = [
            GoalProgress(
                goal_id=g["_id"],
                name=g["name"],
                target_amount=g["target_amount"],
                current_amount=g["current_amount"],
                progress_percentage=(g["current_amount"] / g["target_amount"] * 100) if g["target_amount"] > 0 else 0,
                status=g["status"]
            )
            for g in goals
        ]
        
        total_allocated = sum(g["current_amount"] for g in goals)
        
        # Calculate daily averages
        days_in_period = (end_date - start_date).days + 1
        avg_daily_inflow = total_inflow / days_in_period if days_in_period > 0 else 0
        avg_daily_outflow = total_outflow / days_in_period if days_in_period > 0 else 0
        
        # Top categories
        top_income = inflow_by_category[0].category if inflow_by_category else None
        top_expense = outflow_by_category[0].category if outflow_by_category else None
        
        report = FinancialReport(
            period=report_request.period,
            start_date=start_date,
            end_date=end_date,
            total_inflow=total_inflow,
            total_outflow=total_outflow,
            net_balance=net_balance,
            inflow_by_category=inflow_by_category,
            outflow_by_category=outflow_by_category,
            goals=goals_progress,
            total_allocated_to_goals=total_allocated,
            total_transactions=len(transactions),
            inflow_count=len(inflows),
            outflow_count=len(outflows),
            top_income_category=top_income,
            top_expense_category=top_expense,
            average_daily_inflow=avg_daily_inflow,
            average_daily_outflow=avg_daily_outflow,
            generated_at=datetime.now(UTC)
        )
        
        return report
        
    except Exception as e:
        print(f"Error generating report: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to generate report: {str(e)}"
        )


@router.post("/download")
async def download_report_pdf(
    report_request: ReportRequest,
    current_user: dict = Depends(require_premium)
):
    """Generate and download a financial report as PDF"""
    try:
        # Generate the report data
        start_date, end_date = calculate_report_dates(
            report_request.period,
            report_request.start_date,
            report_request.end_date
        )
        
        # Fetch all transactions in the period
        transactions = list(transactions_collection.find({
            "user_id": current_user["_id"],
            "date": {"$gte": start_date, "$lte": end_date}
        }))
        
        # Calculate metrics (same as generate_report)
        inflows = [t for t in transactions if t["type"] == "inflow"]
        outflows = [t for t in transactions if t["type"] == "outflow"]
        
        total_inflow = sum(t["amount"] for t in inflows)
        total_outflow = sum(t["amount"] for t in outflows)
        net_balance = total_inflow - total_outflow
        
        # Calculate category breakdowns for inflows
        inflow_categories = {}
        for t in inflows:
            cat = t["main_category"]
            if cat not in inflow_categories:
                inflow_categories[cat] = {"amount": 0, "count": 0}
            inflow_categories[cat]["amount"] += t["amount"]
            inflow_categories[cat]["count"] += 1
        
        inflow_by_category = [
            CategoryBreakdown(
                category=cat,
                amount=data["amount"],
                percentage=(data["amount"] / total_inflow * 100) if total_inflow > 0 else 0,
                transaction_count=data["count"]
            )
            for cat, data in inflow_categories.items()
        ]
        inflow_by_category.sort(key=lambda x: x.amount, reverse=True)
        
        # Calculate category breakdowns for outflows
        outflow_categories = {}
        for t in outflows:
            cat = t["main_category"]
            if cat not in outflow_categories:
                outflow_categories[cat] = {"amount": 0, "count": 0}
            outflow_categories[cat]["amount"] += t["amount"]
            outflow_categories[cat]["count"] += 1
        
        outflow_by_category = [
            CategoryBreakdown(
                category=cat,
                amount=data["amount"],
                percentage=(data["amount"] / total_outflow * 100) if total_outflow > 0 else 0,
                transaction_count=data["count"]
            )
            for cat, data in outflow_categories.items()
        ]
        outflow_by_category.sort(key=lambda x: x.amount, reverse=True)
        
        # Get goals data
        goals = list(goals_collection.find({"user_id": current_user["_id"]}))
        goals_progress = [
            GoalProgress(
                goal_id=g["_id"],
                name=g["name"],
                target_amount=g["target_amount"],
                current_amount=g["current_amount"],
                progress_percentage=(g["current_amount"] / g["target_amount"] * 100) if g["target_amount"] > 0 else 0,
                status=g["status"]
            )
            for g in goals
        ]
        
        total_allocated = sum(g["current_amount"] for g in goals)
        
        # Calculate daily averages
        days_in_period = (end_date - start_date).days + 1
        avg_daily_inflow = total_inflow / days_in_period if days_in_period > 0 else 0
        avg_daily_outflow = total_outflow / days_in_period if days_in_period > 0 else 0
        
        # Top categories
        top_income = inflow_by_category[0].category if inflow_by_category else None
        top_expense = outflow_by_category[0].category if outflow_by_category else None
        
        report = FinancialReport(
            period=report_request.period,
            start_date=start_date,
            end_date=end_date,
            total_inflow=total_inflow,
            total_outflow=total_outflow,
            net_balance=net_balance,
            inflow_by_category=inflow_by_category,
            outflow_by_category=outflow_by_category,
            goals=goals_progress,
            total_allocated_to_goals=total_allocated,
            total_transactions=len(transactions),
            inflow_count=len(inflows),
            outflow_count=len(outflows),
            top_income_category=top_income,
            top_expense_category=top_expense,
            average_daily_inflow=avg_daily_inflow,
            average_daily_outflow=avg_daily_outflow,
            generated_at=datetime.now(UTC)
        )
        
        # Generate PDF with user's timezone offset (if provided)
        user_timezone_offset = report_request.timezone_offset if hasattr(report_request, 'timezone_offset') and report_request.timezone_offset is not None else 0
        pdf_buffer = generate_financial_report_pdf(report, current_user["name"], user_timezone_offset)
        
        # Create filename
        period_name = report_request.period.value
        filename = f"financial_report_{period_name}_{start_date.strftime('%Y%m%d')}_{end_date.strftime('%Y%m%d')}.pdf"
        
        return StreamingResponse(
            pdf_buffer,
            media_type="application/pdf",
            headers={"Content-Disposition": f"attachment; filename={filename}"}
        )
        
    except Exception as e:
        print(f"Error generating PDF: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to generate PDF: {str(e)}"
        )