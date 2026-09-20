"""create shops and reports tables with enums

Revision ID: 0001
Revises:
Create Date: 2026-09-19

"""
from alembic import op

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TYPE machine_brand AS ENUM (
            'LA_MARZOCCO', 'SLAYER', 'SYNESSO', 'KEES_VAN_DER_WESTEN',
            'VICTORIA_ARDUINO', 'NUOVA_SIMONELLI', 'MODBAR', 'ROCKET',
            'RANCILIO', 'BREVILLE', 'DECENT', 'OTHER', 'UNKNOWN'
        )
        """
    )
    op.execute(
        """
        CREATE TYPE bean_source AS ENUM (
            'IN_HOUSE_ROAST', 'LOCAL_ROASTER', 'NATIONAL_ROASTER',
            'MULTI_ROASTER', 'UNKNOWN'
        )
        """
    )
    op.execute("CREATE TYPE report_source AS ENUM ('TEXT', 'PHOTO')")
    op.execute(
        """
        CREATE TABLE shops (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            name text NOT NULL,
            address text NOT NULL,
            city text NOT NULL,
            lat double precision NOT NULL,
            lng double precision NOT NULL,
            machine machine_brand NOT NULL DEFAULT 'UNKNOWN',
            machine_model text,
            bean_source bean_source NOT NULL DEFAULT 'UNKNOWN',
            roaster text,
            milk_options jsonb NOT NULL DEFAULT '[]'::jsonb,
            milk_brand text,
            updated_at timestamptz NOT NULL DEFAULT now()
        )
        """
    )
    op.execute(
        """
        CREATE TABLE reports (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            shop_id uuid NOT NULL REFERENCES shops(id),
            machine machine_brand,
            machine_model text,
            bean_source bean_source,
            roaster text,
            milk_options jsonb,
            milk_brand text,
            note text,
            source report_source NOT NULL DEFAULT 'TEXT',
            created_at timestamptz NOT NULL DEFAULT now()
        )
        """
    )


def downgrade() -> None:
    op.execute("DROP TABLE reports")
    op.execute("DROP TABLE shops")
    op.execute("DROP TYPE report_source")
    op.execute("DROP TYPE bean_source")
    op.execute("DROP TYPE machine_brand")
