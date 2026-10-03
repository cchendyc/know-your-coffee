"""reviews table. One row per signed-in user per shop.

A later pass can badge reviews from a delivered order on this site.
That check is not stored here, and it does not gate who can review.
"""

from __future__ import annotations

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .base import Base, IntId, TimestampedMixin
from .user import User


class Review(Base, TimestampedMixin):
    __tablename__ = "reviews"

    id: Mapped[int] = mapped_column(IntId, sa.Identity(), primary_key=True)
    shop_id: Mapped[int] = mapped_column(IntId)
    # Null after the author deletes their account. The review stays.
    user_id: Mapped[int | None] = mapped_column(IntId)
    rating: Mapped[int] = mapped_column(sa.SmallInteger)
    body: Mapped[str | None] = mapped_column(sa.Text)

    user: Mapped[User | None] = relationship(primaryjoin="foreign(Review.user_id) == User.id", viewonly=True)

    __table_args__ = (
        sa.CheckConstraint("rating BETWEEN 1 AND 5", name="reviews_rating_check"),
        sa.Index("reviews_shop_created", "shop_id", sa.text("created_at DESC")),
        sa.Index(
            "reviews_shop_user",
            "shop_id",
            "user_id",
            unique=True,
            postgresql_where=sa.text("user_id IS NOT NULL"),
        ),
    )
