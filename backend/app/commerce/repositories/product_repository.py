"""Seller storefront products."""

import sqlalchemy as sa
from sqlalchemy.orm import sessionmaker

from ... import models as m
from ...core.db import fetch_page, now


class ProductRepository:
    def __init__(self, session: sessionmaker):
        self._session = session

    def list(
        self, shop_id: str, include_inactive: bool = False, status: m.ListingStatus | None = None
    ) -> list[m.Product]:
        stmt = sa.select(m.Product).where(m.Product.shop_id == shop_id)
        if not include_inactive:
            stmt = stmt.where(m.Product.active.is_(True))
        if status:
            stmt = stmt.where(m.Product.status_is(status))
        with self._session() as s:
            return list(s.scalars(stmt.order_by(m.Product.created_at.asc())))

    def page(
        self, shop_id: str, status: m.ListingStatus | None, limit: int, offset: int
    ) -> tuple[list[m.Product], int]:
        """Seller view, hidden listings included, oldest first."""
        stmt = sa.select(m.Product).where(m.Product.shop_id == shop_id)
        if status:
            stmt = stmt.where(m.Product.status_is(status))
        stmt = stmt.order_by(m.Product.created_at.asc(), m.Product.id.asc())
        return fetch_page(self._session, stmt, limit, offset)

    def status_counts(self, shop_id: str) -> dict[m.ListingStatus, int]:
        cols = [sa.func.count().filter(m.Product.status_is(st)) for st in m.ListingStatus]
        with self._session() as s:
            row = s.execute(sa.select(*cols).where(m.Product.shop_id == shop_id)).one()
        return dict(zip(m.ListingStatus, row))

    def count_for_shops(self, shop_ids: list[str], status: m.ListingStatus) -> int:
        if not shop_ids:
            return 0
        stmt = sa.select(sa.func.count()).where(m.Product.shop_id.in_(shop_ids), m.Product.status_is(status))
        with self._session() as s:
            return s.scalar(stmt) or 0

    def get(self, product_id: str) -> m.Product | None:
        with self._session() as s:
            return s.get(m.Product, product_id)

    def create(self, shop_id: str, values: dict) -> m.Product:
        """values: products column names -> values; unset columns get defaults."""
        defaults = {"stock_qty": 0, "low_stock_threshold": 5, "active": True}
        with self._session.begin() as s:
            row = m.Product(shop_id=shop_id, **{**defaults, **values})
            s.add(row)
            s.flush()
            s.refresh(row)  # load created_at/updated_at before the row detaches
            return row

    def update(self, product_id: str, changes: dict) -> m.Product | None:
        """Patch semantics: only the columns in changes are touched."""
        if not changes:
            return self.get(product_id)
        with self._session.begin() as s:
            row = s.get(m.Product, product_id)
            if not row:
                return None
            for column, value in changes.items():
                setattr(row, column, value)
            row.updated_at = now()
            return row

    def delete(self, product_id: str) -> bool:
        # No FK constraints: drop the listing's photos in the same transaction.
        with self._session.begin() as s:
            s.execute(sa.delete(m.ProductPhoto).where(m.ProductPhoto.product_id == product_id))
            row = s.execute(
                sa.delete(m.Product).where(m.Product.id == product_id).returning(m.Product.id)
            ).first()
        return bool(row)
