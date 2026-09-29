"""In-memory user repository, mirroring the Postgres behavior."""

import hmac
import time
from datetime import UTC, datetime

from ... import models as m
from ...core.errors import DuplicateEmailError
from ...core.memory import MemoryStore


class MemoryUserRepository:
    def __init__(self, store: MemoryStore):
        self._store = store

    def _new_user(self, **fields) -> m.User:
        defaults = {
            "google_sub": None,
            "apple_sub": None,
            "email": None,
            "phone": None,
            "picture": None,
            "role": "USER",
            "created_at": datetime.now(UTC),
        }
        record = m.User(id=self._store.next_id(), **{**defaults, **fields})
        self._store.users[str(record.id)] = record
        return record

    def get(self, user_id: str) -> m.User | None:
        return self._store.users.get(str(user_id))

    def upsert_google_user(self, sub: str, email: str, name: str, picture: str | None, role: str | None) -> m.User:
        email = email.lower()
        users = self._store.users
        existing = next((u for u in users.values() if u.google_sub == sub), None)
        if not existing:
            by_email = next((u for u in users.values() if (u.email or "").lower() == email), None)
            if by_email:
                if by_email.google_sub and by_email.google_sub != sub:
                    raise DuplicateEmailError()
                existing = by_email
        if existing:
            taken = any(
                u.id != existing.id and (u.email or "").lower() == email for u in users.values()
            )
            if taken:
                raise DuplicateEmailError()
            if role == "ADMIN":
                existing.role = "ADMIN"
            existing.google_sub = sub
            existing.email = email or existing.email
            existing.name = name
            existing.picture = picture or existing.picture
            return existing
        return self._new_user(
            google_sub=sub, email=email, name=name, picture=picture,
            role="ADMIN" if role == "ADMIN" else "USER",
        )

    def upsert_phone_user(self, phone: str, name: str) -> m.User:
        existing = next((u for u in self._store.users.values() if u.phone == phone), None)
        return existing or self._new_user(phone=phone, name=name)

    def upsert_email_user(self, email: str, name: str) -> m.User:
        email = email.lower()
        existing = next((u for u in self._store.users.values() if (u.email or "").lower() == email), None)
        return existing or self._new_user(email=email, name=name)

    def upsert_apple_user(self, apple_sub: str, email: str | None, name: str) -> m.User:
        users = self._store.users
        existing = next((u for u in users.values() if u.apple_sub == apple_sub), None)
        if existing:
            return existing
        email = email.lower() if email else None
        if email:
            match = next((u for u in users.values() if (u.email or "").lower() == email), None)
            if match:
                if match.apple_sub and match.apple_sub != apple_sub:
                    raise DuplicateEmailError()
                match.apple_sub = apple_sub
                return match
        return self._new_user(apple_sub=apple_sub, email=email, name=name)

    def delete(self, user_id: str) -> bool:
        store = self._store
        user_id = str(user_id)
        if user_id not in store.users:
            return False
        del store.users[user_id]
        # Anonymize like Postgres: cut the user link so role lookups on
        # reports and photos stop resolving.
        for reports in store.reports.values():
            for report in reports:
                if str(report.user_id or "") == user_id:
                    report.user_id = None
                    report.user = None
        for photos in store.photos.values():
            for photo in photos:
                if str(photo.user_id or "") == user_id:
                    photo.user_id = None
                    photo.user = None
        for order in store.orders.values():
            if str(order.buyer_user_id or "") == user_id:
                order.buyer_user_id = None
                order.buyer = None
        for shop in store.shops.values():
            if str(shop.owner_user_id or "") == user_id:
                shop.owner_user_id = None
        store.bookmarks = {k for k in store.bookmarks if k[0] != user_id}
        store.visits = {k for k in store.visits if k[0] != user_id}
        store.claims = {cid: c for cid, c in store.claims.items() if str(c.user_id) != user_id}
        return True

    # -------------------------------------------------------- login codes

    def save_login_code(self, identifier: str, code_hash: str, ttl_seconds: int) -> None:
        self._store.login_codes[identifier] = {
            "hash": code_hash,
            "attempts": 0,
            "expires_at": time.time() + ttl_seconds,
            "created_at": time.time(),
        }

    def login_code_age(self, identifier: str) -> float | None:
        entry = self._store.login_codes.get(identifier)
        return time.time() - entry["created_at"] if entry else None

    def use_login_code(self, identifier: str, code_hash: str) -> bool:
        entry = self._store.login_codes.get(identifier)
        # Count the attempt first so guessing burns tries even on mismatch; 5 max.
        if not entry or entry["expires_at"] < time.time() or entry["attempts"] >= 5:
            return False
        entry["attempts"] += 1
        ok = hmac.compare_digest(entry["hash"], code_hash)
        if ok:
            del self._store.login_codes[identifier]
        return ok
