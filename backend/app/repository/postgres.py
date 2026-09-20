"""Postgres repository (Neon). Plain SQL via psycopg; camelCase dicts out."""

from datetime import datetime
from typing import Any

from psycopg.rows import dict_row
from psycopg.types.json import Json
from psycopg_pool import ConnectionPool

from ..models import CoffeeShop, NewShop, Report, ShopPhoto, User


def _iso(dt: datetime) -> str:
    return dt.isoformat()


def _to_shop(r: dict) -> CoffeeShop:
    return {
        "id": str(r["id"]),
        "name": r["name"],
        "address": r["address"],
        "city": r["city"],
        "lat": r["lat"],
        "lng": r["lng"],
        "machine": r["machine"],
        "machineModel": r["machine_model"],
        "beanSource": r["bean_source"],
        "roaster": r["roaster"],
        "beanOrigins": r["bean_origins"],
        "grinders": r["grinders"],
        "drinks": r["drinks"],
        "milkBrands": r["milk_brands"],
        "vibe": r["vibe"],
        "dogFriendly": r["dog_friendly"],
        "wifi": r["wifi"],
        "outdoorSeating": r["outdoor_seating"],
        "photoUrl": r["photo_url"],
        "website": r["website"],
        "savedByMe": bool(r.get("saved_by_me")),
        "beenByMe": bool(r.get("been_by_me")),
        "updatedAt": _iso(r["updated_at"]),
    }


def _to_report(r: dict) -> Report:
    return {
        "id": str(r["id"]),
        "shopId": str(r["shop_id"]),
        "machine": r["machine"],
        "machineModel": r["machine_model"],
        "beanSource": r["bean_source"],
        "roaster": r["roaster"],
        "beanOrigins": r["bean_origins"],
        "grinders": r["grinders"],
        "drinks": r["drinks"],
        "milkBrands": r["milk_brands"],
        "dogFriendly": r["dog_friendly"],
        "wifi": r["wifi"],
        "outdoorSeating": r["outdoor_seating"],
        "note": r["note"],
        "source": r["source"],
        "reporter": {"name": r["reporter_name"], "picture": r["reporter_picture"]} if r.get("reporter_name") else None,
        "createdAt": _iso(r["created_at"]),
    }


def _to_photo(r: dict) -> ShopPhoto:
    return {
        "id": str(r["id"]),
        "shopId": str(r["shop_id"]),
        "kind": r["kind"],
        "data": r["data"],
        "uploader": {"name": r["uploader_name"], "picture": r["uploader_picture"]} if r.get("uploader_name") else None,
        "createdAt": _iso(r["created_at"]),
    }


_SEARCHABLE = """(name ILIKE %(q)s OR city ILIKE %(q)s OR address ILIKE %(q)s OR roaster ILIKE %(q)s
  OR machine_model ILIKE %(q)s OR array_to_string(bean_origins, ' ') ILIKE %(q)s
  OR array_to_string(grinders, ' ') ILIKE %(q)s)"""

# Completeness-weighted rank: known machine dominates (it is the app's core
# data point), then other filled fields, then recency. Name last keeps offset
# pagination stable within equal ranks. Amenities count when known either way.
_RANK = """
  (machine <> 'UNKNOWN')::int * 8
  + (machine_model IS NOT NULL)::int * 2
  + (bean_source <> 'UNKNOWN')::int * 2
  + (roaster IS NOT NULL)::int * 2
  + (cardinality(grinders) > 0)::int
  + (jsonb_array_length(COALESCE(drinks, '[]'::jsonb)) > 0)::int
  + (cardinality(milk_brands) > 0)::int
  + (vibe IS NOT NULL)::int
  + (dog_friendly IS NOT NULL)::int
  + (wifi IS NOT NULL)::int
  + (outdoor_seating IS NOT NULL)::int
  DESC, updated_at DESC, name ASC
"""

