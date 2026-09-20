"""One-off cleanup: clear machine guesses that came from over-eager enrichment
patterns (e.g. "Strada" in a shop name, "a decent espresso" in a review).
Keeps machines confirmed by user reports.
Usage: python -m scripts.reset_machines
"""

import sys

import psycopg

from app import settings

if not settings.DATABASE_URL:
    print("DATABASE_URL is not set")
    sys.exit(1)

with psycopg.connect(settings.DATABASE_URL) as conn:
    rows = conn.execute(
        """UPDATE shops SET machine = 'UNKNOWN', machine_model = NULL
           WHERE machine <> 'UNKNOWN'
             AND id NOT IN (SELECT shop_id FROM reports WHERE machine IS NOT NULL)
           RETURNING name"""
    ).fetchall()

print(f"reset {len(rows)}: {', '.join(r[0] for r in rows)}")
