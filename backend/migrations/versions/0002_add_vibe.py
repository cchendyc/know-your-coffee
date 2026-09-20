"""add vibe column to shops

Revision ID: 0002
Revises: 0001
Create Date: 2026-09-19

"""
from alembic import op

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE shops ADD COLUMN vibe text")


def downgrade() -> None:
    op.execute("ALTER TABLE shops DROP COLUMN vibe")
