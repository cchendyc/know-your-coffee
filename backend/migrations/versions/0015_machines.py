"""add machines jsonb list to shops and reports

Shops can run several espresso machines (e.g. a Modbar bar plus a Linea).
Each entry is {brand, model}. The scalar machine/machine_model columns
stay as the primary machine — filters and ranking use them — and are
derived from the first list entry on new reports.

Revision ID: 0015
Revises: 0014
Create Date: 2026-09-19

"""
from alembic import op

revision = "0015"
down_revision = "0014"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE shops ADD COLUMN machines jsonb NOT NULL DEFAULT '[]'::jsonb")
    op.execute("ALTER TABLE reports ADD COLUMN machines jsonb")
    op.execute(
        """UPDATE shops SET machines = jsonb_build_array(jsonb_strip_nulls(
               jsonb_build_object('brand', machine::text, 'model', machine_model)))
           WHERE machine <> 'UNKNOWN'"""
    )
    # Serves the any-machine filter: machines @> '[{"brand":"LA_MARZOCCO"}]'
    op.execute("CREATE INDEX shops_machines_gin ON shops USING gin (machines jsonb_path_ops)")


def downgrade() -> None:
    op.execute("DROP INDEX shops_machines_gin")
    op.execute("ALTER TABLE reports DROP COLUMN machines")
    op.execute("ALTER TABLE shops DROP COLUMN machines")
