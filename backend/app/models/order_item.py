"""order_items and order_events tables.

order_items snapshots name, subtitle and unit price at purchase so deleting
or editing a product never changes history. shipment_id is set when the
item is packed into a shipment. order_events is the append-only status
timeline shown on the order detail page."""

from __future__ import annotations

from datetime import datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from .base import Base, CreatedAtMixin, IntId, pg_enum
from .enums import OrderStatus


class OrderItem(Base, CreatedAtMixin):
    __tablename__ = "order_items"
    __table_args__ = (sa.CheckConstraint("quantity > 0", name="order_items_quantity_check"),)

    id: Mapped[int] = mapped_column(IntId, sa.Identity(), primary_key=True)
    order_id: Mapped[int] = mapped_column(IntId)
    product_id: Mapped[int] = mapped_column(IntId)
    name: Mapped[str] = mapped_column()
    subtitle: Mapped[str | None] = mapped_column()
    unit_price_cents: Mapped[int] = mapped_column()
    quantity: Mapped[int] = mapped_column()
    shipment_id: Mapped[int | None] = mapped_column(IntId)


class OrderEvent(Base):
    __tablename__ = "order_events"

    id: Mapped[int] = mapped_column(IntId, sa.Identity(), primary_key=True)
    order_id: Mapped[int] = mapped_column(IntId)
    status: Mapped[OrderStatus] = mapped_column(pg_enum(OrderStatus, "order_status"))
    # Null for system events (carrier scans, auto-cancel).
    actor_user_id: Mapped[int | None] = mapped_column(IntId)
    note: Mapped[str | None] = mapped_column()
    created_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), server_default=sa.text("now()"))
