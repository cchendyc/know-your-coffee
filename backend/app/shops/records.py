"""Import payloads produced by the Google/Yelp services."""

from typing import NotRequired, TypedDict


# A shop as produced by importers: no id or timestamps yet. Keys are shops
# column names, so repositories can persist the payload as-is.
class NewShop(TypedDict):
    name: str
    address: str
    city: str
    lat: float
    lng: float
    machine: str
    machine_model: str | None
    bean_source: str
    roaster: str | None
    bean_origins: list[str]
    grinders: list[str]
    drinks: list[dict]
    milk_brands: list[str]
    vibe: str | None
    photo_url: str | None
    website: str | None
    dog_friendly: NotRequired[bool | None]
    wifi: NotRequired[bool | None]
    outdoor_seating: NotRequired[bool | None]
    coffees: NotRequired[list[dict]]
    machines: NotRequired[list[dict]]
