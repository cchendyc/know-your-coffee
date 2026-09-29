"""add products, orders, and shipments for the seller hub

Verified owners sell online: products with stock counts, auto-accepted
orders with jsonb line-item snapshots, and one shipment per order.

Revision ID: 0022
Revises: 0021
Create Date: 2026-09-27

"""
from alembic import op

revision = "0022"
down_revision = "0021"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE products (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            shop_id uuid NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
            name text NOT NULL,
            variant text,
            price numeric(10,2) NOT NULL,
            stock_qty int NOT NULL DEFAULT 0 CHECK (stock_qty >= 0),
            low_stock_threshold int NOT NULL DEFAULT 5,
            active boolean NOT NULL DEFAULT true,
            created_at timestamptz NOT NULL DEFAULT now(),
            updated_at timestamptz NOT NULL DEFAULT now()
        )
        """
    )
    op.execute("CREATE INDEX products_shop ON products (shop_id)")
    op.execute(
        """
        CREATE TABLE orders (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            number bigint GENERATED ALWAYS AS IDENTITY (START WITH 1001),
            shop_id uuid NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
            buyer_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
            items jsonb NOT NULL,
            total numeric(10,2) NOT NULL,
            status text NOT NULL DEFAULT 'PLACED',
            created_at timestamptz NOT NULL DEFAULT now()
        )
        """
    )
    op.execute("CREATE INDEX orders_shop ON orders (shop_id, created_at DESC)")
    op.execute("CREATE INDEX orders_buyer ON orders (buyer_user_id)")
    op.execute(
        """
        CREATE TABLE shipments (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            order_id uuid NOT NULL UNIQUE REFERENCES orders(id) ON DELETE CASCADE,
            carrier text,
            tracking text,
            ship_by date,
            status text NOT NULL DEFAULT 'LABEL_READY',
            created_at timestamptz NOT NULL DEFAULT now(),
            updated_at timestamptz NOT NULL DEFAULT now()
        )
        """
    )


def downgrade() -> None:
    op.execute("DROP TABLE shipments")
    op.execute("DROP TABLE orders")
    op.execute("DROP TABLE products")
