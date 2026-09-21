"""Postgres repository (Neon). Plain SQL via psycopg; camelCase dicts out."""

import hmac
from datetime import datetime
from typing import Any

from psycopg.errors import UniqueViolation
from psycopg.rows import dict_row
from psycopg.types.json import Json
from psycopg_pool import ConnectionPool

from ..models import Chain, CoffeeShop, NewShop, Report, ShopClaim, ShopPhoto, User
from . import DuplicateEmailError, EMAIL_IN_USE
from .util import brand_name, cluster_shops, norm_coffees, split_search, slugify_brand


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
        "chainId": str(r["chain_id"]) if r.get("chain_id") else None,
        "machine": r["machine"],
        "machineModel": r["machine_model"],
        "machines": r["machines"] or [],
        "beanSource": r["bean_source"],
        "roaster": r["roaster"],
        "beanOrigins": r["bean_origins"],
        "coffees": norm_coffees(r["coffees"]),
        "grinders": r["grinders"],
        "drinks": r["drinks"],
        "milkBrands": r["milk_brands"],
        "vibe": r["vibe"],
        "dogFriendly": r["dog_friendly"],
        "wifi": r["wifi"],
        "outdoorSeating": r["outdoor_seating"],
        "photoUrl": r["photo_url"],
        "website": r["website"],
        "ownerId": str(r["owner_user_id"]) if r.get("owner_user_id") else None,
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
        "machines": r["machines"],
        "beanSource": r["bean_source"],
        "roaster": r["roaster"],
        "beanOrigins": r["bean_origins"],
        "coffees": norm_coffees(r["coffees"]) if r["coffees"] is not None else None,
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


def _to_user(r: dict) -> User:
    return {
        "id": str(r["id"]),
        "googleSub": r["google_sub"],
        "appleSub": r["apple_sub"],
        "email": r["email"],
        "phone": r["phone"],
        "name": r["name"],
        "picture": r["picture"],
        "role": r["role"],
    }


