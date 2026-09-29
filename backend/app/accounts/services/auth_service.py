"""Sign-in flows: identity upserts, one-time codes, session payloads.

Raises core.errors domain errors; resolvers translate them for clients."""

import secrets

from ... import models as m
from ... import settings
from ...auth import (
    create_session_token,
    hash_login_code,
    verify_apple_identity_token,
    verify_google_id_token,
)
from ...core.errors import CodeCooldownError, InvalidCodeError

CODE_TTL_SECONDS = 600
RESEND_COOLDOWN_SECONDS = 60


class AuthService:
    def __init__(self, users):
        self._users = users

    def session_payload(self, user: m.User) -> dict:
        session = {"id": str(user.id), "name": user.name, "email": user.email, "picture": user.picture}
        return {"token": create_session_token(session), "user": user}

    async def sign_in_with_google(self, id_token: str) -> dict:
        identity = await verify_google_id_token(id_token)
        email = identity["email"].lower()
        user = self._users.upsert_google_user(
            sub=identity["sub"],
            email=email,
            name=identity["name"],
            picture=identity["picture"],
            role="ADMIN" if email in settings.ADMIN_EMAILS else None,
        )
        return self.session_payload(user)

    async def sign_in_with_apple(self, identity_token: str, name: str | None) -> dict:
        identity = await verify_apple_identity_token(identity_token)
        # Apple sends the name only on first authorization, and only client-side.
        email = identity["email"].lower() if identity.get("email") else None
        user = self._users.upsert_apple_user(identity["sub"], email, name=(name or "").strip() or "Coffee fan")
        return self.session_payload(user)

    def issue_code(self, identifier: str) -> str:
        """Cooldown check + fresh 6-digit code, stored hashed."""
        age = self._users.login_code_age(identifier)
        if age is not None and age < RESEND_COOLDOWN_SECONDS:
            raise CodeCooldownError(int(RESEND_COOLDOWN_SECONDS - age))
        code = f"{secrets.randbelow(1_000_000):06d}"
        self._users.save_login_code(identifier, hash_login_code(identifier, code), CODE_TTL_SECONDS)
        return code

    def sign_in_with_phone(self, phone: str, code: str) -> dict:
        if not self._users.use_login_code(phone, hash_login_code(phone, code.strip())):
            raise InvalidCodeError()
        # Public display name must not expose the full number; last 4 is enough.
        user = self._users.upsert_phone_user(phone, name=f"Coffee fan {phone[-4:]}")
        return self.session_payload(user)

    def sign_in_with_email(self, email: str, code: str) -> dict:
        if not self._users.use_login_code(email, hash_login_code(email, code.strip())):
            raise InvalidCodeError()
        user = self._users.upsert_email_user(email, name=email.split("@")[0])
        return self.session_payload(user)
