from datetime import UTC, datetime, timedelta
from typing import Optional
from fastapi import Depends, HTTPException , status
from fastapi import security
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from ai_chatbot import financial_chatbot
from database import users_collection, transactions_collection, goals_collection
from jose import JWTError, jwt
from passlib.context import CryptContext


from config import settings


security = HTTPBearer()

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify a password against its hash"""
    return pwd_context.verify(plain_password, hashed_password)


def get_password_hash(password: str) -> str:
    """Hash a password"""
    return pwd_context.hash(password)


def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    """Create JWT access token"""
    to_encode = data.copy()
    expire = datetime.now(UTC) + (expires_delta or timedelta(minutes=15))
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def verify_token(token: str) -> str:
    """Verify JWT token and return email"""
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        email: str = payload.get("sub")
        if email is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Could not validate credentials: Subject not found"
            )
        return email
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not validate credentials: Token invalid or expired"
        )


def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security)):
    """Get current authenticated user"""
    email = verify_token(credentials.credentials)
    user = users_collection.find_one({"email": email})
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found")
    return user


def ensure_utc_datetime(dt) -> datetime:
    """Ensure datetime is timezone-aware UTC"""
    if dt is None:
        return None
    
    # If it's a string, parse it
    if isinstance(dt, str):
        dt = datetime.fromisoformat(dt.replace("Z", "+00:00"))
    
    # If naive (no timezone), make it UTC
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=UTC)
    # If has timezone but not UTC, convert to UTC
    elif dt.tzinfo != UTC:
        dt = dt.astimezone(UTC)
    
    return dt


async def get_user_balance(user_id: str, currency: Optional[str] = None) -> dict:
    """
    Calculate user's financial balance including goal allocations
    If currency is specified, calculate balance for that currency only
    Otherwise, return balances for all currencies
    
    Returns:
        dict with currency-specific balances or all balances
    """
    if currency:
        # Get balance for specific currency
        pipeline_inflow = [
            {"$match": {"user_id": user_id, "type": "inflow", "currency": currency}},
            {"$group": {"_id": None, "total": {"$sum": "$amount"}}}
        ]
        pipeline_outflow = [
            {"$match": {"user_id": user_id, "type": "outflow", "currency": currency}},
            {"$group": {"_id": None, "total": {"$sum": "$amount"}}}
        ]

        inflow_result = list(transactions_collection.aggregate(pipeline_inflow))
        outflow_result = list(transactions_collection.aggregate(pipeline_outflow))

        total_inflow = inflow_result[0]["total"] if inflow_result else 0
        total_outflow = outflow_result[0]["total"] if outflow_result else 0
        
        # Calculate total allocated to goals for this currency
        goals_pipeline = [
            {"$match": {"user_id": user_id, "currency": currency}},
            {"$group": {"_id": None, "total": {"$sum": "$current_amount"}}}
        ]
        goals_result = list(goals_collection.aggregate(goals_pipeline))
        total_allocated_to_goals = goals_result[0]["total"] if goals_result else 0

        total_balance = total_inflow - total_outflow
        available_balance = total_balance - total_allocated_to_goals

        return {
            "currency": currency,
            "balance": total_balance,
            "available_balance": available_balance,
            "allocated_to_goals": total_allocated_to_goals,
            "total_inflow": total_inflow,
            "total_outflow": total_outflow
        }
    else:
        # Get all transactions grouped by currency
        tx_pipeline = [
            {"$match": {"user_id": user_id}},
            {
                "$group": {
                    "_id": "$currency",
                    "total_inflow": {
                        "$sum": {"$cond": [{"$eq": ["$type", "inflow"]}, "$amount", 0]}
                    },
                    "total_outflow": {
                        "$sum": {"$cond": [{"$eq": ["$type", "outflow"]}, "$amount", 0]}
                    }
                }
            }
        ]
        
        # Get allocations grouped by currency
        goals_pipeline = [
            {"$match": {"user_id": user_id}},
            {"$group": {"_id": "$currency", "total_allocated": {"$sum": "$current_amount"}}}
        ]
        
        tx_results = list(transactions_collection.aggregate(tx_pipeline))
        goal_results = list(goals_collection.aggregate(goals_pipeline))
        
        # Map transaction data for easy lookup
        tx_map = {
            res["_id"]: {
                "inflow": res["total_inflow"],
                "outflow": res["total_outflow"]
            }
            for res in tx_results if res["_id"]  # Skip None currencies
        }
        
        # Collect all currencies from both transactions and goals
        all_currencies = set(tx_map.keys())
        for g in goal_results:
            if g["_id"]:  # Skip None currencies
                all_currencies.add(g["_id"])
        
        # If no currencies found, use default from user profile
        if not all_currencies:
            user = users_collection.find_one({"_id": user_id})
            default_currency = user.get("default_currency", "usd") if user else "usd"
            all_currencies = {default_currency}
        
        balances = {}
        for curr in all_currencies:
            tx_data = tx_map.get(curr, {"inflow": 0, "outflow": 0})
            inflow = tx_data["inflow"]
            outflow = tx_data["outflow"]
            
            # Find allocated amount for this currency
            allocated = 0
            for g in goal_results:
                if g["_id"] == curr:
                    allocated = g["total_allocated"]
                    break
            
            total_balance = inflow - outflow
            
            balances[curr] = {
                "currency": curr,
                "balance": total_balance,
                "available_balance": total_balance - allocated,
                "allocated_to_goals": allocated,
                "total_inflow": inflow,
                "total_outflow": outflow
            }
            
        return {"balances": balances}


def require_premium(current_user: dict = Depends(get_current_user)):
    """Middleware to check if user has premium subscription"""
    subscription_type = current_user.get("subscription_type", "free")
    
    if subscription_type == "premium":
        # Check if subscription hasn't expired
        expires_at = current_user.get("subscription_expires_at")
        if expires_at:
            # FIX: Ensure expires_at is timezone-aware before comparison
            expires_at_utc = ensure_utc_datetime(expires_at)
            if expires_at_utc > datetime.now(UTC):
                return current_user
        elif not expires_at:  # Lifetime premium (no expiration date)
            return current_user
    
    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="This feature requires a premium subscription"
    )
    
    
def refresh_ai_data_silent(user_id: str):
    """Silently refresh AI data without failing on error"""
    try:
        # 1. Update Gemini/OpenAI Context
        if financial_chatbot:
            financial_chatbot.refresh_user_data(user_id)
        
    except Exception as e:
        print(f"Error refreshing AI data: {e}")