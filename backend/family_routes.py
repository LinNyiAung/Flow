"""The family: /api/family (members, roles, invitations, the per-person breakdown) and /api/transfers (moving money
between a personal wallet and the family wallet). Thin routes over families.service, which holds the rules and raises
the refusals as {"detail": {"code", "message"}}, families.breakdown and families.transfers."""
from typing import Literal, Optional

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, status
from pydantic import BaseModel, ConfigDict, field_validator, model_validator

from families import breakdown as family_breakdown
from families import service
from families import spending as family_spending
from families import transfers
from families.book import Book, get_book, refuse
from models import Currency, PositiveAmount
from plans.contact import normalize_email
from report_models import ReportPeriod
from report_routes import calculate_report_dates
from tz_utils import CalendarDate, WallClock
from user_zones import user_zone
from utils import get_current_user

router = APIRouter(prefix="/api/family", tags=["family"])
transfers_router = APIRouter(prefix="/api/transfers", tags=["family"])

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


class TransferBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    direction: Literal["to_family", "to_personal"]
    amount: PositiveAmount
    currency: Currency
    date: WallClock  # the local date and time, as for a transaction
    description: Optional[str] = None


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


@router.get("/breakdown")
async def breakdown(start_date: CalendarDate = Query(...), end_date: CalendarDate = Query(...),
                    currency: Optional[Currency] = None, book: Book = Depends(get_book)):
    """Spending per person it was for, start_date..end_date as whole calendar days (as custom reports take them),
    in `currency` (default: the family's, service.family_currency). Any active member; X-Book is optional here."""
    family = book.family if book.is_family else await service.family_of(book.person)
    date_from, date_to = calculate_report_dates(ReportPeriod.CUSTOM, start_date, end_date, user_zone(book.person))
    code = currency.value if currency else await service.family_currency(family["id"])
    if code not in {c.value for c in Currency}:
        code = Currency.USD.value
    return await family_breakdown.family_breakdown(family, code, date_from, date_to)


async def _spending_scope(book: Book, month: str, currency: Optional[Currency]):
    """(family, person, currency code, the month's 1st) for a Family spending request; 409 no_family outside a family,
    422 for a month that isn't YYYY-MM."""
    family = book.family if book.is_family else await service.family_of(book.person)
    try:
        first = family_spending.parse_month(month)
    except ValueError:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="month must be YYYY-MM")
    code = currency.value if currency else await service.family_currency(family["id"])
    if code not in {c.value for c in Currency}:
        code = Currency.USD.value
    return family, book.person, code, first


@router.get("/spending")
async def spending(month: str = Query(...), currency: Optional[Currency] = None, book: Book = Depends(get_book)):
    """The Family spending screen's month: spending per person it was for (the breakdown's rows) with each person's
    previous month, in `currency` (default: the family's). Any active member; X-Book is optional here."""
    family, person, code, first = await _spending_scope(book, month, currency)
    return await family_spending.month_overview(family, person, code, first)


@router.get("/spending/person")
async def spending_person(month: str = Query(...), currency: Optional[Currency] = None,
                          member_id: Optional[str] = None, book: Book = Depends(get_book)):
    """One person's month on the Family spending screen (no member_id: Whole family): categories, the 6-month trend,
    the biggest entries and who added them. 404 not_found for a member_id that isn't in the caller's family."""
    family, person, code, first = await _spending_scope(book, month, currency)
    result = await family_spending.person_month(family, person, code, first, member_id)
    if result is None:
        refuse(person, status.HTTP_404_NOT_FOUND, "not_found")
    return result


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


@transfers_router.post("")
async def create_transfer(body: TransferBody, background_tasks: BackgroundTasks,
                          current_user: dict = Depends(get_current_user)):
    """Move money between the caller's wallet and their own family's wallet (X-Book doesn't matter)."""
    return await transfers.create_transfer(current_user, body.direction, body.amount, body.currency.value, body.date,
                                           body.description, background_tasks)


@transfers_router.delete("/{transfer_id}")
async def undo_transfer(transfer_id: str, background_tasks: BackgroundTasks,
                        current_user: dict = Depends(get_current_user)):
    """Undo a transfer the caller made: both legs go together."""
    return await transfers.undo_transfer(current_user, transfer_id, background_tasks)
