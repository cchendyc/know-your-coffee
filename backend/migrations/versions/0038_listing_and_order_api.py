"""tighten the MVP schema now that the API reads the new columns

- products.category_id NOT NULL: createProduct requires categoryId.
- category_attributes.section: which card of the listing editor shows the
  field (DETAILS = what it is, FORMAT = size / form / condition).
- product_attributes.validation.presets: chip values the editor offers for
  INT attributes (grams: 8 oz, 12 oz, 2 lb, 5 lb; ml: 8, 12, 16 oz).
- shipments.carrier becomes an enum; no shipment rows exist yet.
- orders.items / orders.total go away; order_items and *_cents hold the data.

Revision ID: 0038
Revises: 0037
Create Date: 2026-09-30

"""
from alembic import op

revision = "0038"
down_revision = "0037"
branch_labels = None
depends_on = None

FORMAT_KEYS = ("weight_g", "form", "grind", "roasted_to_order", "volume_ml", "serve", "condition", "size", "color")


def upgrade() -> None:
    op.execute("ALTER TABLE products ALTER COLUMN category_id SET NOT NULL")

    op.execute("CREATE TYPE attribute_section AS ENUM ('DETAILS', 'FORMAT')")
    op.execute("ALTER TABLE category_attributes ADD COLUMN section attribute_section NOT NULL DEFAULT 'DETAILS'")
    keys = ", ".join(f"'{k}'" for k in FORMAT_KEYS)
    op.execute(
        "UPDATE category_attributes ca SET section = 'FORMAT' "
        f"FROM product_attributes a WHERE a.id = ca.attribute_id AND a.key IN ({keys})"
    )
    op.execute("""UPDATE product_attributes SET validation = '{"presets": [227, 340, 907, 2268]}' WHERE key = 'weight_g'""")
    op.execute("""UPDATE product_attributes SET validation = '{"presets": [237, 355, 473]}' WHERE key = 'volume_ml'""")

    op.execute("CREATE TYPE carrier AS ENUM ('USPS', 'UPS', 'FEDEX', 'OTHER')")
    op.execute(
        "ALTER TABLE shipments ALTER COLUMN carrier TYPE carrier "
        "USING (CASE WHEN carrier IN ('USPS', 'UPS', 'FEDEX', 'OTHER') THEN carrier::carrier ELSE NULL END)"
    )

    op.execute("ALTER TABLE orders DROP COLUMN items, DROP COLUMN total")
    op.execute("UPDATE orders SET subtotal_cents = 0 WHERE subtotal_cents IS NULL")
    op.execute("UPDATE orders SET total_cents = 0 WHERE total_cents IS NULL")
    op.execute("ALTER TABLE orders ALTER COLUMN subtotal_cents SET NOT NULL, ALTER COLUMN total_cents SET NOT NULL")


def downgrade() -> None:
    op.execute("ALTER TABLE orders ALTER COLUMN subtotal_cents DROP NOT NULL, ALTER COLUMN total_cents DROP NOT NULL")
    op.execute("ALTER TABLE orders ADD COLUMN items jsonb NOT NULL DEFAULT '[]'::jsonb, ADD COLUMN total numeric NOT NULL DEFAULT 0")
    op.execute("UPDATE orders SET total = total_cents / 100.0")
    op.execute("ALTER TABLE shipments ALTER COLUMN carrier TYPE text USING carrier::text")
    op.execute("DROP TYPE carrier")
    op.execute("ALTER TABLE category_attributes DROP COLUMN section")
    op.execute("DROP TYPE attribute_section")
    op.execute("UPDATE product_attributes SET validation = '{}' WHERE key IN ('weight_g', 'volume_ml')")
    op.execute("ALTER TABLE products ALTER COLUMN category_id DROP NOT NULL")
