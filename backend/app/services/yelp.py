"""Yelp Fusion: shop import and review excerpts."""

import httpx
from graphql import GraphQLError

from .. import settings
from ..models import NewShop


async def fetch_shops_from_yelp(location: str) -> list[NewShop]:
    if not settings.YELP_API_KEY:
        raise GraphQLError("Yelp import is not configured (server is missing YELP_API_KEY).")

    async with httpx.AsyncClient(timeout=30) as client:
        res = await client.get(
            "https://api.yelp.com/v3/businesses/search",
            params={"term": "coffee", "location": location, "categories": "coffee,coffeeroasteries,cafes", "limit": 50},
            headers={"authorization": f"Bearer {settings.YELP_API_KEY}"},
        )
    if res.status_code != 200:
        raise GraphQLError(f"Yelp request failed: {res.status_code} {res.text}")

    shops: list[NewShop] = []
    for b in res.json().get("businesses", []):
        if not b.get("location", {}).get("address1") or not b.get("coordinates"):
            continue
        shops.append(
            {
                "name": b["name"],
                "address": b["location"]["address1"],
                "city": b["location"]["city"],
                "lat": b["coordinates"]["latitude"],
                "lng": b["coordinates"]["longitude"],
                "machine": "UNKNOWN",
                "machineModel": None,
                "beanSource": "UNKNOWN",
                "roaster": None,
                "beanOrigins": [],
                "grinders": [],
                "drinks": [],
                "milkBrands": [],
                "vibe": None,
                "photoUrl": None,
                "website": None,
            }
        )
    return shops


async def fetch_yelp_reviews(name: str, address: str, city: str) -> list[str]:
    """Returns up to 3 review excerpts for a shop, or [] if no Yelp match."""
    if not settings.YELP_API_KEY:
        return []
    headers = {"authorization": f"Bearer {settings.YELP_API_KEY}"}

    async with httpx.AsyncClient(timeout=30) as client:
        match_res = await client.get(
            "https://api.yelp.com/v3/businesses/matches",
            params={"name": name, "address1": address, "city": city, "state": "CA", "country": "US"},
            headers=headers,
        )
        if match_res.status_code != 200:
            return []
        businesses = match_res.json().get("businesses", [])
        if not businesses:
            return []
        review_res = await client.get(
            f"https://api.yelp.com/v3/businesses/{businesses[0]['id']}/reviews",
            params={"limit": 3, "sort_by": "newest"},
            headers=headers,
        )
    if review_res.status_code != 200:
        return []
    return [r["text"] for r in review_res.json().get("reviews", [])]
