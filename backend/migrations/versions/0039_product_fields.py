"""products: quantity, drop variant and sold_count

The listing form edits per-category fields (products.attributes), so the
free-text variant goes away. Variant text that 0033 could not parse into
attributes is kept as the description so nothing a seller typed is lost.

Revision ID: 0039
Revises: 0038
Create Date: 2026-09-30

"""
from alembic import op

revision = "0039"
down_revision = "0038"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE products RENAME COLUMN stock_qty TO quantity")
    op.execute("ALTER TABLE products RENAME CONSTRAINT products_stock_qty_check TO products_quantity_check")
    op.execute("ALTER TABLE products DROP COLUMN sold_count")
    op.execute(
        """
        UPDATE products SET description = variant
        WHERE description IS NULL AND variant IS NOT NULL AND attributes = '{}'::jsonb
        """
    )
    op.execute("ALTER TABLE products DROP COLUMN variant")


def downgrade() -> None:
    op.execute("ALTER TABLE products ADD COLUMN variant text")
    op.execute("ALTER TABLE products ADD COLUMN sold_count int NOT NULL DEFAULT 0")
    op.execute("ALTER TABLE products RENAME CONSTRAINT products_quantity_check TO products_stock_qty_check")
    op.execute("ALTER TABLE products RENAME COLUMN quantity TO stock_qty")
