"""backfill existing users as admins

Every account created before this point belongs to the founding team,
so grant them ADMIN. New sign-ups keep the USER default.

Revision ID: 0020
Revises: 0019
Create Date: 2026-09-20

"""
from alembic import op

revision = "0020"
down_revision = "0019"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("UPDATE users SET role = 'ADMIN'")


def downgrade() -> None:
    op.execute("UPDATE users SET role = 'USER'")
