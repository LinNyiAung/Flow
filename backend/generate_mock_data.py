import requests
import random
from datetime import datetime, timedelta, UTC
import json

# Configuration
API_BASE_URL = "http://10.80.21.130:8000"
ACCESS_TOKEN = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ0ZXN0QGdtYWlsLmNvbSIsImV4cCI6MTc2MzM3NTExMX0.NxTxkbU3Y09h6J8ALSaeN3IOpRCp-sTvKTZpzFoNAJ0"  # Replace with your actual token

# Realistic transaction templates matching your database.py categories
MOCK_TRANSACTIONS = {
    "inflow": [
        {"main": "Income", "sub": "Salary", "amount_range": (3000, 5000), "description": "Monthly salary deposit"},
        {"main": "Income", "sub": "Bonus", "amount_range": (500, 2000), "description": "Performance bonus"},
        {"main": "Income", "sub": "Freelance", "amount_range": (200, 1500), "description": "Freelance project payment"},
        {"main": "Income", "sub": "Business", "amount_range": (300, 2000), "description": "Business income"},
        {"main": "Income", "sub": "Investment Returns", "amount_range": (50, 500), "description": "Investment returns"},
        {"main": "Refunds", "sub": "Purchase Refund", "amount_range": (20, 200), "description": "Product return refund"},
        {"main": "Refunds", "sub": "Tax Refund", "amount_range": (500, 2000), "description": "Tax refund"},
        {"main": "Gifts", "sub": "Birthday", "amount_range": (50, 300), "description": "Birthday gift money"},
    ],
    "outflow": [
        # Food & Dining
        {"main": "Food & Dining", "sub": "Groceries", "amount_range": (50, 150), "description": "Weekly grocery shopping"},
        {"main": "Food & Dining", "sub": "Restaurants", "amount_range": (15, 80), "description": "Dinner at restaurant"},
        {"main": "Food & Dining", "sub": "Fast Food", "amount_range": (8, 25), "description": "Quick lunch"},
        {"main": "Food & Dining", "sub": "Coffee & Tea", "amount_range": (4, 12), "description": "Coffee shop"},
        {"main": "Food & Dining", "sub": "Alcohol & Bars", "amount_range": (20, 100), "description": "Drinks with friends"},
        
        # Transportation
        {"main": "Transportation", "sub": "Gas & Fuel", "amount_range": (40, 80), "description": "Gas station fill-up"},
        {"main": "Transportation", "sub": "Parking", "amount_range": (5, 20), "description": "Parking fee"},
        {"main": "Transportation", "sub": "Public Transport", "amount_range": (2, 10), "description": "Bus/subway fare"},
        {"main": "Transportation", "sub": "Taxi & Uber", "amount_range": (10, 40), "description": "Uber/Lyft ride"},
        {"main": "Transportation", "sub": "Car Maintenance", "amount_range": (50, 300), "description": "Car service"},
        
        # Shopping
        {"main": "Shopping", "sub": "Clothing", "amount_range": (30, 200), "description": "New clothes"},
        {"main": "Shopping", "sub": "Electronics", "amount_range": (50, 800), "description": "Electronics purchase"},
        {"main": "Shopping", "sub": "Books", "amount_range": (10, 50), "description": "Books"},
        {"main": "Shopping", "sub": "Home & Garden", "amount_range": (20, 150), "description": "Home supplies"},
        {"main": "Shopping", "sub": "Sports & Recreation", "amount_range": (30, 200), "description": "Sports equipment"},
        
        # Entertainment
        {"main": "Entertainment", "sub": "Movies & Theater", "amount_range": (12, 50), "description": "Movie tickets"},
        {"main": "Entertainment", "sub": "Music", "amount_range": (10, 100), "description": "Concert/music"},
        {"main": "Entertainment", "sub": "Games", "amount_range": (20, 70), "description": "Video games"},
        {"main": "Entertainment", "sub": "Hobbies", "amount_range": (15, 100), "description": "Hobby supplies"},
        {"main": "Entertainment", "sub": "Sports Events", "amount_range": (30, 150), "description": "Sports event tickets"},
        
        # Bills & Utilities
        {"main": "Bills & Utilities", "sub": "Phone", "amount_range": (40, 80), "description": "Mobile phone bill"},
        {"main": "Bills & Utilities", "sub": "Internet", "amount_range": (50, 100), "description": "Internet service"},
        {"main": "Bills & Utilities", "sub": "Electricity", "amount_range": (80, 200), "description": "Electric bill"},
        {"main": "Bills & Utilities", "sub": "Water", "amount_range": (30, 80), "description": "Water bill"},
        {"main": "Bills & Utilities", "sub": "Gas", "amount_range": (40, 120), "description": "Gas utility"},
        {"main": "Bills & Utilities", "sub": "Cable TV", "amount_range": (50, 100), "description": "Cable/streaming"},
        
        # Health & Fitness
        {"main": "Health & Fitness", "sub": "Doctor", "amount_range": (30, 200), "description": "Doctor visit"},
        {"main": "Health & Fitness", "sub": "Dentist", "amount_range": (50, 300), "description": "Dental checkup"},
        {"main": "Health & Fitness", "sub": "Pharmacy", "amount_range": (10, 80), "description": "Prescription medicine"},
        {"main": "Health & Fitness", "sub": "Gym", "amount_range": (30, 80), "description": "Gym membership"},
        {"main": "Health & Fitness", "sub": "Health Insurance", "amount_range": (200, 500), "description": "Health insurance"},
        
        # Travel
        {"main": "Travel", "sub": "Hotels", "amount_range": (100, 400), "description": "Hotel stay"},
        {"main": "Travel", "sub": "Flights", "amount_range": (200, 800), "description": "Airline ticket"},
        {"main": "Travel", "sub": "Car Rental", "amount_range": (40, 150), "description": "Rental car"},
        
        # Education
        {"main": "Education", "sub": "Books", "amount_range": (20, 100), "description": "Textbooks"},
        {"main": "Education", "sub": "Courses", "amount_range": (50, 500), "description": "Online course"},
        {"main": "Education", "sub": "Training", "amount_range": (100, 1000), "description": "Professional training"},
        
        # Personal Care
        {"main": "Personal Care", "sub": "Haircut", "amount_range": (25, 70), "description": "Haircut and styling"},
        {"main": "Personal Care", "sub": "Cosmetics", "amount_range": (15, 80), "description": "Cosmetics"},
        {"main": "Personal Care", "sub": "Spa & Massage", "amount_range": (50, 150), "description": "Spa treatment"},
        
        # Gifts & Donations
        {"main": "Gifts & Donations", "sub": "Gifts", "amount_range": (20, 150), "description": "Gift purchase"},
        {"main": "Gifts & Donations", "sub": "Charity", "amount_range": (10, 200), "description": "Charitable donation"},
        
        # Financial
        {"main": "Financial", "sub": "Bank Fees", "amount_range": (5, 35), "description": "Bank service fee"},
        {"main": "Financial", "sub": "Insurance", "amount_range": (100, 400), "description": "Insurance premium"},
        {"main": "Financial", "sub": "Investments", "amount_range": (100, 1000), "description": "Investment contribution"},
    ]
}

