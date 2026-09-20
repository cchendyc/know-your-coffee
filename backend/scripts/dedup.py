"""Merge duplicate shops created by differing Yelp/Google address formats.
Duplicate = same normalized name, or one name a prefix of the other
("Crema Coffee Roasting" vs "Crema Coffee Roasting Company."), within ~250m.
Keeps the row with the most known data, repoints its reports, deletes the rest.
Usage: python -m scripts.dedup
"""

import math
import sys

import psycopg
from psycopg.rows import dict_row

from app import settings
from app.repository.util import norm_name

if not settings.DATABASE_URL:
    print("DATABASE_URL is not set; dedup only applies to the Postgres store")
    sys.exit(1)


def distance_meters(a: dict, b: dict) -> float:
    d_lat = (a["lat"] - b["lat"]) * 111_320
    d_lng = (a["lng"] - b["lng"]) * 111_320 * math.cos(math.radians(a["lat"]))
    return math.hypot(d_lat, d_lng)


def score(r: dict) -> int:
    return sum(
        [
            r["machine"] != "UNKNOWN",
            r["machine_model"] is not None,
            r["bean_source"] != "UNKNOWN",
            r["roaster"] is not None,
            len(r["milk_brands"]) > 0,
            r["vibe"] is not None,
            r["photo_url"] is not None,
            r["website"] is not None,
        ]
    )


def is_duplicate(a: dict, b: dict) -> bool:
    """Prefix guard of 6+ chars avoids merging distinct shops that share a short
    word ("Cafe X" vs "Cafe Y") but still catches corporate-suffix variants."""
    if distance_meters(a, b) >= 250:
        return False
    na, nb = norm_name(a["name"]), norm_name(b["name"])
    if na == nb:
        return True
    return min(len(na), len(nb)) >= 6 and (na.startswith(nb) or nb.startswith(na))


with psycopg.connect(settings.DATABASE_URL, row_factory=dict_row) as conn:
    shops = conn.execute("SELECT * FROM shops").fetchall()

    clusters: list[list[dict]] = []
    for shop in shops:
        cluster = next((c for c in clusters if any(is_duplicate(m, shop) for m in c)), None)
        if cluster is not None:
            cluster.append(shop)
        else:
            clusters.append([shop])

    merged = 0
    for cluster in clusters:
        if len(cluster) < 2:
            continue
        cluster.sort(key=score, reverse=True)
        keeper, losers = cluster[0], cluster[1:]
        loser_ids = [l["id"] for l in losers]
        conn.execute("UPDATE reports SET shop_id = %s WHERE shop_id = ANY(%s)", [keeper["id"], loser_ids])
        conn.execute("DELETE FROM shops WHERE id = ANY(%s)", [loser_ids])
        merged += len(losers)
        print(f"{keeper['name']} ({keeper['city']}): merged {len(losers)} duplicate(s)")

print(f"done: removed {merged} duplicates, {len(shops) - merged} shops remain")
