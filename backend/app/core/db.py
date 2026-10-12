"""Engine and session factory shared by every Postgres repository."""

import logging
import time
from datetime import UTC, datetime

import sqlalchemy as sa
from sqlalchemy.orm import sessionmaker

log = logging.getLogger("kyc.db")

# Queries slower than this are logged with their SQL. Review the log before
# lowering statement_timeout (migration 0042) so the limit never kills a
# query the app relies on.
SLOW_QUERY_MS = 1000


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


def _log_slow_queries(engine: sa.Engine) -> None:
    @sa.event.listens_for(engine, "before_cursor_execute")
    def start_timer(conn, _cursor, _statement, _parameters, _context, _executemany):
        conn.info["kyc_query_started"] = time.perf_counter()

    @sa.event.listens_for(engine, "after_cursor_execute")
    def report_slow(conn, _cursor, statement, _parameters, _context, _executemany):
        started = conn.info.pop("kyc_query_started", None)
        if started is None:
            return
        elapsed_ms = (time.perf_counter() - started) * 1000
        if elapsed_ms >= SLOW_QUERY_MS:
            log.warning("slow query %.0fms: %s", elapsed_ms, " ".join(statement.split())[:300])


def create_session_factory(database_url: str) -> sessionmaker:
    # Neon closes idle connections after ~5 min; pre_ping revives dead
    # ones instead of surfacing "SSL connection has been closed".
    #
    # Repositories run in worker threads (core.graphql.threaded, core.loaders),
    # so a blocked psycopg call holds one thread and one pool slot instead of
    # the event loop. Keepalives still matter: a half-dead socket would
    # otherwise pin that slot until the kernel TCP timeout (~15 min on Linux).
    #
    # Pool is 5 + 5 overflow for ~40 worker threads; the rest queue up to
    # pool_timeout. Neon's pooler is in transaction mode and rejects
    # statement_timeout as a startup option, so the per-query cap is a role
    # default instead (migration 0042).
    engine = sa.create_engine(
        _engine_url(database_url),
        pool_size=5,
        max_overflow=5,
        pool_recycle=240,
        pool_pre_ping=True,
        pool_timeout=10,
        connect_args={
            "connect_timeout": 10,
            "keepalives": 1,
            "keepalives_idle": 30,
            "keepalives_interval": 10,
            "keepalives_count": 3,
        },
    )
    _log_slow_queries(engine)
    return sessionmaker(engine, expire_on_commit=False)
