"""product_photos table."""

from __future__ import annotations

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from .base import Base, CreatedAtMixin, IntId

# Listing photo limits, enforced at the GraphQL boundary.
MAX_PRODUCT_PHOTOS = 6
MAX_PHOTO_BYTES = 700_000


class ProductPhoto(Base, CreatedAtMixin):
    __tablename__ = "product_photos"

    id: Mapped[int] = mapped_column(IntId, sa.Identity(), primary_key=True)
    product_id: Mapped[int] = mapped_column(IntId)
    position: Mapped[int] = mapped_column(default=0, server_default=sa.text("0"))  # 0 = cover
    data: Mapped[str] = mapped_column()  # whole data URL; fetched per listing only
