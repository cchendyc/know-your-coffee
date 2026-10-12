"""Option lists for the report sheets.

The server owns every list so clients render whatever arrives. Free-text
lists merge values already on shops (most common first) with a curated seed
so a fresh database still offers suggestions.
"""

from collections import Counter
from typing import Any, Iterable

from app.models.enums import ShopReportReason

# MACHINE_BRANDS minus OTHER and UNKNOWN; clients send OTHER for unmatched text.
MACHINE_BRAND_LABELS = {
    "LA_MARZOCCO": "La Marzocco",
    "SLAYER": "Slayer",
    "SYNESSO": "Synesso",
    "KEES_VAN_DER_WESTEN": "Kees van der Westen",
    "VICTORIA_ARDUINO": "Victoria Arduino",
    "NUOVA_SIMONELLI": "Nuova Simonelli",
    "MODBAR": "Modbar",
    "ROCKET": "Rocket",
    "RANCILIO": "Rancilio",
    "BREVILLE": "Breville",
    "DECENT": "Decent",
    "FAEMA": "Faema",
}

MACHINE_MODELS = {
    "LA_MARZOCCO": ["Linea PB", "Linea Classic", "Linea Mini", "Strada", "GB5", "KB90"],
    "SLAYER": ["Steam LP", "Steam EP", "Espresso"],
    "SYNESSO": ["MVP Hydra", "S200", "ES.1"],
    "KEES_VAN_DER_WESTEN": ["Spirit", "Mirage", "Speedster"],
    "VICTORIA_ARDUINO": ["Black Eagle Maverick", "Eagle One", "White Eagle"],
    "NUOVA_SIMONELLI": ["Aurelia Wave", "Appia Life"],
    "MODBAR": ["Espresso AV", "Pour-Over", "Steam"],
    "ROCKET": ["R9 One", "RE Doppia"],
    "RANCILIO": ["Classe 20", "Classe 11", "Specialty RS1"],
    "BREVILLE": ["Barista Express", "Oracle Touch"],
    "DECENT": ["DE1PRO", "DE1XL"],
    "FAEMA": ["E71", "E61 Legend", "President"],
}

# BEAN_SOURCES minus UNKNOWN.
BEAN_SOURCE_LABELS = {
    "IN_HOUSE_ROAST": "Roasts in-house",
    "LOCAL_ROASTER": "Local roaster",
    "NATIONAL_ROASTER": "National roaster",
    "MULTI_ROASTER": "Multi-roaster",
    "PRIVATE_LABEL": "Private label",
    "DISTRIBUTOR": "Commercial distributor",
}

COFFEE_TYPE_LABELS = {"SINGLE_ORIGIN": "Single origin", "BLEND": "Blend"}

PROCESS_LABELS = {
    "WASHED": "Washed",
    "NATURAL": "Natural",
    "HONEY": "Honey",
    "WET_HULLED": "Wet-hulled",
    "OTHER": "Other",
}

ROAST_LEVEL_LABELS = {"LIGHT": "Light", "MEDIUM": "Medium", "DARK": "Dark"}

# Only ReportInput fields that hold a tri-state Boolean; value is the field name.
AMENITY_LABELS = {
    "dogFriendly": "Dog friendly",
    "wifi": "Wi-Fi",
    "outdoorSeating": "Outdoor seating",
}

# NOTE saves ReportInput.note; the rest flag the shop through reportShop.
REPORT_REASON_LABELS = {
    "NOTE": "Just a note",
    ShopReportReason.WRONG_INFO.value: "Wrong info",
    ShopReportReason.CLOSED.value: "Closed or moved",
    ShopReportReason.NOT_A_COFFEE_SHOP.value: "Not a coffee shop",
    ShopReportReason.INAPPROPRIATE.value: "Inappropriate content",
    ShopReportReason.SPAM.value: "Spam or scam",
}

