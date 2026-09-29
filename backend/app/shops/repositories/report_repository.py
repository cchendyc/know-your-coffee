"""reports table access. Non-null report fields fold into the shop row on
write: the latest report wins."""

import sqlalchemy as sa
from sqlalchemy.orm import contains_eager, sessionmaker

from ... import models as m


def _community_reports(shop_id: str):
    # Admin reports fold into the shop record like any other, but they are
    # data entry, not community activity: list and count both skip them.
    # Anonymous reports (user_id NULL) stay visible.
    return (
        sa.select(m.Report)
        .outerjoin(m.Report.user)
        .where(
            m.Report.shop_id == shop_id,
            sa.or_(m.User.role.is_(None), m.User.role != "ADMIN"),
        )
    )


class ReportRepository:
    def __init__(self, session: sessionmaker):
        self._session = session

    def list(self, shop_id: str, limit: int | None = None) -> list[m.Report]:
        stmt = (
            _community_reports(shop_id)
            .options(contains_eager(m.Report.user))
            .order_by(m.Report.created_at.desc())
            .limit(limit)
        )
        with self._session() as s:
            return list(s.scalars(stmt))

    def count(self, shop_id: str) -> int:
        with self._session() as s:
            return s.scalar(sa.select(sa.func.count()).select_from(_community_reports(shop_id).subquery())) or 0

    def add(self, shop_id: str, user_id: str | None, note: str | None, source: str, fields: dict) -> m.Report:
        """fields: report column names -> values (machine, coffees, wifi, ...)."""
        # The scalar primary mirrors the first machines entry.
        machines = fields.get("machines")
        if machines and not fields.get("machine"):
            fields = {**fields, "machine": machines[0]["brand"], "machine_model": machines[0].get("model")}
        with self._session.begin() as s:
            row = m.Report(shop_id=shop_id, user_id=user_id, note=note, source=source, **fields)
            s.add(row)
            s.flush()
            # Load server defaults and the reporter before the row detaches.
            s.refresh(row)
            _ = row.user
            folded = {column: value for column, value in fields.items() if value is not None}
            if folded:
                s.execute(
                    sa.update(m.Shop).where(m.Shop.id == shop_id).values(updated_at=sa.func.now(), **folded)
                )
            return row
