"""SQLAlchemy foundation.

Models are the canonical in-code description of the Postgres tables and what
PostgresRepository queries. DDL still ships as raw-SQL Alembic migrations;
keep the two in sync when adding columns.
"""

from datetime import datetime
from enum import StrEnum

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import ENUM
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


class IntId(sa.TypeDecorator):
    """bigint column type for every id and *_id column.

    GraphQL sends ids as strings; psycopg3 binds str as text and Postgres
    rejects bigint = text, so this casts to int on the way in. References
    between tables are plain *_id columns with no FOREIGN KEY constraint;
    repositories clean up dependent rows themselves.
    """

    impl = sa.BigInteger
    cache_ok = True

    def process_bind_param(self, value, dialect):
        return None if value is None else int(value)

    def coerce_compared_value(self, op, value):
        return self


def _tz_now() -> Mapped[datetime]:
    return mapped_column(sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()"))


class CreatedAtMixin:
    created_at: Mapped[datetime] = _tz_now()


class TimestampedMixin(CreatedAtMixin):
    updated_at: Mapped[datetime] = _tz_now()


def pg_enum(enum: type[StrEnum], name: str) -> ENUM:
    """Column type for a native Postgres enum; the type itself is created by a migration."""
    return ENUM(enum, name=name, create_type=False, values_callable=lambda e: [m.value for m in e])

