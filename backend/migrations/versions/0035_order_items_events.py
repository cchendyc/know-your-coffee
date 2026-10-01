"""orders: PACKED state, money in cents, line items and events as rows

order_items replaces the orders.items jsonb; the column stays until the
repositories read from the table, then a later migration drops it (same
for orders.total). New money columns are nullable for the same reason.

ALTER TYPE ... ADD VALUE cannot run inside the migration transaction, so
it goes through an autocommit block.

Revision ID: 0035
Revises: 0034
Create Date: 2026-09-29

"""
from alembic import op

revision = "0035"
down_revision = "0034"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.get_context().autocommit_block():
        op.execute("ALTER TYPE order_status ADD VALUE IF NOT EXISTS 'PACKED' AFTER 'PLACED'")

    op.execute(
        """
        ALTER TABLE orders
            ADD COLUMN shipping_address_id bigint,
            ADD COLUMN subtotal_cents int,
            ADD COLUMN shipping_cents int NOT NULL DEFAULT 0,
            ADD COLUMN total_cents int,
            ADD COLUMN currency text NOT NULL DEFAULT 'USD',
            ADD COLUMN payment_id bigint,
            ADD COLUMN pickup_code text,
            ADD COLUMN cancelled_at timestamptz,
            ADD COLUMN cancellation_reason text,
            ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now()
        """
    )
    # Shipping has been free so far: subtotal equals total.
    op.execute("UPDATE orders SET total_cents = round(total * 100), subtotal_cents = round(total * 100)")

    op.execute(
        """
        CREATE TABLE order_items (
            id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            order_id bigint NOT NULL,
            product_id bigint NOT NULL,
            name text NOT NULL,
            subtitle text,
            unit_price_cents int NOT NULL,
            quantity int NOT NULL CHECK (quantity > 0),
            shipment_id bigint,
            created_at timestamptz NOT NULL DEFAULT now()
        )
        """
    )
    op.execute("CREATE INDEX order_items_order_idx ON order_items (order_id)")
    op.execute("CREATE INDEX order_items_product_idx ON order_items (product_id)")
    op.execute(
        """
        INSERT INTO order_items (order_id, product_id, name, unit_price_cents, quantity, created_at)
        SELECT o.id, (i->>'productId')::bigint, i->>'name',
               round((i->>'unitPrice')::numeric * 100)::int, (i->>'qty')::int, o.created_at
        FROM orders o, jsonb_array_elements(o.items) i
        """
    )
    op.execute(
        """
        UPDATE products p SET sold_count = s.qty
        FROM (SELECT product_id, sum(quantity)::int AS qty FROM order_items GROUP BY product_id) s
        WHERE p.id = s.product_id
        """
    )

    op.execute(
        """
        CREATE TABLE order_events (
            id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            order_id bigint NOT NULL,
            status order_status NOT NULL,
            actor_user_id bigint,
            note text,
            created_at timestamptz NOT NULL DEFAULT now()
        )
        """
    )
    op.execute("CREATE INDEX order_events_order_idx ON order_events (order_id, created_at)")
    op.execute("INSERT INTO order_events (order_id, status, created_at) SELECT id, 'PLACED', created_at FROM orders")

    op.execute(
        """
        ALTER TABLE shipments
            ADD COLUMN label_url text,
            ADD COLUMN cost_cents int,
            ADD COLUMN tracking_status text,
            ADD COLUMN dropped_off_at timestamptz,
            ADD COLUMN delivered_at timestamptz
        """
    )


def downgrade() -> None:
    op.execute(
        "ALTER TABLE shipments DROP COLUMN delivered_at, DROP COLUMN dropped_off_at, "
        "DROP COLUMN tracking_status, DROP COLUMN cost_cents, DROP COLUMN label_url"
    )
    op.execute("DROP TABLE order_events")
    op.execute("DROP TABLE order_items")
    op.execute(
        """
        ALTER TABLE orders
            DROP COLUMN updated_at, DROP COLUMN cancellation_reason, DROP COLUMN cancelled_at,
            DROP COLUMN pickup_code, DROP COLUMN payment_id, DROP COLUMN currency, DROP COLUMN total_cents,
            DROP COLUMN shipping_cents, DROP COLUMN subtotal_cents, DROP COLUMN shipping_address_id
        """
    )
    # Postgres cannot drop an enum value; PACKED stays.
