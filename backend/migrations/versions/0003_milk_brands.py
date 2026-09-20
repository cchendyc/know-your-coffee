"""track milk by brand instead of milk type

Revision ID: 0003
Revises: 0002
Create Date: 2026-09-19

"""
from alembic import op

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None

# Splits legacy "Straus / Oatly" strings into ["Straus", "Oatly"].
_SPLIT_BRAND = """
    to_jsonb(ARRAY(
        SELECT trim(x) FROM unnest(string_to_array(milk_brand, '/')) AS x
        WHERE trim(x) <> ''
    ))
"""


def upgrade() -> None:
    op.execute("ALTER TABLE shops ADD COLUMN milk_brands jsonb NOT NULL DEFAULT '[]'::jsonb")
    op.execute(f"UPDATE shops SET milk_brands = {_SPLIT_BRAND} WHERE milk_brand IS NOT NULL")
    op.execute("ALTER TABLE shops DROP COLUMN milk_options, DROP COLUMN milk_brand")

    op.execute("ALTER TABLE reports ADD COLUMN milk_brands jsonb")
    op.execute(f"UPDATE reports SET milk_brands = {_SPLIT_BRAND} WHERE milk_brand IS NOT NULL")
    op.execute("ALTER TABLE reports DROP COLUMN milk_options, DROP COLUMN milk_brand")


def downgrade() -> None:
    op.execute("ALTER TABLE shops ADD COLUMN milk_options jsonb NOT NULL DEFAULT '[]'::jsonb")
    op.execute("ALTER TABLE shops ADD COLUMN milk_brand text")
    op.execute("ALTER TABLE shops DROP COLUMN milk_brands")
    op.execute("ALTER TABLE reports ADD COLUMN milk_options jsonb")
    op.execute("ALTER TABLE reports ADD COLUMN milk_brand text")
    op.execute("ALTER TABLE reports DROP COLUMN milk_brands")