def _to_claim(r: dict) -> ShopClaim:
    return {
        "id": str(r["id"]),
        "shopId": str(r["shop_id"]),
        "userId": str(r["user_id"]),
        "status": r["status"],
        "note": r["note"],
        "createdAt": _iso(r["created_at"]),
        "resolvedAt": _iso(r["resolved_at"]) if r["resolved_at"] else None,
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


# One search token; list_shops instantiates it per token (q0, q1, …) so a
# free-form query like "gesha in oakland" ANDs across fields.
_SEARCHABLE = """(name ILIKE %(q)s OR city ILIKE %(q)s OR address ILIKE %(q)s OR roaster ILIKE %(q)s
  OR machine::text ILIKE %(q)s OR machine_model ILIKE %(q)s
  OR array_to_string(bean_origins, ' ') ILIKE %(q)s
  OR array_to_string(grinders, ' ') ILIKE %(q)s
  OR array_to_string(milk_brands, ' ') ILIKE %(q)s
  OR vibe ILIKE %(q)s
  OR EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(drinks, '[]'::jsonb)) d WHERE d->>'name' ILIKE %(q)s)
  OR EXISTS (SELECT 1 FROM jsonb_array_elements(machines) m
             WHERE m->>'brand' ILIKE %(q)s OR m->>'model' ILIKE %(q)s)
  OR EXISTS (SELECT 1 FROM jsonb_array_elements(coffees) c
             WHERE c->>'name' ILIKE %(q)s OR c->>'roaster' ILIKE %(q)s
                OR c->>'fermentation' ILIKE %(q)s
                OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(COALESCE(c->'origins', '[]'::jsonb)) o
                           WHERE o ILIKE %(q)s)
                OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(COALESCE(c->'varieties', '[]'::jsonb)) v
                           WHERE v ILIKE %(q)s)
                OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(COALESCE(c->'tastingNotes', '[]'::jsonb)) t
                           WHERE t ILIKE %(q)s)))"""

# Completeness-weighted rank: known machine dominates (it is the app's core
# data point), then other filled fields, then recency. Name last keeps offset
# pagination stable within equal ranks. Amenities count when known either way.
_RANK = """
  (machine <> 'UNKNOWN')::int * 8
  + (machine_model IS NOT NULL)::int * 2
  + (bean_source <> 'UNKNOWN')::int * 2
  + (roaster IS NOT NULL)::int * 2
  + (cardinality(grinders) > 0)::int
  + (jsonb_array_length(coffees) > 0)::int
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
            # Match the primary or any machine on the bar. The cast matters:
            # Json params bind as json, and @> only exists for jsonb.
            conditions.append("(machine = %(machine)s OR machines @> %(machine_json)s::jsonb)")
            params["machine"] = filter["machine"]
            params["machine_json"] = Json([{"brand": filter["machine"]}])
        if filter.get("city"):
            conditions.append("city ILIKE %(city)s")
            params["city"] = filter["city"]
        if filter.get("saved") and user_id:
            conditions.append("us.saved = true")
        if filter.get("been") and user_id:
            conditions.append("us.been = true")
        if filter.get("search"):
            tokens, amenities = split_search(filter["search"])
            for i, token in enumerate(tokens):
                conditions.append(_SEARCHABLE.replace("%(q)s", f"%(q{i})s"))
                params[f"q{i}"] = f"%{token}%"
            for key, col in (("dogFriendly", "dog_friendly"), ("wifi", "wifi"), ("outdoorSeating", "outdoor_seating")):
                if amenities.get(key):
                    conditions.append(f"{col} = true")
        if filter.get("chainId"):
            conditions.append("s.chain_id = %(chain_id)s")
            params["chain_id"] = filter["chainId"]

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

    def delete_shop(self, shop_id: str) -> bool:
        # reports and shop_claims have no ON DELETE CASCADE yet (pre-0019).
        with self._pool.connection() as conn:
            conn.execute("DELETE FROM reports WHERE shop_id = %s", [shop_id])
            conn.execute("DELETE FROM shop_claims WHERE shop_id = %s", [shop_id])
            row = conn.execute("DELETE FROM shops WHERE id = %s RETURNING id", [shop_id]).fetchone()
        return bool(row)

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

    # Admin reports fold into the shop record like any other, but they are
    # data entry, not community activity: both the list and the count skip
    # them. Anonymous reports (user_id NULL) stay visible.
    def list_reports(self, shop_id: str, limit: int | None = None) -> list[Report]:
        rows = self._query(
            """SELECT r.*, u.name AS reporter_name, u.picture AS reporter_picture
               FROM reports r LEFT JOIN users u ON u.id = r.user_id
               WHERE r.shop_id = %(shop_id)s AND (u.role IS NULL OR u.role <> 'ADMIN')
               ORDER BY r.created_at DESC LIMIT %(limit)s""",
            {"shop_id": shop_id, "limit": limit},
        )
        return [_to_report(r) for r in rows]

    def count_reports(self, shop_id: str) -> int:
        return self._query(
            """SELECT count(*) AS n
               FROM reports r LEFT JOIN users u ON u.id = r.user_id
               WHERE r.shop_id = %s AND (u.role IS NULL OR u.role <> 'ADMIN')""",
            [shop_id],
        )[0]["n"]

    def add_report(self, report: dict) -> Report:
        # The scalar primary mirrors the first machines entry.
        machines = report.get("machines")
        if machines and not report.get("machine"):
            report = {**report, "machine": machines[0]["brand"], "machineModel": machines[0].get("model")}
        params = {
            "shop_id": report["shopId"],
            "machine": report.get("machine"),
            "machine_model": report.get("machineModel"),
            "machines": Json(machines) if machines is not None else None,
            "bean_source": report.get("beanSource"),
            "roaster": report.get("roaster"),
            "bean_origins": report.get("beanOrigins"),
            "coffees": Json(report["coffees"]) if report.get("coffees") is not None else None,
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
            """INSERT INTO reports (shop_id, machine, machine_model, machines, bean_source, roaster,
                                    bean_origins, coffees, grinders, drinks, milk_brands,
                                    dog_friendly, wifi, outdoor_seating, note, source, user_id)
               VALUES (%(shop_id)s, %(machine)s, %(machine_model)s, %(machines)s, %(bean_source)s, %(roaster)s,
                       %(bean_origins)s, %(coffees)s, %(grinders)s, %(drinks)s, %(milk_brands)s,
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
                 machines = COALESCE(%(machines)s::jsonb, machines),
                 bean_source = COALESCE(%(bean_source)s, bean_source),
                 roaster = COALESCE(%(roaster)s, roaster),
                 bean_origins = COALESCE(%(bean_origins)s::text[], bean_origins),
                 coffees = COALESCE(%(coffees)s::jsonb, coffees),
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
                """INSERT INTO shops (name, address, city, lat, lng, machine, machine_model, machines, bean_source,
                                      roaster, bean_origins, coffees, grinders, drinks, milk_brands, vibe, photo_url,
                                      website, dog_friendly, wifi, outdoor_seating)
                   VALUES (%(name)s, %(address)s, %(city)s, %(lat)s, %(lng)s, %(machine)s, %(machineModel)s,
                           %(machines)s, %(beanSource)s, %(roaster)s, %(beanOrigins)s, %(coffees)s, %(grinders)s,
                           %(drinks)s, %(milkBrands)s, %(vibe)s, %(photoUrl)s, %(website)s, %(dogFriendly)s,
                           %(wifi)s, %(outdoorSeating)s)
                   RETURNING *""",
                {
                    "dogFriendly": None,
                    "wifi": None,
                    "outdoorSeating": None,
                    **s,
                    "drinks": Json(s["drinks"]),
                    "coffees": Json(s.get("coffees") or []),
                    "machines": Json(s.get("machines") or []),
                },
            )
            result.append(_to_shop(rows[0]))
        self.relink_chains()
        return [self.get_shop(s["id"]) or s for s in result]

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
        # Role only ever escalates here (ADMIN_EMAILS bootstrap); sign-in never demotes.
        params = {"role": None, **user, "email": (user.get("email") or "").lower() or None}
        try:
            rows = self._query("SELECT * FROM users WHERE google_sub = %(googleSub)s", params)
            if not rows and params["email"]:
                rows = self._query(
                    "SELECT * FROM users WHERE lower(email) = lower(%(email)s)",
                    params,
                )
                if rows and rows[0].get("google_sub") and rows[0]["google_sub"] != params["googleSub"]:
                    raise DuplicateEmailError(EMAIL_IN_USE)
            if rows:
                params["id"] = rows[0]["id"]
                rows = self._query(
                    """UPDATE users SET
                         google_sub = %(googleSub)s,
                         email = %(email)s, name = %(name)s, picture = %(picture)s,
                         role = CASE WHEN %(role)s = 'ADMIN' THEN 'ADMIN' ELSE users.role END
                       WHERE id = %(id)s
                       RETURNING *""",
                    params,
                )
                return _to_user(rows[0])
            rows = self._query(
                """INSERT INTO users (google_sub, email, name, picture, role)
                   VALUES (%(googleSub)s, %(email)s, %(name)s, %(picture)s, COALESCE(%(role)s, 'USER'))
                   RETURNING *""",
                params,
            )
            return _to_user(rows[0])
        except UniqueViolation:
            raise DuplicateEmailError(EMAIL_IN_USE)

    def get_user(self, user_id: str) -> User | None:
        rows = self._query("SELECT * FROM users WHERE id = %s", [user_id])
        return _to_user(rows[0]) if rows else None

    def upsert_phone_user(self, phone: str, name: str) -> User:
        # The no-op SET makes RETURNING work for existing rows; their name is kept.
        rows = self._query(
            """INSERT INTO users (phone, name) VALUES (%s, %s)
               ON CONFLICT (phone) DO UPDATE SET phone = EXCLUDED.phone
               RETURNING *""",
            [phone, name],
        )
        return _to_user(rows[0])

    def upsert_email_user(self, email: str, name: str) -> User:
        email = email.lower()
        rows = self._query("SELECT * FROM users WHERE lower(email) = lower(%s)", [email])
        if rows:
            return _to_user(rows[0])
        try:
            rows = self._query(
                "INSERT INTO users (email, name) VALUES (%s, %s) RETURNING *",
                [email, name],
            )
            return _to_user(rows[0])
        except UniqueViolation:
            rows = self._query("SELECT * FROM users WHERE lower(email) = lower(%s)", [email])
            if rows:
                return _to_user(rows[0])
            raise DuplicateEmailError(EMAIL_IN_USE)

    def upsert_apple_user(self, apple_sub: str, email: str | None, name: str) -> User:
        email = email.lower() if email else None
        rows = self._query("SELECT * FROM users WHERE apple_sub = %s", [apple_sub])
        if rows:
            return _to_user(rows[0])
        if email:
            rows = self._query("SELECT * FROM users WHERE lower(email) = lower(%s)", [email])
            if rows:
                existing = rows[0]
                if existing.get("apple_sub") and existing["apple_sub"] != apple_sub:
                    raise DuplicateEmailError(EMAIL_IN_USE)
                rows = self._query(
                    "UPDATE users SET apple_sub = %s WHERE id = %s RETURNING *",
                    [apple_sub, existing["id"]],
                )
                return _to_user(rows[0])
        try:
            rows = self._query(
                "INSERT INTO users (apple_sub, email, name) VALUES (%s, %s, %s) RETURNING *",
                [apple_sub, email, name],
            )
            return _to_user(rows[0])
        except UniqueViolation:
            raise DuplicateEmailError(EMAIL_IN_USE)

    def save_login_code(self, identifier: str, code_hash: str, ttl_seconds: int) -> None:
        self._execute(
            """INSERT INTO login_codes (identifier, code_hash, expires_at)
               VALUES (%(id)s, %(hash)s, now() + %(ttl)s * interval '1 second')
               ON CONFLICT (identifier) DO UPDATE SET
                 code_hash = %(hash)s, attempts = 0,
                 expires_at = now() + %(ttl)s * interval '1 second', created_at = now()""",
            {"id": identifier, "hash": code_hash, "ttl": ttl_seconds},
        )

    def login_code_age(self, identifier: str) -> float | None:
        rows = self._query(
            "SELECT extract(epoch FROM now() - created_at) AS age FROM login_codes WHERE identifier = %s",
            [identifier],
        )
        return float(rows[0]["age"]) if rows else None

    def use_login_code(self, identifier: str, code_hash: str) -> bool:
        # Count the attempt first so guessing burns tries even on mismatch; 5 max.
        rows = self._query(
            """UPDATE login_codes SET attempts = attempts + 1
               WHERE identifier = %s AND expires_at > now() AND attempts < 5
               RETURNING code_hash""",
            [identifier],
        )
        ok = bool(rows) and hmac.compare_digest(rows[0]["code_hash"], code_hash)
        if ok:
            self._execute("DELETE FROM login_codes WHERE identifier = %s", [identifier])
        return ok

    def delete_user(self, user_id: str) -> bool:
        with self._pool.connection() as conn:
            conn.execute("UPDATE reports SET user_id = NULL WHERE user_id = %s", [user_id])
            conn.execute("UPDATE shop_photos SET user_id = NULL WHERE user_id = %s", [user_id])
            conn.execute("DELETE FROM shop_claims WHERE user_id = %s", [user_id])
            conn.execute("UPDATE shops SET owner_user_id = NULL WHERE owner_user_id = %s", [user_id])
            # user_shops cascades on delete.
            row = conn.execute("DELETE FROM users WHERE id = %s RETURNING id", [user_id]).fetchone()
        return bool(row)

    def list_owned_shops(self, user_id: str) -> list[CoffeeShop]:
        rows = self._query(
            """SELECT s.*, us.saved AS saved_by_me, us.been AS been_by_me
               FROM shops s LEFT JOIN user_shops us ON us.shop_id = s.id AND us.user_id = %(user_id)s
               WHERE s.owner_user_id = %(user_id)s ORDER BY s.name""",
            {"user_id": user_id},
        )
        return [_to_shop(r) for r in rows]

    def create_claim(self, user_id: str, shop_id: str, note: str | None) -> ShopClaim:
        pending = self._query(
            "SELECT * FROM shop_claims WHERE user_id = %s AND shop_id = %s AND status = 'PENDING'",
            [user_id, shop_id],
        )
        if pending:
            return _to_claim(pending[0])
        rows = self._query(
            """INSERT INTO shop_claims (shop_id, user_id, note)
               VALUES (%(shop_id)s, %(user_id)s, %(note)s) RETURNING *""",
            {"shop_id": shop_id, "user_id": user_id, "note": note},
        )
        return _to_claim(rows[0])

    def list_claims(self, user_id: str | None = None, status: str | None = None) -> list[ShopClaim]:
        conditions = ["true"]
        params: dict[str, Any] = {"user_id": user_id, "status": status}
        if user_id:
            conditions.append("user_id = %(user_id)s")
        if status:
            conditions.append("status = %(status)s")
        # Admins review oldest first; a user's own list shows newest first.
        order = "created_at ASC" if status == "PENDING" else "created_at DESC"
        rows = self._query(
            f"SELECT * FROM shop_claims WHERE {' AND '.join(conditions)} ORDER BY {order}",
            params,
        )
        return [_to_claim(r) for r in rows]

    def resolve_claim(self, claim_id: str, approve: bool) -> ShopClaim | None:
        rows = self._query(
            """UPDATE shop_claims SET status = %s, resolved_at = now()
               WHERE id = %s AND status = 'PENDING' RETURNING *""",
            ["APPROVED" if approve else "REJECTED", claim_id],
        )
        if not rows:
            return None
        claim = _to_claim(rows[0])
        if approve:
            self._execute("UPDATE shops SET owner_user_id = %s WHERE id = %s", [claim["userId"], claim["shopId"]])
        return claim

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

    def list_photos(self, shop_id: str, limit: int | None = None) -> list[ShopPhoto]:
        rows = self._query(
            """SELECT p.*, u.name AS uploader_name, u.picture AS uploader_picture
               FROM shop_photos p LEFT JOIN users u ON u.id = p.user_id
               WHERE p.shop_id = %(shop_id)s ORDER BY p.created_at DESC LIMIT %(limit)s""",
            {"shop_id": shop_id, "limit": limit},
        )
        return [_to_photo(r) for r in rows]

    def count_photos(self, shop_id: str) -> int:
        return self._query("SELECT count(*) AS n FROM shop_photos WHERE shop_id = %s", [shop_id])[0]["n"]

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

    def get_chain(self, chain_id: str) -> Chain | None:
        rows = self._query("SELECT id, name, slug, website FROM chains WHERE id = %s", [chain_id])
        if not rows:
            return None
        r = rows[0]
        return {"id": str(r["id"]), "name": r["name"], "slug": r["slug"], "website": r["website"]}

    def list_chain_shops(self, chain_id: str, user_id: str | None = None) -> list[CoffeeShop]:
        if user_id:
            rows = self._query(
                """SELECT s.*, us.saved AS saved_by_me, us.been AS been_by_me
                   FROM shops s LEFT JOIN user_shops us ON us.shop_id = s.id AND us.user_id = %s
                   WHERE s.chain_id = %s ORDER BY s.city ASC, s.name ASC""",
                [user_id, chain_id],
            )
        else:
            rows = self._query(
                "SELECT * FROM shops WHERE chain_id = %s ORDER BY city ASC, name ASC",
                [chain_id],
            )
        return [_to_shop(r) for r in rows]

    def relink_chains(self) -> int:
        rows = self._query("SELECT id, name, website, chain_id FROM shops")
        clusters = cluster_shops(rows)
        assigned = 0
        keep: list[str] = []
        with self._pool.connection() as conn:
            for members in clusters:
                existing = [str(m["chain_id"]) for m in members if m.get("chain_id")]
                name = min((brand_name(m["name"]) for m in members), key=len)
                slug = slugify_brand(name)
                website = next((m["website"] for m in members if m.get("website")), None)
                chain_id = None
                if existing:
                    found = conn.execute("SELECT id FROM chains WHERE id = %s", [existing[0]]).fetchone()
                    if found:
                        chain_id = existing[0]
                        conn.execute(
                            "UPDATE chains SET name = %s, website = COALESCE(%s, website) WHERE id = %s",
                            [name, website, chain_id],
                        )
                if chain_id is None:
                    row = conn.execute(
                        """INSERT INTO chains (name, slug, website) VALUES (%s, %s, %s)
                           ON CONFLICT (slug) DO UPDATE SET name = EXCLUDED.name,
                             website = COALESCE(EXCLUDED.website, chains.website)
                           RETURNING id""",
                        [name, slug, website],
                    ).fetchone()
                    chain_id = str(row["id"])
                ids = [str(m["id"]) for m in members]
                conn.execute("UPDATE shops SET chain_id = %s WHERE id = ANY(%s::uuid[])", [chain_id, ids])
                keep.append(chain_id)
                assigned += len(members)
            if keep:
                conn.execute(
                    "UPDATE shops SET chain_id = NULL WHERE chain_id IS NOT NULL AND NOT (chain_id = ANY(%s::uuid[]))",
                    [keep],
                )
                conn.execute("DELETE FROM chains WHERE NOT (id = ANY(%s::uuid[]))", [keep])
            else:
                conn.execute("UPDATE shops SET chain_id = NULL WHERE chain_id IS NOT NULL")
                conn.execute("DELETE FROM chains")
        return assigned
