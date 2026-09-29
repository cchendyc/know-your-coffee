"""shipments table: one package per order, created with the order."""

from __future__ import annotations

from datetime import date
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .base import Base, IntId, TimestampedMixin, pg_enum
from .enums import ShipmentStatus
from .order import Order


class Shipment(Base, TimestampedMixin):
    __tablename__ = "shipments"

    id: Mapped[int] = mapped_column(IntId, sa.Identity(), primary_key=True)
    order_id: Mapped[int] = mapped_column(IntId, unique=True)
    carrier: Mapped[str | None] = mapped_column()
    tracking: Mapped[str | None] = mapped_column()
    ship_by: Mapped[date | None] = mapped_column()  # purchase date + 2 days
    status: Mapped[ShipmentStatus] = mapped_column(
        pg_enum(ShipmentStatus, "shipment_status"),
        default=ShipmentStatus.LABEL_READY,
        server_default=sa.text("'LABEL_READY'"),
    )

    order: Mapped[Order] = relationship(primaryjoin="foreign(Shipment.order_id) == Order.id", viewonly=True)
