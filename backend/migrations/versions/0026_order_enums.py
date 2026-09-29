"""store order status, fulfillment, and shipment status as native enums

Replaces text columns (and the fulfillment CHECK from 0024) with Postgres
enum types matching app.models.enums.

Revision ID: 0026
Revises: 0025
Create Date: 2026-09-28

"""
from alembic import op

revision = "0026"
down_revision = "0025"
branch_labels = None
depends_on = None

# (table, column, type, values, default)
_COLUMNS = [
    ("orders", "status", "order_status",
     ["PLACED", "SHIPPED", "DELIVERED", "READY_FOR_PICKUP", "PICKED_UP", "CANCELED"], "PLACED"),
    ("orders", "fulfillment", "fulfillment", ["SHIP", "PICKUP"], "SHIP"),
    ("shipments", "status", "shipment_status",
     ["LABEL_READY", "READY_FOR_DROPOFF", "IN_TRANSIT", "DELIVERED"], "LABEL_READY"),
]


def upgrade() -> None:
    op.execute("ALTER TABLE orders DROP CONSTRAINT orders_fulfillment_check")
    for table, column, type_name, values, default in _COLUMNS:
        labels = ", ".join(f"'{v}'" for v in values)
        op.execute(f"CREATE TYPE {type_name} AS ENUM ({labels})")
        op.execute(f"ALTER TABLE {table} ALTER COLUMN {column} DROP DEFAULT")
        op.execute(f"ALTER TABLE {table} ALTER COLUMN {column} TYPE {type_name} USING {column}::{type_name}")
        op.execute(f"ALTER TABLE {table} ALTER COLUMN {column} SET DEFAULT '{default}'")


def downgrade() -> None:
    for table, column, type_name, _values, default in _COLUMNS:
        op.execute(f"ALTER TABLE {table} ALTER COLUMN {column} DROP DEFAULT")
        op.execute(f"ALTER TABLE {table} ALTER COLUMN {column} TYPE text USING {column}::text")
        op.execute(f"ALTER TABLE {table} ALTER COLUMN {column} SET DEFAULT '{default}'")
        op.execute(f"DROP TYPE {type_name}")
    op.execute("ALTER TABLE orders ADD CONSTRAINT orders_fulfillment_check CHECK (fulfillment IN ('SHIP', 'PICKUP'))")
