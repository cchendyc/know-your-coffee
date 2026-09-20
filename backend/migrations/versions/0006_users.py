"""add users table and report attribution

Revision ID: 0006
Revises: 0005
Create Date: 2026-09-19

"""
from alembic import op

revision = "0006"
down_revision = "0005"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE users (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            google_sub text NOT NULL UNIQUE,
            email text NOT NULL,
            name text NOT NULL,
            picture text,
            created_at timestamptz NOT NULL DEFAULT now()
        )
        """
    )
    op.execute("ALTER TABLE reports ADD COLUMN user_id uuid REFERENCES users(id)")


def downgrade() -> None:
    op.execute("ALTER TABLE reports DROP COLUMN user_id")
    op.execute("DROP TABLE users")
