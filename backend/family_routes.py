"""The family: /api/family (members, roles, invitations). Thin routes over families.service, which holds the rules and
raises the refusals as {"detail": {"code", "message"}}."""
from typing import Literal, Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel, ConfigDict, field_validator, model_validator

from families import service
from plans.contact import normalize_email
from utils import get_current_user

router = APIRouter(prefix="/api/family", tags=["family"])

MAX_NAME_LENGTH = 60


def _name(value: str) -> str:
    """Stripped, 1 to MAX_NAME_LENGTH characters."""
    value = (value or "").strip()
    if not value or len(value) > MAX_NAME_LENGTH:
        raise ValueError(f"must be 1 to {MAX_NAME_LENGTH} characters")
    return value


class FamilyName(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: str

    @field_validator("name")
    @classmethod
    def _clean(cls, v: str) -> str:
        return _name(v)


class ConfirmName(BaseModel):
    model_config = ConfigDict(extra="forbid")
    confirm_name: str


class Placeholder(BaseModel):
    model_config = ConfigDict(extra="forbid")
    display_name: str

    @field_validator("display_name")
    @classmethod
    def _clean(cls, v: str) -> str:
        return _name(v)


class MemberUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    display_name: Optional[str] = None
    role: Optional[Literal["admin", "member"]] = None

    @field_validator("display_name")
    @classmethod
    def _clean(cls, v: Optional[str]) -> Optional[str]:
        return None if v is None else _name(v)

    @model_validator(mode="after")
    def _something(self):
        if self.display_name is None and self.role is None:
            raise ValueError("give display_name or role")
        return self


class Ownership(BaseModel):
    model_config = ConfigDict(extra="forbid")
    member_id: str


class InviteBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    email: str
    link_member_id: Optional[str] = None

    @field_validator("email")
    @classmethod
    def _clean_email(cls, v: str) -> str:
        email = normalize_email(v)
        if email is None:
            raise ValueError("Enter a valid email address")
        return email.lower()


@router.get("")
async def get_family(current_user: dict = Depends(get_current_user)):
    return await service.overview(current_user)


@router.post("")
async def create_family(body: FamilyName, current_user: dict = Depends(get_current_user)):
    return await service.create_family(current_user, body.name)


@router.patch("")
async def rename_family(body: FamilyName, current_user: dict = Depends(get_current_user)):
    return await service.rename_family(current_user, body.name)


@router.delete("")
async def delete_family(body: ConfirmName, current_user: dict = Depends(get_current_user)):
    return await service.delete_family(current_user, body.confirm_name)


@router.post("/placeholders")
async def add_placeholder(body: Placeholder, current_user: dict = Depends(get_current_user)):
    return await service.add_placeholder(current_user, body.display_name)


@router.patch("/members/{member_id}")
async def update_member(member_id: str, body: MemberUpdate, current_user: dict = Depends(get_current_user)):
    return await service.update_member(current_user, member_id, body.display_name, body.role)


@router.delete("/members/{member_id}")
async def remove_member(member_id: str, current_user: dict = Depends(get_current_user)):
    return await service.remove_member(current_user, member_id)


@router.post("/leave")
async def leave(current_user: dict = Depends(get_current_user)):
    return await service.leave(current_user)


@router.post("/transfer-ownership")
async def transfer_ownership(body: Ownership, current_user: dict = Depends(get_current_user)):
    return await service.transfer_ownership(current_user, body.member_id)


@router.post("/invites")
async def create_invite(body: InviteBody, current_user: dict = Depends(get_current_user)):
    return await service.create_invite(current_user, body.email, body.link_member_id)


@router.get("/invites/mine")
async def my_invites(current_user: dict = Depends(get_current_user)):
    return await service.my_invites(current_user)


@router.delete("/invites/{invite_id}")
async def cancel_invite(invite_id: str, current_user: dict = Depends(get_current_user)):
    return await service.cancel_invite(current_user, invite_id)


@router.post("/invites/{invite_id}/accept")
async def accept_invite(invite_id: str, current_user: dict = Depends(get_current_user)):
    return await service.accept_invite(current_user, invite_id)


@router.post("/invites/{invite_id}/decline")
async def decline_invite(invite_id: str, current_user: dict = Depends(get_current_user)):
    return await service.decline_invite(current_user, invite_id)
