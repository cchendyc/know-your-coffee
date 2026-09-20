"""Domain models. Dicts use camelCase keys so they map 1:1 onto schema.graphql."""

from typing import NotRequired, TypedDict

MACHINE_BRANDS = [
    "LA_MARZOCCO",
    "SLAYER",
    "SYNESSO",
    "KEES_VAN_DER_WESTEN",
    "VICTORIA_ARDUINO",
    "NUOVA_SIMONELLI",
    "MODBAR",
    "ROCKET",
    "RANCILIO",
    "BREVILLE",
    "DECENT",
    "FAEMA",
    "OTHER",
    "UNKNOWN",
]

BEAN_SOURCES = ["IN_HOUSE_ROAST", "LOCAL_ROASTER", "NATIONAL_ROASTER", "MULTI_ROASTER", "UNKNOWN"]

PHOTO_KINDS = ["MACHINE", "BEANS", "DRINKS", "MENU", "VIBE", "OTHER"]


class DrinkItem(TypedDict):
    name: str
    price: float | None


class Reporter(TypedDict):
    name: str
    picture: str | None


class Chain(TypedDict):
    id: str
    name: str
    slug: str
    website: str | None


class CoffeeShop(TypedDict):
    id: str
    name: str
    address: str
    city: str
    lat: float
    lng: float
    chainId: str | None
    machine: str
    machineModel: str | None
    beanSource: str
    roaster: str | None
    beanOrigins: list[str]
    grinders: list[str]
    drinks: list[DrinkItem]
    milkBrands: list[str]
    vibe: str | None
    dogFriendly: bool | None
    wifi: bool | None
    outdoorSeating: bool | None
    photoUrl: str | None
    website: str | None
    savedByMe: bool
    beenByMe: bool
    updatedAt: str


# A shop as produced by importers: no id/updatedAt/viewer flags yet.
class NewShop(TypedDict):
    name: str
    address: str
    city: str
    lat: float
    lng: float
    machine: str
    machineModel: str | None
    beanSource: str
    roaster: str | None
    beanOrigins: list[str]
    grinders: list[str]
    drinks: list[DrinkItem]
    milkBrands: list[str]
    vibe: str | None
    photoUrl: str | None
    website: str | None
    dogFriendly: NotRequired[bool | None]
    wifi: NotRequired[bool | None]
    outdoorSeating: NotRequired[bool | None]


class Report(TypedDict):
    id: str
    shopId: str
    machine: str | None
    machineModel: str | None
    beanSource: str | None
    roaster: str | None
    beanOrigins: list[str] | None
    grinders: list[str] | None
    drinks: list[DrinkItem] | None
    milkBrands: list[str] | None
    dogFriendly: bool | None
    wifi: bool | None
    outdoorSeating: bool | None
    note: str | None
    source: str
    reporter: Reporter | None
    createdAt: str


class User(TypedDict):
    id: str
    googleSub: str
    email: str
    name: str
    picture: str | None


class ShopPhoto(TypedDict):
    id: str
    shopId: str
    kind: str
    data: str
    uploader: Reporter | None
    createdAt: str


class MachineGuess(TypedDict):
    machine: str
    machineModel: str | None
    confidence: float
    notes: str | None
