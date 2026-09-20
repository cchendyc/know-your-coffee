"""add PRIVATE_LABEL and DISTRIBUTOR bean sources

PRIVATE_LABEL: a third party roasts to the shop's spec under the shop's
brand, so it looks in-house but is not. DISTRIBUTOR: bulk pre-roasted
commercial-grade coffee from a foodservice distributor, typically weeks
old.

Revision ID: 0014
Revises: 0013
Create Date: 2026-09-19

"""
from alembic import op

revision = "0014"
down_revision = "0013"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # A new enum value cannot be used inside the transaction that adds it.
    with op.get_context().autocommit_block():
        op.execute("ALTER TYPE bean_source ADD VALUE IF NOT EXISTS 'PRIVATE_LABEL' BEFORE 'UNKNOWN'")
        op.execute("ALTER TYPE bean_source ADD VALUE IF NOT EXISTS 'DISTRIBUTOR' BEFORE 'UNKNOWN'")


def downgrade() -> None:
    # Postgres cannot drop an enum value; reclassify the rows only.
    for table in ("shops", "reports"):
        op.execute(f"UPDATE {table} SET bean_source = 'UNKNOWN' WHERE bean_source IN ('PRIVATE_LABEL', 'DISTRIBUTOR')")
