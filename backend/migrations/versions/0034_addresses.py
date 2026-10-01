"""addresses: buyer ship-to addresses

Rows are immutable once used: editing inserts a new row and soft-deletes
the old one, so orders can reference shipping_address_id without a
snapshot. user_id is a soft reference.

Revision ID: 0034
Revises: 0033
Create Date: 2026-09-29

"""
from alembic import op

revision = "0034"
down_revision = "0033"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE addresses (
            id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            user_id bigint NOT NULL,
            full_name text NOT NULL,
            line1 text NOT NULL,
            line2 text,
            city text NOT NULL,
            state text NOT NULL,
            postal_code text NOT NULL,
            country_code text NOT NULL DEFAULT 'US',
            phone text,
            is_default boolean NOT NULL DEFAULT false,
            deleted boolean NOT NULL DEFAULT false,
            created_at timestamptz NOT NULL DEFAULT now()
        )
        """
    )
    op.execute("CREATE INDEX addresses_user_idx ON addresses (user_id) WHERE NOT deleted")


def downgrade() -> None:
    op.execute("DROP TABLE addresses")
