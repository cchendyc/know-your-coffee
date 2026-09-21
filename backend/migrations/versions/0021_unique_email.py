"""unique email per account

Google, Apple, and email-code sign-in all key off the same address, so
duplicates must collapse before the unique index can be added.

Revision ID: 0021
Revises: 0020
Create Date: 2026-09-20

"""
from alembic import op

revision = "0021"
down_revision = "0020"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE email_dupes_0020 AS
        WITH ranked AS (
            SELECT id, lower(email) AS e,
                   row_number() OVER (
                       PARTITION BY lower(email)
                       ORDER BY (google_sub IS NOT NULL) DESC,
                                (apple_sub IS NOT NULL) DESC,
                                created_at ASC
                   ) AS n
            FROM users
            WHERE email IS NOT NULL AND email <> ''
        )
        SELECT u.id AS dupe_id, k.id AS keep_id
        FROM users u
        JOIN ranked k ON lower(u.email) = k.e AND k.n = 1
        WHERE u.email IS NOT NULL AND u.id <> k.id
        """
    )
    op.execute(
        """
        UPDATE reports r SET user_id = d.keep_id
        FROM email_dupes_0020 d WHERE r.user_id = d.dupe_id
        """
    )
    op.execute(
        """
        UPDATE shop_photos p SET user_id = d.keep_id
        FROM email_dupes_0020 d WHERE p.user_id = d.dupe_id
        """
    )
    op.execute(
        """
        UPDATE shop_claims c SET user_id = d.keep_id
        FROM email_dupes_0020 d WHERE c.user_id = d.dupe_id
        """
    )
    op.execute(
        """
        UPDATE shops s SET owner_user_id = d.keep_id
        FROM email_dupes_0020 d WHERE s.owner_user_id = d.dupe_id
        """
    )
    op.execute(
        """
        INSERT INTO user_shops (user_id, shop_id, saved, been)
        SELECT d.keep_id, us.shop_id, us.saved, us.been
        FROM user_shops us
        JOIN email_dupes_0020 d ON us.user_id = d.dupe_id
        ON CONFLICT (user_id, shop_id) DO UPDATE SET
          saved = user_shops.saved OR EXCLUDED.saved,
          been = user_shops.been OR EXCLUDED.been
        """
    )
    op.execute("DELETE FROM user_shops WHERE user_id IN (SELECT dupe_id FROM email_dupes_0020)")
    op.execute("DELETE FROM users WHERE id IN (SELECT dupe_id FROM email_dupes_0020)")
    op.execute("DROP TABLE email_dupes_0020")
    op.execute(
        "CREATE UNIQUE INDEX users_email_lower ON users (lower(email)) WHERE email IS NOT NULL AND email <> ''"
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS users_email_lower")
