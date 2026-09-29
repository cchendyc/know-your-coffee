"""Orders. SHIP orders get a shipment at creation; PICKUP orders never have one.

Order item snapshots are stored jsonb with camelCase keys (productId,
unitPrice); that shape is shared with existing rows."""

from datetime import timedelta

import sqlalchemy as sa
from sqlalchemy.orm import contains_eager, sessionmaker

from ... import models as m
from ...core.db import fetch_page, now
from ...core.errors import OutOfStockError
from ...models.enums import CANCELABLE_STATUSES, Fulfillment, OrderStatus


def order_stmt():
    return sa.select(m.Order).outerjoin(m.Order.buyer).options(contains_eager(m.Order.buyer))


class OrderRepository:
    def __init__(self, session: sessionmaker):
        self._session = session

    def create(
        self,
        shop_id: str,
        buyer_user_id: str,
        items: list[dict],
        total: float,
        fulfillment: Fulfillment,
    ) -> m.Order:
        # One transaction: an out-of-stock line rolls back earlier decrements.
        with self._session.begin() as s:
            for item in items:
                row = s.execute(
                    sa.update(m.Product)
                    .where(m.Product.id == item["productId"], m.Product.stock_qty >= item["qty"])
                    .values(stock_qty=m.Product.stock_qty - item["qty"], updated_at=sa.func.now())
                    .returning(m.Product.id)
                ).first()
                if not row:
                    raise OutOfStockError(item["name"])
            order = m.Order(
                shop_id=shop_id,
                buyer_user_id=buyer_user_id,
                items=items,
                total=total,
                fulfillment=fulfillment,
            )
            s.add(order)
            s.flush()
            if fulfillment is Fulfillment.SHIP:
                s.add(m.Shipment(order_id=order.id, ship_by=(now() + timedelta(days=2)).date()))
            order_id = str(order.id)
        result = self.get(order_id)
        assert result is not None
        return result

    def get(self, order_id: str) -> m.Order | None:
        with self._session() as s:
            return s.scalars(order_stmt().where(m.Order.id == order_id)).first()

    def page_for_shops(
        self, shop_ids: list[str], status: OrderStatus | None, limit: int, offset: int
    ) -> tuple[list[m.Order], int]:
        """Orders across several shops (a multi-shop seller), newest first."""
        if not shop_ids:
            return [], 0
        stmt = order_stmt().where(m.Order.shop_id.in_(shop_ids))
        if status:
            stmt = stmt.where(m.Order.status == status)
        stmt = stmt.order_by(m.Order.created_at.desc(), m.Order.id.desc())
        return fetch_page(self._session, stmt, limit, offset)

    def count_for_shops(self, shop_ids: list[str], statuses: tuple[OrderStatus, ...]) -> int:
        if not shop_ids:
            return 0
        stmt = sa.select(sa.func.count()).where(m.Order.shop_id.in_(shop_ids), m.Order.status.in_(statuses))
        with self._session() as s:
            return s.scalar(stmt) or 0

    def list_purchases(self, buyer_user_id: str) -> list[m.Order]:
        stmt = order_stmt().where(m.Order.buyer_user_id == buyer_user_id)
        with self._session() as s:
            return list(s.scalars(stmt.order_by(m.Order.created_at.desc())))

    def cancel(self, order_id: str) -> m.Order | None:
        with self._session.begin() as s:
            row = s.execute(
                sa.update(m.Order)
                .where(m.Order.id == order_id, m.Order.status.in_(CANCELABLE_STATUSES))
                .values(status=OrderStatus.CANCELED)
                .returning(m.Order.items)
            ).first()
            if not row:
                return None
            for item in row[0]:
                s.execute(
                    sa.update(m.Product)
                    .where(m.Product.id == item["productId"])
                    .values(stock_qty=m.Product.stock_qty + item["qty"], updated_at=sa.func.now())
                )
            s.execute(sa.delete(m.Shipment).where(m.Shipment.order_id == order_id))
        return self.get(order_id)

    def transition(self, order_id: str, from_status: OrderStatus, to_status: OrderStatus) -> m.Order | None:
        with self._session.begin() as s:
            row = s.execute(
                sa.update(m.Order)
                .where(m.Order.id == order_id, m.Order.status == from_status)
                .values(status=to_status)
                .returning(m.Order.id)
            ).first()
        return self.get(order_id) if row else None
