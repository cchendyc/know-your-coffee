"""reports table: community updates that fold into the shop record."""

from __future__ import annotations

from typing import Any

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import ARRAY, ENUM, JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .base import Base, CreatedAtMixin, IntId
from .enums import REPORT_SOURCES
from .shop import bean_source, machine_brand
from .user import User


report_source = ENUM(*REPORT_SOURCES, name="report_source", create_type=False)


class Report(Base, CreatedAtMixin):
    __tablename__ = "reports"

    id: Mapped[int] = mapped_column(IntId, sa.Identity(), primary_key=True)
    shop_id: Mapped[int] = mapped_column(IntId)
    machine: Mapped[str | None] = mapped_column(machine_brand)
    machine_model: Mapped[str | None] = mapped_column()
    machines: Mapped[list[Any] | None] = mapped_column(JSONB)
    bean_source: Mapped[str | None] = mapped_column(bean_source)
    roaster: Mapped[str | None] = mapped_column()
    bean_origins: Mapped[list[str] | None] = mapped_column(ARRAY(sa.Text))
    coffees: Mapped[list[Any] | None] = mapped_column(JSONB)
    grinders: Mapped[list[str] | None] = mapped_column(ARRAY(sa.Text))
    drinks: Mapped[list[Any] | None] = mapped_column(JSONB)
    milk_brands: Mapped[list[str] | None] = mapped_column(ARRAY(sa.Text))
    dog_friendly: Mapped[bool | None] = mapped_column()
    wifi: Mapped[bool | None] = mapped_column()
    outdoor_seating: Mapped[bool | None] = mapped_column()
    note: Mapped[str | None] = mapped_column()
    source: Mapped[str] = mapped_column(report_source, default="TEXT", server_default=sa.text("'TEXT'"))
    # Null after the reporter deletes their account.
    user_id: Mapped[int | None] = mapped_column(IntId)

    user: Mapped[User | None] = relationship(primaryjoin="foreign(Report.user_id) == User.id", viewonly=True)
