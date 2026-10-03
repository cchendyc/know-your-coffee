"""reviews: one visitor review per user per shop

Any signed-in user can review any shop. Verified-buyer badges from
delivered orders are not stored yet.

Revision ID: 0040
Revises: 0039
Create Date: 2026-10-03

"""
from alembic import op

revision = "0040"
down_revision = "0039"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE reviews (
            id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            shop_id bigint NOT NULL,
            user_id bigint,
            rating smallint NOT NULL,
            body text,
            created_at timestamptz NOT NULL DEFAULT now(),
            updated_at timestamptz NOT NULL DEFAULT now(),
            CONSTRAINT reviews_rating_check CHECK (rating BETWEEN 1 AND 5)
        )
        """
    )
    op.execute("CREATE INDEX reviews_shop_created ON reviews (shop_id, created_at DESC)")
    op.execute(
        "CREATE UNIQUE INDEX reviews_shop_user ON reviews (shop_id, user_id) WHERE user_id IS NOT NULL"
    )


def downgrade() -> None:
    op.execute("DROP TABLE reviews")
