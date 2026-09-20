import re
import secrets

from ariadne import MutationType
from graphql import GraphQLError

from .. import settings
from ..auth import (
    create_session_token,
    hash_login_code,
    verify_apple_identity_token,
    verify_google_id_token,
)
from ..repository import DuplicateEmailError
from ..services import email as email_service
from ..services import sms
from ..services.google import fetch_shops_from_google, new_shop_from_place
from ..services.vision import identify_machine, parse_menu
from ..services.yelp import fetch_shops_from_yelp

mutation = MutationType()


def _require_user(info) -> dict:
    user = info.context["user"]
    if not user:
        # Clients match on "Sign in" + "contribute" to detect a stale session.
        raise GraphQLError("Sign in to contribute.")
    return user


def require_admin(info) -> dict:
    user = _require_user(info)
    record = info.context["repo"].get_user(user["id"])
    if not record or record["role"] != "ADMIN":
        raise GraphQLError("Admin access required.")
    return user


@mutation.field("signInWithGoogle")
async def resolve_sign_in(_, info, idToken):
    identity = await verify_google_id_token(idToken)
    email = identity["email"].lower()
    return _commit_sign_in(
        lambda: info.context["repo"].upsert_user(
            {
                "googleSub": identity["sub"],
                "email": email,
                "name": identity["name"],
                "picture": identity["picture"],
                "role": "ADMIN" if email in settings.ADMIN_EMAILS else None,
            }
        )
    )


_CODE_TTL_SECONDS = 600
_RESEND_COOLDOWN_SECONDS = 60


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


def _issue_login_code(repo, identifier: str) -> str:
    """Cooldown check + fresh 6-digit code, stored hashed."""
    age = repo.login_code_age(identifier)
    if age is not None and age < _RESEND_COOLDOWN_SECONDS:
        raise GraphQLError(f"A code was just sent. You can resend in {int(_RESEND_COOLDOWN_SECONDS - age)}s.")
    code = f"{secrets.randbelow(1_000_000):06d}"
    repo.save_login_code(identifier, hash_login_code(identifier, code), _CODE_TTL_SECONDS)
    return code


def _session_payload(user) -> dict:
    session = {"id": user["id"], "name": user["name"], "email": user["email"], "picture": user["picture"]}
    return {"token": create_session_token(session), "user": user}


def _commit_sign_in(fn):
    try:
        return _session_payload(fn())
    except DuplicateEmailError as e:
        raise GraphQLError(str(e))


@mutation.field("startPhoneSignIn")
async def resolve_start_phone_sign_in(_, info, phone):
    normalized = _normalize_phone(phone)
    code = _issue_login_code(info.context["repo"], normalized)
    if sms.configured():
        try:
            await sms.send_sms(normalized, f"{code} is your Know Your Coffee sign-in code.")
        except RuntimeError as e:
            print(f"phone sign-in: {e}")
            raise GraphQLError("The text message could not be sent. Check the number and try again.")
        return {"sent": True, "devCode": None}
    if not settings.AUTH_DEV_CODES:
        raise GraphQLError("Phone sign-in is not available on this server yet.")
    # Dev fallback: no SMS provider, so hand the code back (AUTH_DEV_CODES=1 only).
    print(f"phone sign-in (SMS not configured): code for {normalized} is {code}")
    return {"sent": False, "devCode": code}


@mutation.field("signInWithPhone")
def resolve_sign_in_with_phone(_, info, phone, code):
    repo = info.context["repo"]
    normalized = _normalize_phone(phone)
    if not repo.use_login_code(normalized, hash_login_code(normalized, code.strip())):
        raise GraphQLError("That code is wrong or expired. Request a new one.")
    # Public display name must not expose the full number; last 4 is enough.
    return _commit_sign_in(
        lambda: repo.upsert_phone_user(normalized, name=f"Coffee fan {normalized[-4:]}")
    )


_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def _normalize_email(raw: str) -> str:
    normalized = raw.strip().lower()
    if not _EMAIL_RE.match(normalized):
        raise GraphQLError("That doesn't look like an email address.")
    return normalized


@mutation.field("startEmailSignIn")
async def resolve_start_email_sign_in(_, info, email):
    normalized = _normalize_email(email)
    code = _issue_login_code(info.context["repo"], normalized)
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
        return {"sent": True, "devCode": None}
    if not settings.AUTH_DEV_CODES:
        raise GraphQLError("Email sign-in is not available on this server yet.")
    # Dev fallback: no email provider, so hand the code back (AUTH_DEV_CODES=1 only).
    print(f"email sign-in (Resend not configured): code for {normalized} is {code}")
    return {"sent": False, "devCode": code}


