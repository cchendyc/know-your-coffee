"""shipments table: one package per order, created with the order."""

from __future__ import annotations

from datetime import date, datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .base import Base, IntId, TimestampedMixin, pg_enum
from .enums import Carrier, ShipmentStatus
from .order import Order


class Shipment(Base, TimestampedMixin):
    __tablename__ = "shipments"

    id: Mapped[int] = mapped_column(IntId, sa.Identity(), primary_key=True)
    order_id: Mapped[int] = mapped_column(IntId, unique=True)
    carrier: Mapped[Carrier | None] = mapped_column(pg_enum(Carrier, "carrier"))
    tracking: Mapped[str | None] = mapped_column()
    ship_by: Mapped[date | None] = mapped_column()  # purchase date + 2 days
    status: Mapped[ShipmentStatus] = mapped_column(
        pg_enum(ShipmentStatus, "shipment_status"),
        default=ShipmentStatus.LABEL_READY,
        server_default=sa.text("'LABEL_READY'"),
    )
    label_url: Mapped[str | None] = mapped_column()
    cost_cents: Mapped[int | None] = mapped_column()
    # Raw carrier status string; `status` is our normalized state.
    tracking_status: Mapped[str | None] = mapped_column()
    dropped_off_at: Mapped[datetime | None] = mapped_column(sa.DateTime(timezone=True))
    delivered_at: Mapped[datetime | None] = mapped_column(sa.DateTime(timezone=True))

    order: Mapped[Order] = relationship(primaryjoin="foreign(Shipment.order_id) == Order.id", viewonly=True)
