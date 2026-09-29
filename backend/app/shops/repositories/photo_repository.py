"""shop_photos table access."""

import sqlalchemy as sa
from sqlalchemy.orm import contains_eager, sessionmaker

from ... import models as m


class PhotoRepository:
    def __init__(self, session: sessionmaker):
        self._session = session

    def list(self, shop_id: str, limit: int | None = None) -> list[m.ShopPhoto]:
        stmt = (
            sa.select(m.ShopPhoto)
            .outerjoin(m.ShopPhoto.user)
            .options(contains_eager(m.ShopPhoto.user))
            .where(m.ShopPhoto.shop_id == shop_id)
            .order_by(m.ShopPhoto.created_at.desc())
            .limit(limit)
        )
        with self._session() as s:
            return list(s.scalars(stmt))

    def count(self, shop_id: str) -> int:
        with self._session() as s:
            return s.scalar(
                sa.select(sa.func.count()).select_from(m.ShopPhoto).where(m.ShopPhoto.shop_id == shop_id)
            ) or 0

    def add(self, shop_id: str, user_id: str | None, photos: list[dict]) -> list[m.ShopPhoto]:
        with self._session.begin() as s:
            added = []
            for photo in photos:
                row = m.ShopPhoto(shop_id=shop_id, user_id=user_id, kind=photo["kind"], data=photo["data"])
                s.add(row)
                added.append(row)
            s.flush()
            # Load server defaults and the uploader before the rows detach.
            for row in added:
                s.refresh(row)
                _ = row.user
            return added
