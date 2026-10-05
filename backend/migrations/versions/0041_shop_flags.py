"""shop_flags: rule violations reported against a shop

One row per signed-in user per shop. Not a community update.

Revision ID: 0041
Revises: 0040
Create Date: 2026-10-03

"""
from alembic import op

revision = "0041"
down_revision = "0040"
branch_labels = None
depends_on = None

_REASONS = "'NOT_A_COFFEE_SHOP', 'CLOSED', 'WRONG_INFO', 'INAPPROPRIATE', 'SPAM'"


def upgrade() -> None:
    op.execute(
        f"""
        CREATE TABLE shop_flags (
            id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            shop_id bigint NOT NULL,
            user_id bigint,
            reason text NOT NULL,
            created_at timestamptz NOT NULL DEFAULT now(),
            CONSTRAINT shop_flags_reason_check CHECK (reason IN ({_REASONS}))
        )
        """
    )
    op.execute("CREATE INDEX shop_flags_shop ON shop_flags (shop_id)")
    op.execute(
        "CREATE UNIQUE INDEX shop_flags_shop_user ON shop_flags (shop_id, user_id) WHERE user_id IS NOT NULL"
    )


def downgrade() -> None:
    op.execute("DROP TABLE shop_flags")
