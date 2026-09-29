"""shop_bookmarks table. A row means the user bookmarked the shop; un-bookmarking
deletes it."""

from __future__ import annotations

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, declared_attr, mapped_column

from .base import Base, CreatedAtMixin, IntId


class ShopBookmark(Base, CreatedAtMixin):
    __tablename__ = "shop_bookmarks"

    user_id: Mapped[int] = mapped_column(IntId, primary_key=True)
    shop_id: Mapped[int] = mapped_column(IntId, primary_key=True)

    @declared_attr.directive
    @classmethod
    def __table_args__(cls) -> tuple:
        return (
            # "My bookmarks, newest first".
            sa.Index("shop_bookmarks_user_created", cls.user_id, cls.created_at.desc()),
            # Per-shop counts and delete_shop cleanup.
            sa.Index("shop_bookmarks_shop", cls.shop_id),
        )
