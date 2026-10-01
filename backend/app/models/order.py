"""orders table. Line items are OrderItem rows; money is integer cents."""

from __future__ import annotations

from datetime import datetime
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .base import Base, IntId, TimestampedMixin, pg_enum
from .enums import Fulfillment, OrderStatus
from .user import User


class Order(Base, TimestampedMixin):
    __tablename__ = "orders"

    id: Mapped[int] = mapped_column(IntId, sa.Identity(), primary_key=True)
    # Human-facing order number; identity starts at 1001.
    number: Mapped[int] = mapped_column(sa.BigInteger, sa.Identity(start=1001))
    shop_id: Mapped[int] = mapped_column(IntId)
    # Null after the buyer deletes their account.
    buyer_user_id: Mapped[int | None] = mapped_column(IntId)
    # Null for PICKUP orders. Addresses are immutable, so no snapshot needed.
    shipping_address_id: Mapped[int | None] = mapped_column(IntId)
    subtotal_cents: Mapped[int] = mapped_column()
    shipping_cents: Mapped[int] = mapped_column(default=0, server_default=sa.text("0"))
    total_cents: Mapped[int] = mapped_column()
    currency: Mapped[str] = mapped_column(default="USD", server_default=sa.text("'USD'"))
    payment_id: Mapped[int | None] = mapped_column(IntId)
    # Short code the buyer shows at the counter; PICKUP orders only.
    pickup_code: Mapped[str | None] = mapped_column()
    cancelled_at: Mapped[datetime | None] = mapped_column(sa.DateTime(timezone=True))
    cancellation_reason: Mapped[str | None] = mapped_column()
    status: Mapped[OrderStatus] = mapped_column(
        pg_enum(OrderStatus, "order_status"), default=OrderStatus.PLACED, server_default=sa.text("'PLACED'")
    )
    # PICKUP orders have no shipment row.
    fulfillment: Mapped[Fulfillment] = mapped_column(
        pg_enum(Fulfillment, "fulfillment"), default=Fulfillment.SHIP, server_default=sa.text("'SHIP'")
    )

    buyer: Mapped[User | None] = relationship(primaryjoin="foreign(Order.buyer_user_id) == User.id", viewonly=True)

    # Set by OrderRepository on every instance it returns; not columns.
    items = ()
    next_actions = ()

    @property
    def total(self) -> float:
        return self.total_cents / 100