# Sources format addresses differently ("7th St" vs "Seventh Street"), so
# imports dedup by normalized name within ~300m. Prefix match catches suffix
# variants like "Crema Coffee Roasting Company".
_UPSERT_MATCH = """
WITH cand AS (SELECT regexp_replace(lower(unaccent(%(name)s)), '[^a-z0-9]', '', 'g') AS n)
SELECT s.* FROM shops s, cand c
WHERE (regexp_replace(lower(unaccent(s.name)), '[^a-z0-9]', '', 'g') LIKE c.n || '%%'
       OR c.n LIKE regexp_replace(lower(unaccent(s.name)), '[^a-z0-9]', '', 'g') || '%%')
  AND least(length(regexp_replace(lower(unaccent(s.name)), '[^a-z0-9]', '', 'g')), length(c.n)) >= 6
  AND abs(lat - %(lat)s) < 0.003 AND abs(lng - %(lng)s) < 0.004
LIMIT 1
"""


class PostgresRepository:
    def __init__(self, database_url: str):
        # Neon closes idle connections after ~5 min; check revives dead ones
        # instead of surfacing "SSL connection has been closed unexpectedly".
        self._pool = ConnectionPool(
            database_url,
            min_size=0,
            max_size=5,
            max_idle=240,
            check=ConnectionPool.check_connection,
            kwargs={"row_factory": dict_row},
            open=True,
        )

    def _query(self, sql: str, params: dict | list | None = None) -> list[dict]:
        with self._pool.connection() as conn:
            rows = conn.execute(sql, params).fetchall()
        return rows

    def _execute(self, sql: str, params: dict | list | None = None) -> None:
        with self._pool.connection() as conn:
            conn.execute(sql, params)

    def list_shops(self, filter: dict, user_id: str | None = None) -> tuple[list[CoffeeShop], int]:
        conditions: list[str] = []
        params: dict[str, Any] = {
            "user_id": user_id,
            "limit": filter.get("limit") or 24,
            "offset": filter.get("offset") or 0,
        }

        join = "LEFT JOIN user_shops us ON us.shop_id = s.id AND us.user_id = %(user_id)s" if user_id else ""
        select = "s.*, us.saved AS saved_by_me, us.been AS been_by_me" if user_id else "s.*"

        if filter.get("machine"):
            conditions.append("machine = %(machine)s")
            params["machine"] = filter["machine"]
        if filter.get("city"):
            conditions.append("city ILIKE %(city)s")
            params["city"] = filter["city"]
        if filter.get("saved") and user_id:
            conditions.append("us.saved = true")
        if filter.get("been") and user_id:
            conditions.append("us.been = true")
        if filter.get("search"):
            conditions.append(_SEARCHABLE)
            params["q"] = f"%{filter['search']}%"

        where = f"WHERE {' AND '.join(conditions)}" if conditions else ""
        rows = self._query(
            f"""SELECT {select}, count(*) OVER() AS total FROM shops s {join} {where}
                ORDER BY {_RANK} LIMIT %(limit)s OFFSET %(offset)s""",
            params,
        )
        total = rows[0]["total"] if rows else 0
        # count(*) OVER() is 0-row-safe only when a page has rows; recount otherwise.
        if not rows and (filter.get("offset") or 0) > 0:
            counted = self._query(f"SELECT count(*) AS total FROM shops s {join} {where}", params)
            total = counted[0]["total"]
        return [_to_shop(r) for r in rows], total

    def get_shop(self, shop_id: str, user_id: str | None = None) -> CoffeeShop | None:
        if user_id:
            rows = self._query(
                """SELECT s.*, us.saved AS saved_by_me, us.been AS been_by_me
                   FROM shops s LEFT JOIN user_shops us ON us.shop_id = s.id AND us.user_id = %s
                   WHERE s.id = %s""",
                [user_id, shop_id],
            )
        else:
            rows = self._query("SELECT * FROM shops WHERE id = %s", [shop_id])
        return _to_shop(rows[0]) if rows else None

    def list_cities(self) -> list[str]:
        return [r["city"] for r in self._query("SELECT DISTINCT city FROM shops ORDER BY city ASC")]

    def list_reports(self, shop_id: str) -> list[Report]:
        rows = self._query(
            """SELECT r.*, u.name AS reporter_name, u.picture AS reporter_picture
               FROM reports r LEFT JOIN users u ON u.id = r.user_id
               WHERE r.shop_id = %s ORDER BY r.created_at DESC""",
            [shop_id],
        )
        return [_to_report(r) for r in rows]

    def add_report(self, report: dict) -> Report:
        params = {
            "shop_id": report["shopId"],
            "machine": report.get("machine"),
            "machine_model": report.get("machineModel"),
            "bean_source": report.get("beanSource"),
            "roaster": report.get("roaster"),
            "bean_origins": report.get("beanOrigins"),
            "grinders": report.get("grinders"),
            "drinks": Json(report["drinks"]) if report.get("drinks") is not None else None,
            "milk_brands": report.get("milkBrands"),
            "dog_friendly": report.get("dogFriendly"),
            "wifi": report.get("wifi"),
            "outdoor_seating": report.get("outdoorSeating"),
            "note": report.get("note"),
            "source": report.get("source") or "TEXT",
            "user_id": report.get("userId"),
        }
        rows = self._query(
            """INSERT INTO reports (shop_id, machine, machine_model, bean_source, roaster,
                                    bean_origins, grinders, drinks, milk_brands,
                                    dog_friendly, wifi, outdoor_seating, note, source, user_id)
               VALUES (%(shop_id)s, %(machine)s, %(machine_model)s, %(bean_source)s, %(roaster)s,
                       %(bean_origins)s, %(grinders)s, %(drinks)s, %(milk_brands)s,
                       %(dog_friendly)s, %(wifi)s, %(outdoor_seating)s, %(note)s,
                       %(source)s, %(user_id)s)
               RETURNING *, NULL AS reporter_name, NULL AS reporter_picture""",
            params,
        )
        # Latest report wins: fold non-null fields into the shop record.
        self._execute(
            """UPDATE shops SET
                 machine = COALESCE(%(machine)s, machine),
                 machine_model = COALESCE(%(machine_model)s, machine_model),
                 bean_source = COALESCE(%(bean_source)s, bean_source),
                 roaster = COALESCE(%(roaster)s, roaster),
                 bean_origins = COALESCE(%(bean_origins)s::text[], bean_origins),
                 grinders = COALESCE(%(grinders)s::text[], grinders),
                 drinks = COALESCE(%(drinks)s::jsonb, drinks),
                 milk_brands = COALESCE(%(milk_brands)s::text[], milk_brands),
                 dog_friendly = COALESCE(%(dog_friendly)s, dog_friendly),
                 wifi = COALESCE(%(wifi)s, wifi),
                 outdoor_seating = COALESCE(%(outdoor_seating)s, outdoor_seating),
                 updated_at = now()
               WHERE id = %(shop_id)s""",
            params,
        )
        return _to_report(rows[0])

    def find_matching_shop(self, name: str, lat: float, lng: float) -> CoffeeShop | None:
        rows = self._query(_UPSERT_MATCH, {"name": name, "lat": lat, "lng": lng})
        return _to_shop(rows[0]) if rows else None

    def upsert_shops(self, shops: list[NewShop]) -> list[CoffeeShop]:
        result: list[CoffeeShop] = []
        for s in shops:
            existing = self.find_matching_shop(s["name"], s["lat"], s["lng"])
            if existing:
                result.append(existing)
                continue
            rows = self._query(
                """INSERT INTO shops (name, address, city, lat, lng, machine, machine_model, bean_source,
                                      roaster, bean_origins, grinders, drinks, milk_brands, vibe, photo_url,
                                      website, dog_friendly, wifi, outdoor_seating)
                   VALUES (%(name)s, %(address)s, %(city)s, %(lat)s, %(lng)s, %(machine)s, %(machineModel)s,
                           %(beanSource)s, %(roaster)s, %(beanOrigins)s, %(grinders)s, %(drinks)s,
                           %(milkBrands)s, %(vibe)s, %(photoUrl)s, %(website)s, %(dogFriendly)s,
                           %(wifi)s, %(outdoorSeating)s)
                   RETURNING *""",
                {
                    "dogFriendly": None,
                    "wifi": None,
                    "outdoorSeating": None,
                    **s,
                    "drinks": Json(s["drinks"]),
                },
            )
            result.append(_to_shop(rows[0]))
        return result

    def enrich_shop(self, shop_id: str, patch: dict) -> None:
        """Review-derived data. Only fills fields that are still UNKNOWN/null/empty,
        so it never overwrites community reports."""
        milk = patch.get("milkBrands") or None
        self._execute(
            """UPDATE shops SET
                 machine = CASE WHEN machine = 'UNKNOWN' AND %(machine)s::machine_brand IS NOT NULL
                                THEN %(machine)s::machine_brand ELSE machine END,
                 machine_model = COALESCE(machine_model, %(machine_model)s),
                 bean_source = CASE WHEN bean_source = 'UNKNOWN' AND %(bean_source)s::bean_source IS NOT NULL
                                    THEN %(bean_source)s::bean_source ELSE bean_source END,
                 roaster = COALESCE(roaster, %(roaster)s),
                 milk_brands = CASE WHEN milk_brands = '{}' AND %(milk_brands)s::text[] IS NOT NULL
                                    THEN %(milk_brands)s::text[] ELSE milk_brands END,
                 vibe = COALESCE(vibe, %(vibe)s),
                 dog_friendly = COALESCE(dog_friendly, %(dog_friendly)s),
                 wifi = COALESCE(wifi, %(wifi)s),
                 outdoor_seating = COALESCE(outdoor_seating, %(outdoor_seating)s),
                 updated_at = now()
               WHERE id = %(id)s""",
            {
                "id": shop_id,
                "machine": patch.get("machine"),
                "machine_model": patch.get("machineModel"),
                "bean_source": patch.get("beanSource"),
                "roaster": patch.get("roaster"),
                "milk_brands": milk,
                "vibe": patch.get("vibe"),
                "dog_friendly": patch.get("dogFriendly"),
                "wifi": patch.get("wifi"),
                "outdoor_seating": patch.get("outdoorSeating"),
            },
        )

    def set_shop_meta(self, shop_id: str, meta: dict) -> None:
        self._execute(
            "UPDATE shops SET photo_url = COALESCE(%s, photo_url), website = COALESCE(%s, website) WHERE id = %s",
            [meta.get("photoUrl"), meta.get("website"), shop_id],
        )

    def upsert_user(self, user: dict) -> User:
        rows = self._query(
            """INSERT INTO users (google_sub, email, name, picture)
               VALUES (%(googleSub)s, %(email)s, %(name)s, %(picture)s)
               ON CONFLICT (google_sub) DO UPDATE SET email = %(email)s, name = %(name)s, picture = %(picture)s
               RETURNING *""",
            user,
        )
        r = rows[0]
        return {
            "id": str(r["id"]),
            "googleSub": r["google_sub"],
            "email": r["email"],
            "name": r["name"],
            "picture": r["picture"],
        }

    def set_shop_status(self, user_id: str, shop_id: str, saved: bool | None, been: bool | None) -> None:
        self._execute(
            """INSERT INTO user_shops (user_id, shop_id, saved, been)
               VALUES (%(user_id)s, %(shop_id)s, COALESCE(%(saved)s, false), COALESCE(%(been)s, false))
               ON CONFLICT (user_id, shop_id) DO UPDATE SET
                 saved = COALESCE(%(saved)s, user_shops.saved),
                 been = COALESCE(%(been)s, user_shops.been),
                 updated_at = now()""",
            {"user_id": user_id, "shop_id": shop_id, "saved": saved, "been": been},
        )

    def user_stats(self, user_id: str) -> dict[str, Any]:
        rows = self._query(
            """SELECT count(*) FILTER (WHERE saved) AS saved, count(*) FILTER (WHERE been) AS been
               FROM user_shops WHERE user_id = %s""",
            [user_id],
        )
        return {"saved": rows[0]["saved"], "been": rows[0]["been"]} if rows else {"saved": 0, "been": 0}

    def list_photos(self, shop_id: str) -> list[ShopPhoto]:
        rows = self._query(
            """SELECT p.*, u.name AS uploader_name, u.picture AS uploader_picture
               FROM shop_photos p LEFT JOIN users u ON u.id = p.user_id
               WHERE p.shop_id = %s ORDER BY p.created_at DESC""",
            [shop_id],
        )
        return [_to_photo(r) for r in rows]

    def add_photos(self, shop_id: str, user_id: str | None, photos: list[dict]) -> list[ShopPhoto]:
        added: list[ShopPhoto] = []
        for photo in photos:
            rows = self._query(
                """INSERT INTO shop_photos (shop_id, user_id, kind, data)
                   VALUES (%s, %s, %s, %s)
                   RETURNING *, NULL AS uploader_name, NULL AS uploader_picture""",
                [shop_id, user_id, photo["kind"], photo["data"]],
            )
            added.append(_to_photo(rows[0]))
        return added
