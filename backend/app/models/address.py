"""addresses table. Rows are immutable once an order references them: an
edit inserts a new row and soft-deletes the old one."""

from __future__ import annotations

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from .base import Base, CreatedAtMixin, IntId


class Address(Base, CreatedAtMixin):
    __tablename__ = "addresses"

    id: Mapped[int] = mapped_column(IntId, sa.Identity(), primary_key=True)
    user_id: Mapped[int] = mapped_column(IntId)
    full_name: Mapped[str] = mapped_column()
    line1: Mapped[str] = mapped_column()
    line2: Mapped[str | None] = mapped_column()
    city: Mapped[str] = mapped_column()
    state: Mapped[str] = mapped_column()
    postal_code: Mapped[str] = mapped_column()
    country_code: Mapped[str] = mapped_column(default="US", server_default=sa.text("'US'"))
    phone: Mapped[str | None] = mapped_column()
    is_default: Mapped[bool] = mapped_column(default=False, server_default=sa.text("false"))
    deleted: Mapped[bool] = mapped_column(default=False, server_default=sa.text("false"))
