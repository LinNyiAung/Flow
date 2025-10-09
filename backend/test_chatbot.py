# test_chatbot.py - Simple test script for the AI chatbot

import requests
import json
import os

# Configuration
BASE_URL = "http://10.80.21.130:8000"  # Your API base URL
EMAIL = "test4@example.com"
PASSWORD = "testpassword123"

class FlowFinanceAITester:
    def __init__(self):
        self.session = requests.Session()
        self.token = None
        self.user_id = None
    
    def register_or_login(self):
        """Register or login to get auth token"""
        # Try to register first
        register_data = {
            "name": "Test User",
            "email": EMAIL,
            "password": PASSWORD
        }
        
        try:
            response = self.session.post(f"{BASE_URL}/api/auth/register", json=register_data)
            if response.status_code == 200:
                data = response.json()
                self.token = data["access_token"]
                self.user_id = data["user"]["id"]
                print("✅ Successfully registered new user")
                return True
        except:
            pass
        
        # If register fails, try login
        login_data = {
            "email": EMAIL,
            "password": PASSWORD
        }
        
        try:
            response = self.session.post(f"{BASE_URL}/api/auth/login", json=login_data)
            if response.status_code == 200:
                data = response.json()
                self.token = data["access_token"]
                self.user_id = data["user"]["id"]
                print("✅ Successfully logged in")
                return True
        except Exception as e:
            print(f"❌ Login failed: {e}")
            return False
        
        print("❌ Authentication failed")
        return False
    
    def set_auth_header(self):
        """Set authorization header for requests"""
        if self.token:
            self.session.headers.update({
                "Authorization": f"Bearer {self.token}",
                "Content-Type": "application/json"
            })
    
    def add_sample_transactions(self):
        """Add some sample transactions for testing"""
        sample_transactions = [
            {
                "type": "outflow",
                "main_category": "Food & Dining",
                "sub_category": "Groceries",
                "date": "2024-01-15T00:00:00Z",
                "description": "Weekly grocery shopping",
                "amount": 85.50
            },
            {
                "type": "outflow",
                "main_category": "Food & Dining",
                "sub_category": "Restaurants",
                "date": "2024-01-14T19:30:00Z",
                "description": "Dinner at Italian restaurant",
                "amount": 45.25
            },
            {
                "type": "inflow",
                "main_category": "Salary & Wages",
                "sub_category": "Primary Job",
                "date": "2024-01-01T00:00:00Z",
                "description": "Monthly salary",
                "amount": 3500.00
            },
            {
                "type": "outflow",
                "main_category": "Transportation",
                "sub_category": "Gas & Fuel",
                "date": "2024-01-12T00:00:00Z",
                "description": "Gas station fill-up",
                "amount": 65.00
            },
            {
                "type": "outflow",
                "main_category": "Entertainment",
                "sub_category": "Movies & Theater",
                "date": "2024-01-10T20:00:00Z",
                "description": "Movie tickets",
                "amount": 28.00
            }
        ]
        
        print("Adding sample transactions...")
        for transaction in sample_transactions:
            try:
                response = self.session.post(f"{BASE_URL}/api/transactions", json=transaction)
                if response.status_code == 200:
                    print(f"✅ Added transaction: {transaction['description']}")
                else:
                    print(f"❌ Failed to add transaction: {transaction['description']}")
            except Exception as e:
                print(f"❌ Error adding transaction: {e}")
    
    def test_chat(self, message):
        """Test chat with AI"""
        print(f"\n🤖 Testing chat with message: '{message}'")
        
        try:
            response = self.session.post(f"{BASE_URL}/api/chat", json={
                "message": message,
                "chat_history": []
            })
            
            if response.status_code == 200:
                data = response.json()
                print(f"✅ AI Response: {data['response']}")
                return data['response']
            else:
                print(f"❌ Chat failed with status {response.status_code}: {response.text}")
                return None
                
        except Exception as e:
            print(f"❌ Chat error: {e}")
            return None
    
    def test_insights(self):
        """Test financial insights"""
        print("\n💡 Testing financial insights...")
        
        try:
            response = self.session.get(f"{BASE_URL}/api/insights")
            
            if response.status_code == 200:
                data = response.json()
                print(f"✅ Insights: {data['insights']}")
                return data['insights']
            else:
                print(f"❌ Insights failed with status {response.status_code}: {response.text}")
                return None
                
        except Exception as e:
            print(f"❌ Insights error: {e}")
            return None
    
    def test_chat_history(self):
        """Test chat history retrieval"""
        print("\n📜 Testing chat history...")
        
        try:
            response = self.session.get(f"{BASE_URL}/api/chat/history?limit=5")
            
            if response.status_code == 200:
                data = response.json()
                print(f"✅ Retrieved {len(data)} messages from history")
                for msg in data:
                    print(f"  {msg['role']}: {msg['content'][:50]}...")
                return data
            else:
                print(f"❌ History failed with status {response.status_code}: {response.text}")
                return None
                
        except Exception as e:
            print(f"❌ History error: {e}")
            return None
    
    def run_full_test(self):
        """Run comprehensive test"""
        print("🚀 Starting Flow Finance AI Chatbot Test\n")
        
        # Step 1: Authenticate
        if not self.register_or_login():
            print("❌ Cannot proceed without authentication")
            return
        
        self.set_auth_header()
        
        # Step 2: Add sample data
        self.add_sample_transactions()
        
        # Step 3: Test various chat scenarios
        test_messages = [
            "How much did I spend on food this month?",
            "What's my total income and expenses?",
            "What are my top spending categories?",
            "Give me some tips to save money based on my spending",
            "How much did I spend on transportation?",
            "What's my current balance?"
        ]
        
        for message in test_messages:
            self.test_chat(message)
        
        # Step 4: Test insights
        self.test_insights()
        
        # Step 5: Test chat history
        self.test_chat_history()
        
        print("\n✅ Test completed!")

def main():
    # Check if OpenAI API key is set
    # if not os.getenv("OPENAI_API_KEY"):
    #     print("❌ Error: OPENAI_API_KEY environment variable not set")
    #     print("Please set your OpenAI API key:")
    #     print("export OPENAI_API_KEY='your-api-key-here'")
    #     return
    
    tester = FlowFinanceAITester()
    tester.run_full_test()

if __name__ == "__main__":
    main()