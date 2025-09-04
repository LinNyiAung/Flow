import os

class Settings:
    MONGODB_URL = os.getenv("MONGODB_URL", "mongodb+srv://linnyiaung1794_db_user:AUXAagITCDMhHYpD@app.fq1ahge.mongodb.net/?retryWrites=true&w=majority&appName=app")
    DATABASE_NAME = os.getenv("DATABASE_NAME", "app")
    SECRET_KEY = os.getenv("SECRET_KEY", "your-secret-key-change-this-in-production-make-it-very-long-and-random-string-for-jwt-tokens")
    ALGORITHM = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES = 30

settings = Settings()