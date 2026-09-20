"""support phone-number accounts

Users can now exist without Google (phone OTP sign-in), so google_sub and
email become nullable and phone is added. phone_logins holds one active
OTP per phone: a keyed hash, an attempt counter, and an expiry.

Revision ID: 0017
Revises: 0016
Create Date: 2026-09-19

"""
from alembic import op

revision = "0017"
down_revision = "0016"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE users ALTER COLUMN google_sub DROP NOT NULL")
    op.execute("ALTER TABLE users ALTER COLUMN email DROP NOT NULL")
    op.execute("ALTER TABLE users ADD COLUMN phone text UNIQUE")
    op.execute(
        """
        CREATE TABLE phone_logins (
            phone text PRIMARY KEY,
            code_hash text NOT NULL,
            attempts int NOT NULL DEFAULT 0,
            expires_at timestamptz NOT NULL,
            created_at timestamptz NOT NULL DEFAULT now()
        )
        """
    )


def downgrade() -> None:
    op.execute("DROP TABLE phone_logins")
    op.execute("DELETE FROM users WHERE google_sub IS NULL")
    op.execute("ALTER TABLE users DROP COLUMN phone")
    op.execute("ALTER TABLE users ALTER COLUMN email SET NOT NULL")
    op.execute("ALTER TABLE users ALTER COLUMN google_sub SET NOT NULL")
