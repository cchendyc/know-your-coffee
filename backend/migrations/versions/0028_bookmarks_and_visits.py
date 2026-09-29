"""split user_shops into shop_bookmarks and shop_visits

One table per relationship, as Whatnot does (livestream_watchlists,
user_follows): a row means the relationship exists and undoing it deletes
the row. Follows and product bookmarks become sibling tables later.
user_shops had no per-flag timestamp, so migrated rows take its updated_at
as created_at.

Revision ID: 0028
Revises: 0027
Create Date: 2026-09-28

"""
from alembic import op

revision = "0028"
down_revision = "0027"
branch_labels = None
depends_on = None

# (new table, user_shops flag it replaces)
_TABLES = [("shop_bookmarks", "saved"), ("shop_visits", "been")]


def upgrade() -> None:
    for table, flag in _TABLES:
        op.execute(
            f"""
            CREATE TABLE {table} (
                user_id bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                shop_id bigint NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
                created_at timestamptz NOT NULL DEFAULT now(),
                PRIMARY KEY (user_id, shop_id)
            )
            """
        )
        op.execute(f"CREATE INDEX {table}_user_created ON {table} (user_id, created_at DESC)")
        op.execute(f"CREATE INDEX {table}_shop ON {table} (shop_id)")
        op.execute(
            f"""INSERT INTO {table} (user_id, shop_id, created_at)
                SELECT user_id, shop_id, updated_at FROM user_shops WHERE {flag}"""
        )
    op.execute("DROP TABLE user_shops")


def downgrade() -> None:
    op.execute(
        """
        CREATE TABLE user_shops (
            user_id bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            shop_id bigint NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
            saved boolean NOT NULL DEFAULT false,
            been boolean NOT NULL DEFAULT false,
            updated_at timestamptz NOT NULL DEFAULT now(),
            PRIMARY KEY (user_id, shop_id)
        )
        """
    )
    for table, flag in _TABLES:
        op.execute(
            f"""INSERT INTO user_shops (user_id, shop_id, {flag}, updated_at)
                SELECT user_id, shop_id, true, created_at FROM {table}
                ON CONFLICT (user_id, shop_id) DO UPDATE SET {flag} = true"""
        )
        op.execute(f"DROP TABLE {table}")
