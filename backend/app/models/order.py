"""orders table. Line items live on the order as jsonb snapshots (name and
unitPrice at purchase time), so deleting a product never breaks history."""

from __future__ import annotations

from decimal import Decimal
from typing import Any

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .base import Base, CreatedAtMixin, IntId, pg_enum
from .enums import Fulfillment, OrderStatus
from .user import User


class Order(Base, CreatedAtMixin):
    __tablename__ = "orders"

    id: Mapped[int] = mapped_column(IntId, sa.Identity(), primary_key=True)
    # Human-facing order number; identity starts at 1001.
    number: Mapped[int] = mapped_column(sa.BigInteger, sa.Identity(start=1001))
    shop_id: Mapped[int] = mapped_column(IntId)
    # Null after the buyer deletes their account.
    buyer_user_id: Mapped[int | None] = mapped_column(IntId)
    items: Mapped[list[Any]] = mapped_column(JSONB)
    total: Mapped[Decimal] = mapped_column(sa.Numeric)
    status: Mapped[OrderStatus] = mapped_column(
        pg_enum(OrderStatus, "order_status"), default=OrderStatus.PLACED, server_default=sa.text("'PLACED'")
    )
    # PICKUP orders have no shipment row.
    fulfillment: Mapped[Fulfillment] = mapped_column(
        pg_enum(Fulfillment, "fulfillment"), default=Fulfillment.SHIP, server_default=sa.text("'SHIP'")
    )

    buyer: Mapped[User | None] = relationship(primaryjoin="foreign(Order.buyer_user_id) == User.id", viewonly=True)
