"""apple accounts and generalized sign-in codes

Sign in with Apple adds a third account key (apple_sub). Email one-time
codes reuse the phone code flow, so phone_logins becomes login_codes and
its key column holds a phone number or an email address.

Revision ID: 0018
Revises: 0017
Create Date: 2026-09-19

"""
from alembic import op

revision = "0018"
down_revision = "0017"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE users ADD COLUMN apple_sub text UNIQUE")
    op.execute("ALTER TABLE phone_logins RENAME TO login_codes")
    op.execute("ALTER TABLE login_codes RENAME COLUMN phone TO identifier")


def downgrade() -> None:
    op.execute("ALTER TABLE login_codes RENAME COLUMN identifier TO phone")
    op.execute("ALTER TABLE login_codes RENAME TO phone_logins")
    op.execute("ALTER TABLE users DROP COLUMN apple_sub")
