"""product_photos: up to 6 listing images per product

Same storage shape as shop_photos (whole data URL in a text column) so no
object store is needed yet. position is the display order; 0 is the cover.
product_id is a soft reference; ProductRepository.delete removes the rows.

Revision ID: 0031
Revises: 0030
Create Date: 2026-09-28

"""
from alembic import op

revision = "0031"
down_revision = "0030"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE product_photos (
            id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            product_id bigint NOT NULL,
            position int NOT NULL DEFAULT 0,
            data text NOT NULL,
            created_at timestamptz NOT NULL DEFAULT now()
        )
        """
    )
    op.execute("CREATE INDEX product_photos_product_idx ON product_photos (product_id, position)")


def downgrade() -> None:
    op.execute("DROP TABLE product_photos")
