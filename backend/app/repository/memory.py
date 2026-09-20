"""In-memory repository for local development without a database."""

from datetime import datetime, timezone
from typing import Any
from uuid import uuid4

from ..models import Chain, CoffeeShop, NewShop, Report, ShopPhoto, User
from .util import brand_name, cluster_shops, is_same_shop, slugify_brand


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _matches(shop: CoffeeShop, filter: dict) -> bool:
    if filter.get("machine") and shop["machine"] != filter["machine"]:
        return False
    if filter.get("city") and shop["city"].lower() != filter["city"].lower():
        return False
    if filter.get("search"):
        haystack = " ".join(
            [
                shop["name"],
                shop["city"],
                shop["address"],
                shop["roaster"] or "",
                shop["machine"],
                shop["machineModel"] or "",
                *shop["beanOrigins"],
                *shop["grinders"],
            ]
        ).lower()
        if filter["search"].lower() not in haystack:
            return False
    if filter.get("chainId") and shop.get("chainId") != filter["chainId"]:
        return False
    return True


def _rank(shop: CoffeeShop) -> int:
    """Mirrors _RANK in postgres.py: known machine dominates, then other filled fields."""
    return (
        (8 if shop["machine"] != "UNKNOWN" else 0)
        + (2 if shop["machineModel"] else 0)
        + (2 if shop["beanSource"] != "UNKNOWN" else 0)
        + (2 if shop["roaster"] else 0)
        + (1 if shop["grinders"] else 0)
        + (1 if shop["drinks"] else 0)
        + (1 if shop["milkBrands"] else 0)
        + (1 if shop["vibe"] else 0)
        # Amenities count when known either way; a "no dogs" answer is still data.
        + (1 if shop["dogFriendly"] is not None else 0)
        + (1 if shop["wifi"] is not None else 0)
        + (1 if shop["outdoorSeating"] is not None else 0)
    )


