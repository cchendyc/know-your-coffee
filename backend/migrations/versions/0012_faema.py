"""add FAEMA machine brand and reclassify OTHER Faema rows

Revision ID: 0012
Revises: 0011
Create Date: 2026-09-19

"""
from alembic import op

revision = "0012"
down_revision = "0011"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # A new enum value cannot be used inside the transaction that adds it.
    with op.get_context().autocommit_block():
        op.execute("ALTER TYPE machine_brand ADD VALUE IF NOT EXISTS 'FAEMA' BEFORE 'OTHER'")

    # "Other" machines carried the brand as a prefix, e.g. "Faema E61".
    for table in ("shops", "reports"):
        op.execute(
            f"""UPDATE {table} SET machine = 'FAEMA',
                machine_model = NULLIF(btrim(regexp_replace(machine_model, '^\\s*faema\\s*', '', 'i')), '')
                WHERE machine_model ~* '^\\s*faema'"""
        )


def downgrade() -> None:
    # Postgres cannot drop an enum value; revert the rows only.
    for table in ("shops", "reports"):
        op.execute(
            f"""UPDATE {table} SET machine = 'OTHER',
                machine_model = btrim('Faema ' || COALESCE(machine_model, ''))
                WHERE machine = 'FAEMA'"""
        )
