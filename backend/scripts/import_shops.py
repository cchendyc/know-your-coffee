"""Import real coffee shops into the store from Yelp and/or Google Places.
Usage: python -m scripts.import_shops "San Francisco, CA" "Oakland, CA"
"""

import asyncio
import sys

from app.core.repositories import create_repositories
from app.shops.services.import_service import ShopImportService


async def main() -> None:
    locations = sys.argv[1:] or ["San Francisco, CA"]
    repos = create_repositories()
    imports = ShopImportService(repos.shops, repos.chains)
    for location in locations:
        for name, fetcher in [("yelp", imports.from_yelp), ("google", imports.from_google)]:
            try:
                stored = await fetcher(location)
                print(f"{name}: {location}: upserted {len(stored)} shops")
            except Exception as e:  # noqa: BLE001 — a missing key skips one source, not the run
                print(f"{name}: {location}: skipped ({e})")


asyncio.run(main())
