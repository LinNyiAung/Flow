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
            {"_id":"inflow","categories":[{"main_category":"Income","sub_categories":["Salary","Freelance","Business","Investment Returns","Bonus","Other"]},{"main_category":"Refunds","sub_categories":["Tax Refund","Purchase Refund","Insurance Claim","Other"]},{"main_category":"Gifts","sub_categories":["Birthday","Holiday","Wedding","Other"]}]},
            {"_id":"outflow","categories":[{"main_category":"Food & Dining","sub_categories":["Restaurants","Groceries","Fast Food","Coffee & Tea","Alcohol & Bars"]},{"main_category":"Transportation","sub_categories":["Gas & Fuel","Parking","Public Transport","Taxi & Uber","Car Maintenance"]},{"main_category":"Shopping","sub_categories":["Clothing","Electronics","Books","Home & Garden","Sports & Recreation"]},{"main_category":"Entertainment","sub_categories":["Movies & Theater","Music","Games","Hobbies","Sports Events"]},{"main_category":"Bills & Utilities","sub_categories":["Phone","Internet","Electricity","Water","Gas","Cable TV"]},{"main_category":"Health & Fitness","sub_categories":["Doctor","Dentist","Pharmacy","Gym","Health Insurance"]},{"main_category":"Travel","sub_categories":["Flights","Hotels","Car Rental","Travel Insurance","Activities"]},{"main_category":"Education","sub_categories":["Tuition","Books","Courses","Training","School Supplies"]},{"main_category":"Personal Care","sub_categories":["Haircut","Cosmetics","Clothing","Spa & Massage"]},{"main_category":"Gifts & Donations","sub_categories":["Gifts","Charity","Religious Donations"]},{"main_category":"Financial","sub_categories":["Bank Fees","Interest","Insurance","Taxes","Investments"]},{"main_category":"Other","sub_categories":["Miscellaneous","Cash Withdrawal","Other"]}]}
        ]
        categories_collection.insert_many(default_categories)

# Call this when the app starts
initialize_categories()