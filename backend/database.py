from motor.motor_asyncio import AsyncIOMotorClient
from pymongo import ASCENDING
from config import settings
import uuid
from datetime import datetime, UTC

# Initialize Async Client
client = AsyncIOMotorClient(settings.MONGODB_URL, tz_aware=True)
database = client[settings.DATABASE_NAME]

def get_database():
    return database

# ==================== COLLECTIONS ====================
budgets_collection = database.budgets

# Admin collections


# ==================== INITIALIZATION FUNCTIONS ====================

async def initialize_categories():
    """Initialize default categories if they don't exist"""
    from sql.categories import seed_default_categories
    default_categories = [
        {
            "_id": "inflow",
            "categories": [
                {
                    "main_category": "Employment Income",
                    "sub_categories": [
                        "Salary", "Overtime Pay", "Bonus", "Commission", "Allowances", "Pension"
                    ]
                },
                {
                    "main_category": "Self-Employment & Business",
                    "sub_categories": [
                        "Freelance Income", "Business Income", 
                        "Side Hustle", "Royalties"
                    ]
                },
                {
                    "main_category": "Investment Income",
                    "sub_categories": [
                        "Dividends", "Interest Income", "Capital Gains",
                        "Crypto Gains", "Rental Income"
                    ]
                },
                {
                    "main_category": "Gifts & Support",
                    "sub_categories": [
                        "Gifts Received", "Family Support",
                        "Wedding / Events", "Inheritance"
                    ]
                },
                {
                    "main_category": "Refunds & Reimbursements",
                    "sub_categories": [
                        "Tax Refund", "Expense Reimbursement",
                        "Purchase Refund", "Insurance Claim", "Cashback / Rewards"
                    ]
                },
                {
                    "main_category": "Other Income",
                    "sub_categories": [
                        "Asset Sale", "Prize / Lottery",
                        "Other Income"
                    ]
                }
            ]
        },
        {
            "_id": "outflow",
            "categories": [
                {
                    "main_category": "Food & Daily Living",
                    "sub_categories": [
                        "Groceries", "Restaurants", "Fast Food",
                        "Coffee & Snacks", "Alcohol"
                    ]
                },
                {
                    "main_category": "Housing & Utilities",
                    "sub_categories": [
                        "Rent", "Mortgage", "Electricity", "Water",
                        "Gas", "Internet", "Mobile Phone", "Home Maintenance"
                    ]
                },
                {
                    "main_category": "Transportation",
                    "sub_categories": [
                        "Fuel", "Public Transport", "Taxi",
                        "Vehicle Maintenance", "Vehicle Insurance",
                        "Parking", "Toll Fees"
                    ]
                },
                {
                    "main_category": "Shopping & Lifestyle",
                    "sub_categories": [
                        "Clothing", "Footwear", "Accessories",
                        "Electronics", "Home Supplies", "Furniture"
                    ]
                },
                {
                    "main_category": "Entertainment & Leisure",
                    "sub_categories": [
                        "Movies & Streaming", "Games", "Music",
                        "Events & Concerts", "Hobbies", "Subscriptions"
                    ]
                },
                {
                    "main_category": "Health & Insurance",
                    "sub_categories": [
                        "Doctor Visits", "Dental", "Pharmacy",
                        "Health Insurance", "Mental Health", "Fitness & Gym"
                    ]
                },
                {
                    "main_category": "Education & Self-Improvement",
                    "sub_categories": [
                        "Tuition Fees", "Online Courses", "Books",
                        "Professional Development", "Workshops", "Learning Subscriptions"
                    ]
                },
                {
                    "main_category": "Travel & Vacation",
                    "sub_categories": [
                        "Flights", "Accommodation", "Transport (Travel)",
                        "Food (Travel)", "Activities", "Travel Insurance"
                    ]
                },
                {
                    "main_category": "Financial Expenses",
                    "sub_categories": [
                        "Bank Fees", "Loan Repayment",
                        "Credit Card Payment", "Interest Paid",
                        "Taxes", "Investment Fees"
                    ]
                },
                {
                    "main_category": "Business Expenses",
                    "sub_categories": [
                        "Software & Tools", "Marketing & Ads",
                        "Office Supplies", "Hosting & Domains",
                        "Business Travel", "Contractor Payments"
                    ]
                },
                {
                    "main_category": "Other & Adjustments",
                    "sub_categories": [
                        "Cash Withdrawal", "Currency Exchange Loss",
                        "Correction / Adjustment", "Miscellaneous", "Emergency Expenses", "Other Expenses"
                    ]
                }
            ]
        }
    ]
    if await seed_default_categories(default_categories):
        print("✅ Default categories initialized")


