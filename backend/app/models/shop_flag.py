"""shop_flags: a person reporting that a shop breaks the rules.

Separate from reports, which are community updates about the bar.
"""

from __future__ import annotations

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from .base import Base, CreatedAtMixin, IntId


class ShopFlag(Base, CreatedAtMixin):
    __tablename__ = "shop_flags"

    id: Mapped[int] = mapped_column(IntId, sa.Identity(), primary_key=True)
    shop_id: Mapped[int] = mapped_column(IntId)
    # Null after the reporter deletes their account. The flag stays.
    user_id: Mapped[int | None] = mapped_column(IntId)
    reason: Mapped[str] = mapped_column()

    __table_args__ = (
        sa.Index("shop_flags_shop", "shop_id"),
        sa.Index(
            "shop_flags_shop_user",
            "shop_id",
            "user_id",
            unique=True,
            postgresql_where=sa.text("user_id IS NOT NULL"),
        ),
    )
