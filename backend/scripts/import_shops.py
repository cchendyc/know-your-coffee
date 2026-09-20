"""Import real coffee shops into the store from Yelp and/or Google Places.
Usage: python -m scripts.import_shops "San Francisco, CA" "Oakland, CA"
"""

import asyncio
import sys

from app.repository import create_repository
from app.services.google import fetch_shops_from_google
from app.services.yelp import fetch_shops_from_yelp


async def main() -> None:
    locations = sys.argv[1:] or ["San Francisco, CA"]
    repo = create_repository()
    for location in locations:
        for name, fetcher in [("yelp", fetch_shops_from_yelp), ("google", fetch_shops_from_google)]:
            try:
                shops = await fetcher(location)
                stored = repo.upsert_shops(shops)
                print(f"{name}: {location}: upserted {len(stored)} shops")
            except Exception as e:  # noqa: BLE001 — a missing key skips one source, not the run
                print(f"{name}: {location}: skipped ({e})")


asyncio.run(main())
