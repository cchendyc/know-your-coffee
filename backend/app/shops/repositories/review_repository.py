"""reviews table access. One review per user per shop; a second submit replaces it."""

from datetime import UTC, datetime

import sqlalchemy as sa
from sqlalchemy.orm import contains_eager, sessionmaker

from ... import models as m


def _shop_reviews(shop_id: str):
    return sa.select(m.Review).outerjoin(m.Review.user).where(m.Review.shop_id == shop_id)


class ReviewRepository:
    def __init__(self, session: sessionmaker):
        self._session = session

    def list(self, shop_id: str, limit: int | None = None) -> list[m.Review]:
        stmt = (
            _shop_reviews(shop_id)
            .options(contains_eager(m.Review.user))
            .order_by(m.Review.created_at.desc())
            .limit(limit)
        )
        with self._session() as s:
            return list(s.scalars(stmt))

    def summary(self, shop_id: str) -> tuple[int, float | None]:
        with self._session() as s:
            count, average = s.execute(
                sa.select(sa.func.count(), sa.func.avg(m.Review.rating)).where(m.Review.shop_id == shop_id)
            ).one()
        return int(count), (float(average) if average is not None else None)

    def for_user(self, shop_id: str, user_id: str) -> m.Review | None:
        stmt = (
            _shop_reviews(shop_id)
            .where(m.Review.user_id == user_id)
            .options(contains_eager(m.Review.user))
        )
        with self._session() as s:
            return s.scalars(stmt).first()

    def upsert(self, shop_id: str, user_id: str, rating: int, body: str | None) -> m.Review:
        with self._session.begin() as s:
            row = s.scalars(
                sa.select(m.Review).where(m.Review.shop_id == shop_id, m.Review.user_id == user_id)
            ).first()
            if row:
                row.rating = rating
                row.body = body
                row.updated_at = datetime.now(UTC)
            else:
                row = m.Review(shop_id=shop_id, user_id=user_id, rating=rating, body=body)
                s.add(row)
            s.flush()
            s.refresh(row)
            _ = row.user
            return row
