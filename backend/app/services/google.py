"""Google Places: shop import, geocoding, photos, websites, and reviews."""

from typing import TypedDict

import httpx
from graphql import GraphQLError

from .. import settings
from ..models import NewShop

_SEARCH_URL = "https://places.googleapis.com/v1/places:searchText"

# Keep type-ahead results near the Bay Area.
_BAY_AREA_BIAS = {
    "rectangle": {
        "low": {"latitude": 36.9, "longitude": -123.15},
        "high": {"latitude": 38.7, "longitude": -121.2},
    }
}


def _component(place: dict, kind: str) -> str | None:
    for c in place.get("addressComponents", []):
        if kind in c.get("types", []):
            return c.get("longText")
    return None


def _empty_shop_fields() -> dict:
    return {
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


async def _search(
    client: httpx.AsyncClient, query: str, field_mask: str, page_size: int, bias: dict | None = None
) -> list[dict]:
    body: dict = {"textQuery": query, "pageSize": page_size}
    if bias:
        body["locationBias"] = bias
    res = await client.post(
        _SEARCH_URL,
        headers={
            "content-type": "application/json",
            "x-goog-api-key": settings.GOOGLE_PLACES_API_KEY,
            "x-goog-fieldmask": field_mask,
        },
        json=body,
    )
    if res.status_code != 200:
        raise GraphQLError(f"Google Places request failed: {res.status_code} {res.text}")
    return res.json().get("places") or []


async def search_places(query: str) -> list[dict]:
    """Type-ahead suggestions for the add-shop form."""
    if not settings.GOOGLE_PLACES_API_KEY:
        raise GraphQLError("Shop search is not configured (server is missing GOOGLE_PLACES_API_KEY).")
    async with httpx.AsyncClient(timeout=15) as client:
        places = await _search(
            client,
            query,
            "places.id,places.displayName,places.formattedAddress",
            6,
            bias=_BAY_AREA_BIAS,
        )
    return [
        {"placeId": p["id"], "name": p["displayName"]["text"], "address": p.get("formattedAddress", "")}
        for p in places
    ]


async def place_preview(place_id: str) -> dict | None:
    """Full details for one place: prefill data plus photo and website."""
    if not settings.GOOGLE_PLACES_API_KEY:
        raise GraphQLError("Shop search is not configured (server is missing GOOGLE_PLACES_API_KEY).")
    async with httpx.AsyncClient(timeout=30) as client:
        res = await client.get(
            f"https://places.googleapis.com/v1/places/{place_id}",
            headers={
                "x-goog-api-key": settings.GOOGLE_PLACES_API_KEY,
                "x-goog-fieldmask": "id,displayName,formattedAddress,addressComponents,location,photos,websiteUri",
            },
        )
    if res.status_code != 200:
        return None
    p = res.json()
    photos = p.get("photos") or []
    street = " ".join(x for x in [_component(p, "street_number"), _component(p, "route")] if x)
    return {
        "placeId": p["id"],
        "name": p["displayName"]["text"],
        "address": street or (p.get("formattedAddress", "").split(",")[0]),
        "city": _component(p, "locality") or _component(p, "sublocality") or "",
        "lat": p["location"]["latitude"],
        "lng": p["location"]["longitude"],
        "photoUrl": await resolve_photo_url(photos[0]["name"]) if photos else None,
        "website": p.get("websiteUri"),
    }


async def new_shop_from_place(place_id: str) -> NewShop | None:
    preview = await place_preview(place_id)
    if not preview:
        return None
    return {
        **_empty_shop_fields(),
        "name": preview["name"],
        "address": preview["address"],
        "city": preview["city"],
        "lat": preview["lat"],
        "lng": preview["lng"],
        "photoUrl": preview["photoUrl"],
        "website": preview["website"],
    }


async def fetch_shops_from_google(location: str) -> list[NewShop]:
    if not settings.GOOGLE_PLACES_API_KEY:
        raise GraphQLError("Google import is not configured (server is missing GOOGLE_PLACES_API_KEY).")

    async with httpx.AsyncClient(timeout=30) as client:
        places = await _search(
            client,
            f"coffee shop in {location}",
            "places.displayName,places.location,places.addressComponents",
            20,
        )

    shops: list[NewShop] = []
    for p in places:
        street_number = _component(p, "street_number")
        route = _component(p, "route")
        city = _component(p, "locality")
        if not route or not city:
            continue
        shops.append(
            {
                "name": p["displayName"]["text"],
                "address": " ".join(x for x in [street_number, route] if x),
                "city": city,
                "lat": p["location"]["latitude"],
                "lng": p["location"]["longitude"],
                **_empty_shop_fields(),
            }
        )
    return shops


async def resolve_photo_url(photo_name: str) -> str | None:
    """Resolves a Places photo reference to a stable googleusercontent URL,
    so the browser never sees our API key."""
    if not settings.GOOGLE_PLACES_API_KEY:
        return None
    async with httpx.AsyncClient(timeout=30) as client:
        res = await client.get(
            f"https://places.googleapis.com/v1/{photo_name}/media",
            params={"maxWidthPx": 640, "skipHttpRedirect": "true"},
            headers={"x-goog-api-key": settings.GOOGLE_PLACES_API_KEY},
        )
    if res.status_code != 200:
        return None
    return res.json().get("photoUri")


class ShopMeta(TypedDict):
    photoUrl: str | None
    website: str | None


async def find_shop_meta(name: str, address: str, city: str) -> ShopMeta:
    """Finds the first Places photo and the shop's own website, or nulls."""
    empty: ShopMeta = {"photoUrl": None, "website": None}
    if not settings.GOOGLE_PLACES_API_KEY:
        return empty
    try:
        async with httpx.AsyncClient(timeout=30) as client:
            places = await _search(client, f"{name} {address} {city}", "places.photos,places.websiteUri", 1)
    except GraphQLError:
        return empty
    if not places:
        return empty
    photos = places[0].get("photos") or []
    return {
        "photoUrl": await resolve_photo_url(photos[0]["name"]) if photos else None,
        "website": places[0].get("websiteUri"),
    }


class GoogleReviewData(TypedDict):
    summary: str | None
    reviews: list[str]


async def fetch_google_reviews(name: str, address: str, city: str) -> GoogleReviewData:
    """Returns up to 5 review texts and the editorial summary, or empty data if no match."""
    empty: GoogleReviewData = {"summary": None, "reviews": []}
    if not settings.GOOGLE_PLACES_API_KEY:
        return empty

    async with httpx.AsyncClient(timeout=30) as client:
        try:
            places = await _search(client, f"{name} {address} {city}", "places.id", 1)
        except GraphQLError:
            return empty
        if not places:
            return empty
        res = await client.get(
            f"https://places.googleapis.com/v1/places/{places[0]['id']}",
            headers={"x-goog-api-key": settings.GOOGLE_PLACES_API_KEY, "x-goog-fieldmask": "reviews,editorialSummary"},
        )
    if res.status_code != 200:
        return empty
    detail = res.json()
    reviews = [r.get("text", {}).get("text") for r in detail.get("reviews", [])]
    return {
        "summary": (detail.get("editorialSummary") or {}).get("text"),
        "reviews": [r for r in reviews if r],
    }
