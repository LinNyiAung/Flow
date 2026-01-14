import json
import os
from dotenv import load_dotenv

load_dotenv()

class Settings:
    MONGODB_URL = os.getenv("MONGODB_URL")
    DATABASE_NAME = os.getenv("DATABASE_NAME")
    SECRET_KEY = os.getenv("SECRET_KEY")
    ALGORITHM = "HS256"
    # 30 days
    ACCESS_TOKEN_EXPIRE_MINUTES = 43200 
    
    # AI Chatbot settings
    OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
    OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
    
    # NEW: Gemini settings
    GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY")
    GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")
    
    
    FIREBASE_CREDENTIALS_PATH: str = os.getenv(
        "FIREBASE_CREDENTIALS_PATH", 
        "toepwar-ai-firebase-adminsdk-fbsvc-cc42c07a7c.json"
    )
    
    # NEW: Allow passing the credentials as a raw JSON string
    FIREBASE_CREDENTIALS_JSON: dict = None
    
    _json_str = os.getenv("FIREBASE_CREDENTIALS_JSON_STR")
    if _json_str:
        try:
            FIREBASE_CREDENTIALS_JSON = json.loads(_json_str)
        except json.JSONDecodeError:
            print("❌ Error decoding FIREBASE_CREDENTIALS_JSON_STR")
    
    MAX_CHAT_HISTORY = int(os.getenv("MAX_CHAT_HISTORY", "20"))

settings = Settings()