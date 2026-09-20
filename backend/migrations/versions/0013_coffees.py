"""add structured coffees jsonb to shops and reports

Each entry describes one coffee on bar: name, roaster, type, origins,
process, fermentation, roast level, varieties, tasting notes. Replaces
the flat bean_origins text[] for new data; bean_origins is backfilled
into a single entry and kept for reads until callers stop using it.

Revision ID: 0013
Revises: 0012
Create Date: 2026-09-19

"""
from alembic import op

revision = "0013"
down_revision = "0012"
branch_labels = None
depends_on = None

# bean_origins mixed countries with meta terms; split them apart.
_META = ("Single origin", "Blend", "Seasonal rotation")

_BACKFILL = f"""
UPDATE shops SET coffees = jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
  'type', CASE WHEN 'Single origin' = ANY(bean_origins) THEN 'SINGLE_ORIGIN'
               WHEN 'Blend' = ANY(bean_origins) THEN 'BLEND' END,
  'origins', to_jsonb(ARRAY(SELECT o FROM unnest(bean_origins) o
                            WHERE o NOT IN {_META}))
)))
WHERE cardinality(bean_origins) > 0
"""


def upgrade() -> None:
    op.execute("ALTER TABLE shops ADD COLUMN coffees jsonb NOT NULL DEFAULT '[]'::jsonb")
    op.execute("ALTER TABLE reports ADD COLUMN coffees jsonb")
    op.execute(_BACKFILL)
    # jsonb_path_ops serves containment filters like
    # coffees @> '[{"process":"WASHED","origins":["Ethiopia"]}]'
    op.execute("CREATE INDEX shops_coffees_gin ON shops USING gin (coffees jsonb_path_ops)")


def downgrade() -> None:
    op.execute("DROP INDEX shops_coffees_gin")
    op.execute("ALTER TABLE reports DROP COLUMN coffees")
    op.execute("ALTER TABLE shops DROP COLUMN coffees")
