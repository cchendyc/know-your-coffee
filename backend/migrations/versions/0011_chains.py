"""chains table and shops.chain_id

Revision ID: 0011
Revises: 0010
Create Date: 2026-09-19

"""
from alembic import op

revision = "0011"
down_revision = "0010"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE chains (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            name text NOT NULL,
            slug text NOT NULL UNIQUE,
            website text,
            created_at timestamptz NOT NULL DEFAULT now()
        )
        """
    )
    op.execute("ALTER TABLE shops ADD COLUMN chain_id uuid REFERENCES chains(id)")
    op.execute("CREATE INDEX shops_chain_id_idx ON shops (chain_id)")


def downgrade() -> None:
    op.execute("ALTER TABLE shops DROP COLUMN chain_id")
    op.execute("DROP TABLE chains")