async def create_db_indexes():
    """Create indexes - Must be async now"""
    try:
        await budgets_collection.create_index(
            [("user_id", ASCENDING), ("parent_budget_id", ASCENDING), ("start_date", ASCENDING)],
            unique=True,
            background=True,
            partialFilterExpression={
                "parent_budget_id": {"$type": "string"} 
            }
        )

        # Child lookups ("does budget X already have a next-period budget?") for the nightly
        # rollover job and auto-create. Deliberately NOT partial: the planner can't prove
        # that {"parent_budget_id": "<id>"} satisfies a {"$type": "string"} partial filter,
        # so the partial unique index above is never used for these queries.
        try:
            await budgets_collection.create_index(
                [("parent_budget_id", ASCENDING)],
                name="parent_budget_id_lookup",
                background=True,
            )
            # Nightly rollover candidates: auto-create budgets whose period ended.
            await budgets_collection.create_index(
                [("auto_create_enabled", ASCENDING), ("end_date", ASCENDING)],
                name="rollover_candidates",
                background=True,
                partialFilterExpression={"auto_create_enabled": True},
            )
        except Exception as e:
            print(f"⚠️ Could not create budget rollover indexes: {e}")

        # (Transaction indexes: PostgreSQL ix_transactions_*; case-insensitive unique e-mails:
        # PostgreSQL index uq_users_lower_email.)

        print("✅ Database indexes verified/created")
    except Exception as e:
        print(f"⚠️ Failed to create indexes: {e}")


async def initialize_notification_preferences():
    """Initialize default notification preferences for users who don't have them"""
    pass


async def initialize_admin():
    """
    Bootstrap a super admin ONLY when the admins collection is empty AND both
    ADMIN_BOOTSTRAP_EMAIL and ADMIN_BOOTSTRAP_PASSWORD are set in the environment.
    No hard-coded default credentials are ever created.
    """
    import asyncio
    from admin_utils import get_password_hash, initial_admin_password_version, verify_password

    from sql import admins as admins_db

    if await admins_db.count_admins() == 0:
        bootstrap_email = (settings.ADMIN_BOOTSTRAP_EMAIL or "").strip().lower()
        bootstrap_password = settings.ADMIN_BOOTSTRAP_PASSWORD or ""

        if not bootstrap_email or not bootstrap_password:
            print(
                "⚠️  No admin accounts exist. Set ADMIN_BOOTSTRAP_EMAIL and "
                "ADMIN_BOOTSTRAP_PASSWORD and restart to bootstrap a super admin."
            )
            return

        if len(bootstrap_password) < 8:
            print("⚠️  ADMIN_BOOTSTRAP_PASSWORD must be at least 8 characters; super admin NOT created.")
            return

        bootstrap_admin = {
            "_id": str(uuid.uuid4()),
            "name": settings.ADMIN_BOOTSTRAP_NAME or "Super Admin",
            "email": bootstrap_email,
            "password": await asyncio.to_thread(get_password_hash, bootstrap_password),
            "role": "super_admin",
            "password_version": initial_admin_password_version(),
            "created_at": datetime.now(UTC),
            "last_login": None
        }

        await admins_db.insert_admin(bootstrap_admin)
        print(f"✅ Bootstrap super admin created for {bootstrap_email}. "
              "Remove ADMIN_BOOTSTRAP_PASSWORD from the environment now.")
        return

    # Warn loudly if the legacy hard-coded default admin still exists with its default password.
    legacy = await admins_db.get_admin_by_email("admin@toepwar.com")
    if legacy and legacy.get("password"):
        try:
            if await asyncio.to_thread(verify_password, "admin123", legacy["password"]):
                print("🚨 SECURITY WARNING: admin@toepwar.com still uses the default password. "
                      "Change it or delete this admin immediately.")
        except Exception:
            pass