def generate_random_date(start_days_ago=90, end_days_ago=0):
    """Generate a random date within the specified range"""
    today = datetime.now(UTC)
    start_date = today - timedelta(days=start_days_ago)
    end_date = today - timedelta(days=end_days_ago)
    
    time_between = end_date - start_date
    random_days = random.randint(0, time_between.days)
    random_seconds = random.randint(0, 86400)
    
    random_date = start_date + timedelta(days=random_days, seconds=random_seconds)
    return random_date

def create_transaction(token, transaction_data):
    """Create a single transaction via API"""
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    }
    
    response = requests.post(
        f"{API_BASE_URL}/api/transactions",
        headers=headers,
        json=transaction_data
    )
    
    if response.status_code == 200:
        return True, response.json()
    else:
        return False, response.text

def generate_mock_transactions(token, count=50, days_back=90):
    """Generate multiple mock transactions"""
    created = 0
    failed = 0
    
    print(f"Generating {count} mock transactions...")
    print("-" * 50)
    
    for i in range(count):
        # Randomly choose transaction type (more outflows than inflows)
        trans_type = random.choices(["inflow", "outflow"], weights=[1, 4])[0]
        
        # Select random transaction template
        template = random.choice(MOCK_TRANSACTIONS[trans_type])
        
        # Generate random amount within range
        amount = round(random.uniform(*template["amount_range"]), 2)
        
        # Generate random date
        transaction_date = generate_random_date(days_back, 0)
        
        # Create transaction data
        transaction_data = {
            "type": trans_type,
            "main_category": template["main"],
            "sub_category": template["sub"],
            "date": transaction_date.isoformat(),
            "description": template["description"],
            "amount": amount
        }
        
        # Create transaction
        success, result = create_transaction(token, transaction_data)
        
        if success:
            created += 1
            print(f"✅ [{i+1}/{count}] Created: {trans_type} | {template['main']} | ${amount:.2f}")
        else:
            failed += 1
            print(f"❌ [{i+1}/{count}] Failed: {result}")
    
    print("-" * 50)
    print(f"✅ Successfully created: {created}")
    print(f"❌ Failed: {failed}")
    print(f"📊 Total: {count}")

if __name__ == "__main__":
    # Configuration for 3 months of data
    NUM_TRANSACTIONS = 150  # ~50 transactions per month (1-2 per day)
    DAYS_BACK = 90  # Last 3 months (Aug 10 - Nov 10, 2025)
    
    print("=" * 60)
    print("📊 FLOW FINANCE - MOCK DATA GENERATOR")
    print("=" * 60)
    print(f"📅 Date Range: Last {DAYS_BACK} days (3 months)")
    print(f"📝 Transactions: {NUM_TRANSACTIONS} transactions")
    print(f"📍 Today: November 10, 2025")
    print("=" * 60)
    
    # Make sure to set your token
    if ACCESS_TOKEN == "your_token_here":
        print("\n⚠️  SETUP REQUIRED ⚠️")
        print("-" * 60)
        print("Please follow these steps:")
        print("\n1️⃣  Start your FastAPI server:")
        print("   python main.py")
        print("\n2️⃣  Login to get your access token:")
        print("   curl -X POST http://localhost:8000/api/auth/login \\")
        print("     -H 'Content-Type: application/json' \\")
        print("     -d '{\"email\":\"your@email.com\",\"password\":\"your_password\"}'")
        print("\n3️⃣  Copy the 'access_token' from the response")
        print("\n4️⃣  Replace 'your_token_here' in this script with your token:")
        print("   ACCESS_TOKEN = \"eyJhbGciOiJIUzI1NiIsInR5cCI6...\"")
        print("\n5️⃣  Run this script again:")
        print("   python generate_mock_data.py")
        print("=" * 60)
    else:
        print("\n🚀 Starting data generation...")
        print()
        generate_mock_transactions(ACCESS_TOKEN, NUM_TRANSACTIONS, DAYS_BACK)