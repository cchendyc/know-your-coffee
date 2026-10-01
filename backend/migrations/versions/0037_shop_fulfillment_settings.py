"""shops: shipping rate and pickup settings behind the Shipping and pickup page

Flat rate per order is the only shipping price model for MVP.
ship_free_over_cents NULL means no free-shipping threshold.

Revision ID: 0037
Revises: 0036
Create Date: 2026-09-29

"""
from alembic import op

revision = "0037"
down_revision = "0036"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("CREATE TYPE ships_to AS ENUM ('CA', 'US')")
    op.execute(
        """
        ALTER TABLE shops
            ADD COLUMN ship_flat_rate_cents int NOT NULL DEFAULT 0,
            ADD COLUMN ship_free_over_cents int,
            ADD COLUMN ships_within_days smallint NOT NULL DEFAULT 2,
            ADD COLUMN ships_to ships_to NOT NULL DEFAULT 'US',
            ADD COLUMN pickup_ready_minutes int NOT NULL DEFAULT 20,
            ADD COLUMN pickup_hours text
        """
    )


def downgrade() -> None:
    op.execute(
        "ALTER TABLE shops DROP COLUMN pickup_hours, DROP COLUMN pickup_ready_minutes, DROP COLUMN ships_to, "
        "DROP COLUMN ships_within_days, DROP COLUMN ship_free_over_cents, DROP COLUMN ship_flat_rate_cents"
    )
    op.execute("DROP TYPE ships_to")
