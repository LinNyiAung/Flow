from pymongo import MongoClient
from config import settings

client = MongoClient(settings.MONGODB_URL)
database = client[settings.DATABASE_NAME]

def get_database():
    return database

# Collections
users_collection = database.users
transactions_collection = database.transactions
categories_collection = database.categories
chat_sessions_collection = database.chat_sessions
goals_collection = database.goals 
insights_collection = database.insights
budgets_collection = database.budgets
notifications_collection = database.notifications
notification_preferences_collection = database.notification_preferences

# Admin collections
admins_collection = database.admins
admin_action_logs_collection = database.admin_action_logs

# Initialize default categories if they don't exist
def initialize_categories():
    if categories_collection.count_documents({}) == 0:
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
                    "Crypto Gains", "Rental Income"                ]
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
                    "Coffee & Snacks", "Alcohol"                ]
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

        categories_collection.insert_many(default_categories)
        
        
        
def initialize_notification_preferences():
    """Initialize default notification preferences for users who don't have them"""
    # This will be called when a user first accesses notification settings
    pass


def initialize_admin():
    """Initialize default super admin if none exists"""
    if admins_collection.count_documents({}) == 0:
        from admin_utils import get_password_hash
        import uuid
        from datetime import datetime, UTC
        
        # Create default super admin
        default_admin = {
            "_id": str(uuid.uuid4()),
            "name": "Super Admin",
            "email": "admin@flowfinance.com",
            "password": get_password_hash("admin123"),  # Change this in production!
            "role": "super_admin",
            "created_at": datetime.now(UTC),
            "last_login": None
        }
        
        admins_collection.insert_one(default_admin)
        print("✅ Default super admin created (email: admin@flowfinance.com, password: admin123)")


# Call this when the app starts
initialize_categories()
initialize_notification_preferences()
initialize_admin()