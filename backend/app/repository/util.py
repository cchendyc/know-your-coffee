import re
import unicodedata
from collections import defaultdict
from urllib.parse import urlparse

from ..models import Coffee


def norm_coffees(raw: list[dict] | None) -> list[Coffee]:
    """Coffee entries arrive sparse (jsonb or GraphQL input); fill the keys
    the schema requires as non-null lists."""
    return [
        {
            "name": c.get("name"),
            "roaster": c.get("roaster"),
            "type": c.get("type"),
            "origins": c.get("origins") or [],
            "process": c.get("process"),
            "fermentation": c.get("fermentation"),
            "roastLevel": c.get("roastLevel"),
            "varieties": c.get("varieties") or [],
            "tastingNotes": c.get("tastingNotes") or [],
        }
        for c in (raw or [])
    ]

_ALNUM = set("abcdefghijklmnopqrstuvwxyz0123456789")
_LOCATION_SPLIT = re.compile(r"\s+[-–—|@]\s+")
_TRAILING_PAREN = re.compile(r"\s*\([^)]*\)\s*$")

# Ordering, social, and POS hosts that many unrelated shops share.
_GENERIC_HOSTS = {
    "instagram.com",
    "facebook.com",
    "m.facebook.com",
    "twitter.com",
    "x.com",
    "yelp.com",
    "maps.google.com",
    "google.com",
    "goo.gl",
    "linktr.ee",
    "bit.ly",
    "tinyurl.com",
    "t.co",
    "squareup.com",
    "square.site",
    "toasttab.com",
    "clover.com",
    "ubereats.com",
    "doordash.com",
    "grubhub.com",
    "order.online",
}

_GENERIC_SLUGS = {
    "coffee",
    "cafe",
    "coffeehouse",
    "coffeeshop",
    "espresso",
    "thecoffee",
    "thecafe",
}


def norm_name(name: str) -> str:
    """"Caffè" and "Caffe" must normalize identically, so strip diacritics
    (NFKD) before dropping non-alphanumerics."""
    decomposed = unicodedata.normalize("NFKD", name)
    return "".join(c for c in decomposed.lower() if c in _ALNUM)


def brand_name(name: str) -> str:
    """Strip location suffixes: 'Blue Bottle Coffee - Ferry Building' → 'Blue Bottle Coffee'."""
    trimmed = _TRAILING_PAREN.sub("", name).strip()
    head = _LOCATION_SPLIT.split(trimmed, maxsplit=1)[0].strip()
    return head or name.strip()


def brand_slug(name: str) -> str:
    return norm_name(brand_name(name))


def slugify_brand(name: str) -> str:
    decomposed = unicodedata.normalize("NFKD", brand_name(name)).lower()
    chars: list[str] = []
    dash = False
    for c in decomposed:
        if "a" <= c <= "z" or "0" <= c <= "9":
            chars.append(c)
            dash = False
        elif not dash:
            chars.append("-")
            dash = True
    return "".join(chars).strip("-") or "chain"


def website_host(url: str | None) -> str | None:
    if not url:
        return None
    raw = url if "://" in url else f"https://{url}"
    host = urlparse(raw).hostname
    if not host:
        return None
    host = host.lower()
    if host.startswith("www."):
        host = host[4:]
    if host in _GENERIC_HOSTS:
        return None
    return host


def is_groupable_slug(slug: str) -> bool:
    return len(slug) >= 5 and slug not in _GENERIC_SLUGS


def cluster_shops(shops: list[dict]) -> list[list[dict]]:
    """Union shops that share a real website host or a distinctive brand slug.
    Independents (cluster size 1) are omitted."""
    n = len(shops)
    parent = list(range(n))

    def find(i: int) -> int:
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    def union(i: int, j: int) -> None:
        ri, rj = find(i), find(j)
        if ri != rj:
            parent[rj] = ri

    host_index: dict[str, int] = {}
    slug_index: dict[str, int] = {}
    for i, shop in enumerate(shops):
        host = website_host(shop.get("website"))
        if host:
            if host in host_index:
                union(i, host_index[host])
            else:
                host_index[host] = i
        slug = brand_slug(shop["name"])
        if is_groupable_slug(slug):
            if slug in slug_index:
                union(i, slug_index[slug])
            else:
                slug_index[slug] = i

    grouped: dict[int, list[dict]] = defaultdict(list)
    for i, shop in enumerate(shops):
        grouped[find(i)].append(shop)
    return [members for members in grouped.values() if len(members) >= 2]


def is_same_shop(a: dict, b: dict) -> bool:
    return (
        norm_name(a["name"]) == norm_name(b["name"])
        and abs(a["lat"] - b["lat"]) < 0.003
        and abs(a["lng"] - b["lng"]) < 0.004
    )
