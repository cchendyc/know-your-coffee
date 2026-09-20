"""cascade shop child rows on delete

reports and shop_claims referenced shops without ON DELETE CASCADE, so
admin shop removal would fail unless the app deleted children first.

Revision ID: 0019
Revises: 0018
Create Date: 2026-09-20

"""
from alembic import op

revision = "0019"
down_revision = "0018"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE reports DROP CONSTRAINT IF EXISTS reports_shop_id_fkey")
    op.execute(
        """
        ALTER TABLE reports ADD CONSTRAINT reports_shop_id_fkey
          FOREIGN KEY (shop_id) REFERENCES shops(id) ON DELETE CASCADE
        """
    )
    op.execute("ALTER TABLE shop_claims DROP CONSTRAINT IF EXISTS shop_claims_shop_id_fkey")
    op.execute(
        """
        ALTER TABLE shop_claims ADD CONSTRAINT shop_claims_shop_id_fkey
          FOREIGN KEY (shop_id) REFERENCES shops(id) ON DELETE CASCADE
        """
    )


def downgrade() -> None:
    op.execute("ALTER TABLE reports DROP CONSTRAINT IF EXISTS reports_shop_id_fkey")
    op.execute(
        """
        ALTER TABLE reports ADD CONSTRAINT reports_shop_id_fkey
          FOREIGN KEY (shop_id) REFERENCES shops(id)
        """
    )
    op.execute("ALTER TABLE shop_claims DROP CONSTRAINT IF EXISTS shop_claims_shop_id_fkey")
    op.execute(
        """
        ALTER TABLE shop_claims ADD CONSTRAINT shop_claims_shop_id_fkey
          FOREIGN KEY (shop_id) REFERENCES shops(id)
        """
    )
