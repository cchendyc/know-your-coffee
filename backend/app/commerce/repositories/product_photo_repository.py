"""product_photos table access."""

import sqlalchemy as sa
from sqlalchemy.orm import sessionmaker

from ... import models as m


class ProductPhotoRepository:
    def __init__(self, session: sessionmaker):
        self._session = session

    def list(self, product_id: str) -> list[m.ProductPhoto]:
        stmt = (
            sa.select(m.ProductPhoto)
            .where(m.ProductPhoto.product_id == product_id)
            .order_by(m.ProductPhoto.position.asc(), m.ProductPhoto.id.asc())
        )
        with self._session() as s:
            return list(s.scalars(stmt))

    def cover(self, product_id: str) -> m.ProductPhoto | None:
        stmt = (
            sa.select(m.ProductPhoto)
            .where(m.ProductPhoto.product_id == product_id)
            .order_by(m.ProductPhoto.position.asc(), m.ProductPhoto.id.asc())
            .limit(1)
        )
        with self._session() as s:
            return s.scalars(stmt).first()

    def replace(self, product_id: str, items: list[dict]) -> list[m.ProductPhoto]:
        """items, in display order: {"id": existing photo id} or {"data": data URL}.
        Photos of this product not listed are deleted; new ones are inserted;
        every kept photo gets its new position."""
        with self._session.begin() as s:
            existing = {
                str(p.id): p
                for p in s.scalars(sa.select(m.ProductPhoto).where(m.ProductPhoto.product_id == product_id))
            }
            keep_ids = {str(item["id"]) for item in items if item.get("id") is not None}
            for pid, photo in existing.items():
                if pid not in keep_ids:
                    s.delete(photo)
            ordered = []
            for position, item in enumerate(items):
                if item.get("id") is not None:
                    photo = existing.get(str(item["id"]))
                    if not photo:
                        continue  # id from another product or already gone; skip silently
                    photo.position = position
                else:
                    photo = m.ProductPhoto(product_id=product_id, position=position, data=item["data"])
                    s.add(photo)
                ordered.append(photo)
            s.flush()
            for photo in ordered:
                s.refresh(photo)
            return ordered
