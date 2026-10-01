"""products table."""

from __future__ import annotations

from decimal import Decimal
from typing import Any

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from .base import Base, IntId, TimestampedMixin
from .enums import ListingStatus


class Product(Base, TimestampedMixin):
    __tablename__ = "products"
    __table_args__ = (sa.CheckConstraint("quantity >= 0", name="products_quantity_check"),)

    id: Mapped[int] = mapped_column(IntId, sa.Identity(), primary_key=True)
    shop_id: Mapped[int] = mapped_column(IntId)
    category_id: Mapped[int] = mapped_column(IntId)
    name: Mapped[str] = mapped_column()
    description: Mapped[str | None] = mapped_column()
    # Keyed by ProductAttribute.key; ProductService validates against category_attributes.
    attributes: Mapped[dict[str, Any]] = mapped_column(JSONB, default=dict, server_default=sa.text("'{}'::jsonb"))
    price: Mapped[Decimal] = mapped_column(sa.Numeric)
    quantity: Mapped[int] = mapped_column(default=0, server_default=sa.text("0"))
    low_stock_threshold: Mapped[int] = mapped_column(default=5, server_default=sa.text("5"))
    active: Mapped[bool] = mapped_column(default=True, server_default=sa.text("true"))

    @property
    def status(self) -> ListingStatus:
        if not self.active:
            return ListingStatus.HIDDEN
        if self.quantity <= self.low_stock_threshold:
            return ListingStatus.LOW_STOCK
        return ListingStatus.IN_STOCK

    @staticmethod
    def status_is(status: ListingStatus) -> sa.ColumnElement[bool]:
        """SQL twin of `status`; keep the two in step."""
        low = Product.quantity <= Product.low_stock_threshold
        return {
            ListingStatus.HIDDEN: Product.active.is_(False),
            ListingStatus.LOW_STOCK: sa.and_(Product.active.is_(True), low),
            ListingStatus.IN_STOCK: sa.and_(Product.active.is_(True), sa.not_(low)),
        }[status]
