"""add delivery settings to shops

Sellers choose shipping, pickup, or both. Existing shops keep today's
behavior: shipping on, pickup off.

Revision ID: 0025
Revises: 0024
Create Date: 2026-09-27

"""
from alembic import op

revision = "0025"
down_revision = "0024"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE shops ADD COLUMN offers_shipping boolean NOT NULL DEFAULT true")
    op.execute("ALTER TABLE shops ADD COLUMN offers_pickup boolean NOT NULL DEFAULT false")
    op.execute("ALTER TABLE shops ADD COLUMN pickup_instructions text")
    op.execute(
        "ALTER TABLE shops ADD CONSTRAINT shops_offers_fulfillment CHECK (offers_shipping OR offers_pickup)"
    )


def downgrade() -> None:
    op.execute("ALTER TABLE shops DROP CONSTRAINT shops_offers_fulfillment")
    op.execute("ALTER TABLE shops DROP COLUMN pickup_instructions")
    op.execute("ALTER TABLE shops DROP COLUMN offers_pickup")
    op.execute("ALTER TABLE shops DROP COLUMN offers_shipping")
