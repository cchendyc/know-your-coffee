"""shops.seller_onboarded_at: when the owner finished the seller walkthrough

Null until completeSellerOnboarding runs, so clients gate the hub on the
server instead of local state.

Revision ID: 0030
Revises: 0029
Create Date: 2026-09-28

"""
import sqlalchemy as sa
from alembic import op

revision = "0030"
down_revision = "0029"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("shops", sa.Column("seller_onboarded_at", sa.DateTime(timezone=True), nullable=True))


def downgrade() -> None:
    op.drop_column("shops", "seller_onboarded_at")
