from pydantic import BaseModel, EmailStr
from typing import Optional, List
from datetime import datetime
from enum import Enum

class TransactionType(str, Enum):
    INFLOW = "inflow"
    OUTFLOW = "outflow"

class UserCreate(BaseModel):
    name: str
    email: EmailStr
    password: str

class UserLogin(BaseModel):
    email: EmailStr
    password: str

class UserResponse(BaseModel):
    id: str
    name: str
    email: str
    created_at: datetime

class Token(BaseModel):
    access_token: str
    token_type: str
    user: UserResponse

class TransactionCreate(BaseModel):
    type: TransactionType
    main_category: str
    sub_category: str
    date: datetime # Add this field
    description: Optional[str] = None
    amount: float

class TransactionUpdate(BaseModel):
    type: Optional[TransactionType] = None
    main_category: Optional[str] = None
    sub_category: Optional[str] = None
    date: Optional[datetime] = None # Add this field
    description: Optional[str] = None
    amount: Optional[float] = None

class TransactionResponse(BaseModel):
    id: str
    user_id: str
    type: TransactionType
    main_category: str
    sub_category: str
    date: datetime # Add this field
    description: Optional[str]
    amount: float
    created_at: datetime
    updated_at: datetime

class CategoryResponse(BaseModel):
    main_category: str
    sub_categories: List[str]