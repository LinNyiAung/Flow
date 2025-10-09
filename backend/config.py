import os
from dotenv import load_dotenv

load_dotenv()

class Settings:
    MONGODB_URL = os.getenv("MONGODB_URL")
    DATABASE_NAME = os.getenv("DATABASE_NAME")
    SECRET_KEY = os.getenv("SECRET_KEY")
    ALGORITHM = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES = 30
    
    # AI Chatbot settings
    OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")  # Make sure to set this in your environment
    OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-3.5-turbo")
    MAX_CHAT_HISTORY = int(os.getenv("MAX_CHAT_HISTORY",))  # Maximum messages to keep in history

settings = Settings()