"""Backfill shop profile photos and websites from Google Places.
Usage: python -m scripts.backfill [maxShops]
"""

import asyncio
import sys

from app.core.repositories import create_repositories
from app.services.google import find_shop_meta


async def main() -> None:
    max_shops = int(sys.argv[1]) if len(sys.argv) > 1 else None
    repos = create_repositories()
    shops, _total = repos.shops.list({"limit": 10_000})
    shops = [s for s in shops if not s.photo_url or not s.website]
    print(f"{len(shops)} shops missing a photo or website; processing up to {max_shops or 'all'}")

    filled = 0
    for shop in shops[:max_shops]:
        try:
            meta = await find_shop_meta(shop.name, shop.address, shop.city)
            if meta["photo_url"] or meta["website"]:
                repos.shops.set_meta(str(shop.id), meta["photo_url"], meta["website"])
                filled += 1
            await asyncio.sleep(0.15)
        except Exception as e:  # noqa: BLE001 — one bad shop must not stop the run
            print(f"{shop.name}: failed ({str(e)[:120]})")

    linked = repos.chains.relink()
    print(f"done: {filled} shops updated, {len(shops) - filled} without new data, {linked} shops linked into chains")


asyncio.run(main())
