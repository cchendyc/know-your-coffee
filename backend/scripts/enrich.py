"""Enrich shops from public Yelp/Google reviews using keyword heuristics —
no AI calls, so it is free and quota-less. Gemini is reserved for
user-uploaded photos (see app/services/vision.py).
Vibe comes from Google's editorial summary.
Only fills fields that are still UNKNOWN/null; never overwrites reports.
Usage: python -m scripts.enrich [maxShops]
"""

import asyncio
import re
import sys

from app.repository import create_repository
from app.services.google import fetch_google_reviews
from app.services.yelp import fetch_yelp_reviews

# Patterns must be unambiguous: model names like "Strada" or phrases like
# "a decent espresso" appear in reviews without meaning the machine brand.
MACHINE_PATTERNS = [
    ("LA_MARZOCCO", re.compile(r"la ?marzocco|linea (pb|mini|classic)|gb ?5 espresso|kb ?90", re.I)),
    ("SLAYER", re.compile(r"slayer", re.I)),
    ("SYNESSO", re.compile(r"synesso", re.I)),
    ("KEES_VAN_DER_WESTEN", re.compile(r"kees van der westen", re.I)),
    ("VICTORIA_ARDUINO", re.compile(r"victoria arduino|black eagle", re.I)),
    ("NUOVA_SIMONELLI", re.compile(r"nuova simonelli", re.I)),
    ("MODBAR", re.compile(r"modbar", re.I)),
    ("ROCKET", re.compile(r"rocket espresso", re.I)),
    ("RANCILIO", re.compile(r"rancilio", re.I)),
    ("BREVILLE", re.compile(r"breville", re.I)),
    ("DECENT", re.compile(r"decent espresso machine|\bde1\b", re.I)),
]

# Well-known Bay Area (and national) roasters to spot in review text.
KNOWN_ROASTERS = [
    "Ritual", "Four Barrel", "Sightglass", "Blue Bottle", "Verve", "Equator", "Stumptown",
    "Intelligentsia", "Counter Culture", "Temple", "Highwire", "Chromatic", "Firebrand",
    "Red Bay", "Mr. Espresso", "Bicycle Coffee", "De La Paz", "AKA Coffee", "Flywheel",
    "Saint Frank", "Andytown", "Wrecking Ball", "Cat & Cloud", "Camber", "Sextant",
    "Proyecto Diaz", "Linea Caffe", "Sey", "Onyx",
]

MILK_BRAND_PATTERNS = [
    ("Straus", re.compile(r"straus", re.I)),
    ("Clover", re.compile(r"clover (sonoma|dairy|organic|milk)", re.I)),
    ("Oatly", re.compile(r"oatly", re.I)),
    ("Minor Figures", re.compile(r"minor figures", re.I)),
    ("Califia Farms", re.compile(r"califia", re.I)),
    ("Pacific", re.compile(r"pacific (foods|barista)", re.I)),
    ("Milkadamia", re.compile(r"milkadamia", re.I)),
    ("Chobani", re.compile(r"chobani", re.I)),
]

IN_HOUSE = re.compile(r"roast(s|ed|ing)? ((their|its) own|in[- ]?house|on[- ]?site)|house[- ]roasted", re.I)
ROASTER_SUFFIX = re.compile(r"\s*(coffee\s*)?(roasters?|roastery|roasting)( co\.?| company)?\s*$", re.I)

# Amenities: a negative mention ("no wifi") is data too, and beats a positive
# one because reviewers complain more precisely than they praise.
AMENITY_PATTERNS = [
    (
        "dogFriendly",
        re.compile(r"no dogs|dogs? (are )?not (allowed|welcome)", re.I),
        re.compile(r"dog[- ]friendly|dogs? (are )?(allowed|welcome)|pup[- ]?friendly|brought (my|our) dog", re.I),
    ),
    (
        "wifi",
        re.compile(r"no (free )?wi[- ]?fi|wi[- ]?fi (is )?(off|disabled|not available)|without wi[- ]?fi", re.I),
        re.compile(r"\bwi[- ]?fi\b", re.I),
    ),
    (
        "outdoorSeating",
        re.compile(r"no (outdoor|outside|patio) seating", re.I),
        re.compile(r"outdoor seating|patio|parklet|sidewalk (tables?|seating)|seating outside", re.I),
    ),
]


def extract(shop_name: str, texts: list[str], summary: str | None) -> dict:
    all_text = "\n".join(texts)
    patch: dict = {}

    machine = next((brand for brand, pattern in MACHINE_PATTERNS if pattern.search(all_text)), None)
    if machine:
        patch["machine"] = machine

    # A roaster mentioned in reviews is the shop's bean source — unless it is
    # the shop itself, which means they roast in-house.
    mentioned = next((r for r in KNOWN_ROASTERS if re.search(re.escape(r), all_text, re.I)), None)
    if mentioned and mentioned.lower() in shop_name.lower():
        patch["beanSource"] = "IN_HOUSE_ROAST"
        patch["roaster"] = mentioned
    elif re.search(r"roaster|roastery|roasting", shop_name, re.I) or IN_HOUSE.search(all_text):
        patch["beanSource"] = "IN_HOUSE_ROAST"
        patch["roaster"] = ROASTER_SUFFIX.sub("", shop_name).strip() or None
    elif mentioned:
        patch["beanSource"] = "LOCAL_ROASTER"
        patch["roaster"] = mentioned

    milk = [brand for brand, pattern in MILK_BRAND_PATTERNS if pattern.search(all_text)]
    if milk:
        patch["milkBrands"] = milk

    for field, negative, positive in AMENITY_PATTERNS:
        if negative.search(all_text):
            patch[field] = False
        elif positive.search(all_text):
            patch[field] = True

    if summary:
        patch["vibe"] = summary[:200]
    return patch


async def main() -> None:
    max_shops = int(sys.argv[1]) if len(sys.argv) > 1 else None
    repo = create_repository()
    shops, _total = repo.list_shops({"limit": 10_000})
    shops = [
        s
        for s in shops
        if s["machine"] == "UNKNOWN"
        or not s["roaster"]
        or not s["vibe"]
        or s["dogFriendly"] is None
        or s["wifi"] is None
        or s["outdoorSeating"] is None
    ]
    print(f"{len(shops)} shops need enrichment; processing up to {max_shops or 'all'}")

    enriched = skipped = failed = 0
    for shop in shops[:max_shops]:
        try:
            yelp, google = await asyncio.gather(
                fetch_yelp_reviews(shop["name"], shop["address"], shop["city"]),
                fetch_google_reviews(shop["name"], shop["address"], shop["city"]),
            )
            patch = extract(shop["name"], [*google["reviews"], *yelp], google["summary"])
            if any(v for v in patch.values()):
                repo.enrich_shop(shop["id"], patch)
                enriched += 1
                print(
                    f"{shop['name']} ({shop['city']}): machine={patch.get('machine', '-')} "
                    f"roaster={patch.get('roaster', '-')} milk={'/'.join(patch.get('milkBrands', [])) or '-'} "
                    f"vibe={'yes' if patch.get('vibe') else '-'}"
                )
            else:
                skipped += 1
            await asyncio.sleep(0.25)  # light pacing for the Yelp/Google APIs
        except Exception as e:  # noqa: BLE001 — one bad shop must not stop the run
            failed += 1
            print(f"{shop['name']}: failed ({str(e)[:150]})")

    print(f"done: {enriched} enriched, {skipped} skipped (nothing found), {failed} failed")


asyncio.run(main())
