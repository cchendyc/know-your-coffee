"""add bean origins, grinders, drinks, website

Revision ID: 0007
Revises: 0006
Create Date: 2026-09-19

"""
from alembic import op

revision = "0007"
down_revision = "0006"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE shops ADD COLUMN bean_origins text[] NOT NULL DEFAULT '{}'")
    op.execute("ALTER TABLE shops ADD COLUMN grinders text[] NOT NULL DEFAULT '{}'")
    # drinks are {"name": text, "price": number|null} objects, so jsonb, not text[]
    op.execute("ALTER TABLE shops ADD COLUMN drinks jsonb NOT NULL DEFAULT '[]'")
    op.execute("ALTER TABLE shops ADD COLUMN website text")
    op.execute("ALTER TABLE reports ADD COLUMN bean_origins text[]")
    op.execute("ALTER TABLE reports ADD COLUMN grinders text[]")
    op.execute("ALTER TABLE reports ADD COLUMN drinks jsonb")


def downgrade() -> None:
    op.execute("ALTER TABLE reports DROP COLUMN drinks")
    op.execute("ALTER TABLE reports DROP COLUMN grinders")
    op.execute("ALTER TABLE reports DROP COLUMN bean_origins")
    op.execute("ALTER TABLE shops DROP COLUMN website")
    op.execute("ALTER TABLE shops DROP COLUMN drinks")
    op.execute("ALTER TABLE shops DROP COLUMN grinders")
    op.execute("ALTER TABLE shops DROP COLUMN bean_origins")
