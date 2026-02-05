import uuid
from datetime import datetime, timedelta, UTC, timezone
from typing import List, Optional
from recurrence_models import RecurrenceConfig, RecurrenceFrequency
from database import transactions_collection
from notification_service import create_notification

def calculate_next_occurrence(
    last_date: datetime,
    config: RecurrenceConfig
) -> Optional[datetime]:
    """Calculate the next occurrence date based on recurrence config"""
    
    # Ensure last_date is timezone-aware
    if last_date.tzinfo is None:
        last_date = last_date.replace(tzinfo=UTC)
    
    # Ensure end_date is timezone-aware if it exists
    end_date = config.end_date
    if end_date and end_date.tzinfo is None:
        end_date = end_date.replace(tzinfo=UTC)
    
    if end_date and last_date >= end_date:
        return None  # Recurrence has ended
    
    next_date = None
    
    if config.frequency == RecurrenceFrequency.DAILY:
        next_date = last_date + timedelta(days=1)
    
    elif config.frequency == RecurrenceFrequency.WEEKLY:
        if config.day_of_week is None:
            return None
        # Find next occurrence of the specified day of week
        days_ahead = config.day_of_week - last_date.weekday()
        if days_ahead <= 0:  # Target day already happened this week
            days_ahead += 7
        next_date = last_date + timedelta(days=days_ahead)
    
    elif config.frequency == RecurrenceFrequency.MONTHLY:
        if config.day_of_month is None:
            return None
        # Move to next month
        if last_date.month == 12:
            next_month = last_date.replace(year=last_date.year + 1, month=1)
        else:
            next_month = last_date.replace(month=last_date.month + 1)
        
        # Handle day overflow (e.g., Jan 31 -> Feb 28)
        try:
            next_date = next_month.replace(day=config.day_of_month)
        except ValueError:
            # Day doesn't exist in that month, use last day of month
            if next_month.month == 12:
                next_date = next_month.replace(month=12, day=31)
            else:
                next_date = (next_month.replace(month=next_month.month + 1, day=1) - timedelta(days=1))
    
    elif config.frequency == RecurrenceFrequency.ANNUALLY:
        if config.month is None or config.day_of_year is None:
            return None
        # Move to next year
        try:
            next_date = last_date.replace(
                year=last_date.year + 1,
                month=config.month,
                day=config.day_of_year
            )
        except ValueError:
            # Handle Feb 29 on non-leap years
            next_date = last_date.replace(
                year=last_date.year + 1,
                month=config.month,
                day=28
            )
    
    # Ensure next_date is timezone-aware
    if next_date and next_date.tzinfo is None:
        next_date = next_date.replace(tzinfo=UTC)
    
    # Check if next_date exceeds end_date
    if next_date and end_date and next_date > end_date:
        return None
    
    return next_date

