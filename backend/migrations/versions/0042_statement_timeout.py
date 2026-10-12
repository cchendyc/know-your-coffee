"""statement_timeout: cap every app query at 15s

A role default, not a connection option: Neon's pooler runs in transaction
mode and rejects statement_timeout in startup options, and a SET on a
pooled connection leaks to whichever client gets that server connection
next. New sessions for the app role pick this up; the pooler recycles
existing server connections on its own.

Migrations opt out in migrations/env.py (SET LOCAL statement_timeout = 0),
so a slow backfill is not killed by this cap.

Lower the value once the kyc.db slow-query log shows headroom.

Revision ID: 0042
Revises: 0041
Create Date: 2026-10-10

"""
from alembic import op

revision = "0042"
down_revision = "0041"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER ROLE CURRENT_USER SET statement_timeout = '15s'")


def downgrade() -> None:
    op.execute("ALTER ROLE CURRENT_USER RESET statement_timeout")
