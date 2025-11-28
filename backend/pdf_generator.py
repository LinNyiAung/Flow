# pdf_generator.py
from reportlab.lib import colors
from reportlab.lib.pagesizes import letter, A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import inch
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer, PageBreak
from reportlab.platypus import Image as RLImage
from reportlab.lib.enums import TA_CENTER, TA_RIGHT, TA_LEFT
from datetime import datetime, UTC, timezone, timedelta
from io import BytesIO
from models import Currency
from report_models import FinancialReport

def generate_financial_report_pdf(report: FinancialReport, user_name: str, user_timezone_offset: int = 0, currency: Currency = None) -> BytesIO:
    """
    Generate a PDF financial report with currency support
    
    Args:
        report: The financial report data
        user_name: Name of the user
        user_timezone_offset: Timezone offset in minutes from UTC
        currency: Currency for formatting (from models.Currency enum)
    """
    buffer = BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=letter, topMargin=0.5*inch, bottomMargin=0.5*inch)
    
    # Determine currency symbol
    if currency is None:
        currency = report.currency if hasattr(report, 'currency') else Currency.USD
    
    currency_symbol = "$" if currency == Currency.USD else "K"
    currency_name = "USD" if currency == Currency.USD else "MMK"
    
    # Convert UTC times to user's local time
    user_tz = timezone(timedelta(minutes=user_timezone_offset))
    local_generated_at = report.generated_at.astimezone(user_tz)
    current_local_time = datetime.now(UTC).astimezone(user_tz)
    
    # Format timezone offset for display (e.g., UTC+8, UTC-5)
    offset_hours = user_timezone_offset / 60
    if offset_hours >= 0:
        tz_display = f"UTC+{int(offset_hours)}" if offset_hours == int(offset_hours) else f"UTC+{offset_hours:.1f}"
    else:
        tz_display = f"UTC{int(offset_hours)}" if offset_hours == int(offset_hours) else f"UTC{offset_hours:.1f}"
    
    # Container for the 'Flowable' objects
    elements = []
    
    # Define styles
    styles = getSampleStyleSheet()
    title_style = ParagraphStyle(
        'CustomTitle',
        parent=styles['Heading1'],
        fontSize=24,
        textColor=colors.HexColor('#667eea'),
        spaceAfter=30,
        alignment=TA_CENTER,
        fontName='Helvetica-Bold'
    )
    
    heading_style = ParagraphStyle(
        'CustomHeading',
        parent=styles['Heading2'],
        fontSize=16,
        textColor=colors.HexColor('#333333'),
        spaceAfter=12,
        spaceBefore=20,
        fontName='Helvetica-Bold'
    )
    
    subheading_style = ParagraphStyle(
        'CustomSubHeading',
        parent=styles['Heading3'],
        fontSize=12,
        textColor=colors.HexColor('#666666'),
        spaceAfter=10,
        fontName='Helvetica-Bold'
    )
    
    normal_style = ParagraphStyle(
        'CustomNormal',
        parent=styles['Normal'],
        fontSize=10,
        textColor=colors.HexColor('#333333'),
    )
    
    # Title
    title = Paragraph("Financial Report", title_style)
    elements.append(title)
    
    # Report Info
    period_map = {
        "week": "Weekly Report",
        "month": "Monthly Report",
        "year": "Yearly Report",
        "custom": "Custom Period Report"
    }
    
    info_text = f"""
    <b>Generated For:</b> {user_name}<br/>
    <b>Report Type:</b> {period_map.get(report.period, 'Report')}<br/>
    <b>Period:</b> {report.start_date.strftime('%B %d, %Y')} - {report.end_date.strftime('%B %d, %Y')}<br/>
    <b>Generated On:</b> {local_generated_at.strftime('%B %d, %Y %I:%M %p')} ({tz_display})
    """
    info = Paragraph(info_text, normal_style)
    elements.append(info)
    elements.append(Spacer(1, 0.3*inch))
    
    # Summary Section
    summary_heading = Paragraph("Financial Summary", heading_style)
    elements.append(summary_heading)
    
    summary_data = [
        ['Metric', 'Amount'],
        ['Total Income', f"{currency_symbol}{report.total_inflow:,.2f} ({currency_name})"],
        ['Total Expenses', f"{currency_symbol}{report.total_outflow:,.2f} ({currency_name})"],
        ['Net Balance', f"{currency_symbol}{report.net_balance:,.2f} ({currency_name})"],
        ['Allocated to Goals', f"{currency_symbol}{report.total_allocated_to_goals:,.2f} ({currency_name})"],
        ['Total Transactions', str(report.total_transactions)],
    ]
    
    summary_table = Table(summary_data, colWidths=[3*inch, 2*inch])
    summary_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#667eea')),
        ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
        ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
        ('ALIGN', (1, 0), (1, -1), 'RIGHT'),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, 0), 12),
        ('BOTTOMPADDING', (0, 0), (-1, 0), 12),
        ('BACKGROUND', (0, 1), (-1, -1), colors.beige),
        ('GRID', (0, 0), (-1, -1), 1, colors.grey),
        ('FONTNAME', (0, 1), (-1, -1), 'Helvetica'),
        ('FONTSIZE', (0, 1), (-1, -1), 10),
        ('TOPPADDING', (0, 1), (-1, -1), 8),
        ('BOTTOMPADDING', (0, 1), (-1, -1), 8),
    ]))
    elements.append(summary_table)
    elements.append(Spacer(1, 0.3*inch))
    
    # Daily Averages
    avg_heading = Paragraph("Daily Averages", subheading_style)
    elements.append(avg_heading)
    
    avg_data = [
        ['Average Daily Income', f"{currency_symbol}{report.average_daily_inflow:,.2f}"],
        ['Average Daily Expenses', f"{currency_symbol}{report.average_daily_outflow:,.2f}"],
    ]
    
    avg_table = Table(avg_data, colWidths=[3*inch, 2*inch])
    avg_table.setStyle(TableStyle([
        ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
        ('ALIGN', (1, 0), (1, -1), 'RIGHT'),
        ('FONTNAME', (0, 0), (-1, -1), 'Helvetica'),
        ('FONTSIZE', (0, 0), (-1, -1), 10),
        ('TOPPADDING', (0, 0), (-1, -1), 6),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 6),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.grey),
    ]))
    elements.append(avg_table)
    elements.append(Spacer(1, 0.3*inch))
    
    # Income Breakdown
    if report.inflow_by_category:
        income_heading = Paragraph("Income Breakdown by Category", heading_style)
        elements.append(income_heading)
        
        income_data = [['Category', 'Amount', 'Percentage', 'Transactions']]
        for cat in report.inflow_by_category[:10]:  # Top 10
            income_data.append([
                cat.category,
                f"{currency_symbol}{cat.amount:,.2f}",
                f"{cat.percentage:.1f}%",
                str(cat.transaction_count)
            ])
        
        income_table = Table(income_data, colWidths=[2*inch, 1.5*inch, 1*inch, 1*inch])
        income_table.setStyle(TableStyle([
            ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#4CAF50')),
            ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
            ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
            ('ALIGN', (1, 0), (-1, -1), 'RIGHT'),
            ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
            ('FONTSIZE', (0, 0), (-1, 0), 11),
            ('BOTTOMPADDING', (0, 0), (-1, 0), 12),
            ('BACKGROUND', (0, 1), (-1, -1), colors.lightgreen),
            ('GRID', (0, 0), (-1, -1), 1, colors.grey),
            ('FONTNAME', (0, 1), (-1, -1), 'Helvetica'),
            ('FONTSIZE', (0, 1), (-1, -1), 9),
            ('TOPPADDING', (0, 1), (-1, -1), 6),
            ('BOTTOMPADDING', (0, 1), (-1, -1), 6),
        ]))
        elements.append(income_table)
        elements.append(Spacer(1, 0.3*inch))
    
    # Expense Breakdown
    if report.outflow_by_category:
        expense_heading = Paragraph("Expense Breakdown by Category", heading_style)
        elements.append(expense_heading)
        
        expense_data = [['Category', 'Amount', 'Percentage', 'Transactions']]
        for cat in report.outflow_by_category[:10]:  # Top 10
            expense_data.append([
                cat.category,
                f"{currency_symbol}{cat.amount:,.2f}",
                f"{cat.percentage:.1f}%",
                str(cat.transaction_count)
            ])
        
        expense_table = Table(expense_data, colWidths=[2*inch, 1.5*inch, 1*inch, 1*inch])
        expense_table.setStyle(TableStyle([
            ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#FF5722')),
            ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
            ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
            ('ALIGN', (1, 0), (-1, -1), 'RIGHT'),
            ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
            ('FONTSIZE', (0, 0), (-1, 0), 11),
            ('BOTTOMPADDING', (0, 0), (-1, 0), 12),
            ('BACKGROUND', (0, 1), (-1, -1), colors.HexColor('#FFE0DB')),
            ('GRID', (0, 0), (-1, -1), 1, colors.grey),
            ('FONTNAME', (0, 1), (-1, -1), 'Helvetica'),
            ('FONTSIZE', (0, 1), (-1, -1), 9),
            ('TOPPADDING', (0, 1), (-1, -1), 6),
            ('BOTTOMPADDING', (0, 1), (-1, -1), 6),
        ]))
        elements.append(expense_table)
        elements.append(Spacer(1, 0.3*inch))
    
    # Goals Progress
    if report.goals:
        goals_heading = Paragraph("Financial Goals Progress", heading_style)
        elements.append(goals_heading)
        
        goals_data = [['Goal', 'Target', 'Current', 'Progress', 'Status']]
        for goal in report.goals:
            goals_data.append([
                goal.name,
                f"{currency_symbol}{goal.target_amount:,.2f}",
                f"{currency_symbol}{goal.current_amount:,.2f}",
                f"{goal.progress_percentage:.1f}%",
                goal.status.upper()
            ])
        
        goals_table = Table(goals_data, colWidths=[1.8*inch, 1.2*inch, 1.2*inch, 0.8*inch, 1*inch])
        goals_table.setStyle(TableStyle([
            ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#667eea')),
            ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
            ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
            ('ALIGN', (1, 0), (-1, -1), 'RIGHT'),
            ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
            ('FONTSIZE', (0, 0), (-1, 0), 10),
            ('BOTTOMPADDING', (0, 0), (-1, 0), 12),
            ('BACKGROUND', (0, 1), (-1, -1), colors.HexColor('#E8EAF6')),
            ('GRID', (0, 0), (-1, -1), 1, colors.grey),
            ('FONTNAME', (0, 1), (-1, -1), 'Helvetica'),
            ('FONTSIZE', (0, 1), (-1, -1), 9),
            ('TOPPADDING', (0, 1), (-1, -1), 6),
            ('BOTTOMPADDING', (0, 1), (-1, -1), 6),
        ]))
        elements.append(goals_table)
    
    # Footer - Now uses user's local time
    elements.append(Spacer(1, 0.5*inch))
    footer_text = f"<i>Report generated by Flow Finance on {current_local_time.strftime('%B %d, %Y at %I:%M %p')} ({tz_display})</i>"
    footer = Paragraph(footer_text, ParagraphStyle('Footer', parent=styles['Normal'], fontSize=8, textColor=colors.grey, alignment=TA_CENTER))
    elements.append(footer)
    
    # Build PDF
    doc.build(elements)
    buffer.seek(0)
    return buffer