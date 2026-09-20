"""add user saved/been lists and shop photos

Revision ID: 0009
Revises: 0008
Create Date: 2026-09-19

"""
from alembic import op

revision = "0009"
down_revision = "0008"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE user_shops (
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            shop_id uuid NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
            saved boolean NOT NULL DEFAULT false,
            been boolean NOT NULL DEFAULT false,
            updated_at timestamptz NOT NULL DEFAULT now(),
            PRIMARY KEY (user_id, shop_id)
        )
        """
    )
    op.execute(
        """
        CREATE TABLE shop_photos (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            shop_id uuid NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
            user_id uuid REFERENCES users(id),
            kind text NOT NULL,
            data text NOT NULL,
            created_at timestamptz NOT NULL DEFAULT now()
        )
        """
    )
    op.execute("CREATE INDEX shop_photos_shop_idx ON shop_photos (shop_id, kind)")


def downgrade() -> None:
    op.execute("DROP TABLE shop_photos")
    op.execute("DROP TABLE user_shops")