GRINDERS = [
    "Mahlkönig EK43",
    "Mahlkönig E65S GbW",
    "Mahlkönig E80 Supreme",
    "Mazzer Robur S",
    "Mazzer Kold S",
    "Mazzer ZM",
    "Victoria Arduino Mythos One",
    "Victoria Arduino Mythos MY75",
    "Anfim SP II",
    "Eureka Atom 75",
    "Weber EG-1",
    "Ditting 807",
]

FERMENTATIONS = [
    "Anaerobic",
    "Carbonic maceration",
    "Co-ferment",
    "Thermal shock",
    "Extended ferment",
    "Lactic",
    "Koji",
    "Yeast inoculated",
]

ORIGINS = ["Ethiopia", "Colombia", "Brazil", "Guatemala", "Kenya", "Indonesia", "Honduras", "Peru"]

DRINKS = [
    "Espresso",
    "Cortado",
    "Flat white",
    "Latte",
    "Cappuccino",
    "Mocha",
    "Drip",
    "Pour over",
    "Cold brew",
    "Matcha latte",
    "Chai latte",
    "Hojicha",
]

MILK_BRANDS = ["Straus", "Clover", "Oatly", "Minor Figures", "Califia Farms", "Pacific", "Milkadamia"]


def _options(labels: dict[str, str]) -> list[dict[str, str]]:
    return [{"value": value, "label": label} for value, label in labels.items()]


def machine_display(machine: dict[str, Any]) -> str | None:
    brand = MACHINE_BRAND_LABELS.get(machine.get("brand") or "")
    model = (machine.get("model") or "").strip()
    if brand and model:
        return f"{brand} {model}"
    return brand or model or None


def _merge(seen: Counter, curated: list[str]) -> list[str]:
    """Values on shops first, most common first; then curated entries not already present.

    Matching is case-insensitive and keeps the first spelling seen.
    """
    out: list[str] = []
    keys: set[str] = set()
    ordered = [v for v, _ in seen.most_common()] + curated
    for value in ordered:
        key = value.casefold()
        if key not in keys:
            keys.add(key)
            out.append(value)
    return out


def build_report_options(rows: Iterable[Any]) -> dict[str, Any]:
    """Rows need roaster, grinders, milk_brands, drinks, machines, coffees attributes."""
    machines: Counter = Counter()
    grinders: Counter = Counter()
    roasters: Counter = Counter()
    drinks: Counter = Counter()
    milks: Counter = Counter()
    origins: Counter = Counter()
    fermentations: Counter = Counter()

    def count(counter: Counter, value: Any) -> None:
        if isinstance(value, str) and value.strip():
            counter[value.strip()] += 1

    for row in rows:
        count(roasters, row.roaster)
        for grinder in row.grinders or []:
            count(grinders, grinder)
        for brand in row.milk_brands or []:
            count(milks, brand)
        for drink in row.drinks or []:
            count(drinks, (drink or {}).get("name"))
        for machine in row.machines or []:
            count(machines, machine_display(machine or {}))
        for coffee in row.coffees or []:
            coffee = coffee or {}
            count(roasters, coffee.get("roaster"))
            count(fermentations, coffee.get("fermentation"))
            for origin in coffee.get("origins") or []:
                count(origins, origin)

    curated_machines = [
        f"{MACHINE_BRAND_LABELS[brand]} {model}"
        for brand, models in MACHINE_MODELS.items()
        for model in models
    ]

    return {
        "machine_brands": _options(MACHINE_BRAND_LABELS),
        "machines": _merge(machines, curated_machines),
        "grinders": _merge(grinders, GRINDERS),
        "bean_sources": _options(BEAN_SOURCE_LABELS),
        "roasters": _merge(roasters, []),
        "coffee_types": _options(COFFEE_TYPE_LABELS),
        "processes": _options(PROCESS_LABELS),
        "roast_levels": _options(ROAST_LEVEL_LABELS),
        "fermentations": _merge(fermentations, FERMENTATIONS),
        "origins": _merge(origins, ORIGINS),
        "drinks": _merge(drinks, DRINKS),
        "milk_brands": _merge(milks, MILK_BRANDS),
        "amenities": _options(AMENITY_LABELS),
        "report_reasons": _options(REPORT_REASON_LABELS),
    }
