"""Google ID-token verification and HMAC-signed session tokens."""

import base64
import hashlib
import hmac
import json
import secrets
import time
from typing import TypedDict

import httpx
from graphql import GraphQLError

from . import settings

# Sessions die on restart without a fixed SESSION_SECRET; fine for dev.
_SECRET = (settings.SESSION_SECRET or secrets.token_hex(32)).encode()
_TTL_SECONDS = 30 * 24 * 3600


class SessionUser(TypedDict):
    id: str
    name: str
    email: str
    picture: str | None


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def _b64url_decode(text: str) -> bytes:
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


def _sign(payload: str) -> str:
    return _b64url(hmac.new(_SECRET, payload.encode(), hashlib.sha256).digest())


def create_session_token(user: SessionUser) -> str:
    payload = _b64url(json.dumps({**user, "exp": int(time.time()) + _TTL_SECONDS}).encode())
    return f"{payload}.{_sign(payload)}"


def verify_session_token(token: str | None) -> SessionUser | None:
    if not token or "." not in token:
        return None
    payload, signature = token.rsplit(".", 1)
    if not hmac.compare_digest(signature, _sign(payload)):
        return None
    try:
        data = json.loads(_b64url_decode(payload))
    except (ValueError, json.JSONDecodeError):
        return None
    if data.get("exp", 0) < time.time():
        return None
    return {"id": data["id"], "name": data["name"], "email": data["email"], "picture": data.get("picture")}


class GoogleIdentity(TypedDict):
    sub: str
    email: str
    name: str
    picture: str | None


async def verify_google_id_token(id_token: str) -> GoogleIdentity:
    if not settings.GOOGLE_OAUTH_CLIENT_ID:
        raise GraphQLError("Google sign-in is not configured (server is missing GOOGLE_OAUTH_CLIENT_ID).")
    async with httpx.AsyncClient() as client:
        res = await client.get("https://oauth2.googleapis.com/tokeninfo", params={"id_token": id_token})
    if res.status_code != 200:
        raise GraphQLError("Invalid Google token.")
    info = res.json()
    if info.get("aud") != settings.GOOGLE_OAUTH_CLIENT_ID:
        raise GraphQLError("Google token was issued for a different app.")
    return {
        "sub": info["sub"],
        "email": info["email"],
        "name": info.get("name") or info["email"],
        "picture": info.get("picture"),
    }
