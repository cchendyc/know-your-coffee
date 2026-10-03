"""User accounts and one-time login codes."""

import hmac

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import sessionmaker

from ... import models as m
from ...core.errors import DuplicateEmailError


class UserRepository:
    def __init__(self, session: sessionmaker):
        self._session = session

    def get(self, user_id: str) -> m.User | None:
        with self._session() as s:
            return s.get(m.User, user_id)

    def upsert_google_user(self, sub: str, email: str, name: str, picture: str | None, role: str | None) -> m.User:
        # Role only ever escalates here (ADMIN_EMAILS bootstrap); sign-in never demotes.
        email = email.lower()
        try:
            with self._session.begin() as s:
                row = s.scalars(sa.select(m.User).where(m.User.google_sub == sub)).first()
                if not row:
                    row = s.scalars(sa.select(m.User).where(sa.func.lower(m.User.email) == email)).first()
                    if row and row.google_sub and row.google_sub != sub:
                        raise DuplicateEmailError()
                if row:
                    row.google_sub = sub
                    row.email = email
                    row.name = name
                    row.picture = picture
                    if role == "ADMIN":
                        row.role = "ADMIN"
                else:
                    row = m.User(google_sub=sub, email=email, name=name, picture=picture, role=role or "USER")
                    s.add(row)
                    s.flush()
                return row
        except IntegrityError:
            raise DuplicateEmailError()

    def upsert_phone_user(self, phone: str, name: str) -> m.User:
        # The no-op SET makes RETURNING work for existing rows; their name is kept.
        stmt = pg_insert(m.User).values(phone=phone, name=name)
        stmt = stmt.on_conflict_do_update(
            index_elements=[m.User.phone], set_={"phone": stmt.excluded.phone}
        ).returning(m.User.id)
        with self._session.begin() as s:
            user_id = s.execute(stmt).scalar_one()
            user = s.get(m.User, user_id)
            assert user is not None
            return user

    def upsert_email_user(self, email: str, name: str) -> m.User:
        email = email.lower()
        with self._session.begin() as s:
            row = s.scalars(sa.select(m.User).where(sa.func.lower(m.User.email) == email)).first()
            if row:
                return row
        try:
            with self._session.begin() as s:
                row = m.User(email=email, name=name)
                s.add(row)
                s.flush()
                return row
        except IntegrityError:
            # Lost the race to a concurrent first sign-in with the same email.
            with self._session() as s:
                row = s.scalars(sa.select(m.User).where(sa.func.lower(m.User.email) == email)).first()
                if row:
                    return row
                raise DuplicateEmailError()

    def upsert_apple_user(self, apple_sub: str, email: str | None, name: str) -> m.User:
        email = email.lower() if email else None
        try:
            with self._session.begin() as s:
                row = s.scalars(sa.select(m.User).where(m.User.apple_sub == apple_sub)).first()
                if row:
                    return row
                if email:
                    row = s.scalars(sa.select(m.User).where(sa.func.lower(m.User.email) == email)).first()
                    if row:
                        if row.apple_sub and row.apple_sub != apple_sub:
                            raise DuplicateEmailError()
                        row.apple_sub = apple_sub
                        return row
                row = m.User(apple_sub=apple_sub, email=email, name=name)
                s.add(row)
                s.flush()
                return row
        except IntegrityError:
            raise DuplicateEmailError()

    def delete(self, user_id: str) -> bool:
        # Contributions stay, anonymized; ownership and personal edges go.
        with self._session.begin() as s:
            s.execute(sa.update(m.Report).where(m.Report.user_id == user_id).values(user_id=None))
            s.execute(sa.update(m.Review).where(m.Review.user_id == user_id).values(user_id=None))
            s.execute(sa.update(m.ShopPhoto).where(m.ShopPhoto.user_id == user_id).values(user_id=None))
            s.execute(sa.update(m.Order).where(m.Order.buyer_user_id == user_id).values(buyer_user_id=None))
            s.execute(sa.update(m.Shop).where(m.Shop.owner_user_id == user_id).values(owner_user_id=None))
            for model in (m.ShopClaim, m.ShopBookmark, m.ShopVisit):
                s.execute(sa.delete(model).where(model.user_id == user_id))
            row = s.execute(sa.delete(m.User).where(m.User.id == user_id).returning(m.User.id)).first()
        return bool(row)

    # -------------------------------------------------------- login codes

    def save_login_code(self, identifier: str, code_hash: str, ttl_seconds: int) -> None:
        expires = sa.func.now() + sa.func.make_interval(0, 0, 0, 0, 0, 0, ttl_seconds)
        stmt = pg_insert(m.LoginCode).values(identifier=identifier, code_hash=code_hash, expires_at=expires)
        stmt = stmt.on_conflict_do_update(
            index_elements=[m.LoginCode.identifier],
            set_={"code_hash": code_hash, "attempts": 0, "expires_at": expires, "created_at": sa.func.now()},
        )
        with self._session.begin() as s:
            s.execute(stmt)

    def login_code_age(self, identifier: str) -> float | None:
        with self._session() as s:
            age = s.scalar(
                sa.select(sa.func.extract("epoch", sa.func.now() - m.LoginCode.created_at)).where(
                    m.LoginCode.identifier == identifier
                )
            )
            return float(age) if age is not None else None

    def use_login_code(self, identifier: str, code_hash: str) -> bool:
        # Count the attempt first so guessing burns tries even on mismatch; 5 max.
        with self._session.begin() as s:
            row = s.execute(
                sa.update(m.LoginCode)
                .where(
                    m.LoginCode.identifier == identifier,
                    m.LoginCode.expires_at > sa.func.now(),
                    m.LoginCode.attempts < 5,
                )
                .values(attempts=m.LoginCode.attempts + 1)
                .returning(m.LoginCode.code_hash)
            ).first()
            ok = bool(row) and hmac.compare_digest(row[0], code_hash)
            if ok:
                s.execute(sa.delete(m.LoginCode).where(m.LoginCode.identifier == identifier))
        return ok
