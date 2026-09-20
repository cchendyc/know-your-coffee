"""add user roles, shop ownership, and claim requests

Groundwork for owner/admin editing: users get a role, shops get a
verified owner, and claims are the audited path from one to the other.

Revision ID: 0016
Revises: 0015
Create Date: 2026-09-19

"""
from alembic import op

revision = "0016"
down_revision = "0015"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE users ADD COLUMN role text NOT NULL DEFAULT 'USER'")
    op.execute("ALTER TABLE shops ADD COLUMN owner_user_id uuid REFERENCES users(id)")
    op.execute(
        """
        CREATE TABLE shop_claims (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            shop_id uuid NOT NULL REFERENCES shops(id),
            user_id uuid NOT NULL REFERENCES users(id),
            status text NOT NULL DEFAULT 'PENDING',
            note text,
            created_at timestamptz NOT NULL DEFAULT now(),
            resolved_at timestamptz
        )
        """
    )
    op.execute("CREATE INDEX shop_claims_user ON shop_claims (user_id)")
    op.execute("CREATE INDEX shop_claims_pending ON shop_claims (created_at) WHERE status = 'PENDING'")


def downgrade() -> None:
    op.execute("DROP TABLE shop_claims")
    op.execute("ALTER TABLE shops DROP COLUMN owner_user_id")
    op.execute("ALTER TABLE users DROP COLUMN role")
