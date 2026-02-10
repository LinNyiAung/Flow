from datetime import UTC, datetime, timedelta
from typing import Optional
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt
from passlib.context import CryptContext

from config import settings
from database import admins_collection

security_admin = HTTPBearer()
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify a password against its hash"""
    return pwd_context.verify(plain_password, hashed_password)


def get_password_hash(password: str) -> str:
    """Hash a password"""
    return pwd_context.hash(password)


def create_admin_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    """Create JWT access token for admin"""
    to_encode = data.copy()
    expire = datetime.now(UTC) + (expires_delta or timedelta(minutes=60))
    to_encode.update({"exp": expire, "type": "admin"})
    return jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def verify_admin_token(token: str) -> str:
    """Verify admin JWT token and return email"""
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        email: str = payload.get("sub")
        token_type: str = payload.get("type")
        
        if email is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Could not validate credentials: Subject not found"
            )
        
        if token_type != "admin":
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid token type"
            )
        
        return email
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not validate credentials: Token invalid or expired"
        )


async def get_current_admin(credentials: HTTPAuthorizationCredentials = Depends(security_admin)):
    """Get current authenticated admin"""
    email = verify_admin_token(credentials.credentials)
    
    # [FIX] Added await for async database call
    admin = await admins_collection.find_one({"email": email})
    
    if not admin:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Admin not found"
        )
    
    # [FIX] Added await for async database update
    await admins_collection.update_one(
        {"_id": admin["_id"]},
        {"$set": {"last_login": datetime.now(UTC)}}
    )
    
    return admin


def require_super_admin(admin: dict = Depends(get_current_admin)):
    """Middleware to check if admin has super_admin role"""
    if admin.get("role") != "super_admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This action requires super admin privileges"
        )
    return admin


def require_admin_or_super(admin: dict = Depends(get_current_admin)):
    """Middleware to check if admin has admin or super_admin role"""
    if admin.get("role") not in ["admin", "super_admin"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This action requires admin privileges"
        )
    return admin


async def log_admin_action(
    admin_id: str,
    admin_email: str,
    action: str,
    target_user_id: Optional[str] = None,
    target_user_email: Optional[str] = None,
    details: Optional[str] = None
):
    """Log admin actions for audit trail"""
    from database import admin_action_logs_collection
    import uuid
    
    log_entry = {
        "_id": str(uuid.uuid4()),
        "admin_id": admin_id,
        "admin_email": admin_email,
        "action": action,
        "target_user_id": target_user_id,
        "target_user_email": target_user_email,
        "details": details,
        "timestamp": datetime.now(UTC)
    }
    
    try:
        # [FIX] Added await for async database insertion
        await admin_action_logs_collection.insert_one(log_entry)
    except Exception as e:
        print(f"Error logging admin action: {e}")