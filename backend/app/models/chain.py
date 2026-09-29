"""chains table: shops clustered under one brand, rebuilt by relink_chains."""

from __future__ import annotations

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from .base import Base, CreatedAtMixin, IntId


class Chain(Base, CreatedAtMixin):
    __tablename__ = "chains"

    id: Mapped[int] = mapped_column(IntId, sa.Identity(), primary_key=True)
    name: Mapped[str] = mapped_column()
    slug: Mapped[str] = mapped_column(unique=True)
    website: Mapped[str | None] = mapped_column()
