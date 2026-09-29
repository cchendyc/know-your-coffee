"""Bulk shop import: dedupe against existing shops, then relink chains."""

from ... import models as m
from ...services.google import fetch_shops_from_google, new_shop_from_place
from ...services.yelp import fetch_shops_from_yelp
from ..records import NewShop


class ShopImportService:
    def __init__(self, shops, chains):
        self._shops = shops
        self._chains = chains

    def store(self, news: list[NewShop]) -> list[m.Shop]:
        ids = []
        for new in news:
            existing = self._shops.find_matching(new["name"], new["lat"], new["lng"])
            shop = existing or self._shops.insert(dict(new))
            ids.append(str(shop.id))
        self._chains.relink()
        # Relink may have moved chain assignments after the rows detached; re-fetch.
        return [shop for shop_id in ids if (shop := self._shops.get(shop_id))]

    async def from_place(self, place_id: str) -> m.Shop | None:
        new = await new_shop_from_place(place_id)
        return self.store([new])[0] if new else None

    async def from_yelp(self, location: str) -> list[m.Shop]:
        return self.store(await fetch_shops_from_yelp(location))

    async def from_google(self, location: str) -> list[m.Shop]:
        return self.store(await fetch_shops_from_google(location))
