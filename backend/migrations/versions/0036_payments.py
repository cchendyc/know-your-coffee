"""payments: saved payment methods, per-order payment summary, gateway ledger

Card data never lands here: payment_methods holds the gateway token plus
display fields (brand, last4, expiry). payments is the current state of an
order's charge; payment_transactions is the append-only record of every
gateway call, kept for disputes and reconciliation.

Revision ID: 0036
Revises: 0035
Create Date: 2026-09-29

"""
from alembic import op

revision = "0036"
down_revision = "0035"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        "CREATE TYPE payment_status AS ENUM ('REQUIRES_ACTION', 'AUTHORIZED', 'CAPTURED', "
        "'PARTIALLY_REFUNDED', 'REFUNDED', 'FAILED', 'CANCELED')"
    )
    op.execute("CREATE TYPE payment_operation AS ENUM ('AUTHORIZE', 'CAPTURE', 'REFUND', 'VOID')")

    op.execute("ALTER TABLE users ADD COLUMN stripe_customer_id text UNIQUE")
    op.execute("ALTER TABLE shops ADD COLUMN stripe_account_id text UNIQUE")

    op.execute(
        """
        CREATE TABLE payment_methods (
            id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            user_id bigint NOT NULL,
            gateway text NOT NULL DEFAULT 'stripe',
            gateway_method_id text NOT NULL,
            brand text NOT NULL,
            last4 text NOT NULL,
            exp_month smallint NOT NULL,
            exp_year smallint NOT NULL,
            fingerprint text,
            billing_address_id bigint,
            is_default boolean NOT NULL DEFAULT false,
            deleted boolean NOT NULL DEFAULT false,
            created_at timestamptz NOT NULL DEFAULT now(),
            UNIQUE (gateway, gateway_method_id)
        )
        """
    )
    op.execute("CREATE INDEX payment_methods_user_idx ON payment_methods (user_id) WHERE NOT deleted")

    op.execute(
        """
        CREATE TABLE payments (
            id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            order_id bigint NOT NULL UNIQUE,
            user_id bigint NOT NULL,
            gateway text NOT NULL DEFAULT 'stripe',
            gateway_intent_id text UNIQUE,
            payment_method_id bigint,
            amount_authorized_cents int NOT NULL DEFAULT 0,
            amount_captured_cents int NOT NULL DEFAULT 0,
            amount_refunded_cents int NOT NULL DEFAULT 0,
            currency text NOT NULL DEFAULT 'USD',
            method_display text,
            status payment_status NOT NULL,
            failure_reason text,
            created_at timestamptz NOT NULL DEFAULT now(),
            updated_at timestamptz NOT NULL DEFAULT now()
        )
        """
    )
    op.execute("CREATE INDEX payments_user_idx ON payments (user_id)")

    op.execute(
        """
        CREATE TABLE payment_transactions (
            id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            payment_id bigint NOT NULL,
            operation payment_operation NOT NULL,
            amount_cents int NOT NULL,
            currency text NOT NULL DEFAULT 'USD',
            gateway_entity_id text,
            gateway_status text,
            request jsonb,
            response jsonb,
            created_at timestamptz NOT NULL DEFAULT now()
        )
        """
    )
    op.execute("CREATE INDEX payment_transactions_payment_idx ON payment_transactions (payment_id, created_at)")


def downgrade() -> None:
    op.execute("DROP TABLE payment_transactions")
    op.execute("DROP TABLE payments")
    op.execute("DROP TABLE payment_methods")
    op.execute("ALTER TABLE shops DROP COLUMN stripe_account_id")
    op.execute("ALTER TABLE users DROP COLUMN stripe_customer_id")
    op.execute("DROP TYPE payment_operation")
    op.execute("DROP TYPE payment_status")
