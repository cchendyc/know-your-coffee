"""Shipments for SHIP orders."""

import sqlalchemy as sa
from sqlalchemy.orm import sessionmaker

from ... import models as m
from ...core.db import fetch_page, now
from ...models.enums import SHIPMENT_TO_ORDER_STATUS, ShipmentStatus


class ShipmentRepository:
    def __init__(self, session: sessionmaker):
        self._session = session

    def get(self, shipment_id: str) -> m.Shipment | None:
        with self._session() as s:
            return s.get(m.Shipment, shipment_id)

    def for_order(self, order_id: str) -> m.Shipment | None:
        with self._session() as s:
            return s.scalars(sa.select(m.Shipment).where(m.Shipment.order_id == order_id)).first()

    def page_for_shops(
        self, shop_ids: list[str], status: ShipmentStatus | None, limit: int, offset: int
    ) -> tuple[list[m.Shipment], int]:
        """Shipments across several shops (a multi-shop seller), soonest ship-by first."""
        if not shop_ids:
            return [], 0
        stmt = sa.select(m.Shipment).join(m.Shipment.order).where(m.Order.shop_id.in_(shop_ids))
        if status:
            stmt = stmt.where(m.Shipment.status == status)
        stmt = stmt.order_by(
            m.Shipment.ship_by.asc().nulls_last(), m.Shipment.created_at.desc(), m.Shipment.id.desc()
        )
        return fetch_page(self._session, stmt, limit, offset)

    def count_for_shops(self, shop_ids: list[str], statuses: tuple[ShipmentStatus, ...]) -> int:
        if not shop_ids:
            return 0
        stmt = (
            sa.select(sa.func.count())
            .select_from(m.Shipment)
            .join(m.Shipment.order)
            .where(m.Order.shop_id.in_(shop_ids), m.Shipment.status.in_(statuses))
        )
        with self._session() as s:
            return s.scalar(stmt) or 0

    def update(self, shipment_id: str, changes: dict, actor_user_id: str | None = None) -> m.Shipment | None:
        """changes: carrier, tracking, status. A status change syncs the order."""
        if not changes:
            return self.get(shipment_id)
        with self._session.begin() as s:
            row = s.get(m.Shipment, shipment_id)
            if not row:
                return None
            for column, value in changes.items():
                setattr(row, column, value)
            row.updated_at = now()
            if changes.get("status") is ShipmentStatus.IN_TRANSIT:
                row.dropped_off_at = now()
            if changes.get("status") is ShipmentStatus.DELIVERED:
                row.delivered_at = now()
            order_status = SHIPMENT_TO_ORDER_STATUS.get(changes.get("status"))
            if order_status:
                moved = s.execute(
                    sa.update(m.Order)
                    .where(m.Order.id == row.order_id, m.Order.status != order_status)
                    .values(status=order_status, updated_at=sa.func.now())
                    .returning(m.Order.id)
                ).first()
                if moved:
                    s.add(m.OrderEvent(order_id=row.order_id, status=order_status, actor_user_id=actor_user_id))
            return row
