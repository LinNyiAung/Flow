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

# Initialize default categories if they don't exist
def initialize_categories():
    if categories_collection.count_documents({}) == 0:
        default_categories = [
            {
                "_id": "inflow",
                "categories": [
                    {"main_category": "Salary & Wages", "sub_categories": ["Primary Job", "Part-time Job", "Freelance", "Overtime", "Bonus", "Commission"]},
                    {"main_category": "Business Income", "sub_categories": ["Sales Revenue", "Service Income", "Consulting", "Rental Income", "Royalties"]},
                    {"main_category": "Investment Returns", "sub_categories": ["Dividends", "Interest", "Capital Gains", "Crypto Gains", "Stock Returns"]},
                    {"main_category": "Refunds & Returns", "sub_categories": ["Tax Refund", "Purchase Refund", "Insurance Claim", "Cashback", "Rebates"]},
                    {"main_category": "Gifts & Transfers", "sub_categories": ["Family Gift", "Birthday Money", "Holiday Gift", "Inheritance", "Transfers In"]},
                    {"main_category": "Other Inflows", "sub_categories": ["Contest Winnings", "Found Money", "Loan Received", "Government Benefits", "Other"]}
                ]
            },
            {
                "_id": "outflow",
                "categories": [
                    {"main_category": "Food & Dining", "sub_categories": ["Restaurants", "Groceries", "Fast Food", "Coffee & Tea", "Alcohol & Bars", "Delivery"]},
                    {"main_category": "Transportation", "sub_categories": ["Gas & Fuel", "Parking", "Public Transport", "Taxi & Rideshare", "Car Maintenance", "Car Insurance"]},
                    {"main_category": "Shopping", "sub_categories": ["Clothing", "Electronics", "Books", "Home & Garden", "Sports & Recreation", "Online Shopping"]},
                    {"main_category": "Entertainment", "sub_categories": ["Movies & Theater", "Music", "Games", "Hobbies", "Sports Events", "Streaming Services"]},
                    {"main_category": "Bills & Utilities", "sub_categories": ["Electricity", "Water", "Gas", "Internet", "Phone", "Cable TV", "Trash"]},
                    {"main_category": "Housing", "sub_categories": ["Rent", "Mortgage", "Property Tax", "Home Insurance", "Maintenance", "HOA Fees"]},
                    {"main_category": "Healthcare", "sub_categories": ["Doctor Visits", "Dentist", "Pharmacy", "Health Insurance", "Medical Procedures", "Therapy"]},
                    {"main_category": "Travel", "sub_categories": ["Flights", "Hotels", "Car Rental", "Travel Insurance", "Activities", "Meals While Traveling"]},
                    {"main_category": "Education", "sub_categories": ["Tuition", "Books", "Online Courses", "Training", "School Supplies", "Certification"]},
                    {"main_category": "Personal Care", "sub_categories": ["Haircut", "Cosmetics", "Skincare", "Spa & Massage", "Gym Membership", "Personal Items"]},
                    {"main_category": "Financial", "sub_categories": ["Bank Fees", "Investment Fees", "Insurance Premiums", "Taxes", "Interest Payments", "Loan Payments"]},
                    {"main_category": "Gifts & Donations", "sub_categories": ["Family Gifts", "Friend Gifts", "Charity", "Religious Donations", "Tips"]},
                    {"main_category": "Business Expenses", "sub_categories": ["Office Supplies", "Software", "Marketing", "Travel Expenses", "Professional Services"]},
                    {"main_category": "Other Outflows", "sub_categories": ["Cash Withdrawal", "Fines & Penalties", "Emergency Expenses", "Miscellaneous", "Other"]}
                ]
            }
        ]
        categories_collection.insert_many(default_categories)

# Call this when the app starts
initialize_categories()