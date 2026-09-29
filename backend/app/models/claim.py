"""shop_claims table: seller applications, reviewed by support."""

from __future__ import annotations

from datetime import datetime
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .base import Base, CreatedAtMixin, IntId
from .user import User


class ShopClaim(Base, CreatedAtMixin):
    __tablename__ = "shop_claims"

    id: Mapped[int] = mapped_column(IntId, sa.Identity(), primary_key=True)
    shop_id: Mapped[int] = mapped_column(IntId)
    user_id: Mapped[int] = mapped_column(IntId)
    status: Mapped[str] = mapped_column(default="PENDING", server_default=sa.text("'PENDING'"))
    business_role: Mapped[str | None] = mapped_column()
    contact: Mapped[str | None] = mapped_column()
    website: Mapped[str | None] = mapped_column()
    note: Mapped[str | None] = mapped_column()
    resolved_at: Mapped[datetime | None] = mapped_column(sa.DateTime(timezone=True))

    user: Mapped[User | None] = relationship(primaryjoin="foreign(ShopClaim.user_id) == User.id", viewonly=True)
