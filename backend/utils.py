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
        # Get balances for all currencies
        # Get all unique currencies from transactions
        currencies_pipeline = [
            {"$match": {"user_id": user_id}},
            {"$group": {"_id": "$currency"}}
        ]
        currencies_result = list(transactions_collection.aggregate(currencies_pipeline))
        currencies = [c["_id"] for c in currencies_result if c["_id"]]
        
        # If no transactions, use default currency
        if not currencies:
            user = users_collection.find_one({"_id": user_id})
            currencies = [user.get("default_currency", "usd")]
        
        balances = {}
        for curr in currencies:
            balance_data = await get_user_balance(user_id, curr)
            balances[curr] = balance_data
        
        return {"balances": balances}


def require_premium(current_user: dict = Depends(get_current_user)):
    """Middleware to check if user has premium subscription"""
    subscription_type = current_user.get("subscription_type", "free")
    
    if subscription_type == "premium":
        # Check if subscription hasn't expired
        expires_at = current_user.get("subscription_expires_at")
        if expires_at and expires_at > datetime.now(UTC):
            return current_user
        elif not expires_at:  # Lifetime premium
            return current_user
    
    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="This feature requires a premium subscription"
    )
    
    
def refresh_ai_data_silent(user_id: str):
    """Silently refresh AI data and budgets without failing on error"""
    try:
        if financial_chatbot:
            financial_chatbot.refresh_user_data(user_id)
        # Update budgets
        from budget_service import update_all_user_budgets
        update_all_user_budgets(user_id)
    except Exception as e:
        print(f"Error refreshing AI data: {e}")