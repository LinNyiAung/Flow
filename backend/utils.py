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
    Get balance with Read-Through Caching to fix scalability.
    1. Try to read cached balance from user document.
    2. If missing, calculate via aggregation (slow), then save to cache (fast next time).
    """
    # 1. FAST PATH: Check cache
    user = users_collection.find_one({"_id": user_id}, {"balances": 1, "default_currency": 1})
    cached_balances = user.get("balances")

    # If we have a cache, use it immediately
    if cached_balances:
        if currency:
            # Return specific currency from cache (default to 0 if currency not in cache)
            data = cached_balances.get(currency, {
                "balance": 0, "available_balance": 0, 
                "allocated_to_goals": 0, "total_inflow": 0, "total_outflow": 0
            })
            data["currency"] = currency
            return data
        else:
            # Return all cached balances
            return {"balances": cached_balances}

    # 2. SLOW PATH: Aggregation (Run only if cache is missing/invalidated)
    # --- [Keep your existing aggregation logic below] ---
    
    # ... [Keep your existing tx_pipeline and goals_pipeline logic] ...
    # ... [Assuming you run the aggregation and get 'balances' dict as per your original code] ...
    
    # RE-USE YOUR EXISTING AGGREGATION CODE HERE TO GET 'balances' variable
    # (Copy the logic from your original function for calculating 'balances')
    # For brevity, I assume 'balances' is the result of your aggregation logic:
    # balances = { "usd": { ... }, "mmk": { ... } } 
    
    # [Restoring the aggregation logic for completeness of the fix]:
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
    goals_pipeline = [
        {"$match": {"user_id": user_id}},
        {"$group": {"_id": "$currency", "total_allocated": {"$sum": "$current_amount"}}}
    ]
    
    tx_results = list(transactions_collection.aggregate(tx_pipeline))
    goal_results = list(goals_collection.aggregate(goals_pipeline))
    
    tx_map = {res["_id"]: res for res in tx_results if res["_id"]}
    all_currencies = set(tx_map.keys()) | {g["_id"] for g in goal_results if g["_id"]}
    
    if not all_currencies:
        all_currencies = {user.get("default_currency", "usd")}
    
    balances = {}
    for curr in all_currencies:
        tx_data = tx_map.get(curr, {"total_inflow": 0, "total_outflow": 0})
        allocated = next((g["total_allocated"] for g in goal_results if g["_id"] == curr), 0)
        
        balance = tx_data["total_inflow"] - tx_data["total_outflow"]
        balances[curr] = {
            "currency": curr,
            "balance": balance,
            "available_balance": balance - allocated,
            "allocated_to_goals": allocated,
            "total_inflow": tx_data["total_inflow"],
            "total_outflow": tx_data["total_outflow"]
        }

    # 3. CACHE UPDATE: Save the result so next time is O(1)
    users_collection.update_one(
        {"_id": user_id},
        {"$set": {"balances": balances}}
    )

    if currency:
        return balances.get(currency, {
            "currency": currency, "balance": 0, "available_balance": 0, 
            "allocated_to_goals": 0, "total_inflow": 0, "total_outflow": 0
        })
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
    
    
