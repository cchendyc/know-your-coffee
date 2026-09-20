"""convert milk_brands from jsonb to text[]

Revision ID: 0008
Revises: 0007
Create Date: 2026-09-19

"""
from alembic import op

revision = "0008"
down_revision = "0007"
branch_labels = None
depends_on = None

# ALTER COLUMN TYPE ... USING cannot contain subqueries, so convert via a
# temporary column instead.


def upgrade() -> None:
    op.execute("ALTER TABLE shops ADD COLUMN milk_brands_arr text[] NOT NULL DEFAULT '{}'")
    op.execute("UPDATE shops SET milk_brands_arr = ARRAY(SELECT jsonb_array_elements_text(milk_brands))")
    op.execute("ALTER TABLE shops DROP COLUMN milk_brands")
    op.execute("ALTER TABLE shops RENAME COLUMN milk_brands_arr TO milk_brands")

    op.execute("ALTER TABLE reports ADD COLUMN milk_brands_arr text[]")
    op.execute(
        "UPDATE reports SET milk_brands_arr = ARRAY(SELECT jsonb_array_elements_text(milk_brands))"
        " WHERE milk_brands IS NOT NULL"
    )
    op.execute("ALTER TABLE reports DROP COLUMN milk_brands")
    op.execute("ALTER TABLE reports RENAME COLUMN milk_brands_arr TO milk_brands")


def downgrade() -> None:
    op.execute("ALTER TABLE reports ADD COLUMN milk_brands_json jsonb")
    op.execute("UPDATE reports SET milk_brands_json = to_jsonb(milk_brands) WHERE milk_brands IS NOT NULL")
    op.execute("ALTER TABLE reports DROP COLUMN milk_brands")
    op.execute("ALTER TABLE reports RENAME COLUMN milk_brands_json TO milk_brands")

    op.execute("ALTER TABLE shops ADD COLUMN milk_brands_json jsonb NOT NULL DEFAULT '[]'")
    op.execute("UPDATE shops SET milk_brands_json = to_jsonb(milk_brands)")
    op.execute("ALTER TABLE shops DROP COLUMN milk_brands")
    op.execute("ALTER TABLE shops RENAME COLUMN milk_brands_json TO milk_brands")
