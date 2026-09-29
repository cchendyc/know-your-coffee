"""add local pickup to orders

PICKUP orders skip the shipment and move PLACED > READY_FOR_PICKUP >
PICKED_UP. Existing orders are all shipped, so they default to SHIP.

Revision ID: 0024
Revises: 0023
Create Date: 2026-09-27

"""
from alembic import op

revision = "0024"
down_revision = "0023"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """ALTER TABLE orders ADD COLUMN fulfillment text NOT NULL DEFAULT 'SHIP'
           CHECK (fulfillment IN ('SHIP', 'PICKUP'))"""
    )


def downgrade() -> None:
    op.execute("ALTER TABLE orders DROP COLUMN fulfillment")
