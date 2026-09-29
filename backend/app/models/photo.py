"""shop_photos table."""

from __future__ import annotations

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .base import Base, CreatedAtMixin, IntId
from .user import User


class ShopPhoto(Base, CreatedAtMixin):
    __tablename__ = "shop_photos"

    id: Mapped[int] = mapped_column(IntId, sa.Identity(), primary_key=True)
    shop_id: Mapped[int] = mapped_column(IntId)
    # Null after the uploader deletes their account.
    user_id: Mapped[int | None] = mapped_column(IntId)
    kind: Mapped[str] = mapped_column()
    data: Mapped[str] = mapped_column()  # whole base64 image; detail screen only

    user: Mapped[User | None] = relationship(primaryjoin="foreign(ShopPhoto.user_id) == User.id", viewonly=True)
