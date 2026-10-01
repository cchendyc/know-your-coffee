"""Buyer addresses. Rows are immutable once saved: an edit inserts a new row
and soft-deletes the one it replaces, so orders keep pointing at what the
buyer typed at checkout."""

import sqlalchemy as sa
from sqlalchemy.orm import sessionmaker

from ... import models as m


class AddressRepository:
    def __init__(self, session: sessionmaker):
        self._session = session

    def get(self, address_id: str) -> m.Address | None:
        with self._session() as s:
            return s.get(m.Address, address_id)

    def list_for_user(self, user_id: str) -> list[m.Address]:
        stmt = (
            sa.select(m.Address)
            .where(m.Address.user_id == user_id, m.Address.deleted.is_(False))
            .order_by(m.Address.is_default.desc(), m.Address.created_at.desc())
        )
        with self._session() as s:
            return list(s.scalars(stmt))

    def save(self, user_id: str, values: dict, replaces_id: str | None) -> m.Address:
        """values: addresses column names -> values. The first address becomes the default."""
        with self._session.begin() as s:
            existing = s.scalars(
                sa.select(m.Address).where(m.Address.user_id == user_id, m.Address.deleted.is_(False))
            ).all()
            replaced = next((a for a in existing if replaces_id and str(a.id) == str(replaces_id)), None)
            is_default = values.pop("is_default", None)
            if is_default is None:
                is_default = replaced.is_default if replaced else not existing
            if replaced:
                replaced.deleted = True
            if is_default:
                for other in existing:
                    other.is_default = False
            row = m.Address(user_id=user_id, is_default=is_default, **values)
            s.add(row)
            s.flush()
            s.refresh(row)
            return row

    def set_default(self, user_id: str, address_id: str) -> m.Address | None:
        with self._session.begin() as s:
            rows = s.scalars(
                sa.select(m.Address).where(m.Address.user_id == user_id, m.Address.deleted.is_(False))
            ).all()
            chosen = next((a for a in rows if str(a.id) == str(address_id)), None)
            if not chosen:
                return None
            for row in rows:
                row.is_default = row is chosen
            return chosen

    def delete(self, user_id: str, address_id: str) -> bool:
        with self._session.begin() as s:
            row = s.get(m.Address, address_id)
            if not row or str(row.user_id) != str(user_id) or row.deleted:
                return False
            row.deleted = True
            row.is_default = False
        return True