def check_and_create_recurring_transactions():
    """Check all recurring transactions and create new ones if needed"""
    now = datetime.now(UTC)
    
    # Find all transactions with recurrence enabled
    recurring_transactions = transactions_collection.find({
        "recurrence.enabled": True
    })
    
    created_count = 0
    
    for transaction in recurring_transactions:
        recurrence = transaction.get("recurrence", {})
        config_data = recurrence.get("config")
        
        if not config_data:
            continue
        
        # Parse config
        config = RecurrenceConfig(**config_data)
        
        # ENSURE END_DATE IS TIMEZONE-AWARE
        if config.end_date and config.end_date.tzinfo is None:
            config.end_date = config.end_date.replace(tzinfo=UTC)
        
        last_created = recurrence.get("last_created_date", transaction["date"])
        
        # Ensure timezone-aware
        if last_created.tzinfo is None:
            last_created = last_created.replace(tzinfo=UTC)
        
        # Calculate next occurrence
        next_occurrence = calculate_next_occurrence(last_created, config)
        
        if not next_occurrence:
            # Recurrence has ended, disable it
            transactions_collection.update_one(
                {"_id": transaction["_id"]},
                {"$set": {"recurrence.enabled": False}}
            )
            
            # Notify user
            create_notification(
                user_id=transaction["user_id"],
                notification_type="recurring_transaction_ended",
                title="Recurring Transaction Ended 🏁",
                message=f"Your recurring transaction '{transaction.get('description', transaction['sub_category'])}' has reached its end date.",
                goal_id=transaction["_id"],
                goal_name=transaction.get("description", transaction["sub_category"])
            )
            continue
        
        # Check if we should create the next transaction
        if next_occurrence <= now:
            # Create new transaction
            new_transaction_id = str(uuid.uuid4())
            new_transaction = {
                "_id": new_transaction_id,
                "user_id": transaction["user_id"],
                "type": transaction["type"],
                "main_category": transaction["main_category"],
                "sub_category": transaction["sub_category"],
                "date": next_occurrence,
                "description": transaction.get("description"),
                "amount": transaction["amount"],
                "currency": transaction.get("currency", "usd"),  # ADDED - preserve currency from parent
                "created_at": now,
                "updated_at": now,
                "recurrence": {
                    "enabled": False,  # Auto-created transactions don't recurse
                    "config": None,
                    "last_created_date": None,
                    "parent_transaction_id": transaction["_id"]
                }
            }
            
            transactions_collection.insert_one(new_transaction)
            
            # Update parent transaction's last_created_date
            transactions_collection.update_one(
                {"_id": transaction["_id"]},
                {"$set": {"recurrence.last_created_date": next_occurrence}}
            )
            
            created_count += 1
            
            # Get currency symbol for notification
            currency_symbol = "$" if transaction.get("currency", "usd") else ("K" if transaction.get("currency", "mmk") else "฿")
            
            # Notify user
            create_notification(
                user_id=transaction["user_id"],
                notification_type="recurring_transaction_created",
                title="Recurring Transaction Created 🔄",
                message=f"Your recurring {transaction['type']} of {currency_symbol}{transaction['amount']:.2f} for '{transaction.get('description', transaction['sub_category'])}' has been automatically created.",
                goal_id=new_transaction_id,
                goal_name=transaction.get("description", transaction["sub_category"])
            )
    
    if created_count > 0:
        print(f"✅ Created {created_count} recurring transactions")
    
    return created_count


def disable_recurrence_for_transaction(transaction_id: str, user_id: str) -> bool:
    """Disable recurrence for a specific transaction"""
    result = transactions_collection.update_one(
        {"_id": transaction_id, "user_id": user_id},
        {"$set": {"recurrence.enabled": False}}
    )
    return result.modified_count > 0


def disable_recurrence_for_parent(parent_transaction_id: str, user_id: str) -> bool:
    """Disable recurrence for a parent transaction (when editing an auto-created one)"""
    result = transactions_collection.update_one(
        {"_id": parent_transaction_id, "user_id": user_id},
        {"$set": {"recurrence.enabled": False}}
    )
    
    if result.modified_count > 0:
        # Notify user
        parent_tx = transactions_collection.find_one({"_id": parent_transaction_id})
        if parent_tx:
            create_notification(
                user_id=user_id,
                notification_type="recurring_transaction_disabled",
                title="Recurring Transaction Stopped 🛑",
                message=f"Automatic creation has been stopped for '{parent_tx.get('description', parent_tx['sub_category'])}'.",
                goal_id=parent_transaction_id,
                goal_name=parent_tx.get("description", parent_tx["sub_category"])
            )
    
    return result.modified_count > 0


def get_recurring_transaction_preview(
    last_date: datetime,
    config: RecurrenceConfig,
    count: int = 5
) -> List[datetime]:
    """Preview the next N occurrences of a recurring transaction"""
    occurrences = []
    current_date = last_date
    
    for _ in range(count):
        next_date = calculate_next_occurrence(current_date, config)
        if not next_date:
            break
        occurrences.append(next_date)
        current_date = next_date
    
    return occurrences