"""Group existing shops into chains (shared website host or brand name).
Usage: python -m scripts.link_chains
Runs automatically after import/upsert and website backfill; this is for a
one-shot after the chains migration.
"""

import sys

from app import settings
from app.repository import create_repository

if not settings.DATABASE_URL:
    print("DATABASE_URL is not set; chain linking needs the Postgres store")
    sys.exit(1)

assigned = create_repository().relink_chains()
print(f"done: linked {assigned} shops into chains")