@mutation.field("signInWithEmail")
def resolve_sign_in_with_email(_, info, email, code):
    repo = info.context["repo"]
    normalized = _normalize_email(email)
    if not repo.use_login_code(normalized, hash_login_code(normalized, code.strip())):
        raise GraphQLError("That code is wrong or expired. Request a new one.")
    return _commit_sign_in(lambda: repo.upsert_email_user(normalized, name=normalized.split("@")[0]))


@mutation.field("signInWithApple")
async def resolve_sign_in_with_apple(_, info, identityToken, name=None):
    identity = await verify_apple_identity_token(identityToken)
    # Apple sends the name only on first authorization, and only client-side.
    email = identity["email"].lower() if identity.get("email") else None
    return _commit_sign_in(
        lambda: info.context["repo"].upsert_apple_user(
            identity["sub"], email, name=(name or "").strip() or "Coffee fan"
        )
    )


@mutation.field("addShopFromPlace")
async def resolve_add_shop_from_place(_, info, placeId):
    _require_user(info)
    shop = await new_shop_from_place(placeId)
    if not shop:
        raise GraphQLError("That place could not be loaded from Google Places. Try searching again.")
    return info.context["repo"].upsert_shops([shop])[0]


@mutation.field("submitReport")
def resolve_submit_report(_, info, input):
    user = _require_user(info)
    repo = info.context["repo"]
    if not repo.get_shop(input["shopId"]):
        raise GraphQLError(f"Shop {input['shopId']} not found")
    return repo.add_report({**input, "userId": user["id"]})


@mutation.field("setShopStatus")
def resolve_set_shop_status(_, info, shopId, saved=None, been=None):
    user = _require_user(info)
    repo = info.context["repo"]
    repo.set_shop_status(user["id"], shopId, saved, been)
    shop = repo.get_shop(shopId, user["id"])
    if not shop:
        raise GraphQLError(f"Shop {shopId} not found")
    return shop


@mutation.field("addShopPhotos")
def resolve_add_shop_photos(_, info, shopId, photos):
    user = _require_user(info)
    repo = info.context["repo"]
    if not repo.get_shop(shopId):
        raise GraphQLError(f"Shop {shopId} not found")
    if len(photos) > 8:
        raise GraphQLError("At most 8 photos per submission.")
    for p in photos:
        # ~700KB data-URL cap keeps rows small; clients downscale before upload.
        if len(p["data"]) > 700_000:
            raise GraphQLError("A photo is too large. Please retry; it will be resized.")
    return repo.add_photos(shopId, user["id"], photos)


@mutation.field("identifyMachine")
async def resolve_identify_machine(_, info, imageBase64):
    _require_user(info)
    return await identify_machine(imageBase64)


@mutation.field("parseMenu")
async def resolve_parse_menu(_, info, imageBase64):
    _require_user(info)
    return await parse_menu(imageBase64)


@mutation.field("importShopsFromYelp")
async def resolve_import_yelp(_, info, location):
    require_admin(info)
    shops = await fetch_shops_from_yelp(location)
    return info.context["repo"].upsert_shops(shops)


@mutation.field("importShopsFromGoogle")
async def resolve_import_google(_, info, location):
    require_admin(info)
    shops = await fetch_shops_from_google(location)
    return info.context["repo"].upsert_shops(shops)


@mutation.field("claimShop")
def resolve_claim_shop(_, info, shopId, note=None):
    user = _require_user(info)
    repo = info.context["repo"]
    shop = repo.get_shop(shopId)
    if not shop:
        raise GraphQLError(f"Shop {shopId} not found")
    if shop.get("ownerId") == user["id"]:
        raise GraphQLError("You already own this shop.")
    if shop.get("ownerId"):
        raise GraphQLError("This shop already has a verified owner. Contact an admin to dispute.")
    return repo.create_claim(user["id"], shopId, note)


@mutation.field("resolveClaim")
def resolve_resolve_claim(_, info, claimId, approve):
    require_admin(info)
    claim = info.context["repo"].resolve_claim(claimId, approve)
    if not claim:
        raise GraphQLError(f"Claim {claimId} not found or already resolved.")
    return claim


@mutation.field("deleteShop")
def resolve_delete_shop(_, info, id):
    require_admin(info)
    if not info.context["repo"].delete_shop(id):
        raise GraphQLError(f"Shop {id} not found")
    return True
