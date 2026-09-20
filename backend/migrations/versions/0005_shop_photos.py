"""add photo_url to shops

Revision ID: 0005
Revises: 0004
Create Date: 2026-09-19

"""
from alembic import op

revision = "0005"
down_revision = "0004"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE shops ADD COLUMN photo_url text")


def downgrade() -> None:
    op.execute("ALTER TABLE shops DROP COLUMN photo_url")
