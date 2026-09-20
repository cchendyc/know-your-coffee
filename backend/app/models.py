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

BEAN_SOURCES = [
    "IN_HOUSE_ROAST",
    "LOCAL_ROASTER",
    "NATIONAL_ROASTER",
    "MULTI_ROASTER",
    "PRIVATE_LABEL",
    "DISTRIBUTOR",
    "UNKNOWN",
]

COFFEE_TYPES = ["SINGLE_ORIGIN", "BLEND"]

# Primary post-harvest route. Fermentation styles (anaerobic etc.) layer on
# top of one of these; fermentation is free text since techniques outpace
# any fixed list.
COFFEE_PROCESSES = ["WASHED", "NATURAL", "HONEY", "WET_HULLED", "OTHER"]

ROAST_LEVELS = ["LIGHT", "MEDIUM", "DARK"]

PHOTO_KINDS = ["MACHINE", "BEANS", "DRINKS", "MENU", "VIBE", "OTHER"]

USER_ROLES = ["USER", "ADMIN"]

CLAIM_STATUSES = ["PENDING", "APPROVED", "REJECTED"]


# One espresso machine on the bar.
class Machine(TypedDict):
    brand: str
    model: str | None


# One coffee on bar. Stored sparse in jsonb; missing keys mean unknown.
class Coffee(TypedDict):
    name: str | None
    roaster: str | None
    type: str | None
    origins: list[str]
    process: str | None
    fermentation: str | None
    roastLevel: str | None
    varieties: list[str]
    tastingNotes: list[str]


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
    machines: list[Machine]
    beanSource: str
    roaster: str | None
    beanOrigins: list[str]
    coffees: list[Coffee]
    grinders: list[str]
    drinks: list[DrinkItem]
    milkBrands: list[str]
    vibe: str | None
    dogFriendly: bool | None
    wifi: bool | None
    outdoorSeating: bool | None
    photoUrl: str | None
    website: str | None
    # Set once an ownership claim is approved; owner edits outrank community reports.
    ownerId: str | None
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
    coffees: NotRequired[list[Coffee]]
    machines: NotRequired[list[Machine]]


class Report(TypedDict):
    id: str
    shopId: str
    machine: str | None
    machineModel: str | None
    machines: list[Machine] | None
    beanSource: str | None
    roaster: str | None
    beanOrigins: list[str] | None
    coffees: list[Coffee] | None
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
    googleSub: str | None
    appleSub: str | None
    email: str | None
    phone: str | None  # E.164, for phone OTP accounts
    name: str
    picture: str | None
    role: str


# A user's request to be recognized as a shop's owner; resolved by an admin.
class ShopClaim(TypedDict):
    id: str
    shopId: str
    userId: str
    status: str
    note: str | None
    createdAt: str
    resolvedAt: str | None


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
