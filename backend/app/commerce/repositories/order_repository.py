"""Orders with their line items and status timeline.

SHIP orders get a shipment at creation; PICKUP orders never have one. Every
status change appends an order_events row. Orders returned from here carry
`items` (list[OrderItem]) attached."""

from datetime import timedelta

import sqlalchemy as sa
from sqlalchemy.orm import contains_eager, sessionmaker

from ... import models as m
from ...core.db import fetch_page, now
from ...core.errors import OutOfStockError
from ...models.enums import (
    CANCELABLE_STATUSES,
    ORDER_TO_SHIPMENT_STATUS,
    Fulfillment,
    OrderStatus,
    ShipmentStatus,
)


def order_stmt():
    return sa.select(m.Order).outerjoin(m.Order.buyer).options(contains_eager(m.Order.buyer))


class OrderRepository:
    def __init__(self, session: sessionmaker):
        self._session = session

    def _attach_items(self, s, orders: list[m.Order]) -> list[m.Order]:
        if not orders:
            return orders
        ids = [o.id for o in orders]
        rows = s.scalars(
            sa.select(m.OrderItem).where(m.OrderItem.order_id.in_(ids)).order_by(m.OrderItem.id)
        ).all()
        by_order: dict[int, list[m.OrderItem]] = {}
        for row in rows:
            by_order.setdefault(row.order_id, []).append(row)
        for order in orders:
            order.items = by_order.get(order.id, [])
        return orders

    def create(
        self,
        shop_id: str,
        buyer_user_id: str,
        lines: list[dict],
        fulfillment: Fulfillment,
        *,
        subtotal_cents: int,
        shipping_cents: int,
        shipping_address_id: str | None,
        ships_within_days: int,
        pickup_code: str | None,
    ) -> m.Order:
        """lines: dicts with product_id, name, subtitle, unit_price_cents, quantity."""
        # One transaction: an out-of-stock line rolls back earlier decrements.
        with self._session.begin() as s:
            for line in lines:
                row = s.execute(
                    sa.update(m.Product)
                    .where(m.Product.id == line["product_id"], m.Product.quantity >= line["quantity"])
                    .values(quantity=m.Product.quantity - line["quantity"], updated_at=sa.func.now())
                    .returning(m.Product.id)
                ).first()
                if not row:
                    raise OutOfStockError(line["name"])
            order = m.Order(
                shop_id=shop_id,
                buyer_user_id=buyer_user_id,
                fulfillment=fulfillment,
                subtotal_cents=subtotal_cents,
                shipping_cents=shipping_cents,
                total_cents=subtotal_cents + shipping_cents,
                shipping_address_id=shipping_address_id,
                pickup_code=pickup_code,
            )
            s.add(order)
            s.flush()
            for line in lines:
                s.add(m.OrderItem(order_id=order.id, **line))
            s.add(m.OrderEvent(order_id=order.id, status=OrderStatus.PLACED, actor_user_id=buyer_user_id))
            if fulfillment is Fulfillment.SHIP:
                s.add(m.Shipment(order_id=order.id, ship_by=(now() + timedelta(days=ships_within_days)).date()))
            order_id = str(order.id)
        result = self.get(order_id)
        assert result is not None
        return result

    def get(self, order_id: str) -> m.Order | None:
        with self._session() as s:
            order = s.scalars(order_stmt().where(m.Order.id == order_id)).first()
            return self._attach_items(s, [order])[0] if order else None

    def events(self, order_id: str) -> list[m.OrderEvent]:
        stmt = sa.select(m.OrderEvent).where(m.OrderEvent.order_id == order_id).order_by(m.OrderEvent.created_at, m.OrderEvent.id)
        with self._session() as s:
            return list(s.scalars(stmt))

    def page_for_shops(
        self, shop_ids: list[str], statuses: OrderStatus | tuple[OrderStatus, ...] | None, limit: int, offset: int
    ) -> tuple[list[m.Order], int]:
        """Orders across several shops (a multi-shop seller), newest first."""
        if isinstance(statuses, OrderStatus):
            statuses = (statuses,)
        if not shop_ids:
            return [], 0
        stmt = order_stmt().where(m.Order.shop_id.in_(shop_ids))
        if statuses:
            stmt = stmt.where(m.Order.status.in_(statuses))
        stmt = stmt.order_by(m.Order.created_at.desc(), m.Order.id.desc())
        rows, total = fetch_page(self._session, stmt, limit, offset)
        with self._session() as s:
            return self._attach_items(s, rows), total

    def count_for_shops(self, shop_ids: list[str], statuses: tuple[OrderStatus, ...]) -> int:
        if not shop_ids:
            return 0
        stmt = sa.select(sa.func.count()).where(m.Order.shop_id.in_(shop_ids), m.Order.status.in_(statuses))
        with self._session() as s:
            return s.scalar(stmt) or 0

    def count_by_status(self, shop_ids: list[str]) -> dict[OrderStatus, int]:
        counts = dict.fromkeys(OrderStatus, 0)
        if not shop_ids:
            return counts
        stmt = (
            sa.select(m.Order.status, sa.func.count())
            .where(m.Order.shop_id.in_(shop_ids))
            .group_by(m.Order.status)
        )
        with self._session() as s:
            for status, n in s.execute(stmt):
                counts[status] = n
        return counts

    def list_purchases(self, buyer_user_id: str) -> list[m.Order]:
        stmt = order_stmt().where(m.Order.buyer_user_id == buyer_user_id).order_by(m.Order.created_at.desc())
        with self._session() as s:
            return self._attach_items(s, list(s.scalars(stmt)))

    def cancel(self, order_id: str, actor_user_id: str | None = None, reason: str | None = None) -> m.Order | None:
        with self._session.begin() as s:
            row = s.execute(
                sa.update(m.Order)
                .where(m.Order.id == order_id, m.Order.status.in_(CANCELABLE_STATUSES))
                .values(
                    status=OrderStatus.CANCELED,
                    cancelled_at=sa.func.now(),
                    cancellation_reason=reason,
                    updated_at=sa.func.now(),
                )
                .returning(m.Order.id)
            ).first()
            if not row:
                return None
            items = s.scalars(sa.select(m.OrderItem).where(m.OrderItem.order_id == order_id)).all()
            for item in items:
                s.execute(
                    sa.update(m.Product)
                    .where(m.Product.id == item.product_id)
                    .values(quantity=m.Product.quantity + item.quantity, updated_at=sa.func.now())
                )
            s.execute(sa.delete(m.Shipment).where(m.Shipment.order_id == order_id))
            s.add(m.OrderEvent(order_id=int(order_id), status=OrderStatus.CANCELED, actor_user_id=actor_user_id, note=reason))
        return self.get(order_id)

    def transition(
        self,
        order_id: str,
        from_status: OrderStatus,
        to_status: OrderStatus,
        actor_user_id: str | None = None,
        shipment_changes: dict | None = None,
    ) -> m.Order | None:
        """Move an order one step and keep its shipment in sync.

        shipment_changes: carrier / tracking to set at the same time."""
        with self._session.begin() as s:
            row = s.execute(
                sa.update(m.Order)
                .where(m.Order.id == order_id, m.Order.status == from_status)
                .values(status=to_status, updated_at=sa.func.now())
                .returning(m.Order.id)
            ).first()
            if not row:
                return None
            s.add(m.OrderEvent(order_id=int(order_id), status=to_status, actor_user_id=actor_user_id))
            shipment = s.scalars(sa.select(m.Shipment).where(m.Shipment.order_id == order_id)).first()
            if shipment:
                for column, value in (shipment_changes or {}).items():
                    setattr(shipment, column, value)
                shipment_status = ORDER_TO_SHIPMENT_STATUS.get(to_status)
                if shipment_status:
                    shipment.status = shipment_status
                    if shipment_status is ShipmentStatus.IN_TRANSIT:
                        shipment.dropped_off_at = now()
                    if shipment_status is ShipmentStatus.DELIVERED:
                        shipment.delivered_at = now()
                shipment.updated_at = now()
        return self.get(order_id)
