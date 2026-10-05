"""shop_flags table access. One flag per user per shop."""

import sqlalchemy as sa
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import sessionmaker

from ... import models as m


class DuplicateShopFlag(Exception):
    pass


class ShopFlagRepository:
    def __init__(self, session: sessionmaker):
        self._session = session

    def add(self, shop_id: str, user_id: str, reason: str) -> m.ShopFlag:
        try:
            with self._session.begin() as s:
                existing = s.scalars(
                    sa.select(m.ShopFlag).where(m.ShopFlag.shop_id == shop_id, m.ShopFlag.user_id == user_id)
                ).first()
                if existing:
                    raise DuplicateShopFlag()
                row = m.ShopFlag(shop_id=shop_id, user_id=user_id, reason=reason)
                s.add(row)
                s.flush()
                s.refresh(row)
                return row
        except IntegrityError:
            raise DuplicateShopFlag()
