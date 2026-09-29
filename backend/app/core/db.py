"""Engine and session factory shared by every Postgres repository."""

from datetime import UTC, datetime

import sqlalchemy as sa
from sqlalchemy.orm import sessionmaker


def now() -> datetime:
    return datetime.now(UTC)


def fetch_page(session: sessionmaker, stmt: sa.Select, limit: int, offset: int) -> tuple[list, int]:
    """One page of stmt's rows plus the unpaged match count.

    stmt must already be ordered with a unique tiebreak, or offset pages can
    repeat or skip rows.
    """
    total_stmt = sa.select(sa.func.count()).select_from(stmt.order_by(None).subquery())
    with session() as s:
        total = s.scalar(total_stmt) or 0
        rows = list(s.scalars(stmt.limit(limit).offset(offset))) if total > offset else []
    return rows, total


def _engine_url(url: str) -> str:
    # Force the psycopg3 driver; Neon URLs come in as postgres:// or postgresql://.
    for prefix in ("postgres://", "postgresql://"):
        if url.startswith(prefix):
            return "postgresql+psycopg://" + url[len(prefix) :]
    return url


def create_session_factory(database_url: str) -> sessionmaker:
    # Neon closes idle connections after ~5 min; pre_ping revives dead
    # ones instead of surfacing "SSL connection has been closed".
    engine = sa.create_engine(
        _engine_url(database_url),
        pool_size=5,
        max_overflow=0,
        pool_recycle=240,
        pool_pre_ping=True,
    )
    return sessionmaker(engine, expire_on_commit=False)
