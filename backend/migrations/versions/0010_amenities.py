"""add amenity booleans (null = unknown) to shops and reports

Revision ID: 0010
Revises: 0009
Create Date: 2026-09-19

"""
from alembic import op

revision = "0010"
down_revision = "0009"
branch_labels = None
depends_on = None

_COLUMNS = ["dog_friendly", "wifi", "outdoor_seating"]


def upgrade() -> None:
    for table in ("shops", "reports"):
        for col in _COLUMNS:
            op.execute(f"ALTER TABLE {table} ADD COLUMN {col} boolean")


def downgrade() -> None:
    for table in ("shops", "reports"):
        for col in _COLUMNS:
            op.execute(f"ALTER TABLE {table} DROP COLUMN {col}")
