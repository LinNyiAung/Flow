# debug_database.py - Script to check what's actually in the database

from database import transactions_collection, users_collection
from datetime import datetime, timedelta, timezone

def debug_database():
    print("=== DATABASE DEBUG SCRIPT ===\n")
    
    # Check users
    print("1. CHECKING USERS:")
    users = list(users_collection.find({}))
    print(f"Total users found: {len(users)}")
    for user in users[-3:]:  # Show last 3 users
        print(f"  User ID: {user['_id']}")
        print(f"  Email: {user['email']}")
        print(f"  Name: {user['name']}")
        print()
    
    if not users:
        print("No users found in database!")
        return
    
    # Check transactions for each user
    print("2. CHECKING TRANSACTIONS:")
    for user in users[-2:]:  # Check last 2 users
        user_id = user['_id']
        print(f"\nTransactions for user {user_id} ({user['email']}):")
        
        # Try different query approaches
        print("  a) All transactions for this user:")
        all_transactions = list(transactions_collection.find({"user_id": user_id}))
        print(f"     Found: {len(all_transactions)} transactions")
        
        print("  b) Recent transactions (last 30 days):")
        start_date = datetime.now(timezone.utc) - timedelta(days=30)
        recent_transactions = list(transactions_collection.find({
            "user_id": user_id,
            "date": {"$gte": start_date}
        }))
        print(f"     Found: {len(recent_transactions)} transactions")
        
        print("  c) All transactions regardless of date:")
        no_date_filter = list(transactions_collection.find({"user_id": user_id}))
        print(f"     Found: {len(no_date_filter)} transactions")
        
        # Show sample transactions
        if all_transactions:
            print("  d) Sample transactions:")
            for i, t in enumerate(all_transactions[:3]):
                print(f"     Transaction {i+1}:")
                print(f"       ID: {t.get('_id', 'N/A')}")
                print(f"       Type: {t.get('type', 'N/A')}")
                print(f"       Amount: {t.get('amount', 'N/A')}")
                print(f"       Category: {t.get('main_category', 'N/A')} > {t.get('sub_category', 'N/A')}")
                print(f"       Date: {t.get('date', 'N/A')} (type: {type(t.get('date', 'N/A'))})")
                print(f"       Description: {t.get('description', 'N/A')}")
                print()
        else:
            print("     No transactions found for this user!")
    
    print("3. CHECKING ALL TRANSACTIONS:")
    all_transactions = list(transactions_collection.find({}))
    print(f"Total transactions in database: {len(all_transactions)}")
    
    if all_transactions:
        print("\nSample of all transactions:")
        for i, t in enumerate(all_transactions[:5]):
            print(f"  Transaction {i+1}: User={t.get('user_id', 'N/A')[:8]}..., Amount=${t.get('amount', 'N/A')}, Date={t.get('date', 'N/A')}")
    
    print("\n4. TESTING DATE QUERIES:")
    # Test different date query approaches
    now = datetime.now(timezone.utc)
    start_date = now - timedelta(days=365)
    
    print(f"Current time: {now}")
    print(f"Start date (365 days ago): {start_date}")
    
    date_query_results = list(transactions_collection.find({
        "date": {"$gte": start_date}
    }))
    print(f"Transactions with date >= {start_date}: {len(date_query_results)}")
    
    # Try without date filter
    no_date_results = list(transactions_collection.find({}))
    print(f"All transactions (no date filter): {len(no_date_results)}")
    
    print("\n=== DEBUG COMPLETE ===")

if __name__ == "__main__":
    debug_database()