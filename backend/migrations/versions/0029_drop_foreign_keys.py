"""drop foreign key constraints; reference tables by plain *_id columns

Whatnot's migration checklist bans FK constraints ("soft foreign keys"):
they lock the parent row on every child write and make deletes cascade
invisibly. Repositories now delete dependent rows themselves.
Every *_id column keeps or gains a plain index for joins and cleanup.

Revision ID: 0029
Revises: 0028
Create Date: 2026-09-28

"""
from alembic import op

revision = "0029"
down_revision = "0028"
branch_labels = None
depends_on = None

# (table, column, referenced table, ON DELETE action)
_FKS = [
    ("shops", "chain_id", "chains", "SET NULL"),
    ("shops", "owner_user_id", "users", "SET NULL"),
    ("reports", "shop_id", "shops", None),
    ("reports", "user_id", "users", None),
    ("shop_photos", "shop_id", "shops", "CASCADE"),
    ("shop_photos", "user_id", "users", None),
    ("shop_claims", "shop_id", "shops", None),
    ("shop_claims", "user_id", "users", None),
    ("products", "shop_id", "shops", "CASCADE"),
    ("orders", "buyer_user_id", "users", "SET NULL"),
    ("orders", "shop_id", "shops", "CASCADE"),
    ("shipments", "order_id", "orders", "CASCADE"),
    ("shop_bookmarks", "shop_id", "shops", "CASCADE"),
    ("shop_bookmarks", "user_id", "users", "CASCADE"),
    ("shop_visits", "shop_id", "shops", "CASCADE"),
    ("shop_visits", "user_id", "users", "CASCADE"),
]

# *_id columns that relied on the FK alone and had no index.
_INDEXES = [
    ("shops_owner_user_id_idx", "shops", "owner_user_id"),
    ("reports_shop_id_idx", "reports", "shop_id"),
    ("reports_user_id_idx", "reports", "user_id"),
    ("shop_photos_user_id_idx", "shop_photos", "user_id"),
    ("shop_claims_shop_id_idx", "shop_claims", "shop_id"),
]


def upgrade() -> None:
    for table, column, _, _ in _FKS:
        op.execute(f"ALTER TABLE {table} DROP CONSTRAINT IF EXISTS {table}_{column}_fkey")
    for name, table, column in _INDEXES:
        op.execute(f"CREATE INDEX IF NOT EXISTS {name} ON {table} ({column})")


def downgrade() -> None:
    for name, _, _ in _INDEXES:
        op.execute(f"DROP INDEX IF EXISTS {name}")
    for table, column, parent, on_delete in _FKS:
        action = f" ON DELETE {on_delete}" if on_delete else ""
        op.execute(
            f"ALTER TABLE {table} ADD CONSTRAINT {table}_{column}_fkey "
            f"FOREIGN KEY ({column}) REFERENCES {parent}(id){action}"
        )
