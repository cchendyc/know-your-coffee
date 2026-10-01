"""users and login_codes tables."""

from __future__ import annotations

from datetime import datetime
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from .base import Base, CreatedAtMixin, IntId


class User(Base, CreatedAtMixin):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(IntId, sa.Identity(), primary_key=True)
    google_sub: Mapped[str | None] = mapped_column(unique=True)
    apple_sub: Mapped[str | None] = mapped_column(unique=True)
    email: Mapped[str | None] = mapped_column(unique=True)
    phone: Mapped[str | None] = mapped_column(unique=True)  # E.164, for phone OTP accounts
    name: Mapped[str] = mapped_column()
    picture: Mapped[str | None] = mapped_column()
    role: Mapped[str] = mapped_column(default="USER", server_default=sa.text("'USER'"))
    # Stripe Customer; created lazily on first saved payment method.
    stripe_customer_id: Mapped[str | None] = mapped_column(unique=True)

# One active sign-in code per email/phone; attempts capped at 5.
class LoginCode(Base, CreatedAtMixin):
    __tablename__ = "login_codes"

    identifier: Mapped[str] = mapped_column(primary_key=True)
    code_hash: Mapped[str] = mapped_column()
    attempts: Mapped[int] = mapped_column(default=0, server_default=sa.text("0"))
    expires_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True))
