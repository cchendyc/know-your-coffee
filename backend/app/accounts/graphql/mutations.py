"""Sign-in and account mutations. Input normalization and message transport
(SMS/email) stay here; codes and upserts live in AuthService."""

import re

from ariadne import MutationType
from graphql import GraphQLError

from ... import settings
from ...core.errors import DomainError
from ...core.graphql import require_user
from ...services import email as email_service
from ...services import sms

mutation = MutationType()


def _normalize_phone(raw: str) -> str:
    """To E.164. Bare 10-digit numbers are assumed US."""
    digits = re.sub(r"\D", "", raw)
    if raw.strip().startswith("+"):
        normalized = f"+{digits}"
    elif len(digits) == 10:
        normalized = f"+1{digits}"
    elif len(digits) == 11 and digits.startswith("1"):
        normalized = f"+{digits}"
    else:
        raise GraphQLError("Enter the number with a country code, e.g. +14155551234.")
    if not 8 <= len(digits) <= 15:
        raise GraphQLError("That phone number doesn't look valid.")
    return normalized


_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def _normalize_email(raw: str) -> str:
    normalized = raw.strip().lower()
    if not _EMAIL_RE.match(normalized):
        raise GraphQLError("That doesn't look like an email address.")
    return normalized


@mutation.field("signInWithGoogle")
async def resolve_sign_in_with_google(_, info, idToken):
    try:
        return await info.context["services"].auth.sign_in_with_google(idToken)
    except DomainError as e:
        raise GraphQLError(str(e))


@mutation.field("signInWithApple")
async def resolve_sign_in_with_apple(_, info, identityToken, name=None):
    try:
        return await info.context["services"].auth.sign_in_with_apple(identityToken, name)
    except DomainError as e:
        raise GraphQLError(str(e))


@mutation.field("startPhoneSignIn")
async def resolve_start_phone_sign_in(_, info, phone):
    normalized = _normalize_phone(phone)
    try:
        code = info.context["services"].auth.issue_code(normalized)
    except DomainError as e:
        raise GraphQLError(str(e))
    if sms.configured():
        try:
            await sms.send_sms(normalized, f"{code} is your Know Your Coffee sign-in code.")
        except RuntimeError as e:
            print(f"phone sign-in: {e}")
            raise GraphQLError("The text message could not be sent. Check the number and try again.")
        return {"sent": True, "dev_code": None}
    if not settings.AUTH_DEV_CODES:
        raise GraphQLError("Phone sign-in is not available on this server yet.")
    # Dev fallback: no SMS provider, so hand the code back (AUTH_DEV_CODES=1 only).
    print(f"phone sign-in (SMS not configured): code for {normalized} is {code}")
    return {"sent": False, "dev_code": code}


@mutation.field("signInWithPhone")
def resolve_sign_in_with_phone(_, info, phone, code):
    try:
        return info.context["services"].auth.sign_in_with_phone(_normalize_phone(phone), code)
    except DomainError as e:
        raise GraphQLError(str(e))


@mutation.field("startEmailSignIn")
async def resolve_start_email_sign_in(_, info, email):
    normalized = _normalize_email(email)
    try:
        code = info.context["services"].auth.issue_code(normalized)
    except DomainError as e:
        raise GraphQLError(str(e))
    if email_service.configured():
        try:
            await email_service.send_email(
                normalized,
                subject=f"{code} is your Know Your Coffee sign-in code",
                text=f"{code} is your Know Your Coffee sign-in code. It expires in 10 minutes.",
            )
        except RuntimeError as e:
            print(f"email sign-in: {e}")
            raise GraphQLError("The email could not be sent. Check the address and try again.")
        return {"sent": True, "dev_code": None}
    if not settings.AUTH_DEV_CODES:
        raise GraphQLError("Email sign-in is not available on this server yet.")
    # Dev fallback: no email provider, so hand the code back (AUTH_DEV_CODES=1 only).
    print(f"email sign-in (Resend not configured): code for {normalized} is {code}")
    return {"sent": False, "dev_code": code}


@mutation.field("signInWithEmail")
def resolve_sign_in_with_email(_, info, email, code):
    try:
        return info.context["services"].auth.sign_in_with_email(_normalize_email(email), code)
    except DomainError as e:
        raise GraphQLError(str(e))


@mutation.field("deleteAccount")
def resolve_delete_account(_, info):
    user = require_user(info)
    if not info.context["repos"].users.delete(user["id"]):
        raise GraphQLError("Account not found; it may already be deleted.")
    return True
