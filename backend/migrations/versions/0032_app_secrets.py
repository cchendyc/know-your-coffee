"""app_secrets: server-generated secrets that must survive restarts

Holds the session-signing key when SESSION_SECRET is not configured, so a
free-tier Render spin-down no longer signs every user out.

Revision ID: 0032
Revises: 0031
Create Date: 2026-09-28

"""
import sqlalchemy as sa
from alembic import op

revision = "0032"
down_revision = "0031"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "app_secrets",
        sa.Column("name", sa.Text(), primary_key=True),
        sa.Column("value", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )


def downgrade() -> None:
    op.drop_table("app_secrets")
