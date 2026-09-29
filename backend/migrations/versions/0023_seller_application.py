"""add seller application fields to shop claims

Claiming a shop becomes a seller application: role at the business,
a verification contact, and a proof link, reviewed by support.

Revision ID: 0023
Revises: 0022
Create Date: 2026-09-27

"""
from alembic import op

revision = "0023"
down_revision = "0022"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE shop_claims ADD COLUMN business_role text")
    op.execute("ALTER TABLE shop_claims ADD COLUMN contact text")
    op.execute("ALTER TABLE shop_claims ADD COLUMN website text")


def downgrade() -> None:
    op.execute("ALTER TABLE shop_claims DROP COLUMN website")
    op.execute("ALTER TABLE shop_claims DROP COLUMN contact")
    op.execute("ALTER TABLE shop_claims DROP COLUMN business_role")