class MemoryRepository:
    def __init__(self):
        self._shops: dict[str, CoffeeShop] = {}
        self._chains: dict[str, Chain] = {}
        self._reports: dict[str, list[Report]] = {}
        self._users: dict[str, User] = {}
        self._photos: dict[str, list[ShopPhoto]] = {}
        self._statuses: dict[tuple[str, str], dict] = {}  # (user_id, shop_id)

    def _with_flags(self, shop: CoffeeShop, user_id: str | None) -> CoffeeShop:
        status = self._statuses.get((user_id, shop["id"])) if user_id else None
        return {**shop, "savedByMe": bool(status and status["saved"]), "beenByMe": bool(status and status["been"])}

    def list_shops(self, filter: dict, user_id: str | None = None) -> tuple[list[CoffeeShop], int]:
        shops = [self._with_flags(s, user_id) for s in self._shops.values()]
        shops = [s for s in shops if _matches(s, filter)]
        if filter.get("saved"):
            shops = [s for s in shops if s["savedByMe"]]
        if filter.get("been"):
            shops = [s for s in shops if s["beenByMe"]]
        # Stable multi-pass sort: name asc, then recency desc, then rank desc.
        shops.sort(key=lambda s: s["name"])
        shops.sort(key=lambda s: s["updatedAt"], reverse=True)
        shops.sort(key=_rank, reverse=True)
        offset = filter.get("offset") or 0
        limit = filter.get("limit") or 24
        return shops[offset : offset + limit], len(shops)

    def get_shop(self, shop_id: str, user_id: str | None = None) -> CoffeeShop | None:
        shop = self._shops.get(shop_id)
        return self._with_flags(shop, user_id) if shop else None

    def list_cities(self) -> list[str]:
        return sorted({s["city"] for s in self._shops.values()})

    def list_reports(self, shop_id: str, limit: int | None = None) -> list[Report]:
        reports = list(reversed(self._reports.get(shop_id, [])))
        return reports[:limit] if limit else reports

    def count_reports(self, shop_id: str) -> int:
        return len(self._reports.get(shop_id, []))

    def add_report(self, report: dict) -> Report:
        user = self._users.get(report.get("userId") or "")
        stored: Report = {
            "id": str(uuid4()),
            "shopId": report["shopId"],
            "machine": report.get("machine"),
            "machineModel": report.get("machineModel"),
            "beanSource": report.get("beanSource"),
            "roaster": report.get("roaster"),
            "beanOrigins": report.get("beanOrigins"),
            "grinders": report.get("grinders"),
            "drinks": report.get("drinks"),
            "milkBrands": report.get("milkBrands"),
            "dogFriendly": report.get("dogFriendly"),
            "wifi": report.get("wifi"),
            "outdoorSeating": report.get("outdoorSeating"),
            "note": report.get("note"),
            "source": report.get("source") or "TEXT",
            "reporter": {"name": user["name"], "picture": user["picture"]} if user else None,
            "createdAt": _now(),
        }
        self._reports.setdefault(report["shopId"], []).append(stored)

        # Latest report wins: fold non-null fields into the shop record.
        shop = self._shops.get(report["shopId"])
        if shop:
            for report_key, shop_key in [
                ("machine", "machine"),
                ("machineModel", "machineModel"),
                ("beanSource", "beanSource"),
                ("roaster", "roaster"),
                ("beanOrigins", "beanOrigins"),
                ("grinders", "grinders"),
                ("drinks", "drinks"),
                ("milkBrands", "milkBrands"),
                ("dogFriendly", "dogFriendly"),
                ("wifi", "wifi"),
                ("outdoorSeating", "outdoorSeating"),
            ]:
                if stored.get(report_key) is not None:
                    shop[shop_key] = stored[report_key]  # type: ignore[literal-required]
            shop["updatedAt"] = stored["createdAt"]
        return stored

    def find_matching_shop(self, name: str, lat: float, lng: float) -> CoffeeShop | None:
        probe = {"name": name, "lat": lat, "lng": lng}
        return next((s for s in self._shops.values() if is_same_shop(s, probe)), None)

    def upsert_shops(self, shops: list[NewShop]) -> list[CoffeeShop]:
        result: list[CoffeeShop] = []
        for incoming in shops:
            existing = next((s for s in self._shops.values() if is_same_shop(s, incoming)), None)
            if existing:
                result.append(existing)
                continue
            shop: CoffeeShop = {
                "dogFriendly": None,
                "wifi": None,
                "outdoorSeating": None,
                **incoming,
                "id": str(uuid4()),
                "chainId": None,
                "savedByMe": False,
                "beenByMe": False,
                "updatedAt": _now(),
            }
            self._shops[shop["id"]] = shop
            result.append(shop)
        self.relink_chains()
        return [self.get_shop(s["id"]) or s for s in result]

    def enrich_shop(self, shop_id: str, patch: dict) -> None:
        shop = self._shops.get(shop_id)
        if not shop:
            return
        if shop["machine"] == "UNKNOWN" and patch.get("machine"):
            shop["machine"] = patch["machine"]
        if shop["machineModel"] is None and patch.get("machineModel"):
            shop["machineModel"] = patch["machineModel"]
        if shop["beanSource"] == "UNKNOWN" and patch.get("beanSource"):
            shop["beanSource"] = patch["beanSource"]
        if shop["roaster"] is None and patch.get("roaster"):
            shop["roaster"] = patch["roaster"]
        if not shop["milkBrands"] and patch.get("milkBrands"):
            shop["milkBrands"] = patch["milkBrands"]
        if shop["vibe"] is None and patch.get("vibe"):
            shop["vibe"] = patch["vibe"]
        for key in ("dogFriendly", "wifi", "outdoorSeating"):
            if shop[key] is None and patch.get(key) is not None:  # type: ignore[literal-required]
                shop[key] = patch[key]  # type: ignore[literal-required]
        shop["updatedAt"] = _now()

    def set_shop_meta(self, shop_id: str, meta: dict) -> None:
        shop = self._shops.get(shop_id)
        if shop:
            shop["photoUrl"] = meta.get("photoUrl") or shop["photoUrl"]
            shop["website"] = meta.get("website") or shop["website"]
            if meta.get("website"):
                self.relink_chains()

    def upsert_user(self, user: dict) -> User:
        existing = next((u for u in self._users.values() if u["googleSub"] == user["googleSub"]), None)
        record: User = {**user, "id": existing["id"] if existing else str(uuid4())}
        self._users[record["id"]] = record
        return record

    def set_shop_status(self, user_id: str, shop_id: str, saved: bool | None, been: bool | None) -> None:
        key = (user_id, shop_id)
        current = self._statuses.get(key, {"saved": False, "been": False})
        self._statuses[key] = {
            "saved": current["saved"] if saved is None else saved,
            "been": current["been"] if been is None else been,
        }

    def user_stats(self, user_id: str) -> dict[str, Any]:
        mine = [s for (uid, _), s in self._statuses.items() if uid == user_id]
        return {"saved": sum(s["saved"] for s in mine), "been": sum(s["been"] for s in mine)}

    def list_photos(self, shop_id: str, limit: int | None = None) -> list[ShopPhoto]:
        photos = list(reversed(self._photos.get(shop_id, [])))
        return photos[:limit] if limit else photos

    def count_photos(self, shop_id: str) -> int:
        return len(self._photos.get(shop_id, []))

    def add_photos(self, shop_id: str, user_id: str | None, photos: list[dict]) -> list[ShopPhoto]:
        user = self._users.get(user_id or "")
        added: list[ShopPhoto] = [
            {
                "id": str(uuid4()),
                "shopId": shop_id,
                "kind": p["kind"],
                "data": p["data"],
                "uploader": {"name": user["name"], "picture": user["picture"]} if user else None,
                "createdAt": _now(),
            }
            for p in photos
        ]
        self._photos.setdefault(shop_id, []).extend(added)
        return added

    def get_chain(self, chain_id: str) -> Chain | None:
        return self._chains.get(chain_id)

    def list_chain_shops(self, chain_id: str, user_id: str | None = None) -> list[CoffeeShop]:
        shops = [self._with_flags(s, user_id) for s in self._shops.values() if s.get("chainId") == chain_id]
        shops.sort(key=lambda s: (s["city"], s["name"]))
        return shops

    def relink_chains(self) -> int:
        clusters = cluster_shops(list(self._shops.values()))
        keep: set[str] = set()
        assigned = 0
        by_slug = {c["slug"]: c for c in self._chains.values()}
        for members in clusters:
            existing_ids = [m["chainId"] for m in members if m.get("chainId")]
            name = min((brand_name(m["name"]) for m in members), key=len)
            slug = slugify_brand(name)
            website = next((m.get("website") for m in members if m.get("website")), None)
            if existing_ids and existing_ids[0] in self._chains:
                chain_id = existing_ids[0]
                chain = self._chains[chain_id]
                chain["name"] = name
                chain["website"] = website or chain["website"]
            elif slug in by_slug:
                chain_id = by_slug[slug]["id"]
                self._chains[chain_id]["name"] = name
                self._chains[chain_id]["website"] = website or self._chains[chain_id]["website"]
            else:
                chain_id = str(uuid4())
                record: Chain = {"id": chain_id, "name": name, "slug": slug, "website": website}
                self._chains[chain_id] = record
                by_slug[slug] = record
            for member in members:
                member["chainId"] = chain_id
            keep.add(chain_id)
            assigned += len(members)
        for shop in self._shops.values():
            if shop.get("chainId") and shop["chainId"] not in keep:
                shop["chainId"] = None
        self._chains = {cid: c for cid, c in self._chains.items() if cid in keep}
        return assigned
