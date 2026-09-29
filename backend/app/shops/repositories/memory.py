"""In-memory shop-domain repositories, mirroring the Postgres behavior.

Every dict argument uses column names, same as the Postgres classes."""

from datetime import UTC, datetime

from ... import models as m
from ...core.memory import MemoryStore
from ..records import NewShop
from ..text import brand_name, cluster_shops, is_same_shop, slugify_brand, split_search


def _now() -> datetime:
    return datetime.now(UTC)


def _matches(shop: m.Shop, filter: dict) -> bool:
    if (
        filter.get("machine")
        and shop.machine != filter["machine"]
        and not any(mc.get("brand") == filter["machine"] for mc in shop.machines)
    ):
        return False
    if filter.get("city") and shop.city.lower() != filter["city"].lower():
        return False
    if filter.get("search"):
        # jsonb documents keep their stored camelCase keys.
        haystack = " ".join(
            [
                shop.name,
                shop.city,
                shop.address,
                shop.roaster or "",
                shop.machine,
                shop.machine_model or "",
                shop.vibe or "",
                *shop.bean_origins,
                *shop.grinders,
                *shop.milk_brands,
                *[d["name"] for d in shop.drinks],
                *[mc.get("brand") or "" for mc in shop.machines],
                *[mc.get("model") or "" for mc in shop.machines],
                *[c.get("name") or "" for c in shop.coffees],
                *[c.get("roaster") or "" for c in shop.coffees],
                *[c.get("fermentation") or "" for c in shop.coffees],
                *[o for c in shop.coffees for o in c.get("origins") or []],
                *[v for c in shop.coffees for v in c.get("varieties") or []],
                *[t for c in shop.coffees for t in c.get("tastingNotes") or []],
            ]
        ).lower()
        tokens, amenities = split_search(filter["search"])
        if not all(token in haystack for token in tokens):
            return False
        if any(getattr(shop, column) is not True for column in amenities):
            return False
    return True


def _rank(shop: m.Shop) -> int:
    """Mirrors shops/search.py: known machine dominates, then other filled fields."""
    return (
        (8 if shop.machine != "UNKNOWN" else 0)
        + (2 if shop.machine_model else 0)
        + (2 if shop.bean_source != "UNKNOWN" else 0)
        + (2 if shop.roaster else 0)
        + (1 if shop.grinders else 0)
        + (1 if shop.coffees else 0)
        + (1 if shop.drinks else 0)
        + (1 if shop.milk_brands else 0)
        + (1 if shop.vibe else 0)
        # Amenities count when known either way; a "no dogs" answer is still data.
        + (1 if shop.dog_friendly is not None else 0)
        + (1 if shop.wifi is not None else 0)
        + (1 if shop.outdoor_seating is not None else 0)
    )


class MemoryShopRepository:
    def __init__(self, store: MemoryStore):
        self._store = store

    def _flagged(self, shop: m.Shop, viewer_id: str | None) -> m.Shop:
        key = (viewer_id, str(shop.id))
        shop.saved_by_me = key in self._store.bookmarks
        shop.been_by_me = key in self._store.visits
        return shop

    def list(self, filter: dict, viewer_id: str | None = None) -> tuple[list[m.Shop], int]:
        shops = [self._flagged(s, viewer_id) for s in self._store.shops.values() if _matches(s, filter)]
        if filter.get("saved"):
            shops = [s for s in shops if s.saved_by_me]
        if filter.get("been"):
            shops = [s for s in shops if s.been_by_me]
        # Stable multi-pass sort: name asc, then recency desc, then rank desc.
        shops.sort(key=lambda s: s.name)
        shops.sort(key=lambda s: s.updated_at, reverse=True)
        shops.sort(key=_rank, reverse=True)
        offset = filter.get("offset") or 0
        limit = filter.get("limit") or 24
        return shops[offset : offset + limit], len(shops)

    def get(self, shop_id: str, viewer_id: str | None = None) -> m.Shop | None:
        shop = self._store.shops.get(str(shop_id))
        return self._flagged(shop, viewer_id) if shop else None

    def list_owned(self, owner_id: str) -> list[m.Shop]:
        owned = [s for s in self._store.shops.values() if str(s.owner_user_id or "") == owner_id]
        return sorted((self._flagged(s, owner_id) for s in owned), key=lambda s: s.name)

    def cities(self) -> list[str]:
        return sorted({s.city for s in self._store.shops.values()})

    def find_matching(self, name: str, lat: float, lng: float) -> m.Shop | None:
        probe = {"name": name, "lat": lat, "lng": lng}
        return next(
            (
                s
                for s in self._store.shops.values()
                if is_same_shop({"name": s.name, "lat": s.lat, "lng": s.lng}, probe)
            ),
            None,
        )

    def insert(self, values: NewShop) -> m.Shop:
        shop = m.Shop(
            id=self._store.next_id(),
            chain_id=None,
            machines=[],
            coffees=[],
            dog_friendly=None,
            wifi=None,
            outdoor_seating=None,
            owner_user_id=None,
            offers_shipping=True,
            offers_pickup=False,
            pickup_instructions=None,
            updated_at=_now(),
            **values,
        )
        self._store.shops[str(shop.id)] = shop
        return shop

    def update_profile(self, shop_id: str, changes: dict) -> None:
        shop = self._store.shops.get(str(shop_id))
        if not shop:
            return
        for column, value in changes.items():
            setattr(shop, column, value)
        shop.updated_at = _now()

    def complete_seller_onboarding(self, shop_id: str) -> None:
        shop = self._store.shops.get(str(shop_id))
        if shop and shop.seller_onboarded_at is None:
            shop.seller_onboarded_at = _now()

    def update_delivery_settings(self, shop_id: str, changes: dict) -> m.Shop | None:
        shop = self._store.shops.get(str(shop_id))
        if not shop:
            return None
        for column, value in changes.items():
            setattr(shop, column, value)
        shop.updated_at = _now()
        return shop

    def enrich(self, shop_id: str, patch: dict) -> None:
        shop = self._store.shops.get(str(shop_id))
        if not shop:
            return
        if shop.machine == "UNKNOWN" and patch.get("machine"):
            shop.machine = patch["machine"]
        if shop.machine_model is None:
            shop.machine_model = patch.get("machine_model")
        if shop.bean_source == "UNKNOWN" and patch.get("bean_source"):
            shop.bean_source = patch["bean_source"]
        if shop.roaster is None:
            shop.roaster = patch.get("roaster")
        if not shop.milk_brands and patch.get("milk_brands"):
            shop.milk_brands = patch["milk_brands"]
        if shop.vibe is None:
            shop.vibe = patch.get("vibe")
        if shop.dog_friendly is None:
            shop.dog_friendly = patch.get("dog_friendly")
        if shop.wifi is None:
            shop.wifi = patch.get("wifi")
        if shop.outdoor_seating is None:
            shop.outdoor_seating = patch.get("outdoor_seating")
        shop.updated_at = _now()

    def set_meta(self, shop_id: str, photo_url: str | None, website: str | None) -> None:
        shop = self._store.shops.get(str(shop_id))
        if shop:
            shop.photo_url = photo_url or shop.photo_url
            shop.website = website or shop.website

    def delete(self, shop_id: str) -> bool:
        store = self._store
        shop_id = str(shop_id)
        if shop_id not in store.shops:
            return False
        del store.shops[shop_id]
        store.reports.pop(shop_id, None)
        store.photos.pop(shop_id, None)
        store.bookmarks = {k for k in store.bookmarks if k[1] != shop_id}
        store.visits = {k for k in store.visits if k[1] != shop_id}
        store.claims = {cid: c for cid, c in store.claims.items() if str(c.shop_id) != shop_id}
        gone_products = {pid for pid, p in store.products.items() if str(p.shop_id) == shop_id}
        store.products = {pid: p for pid, p in store.products.items() if pid not in gone_products}
        store.product_photos = {pid: ph for pid, ph in store.product_photos.items() if pid not in gone_products}
        gone = {oid for oid, o in store.orders.items() if str(o.shop_id) == shop_id}
        store.orders = {oid: o for oid, o in store.orders.items() if oid not in gone}
        store.shipments = {sid: s for sid, s in store.shipments.items() if str(s.order_id) not in gone}
        return True

    def set_status(self, viewer_id: str, shop_id: str, saved: bool | None, been: bool | None) -> None:
        key = (viewer_id, str(shop_id))
        for edges, on in ((self._store.bookmarks, saved), (self._store.visits, been)):
            if on:
                edges.add(key)
            elif on is False:
                edges.discard(key)

    def viewer_stats(self, viewer_id: str) -> dict:
        return {
            "saved": sum(1 for k in self._store.bookmarks if k[0] == viewer_id),
            "been": sum(1 for k in self._store.visits if k[0] == viewer_id),
        }


class MemoryChainRepository:
    def __init__(self, store: MemoryStore):
        self._store = store

    def get(self, chain_id: str) -> m.Chain | None:
        return self._store.chains.get(str(chain_id))

    def list_shops(self, chain_id: str, viewer_id: str | None = None) -> list[m.Shop]:
        shops = MemoryShopRepository(self._store)
        members = [s for s in self._store.shops.values() if str(s.chain_id or "") == chain_id]
        members.sort(key=lambda s: (s.city, s.name))
        return [shops._flagged(s, viewer_id) for s in members]

    def relink(self) -> int:
        store = self._store
        records = [
            {"name": s.name, "website": s.website, "chain_id": s.chain_id, "shop": s}
            for s in store.shops.values()
        ]
        keep: set[str] = set()
        assigned = 0
        by_slug = {c.slug: c for c in store.chains.values()}
        for members in cluster_shops(records):
            existing_ids = [str(mem["chain_id"]) for mem in members if mem.get("chain_id")]
            name = min((brand_name(mem["name"]) for mem in members), key=len)
            slug = slugify_brand(name)
            website = next((mem.get("website") for mem in members if mem.get("website")), None)
            if existing_ids and existing_ids[0] in store.chains:
                chain = store.chains[existing_ids[0]]
                chain.name = name
                chain.website = website or chain.website
            elif slug in by_slug:
                chain = by_slug[slug]
                chain.name = name
                chain.website = website or chain.website
            else:
                chain = m.Chain(id=store.next_id(), name=name, slug=slug, website=website, created_at=_now())
                store.chains[str(chain.id)] = chain
                by_slug[slug] = chain
            for member in members:
                member["shop"].chain_id = chain.id
            keep.add(str(chain.id))
            assigned += len(members)
        for shop in store.shops.values():
            if shop.chain_id and str(shop.chain_id) not in keep:
                shop.chain_id = None
        store.chains = {cid: c for cid, c in store.chains.items() if cid in keep}
        return assigned


class MemoryReportRepository:
    _FOLD_COLUMNS = (
        "machine", "machine_model", "machines", "bean_source", "roaster", "bean_origins",
        "coffees", "grinders", "drinks", "milk_brands", "dog_friendly", "wifi", "outdoor_seating",
    )

    def __init__(self, store: MemoryStore):
        self._store = store

    def _community(self, shop_id: str) -> list[m.Report]:
        return [
            r for r in self._store.reports.get(str(shop_id), [])
            if not (r.user is not None and r.user.role == "ADMIN")
        ]

    def list(self, shop_id: str, limit: int | None = None) -> list[m.Report]:
        reports = list(reversed(self._community(shop_id)))
        return reports[:limit] if limit else reports

    def count(self, shop_id: str) -> int:
        return len(self._community(shop_id))

    def add(self, shop_id: str, user_id: str | None, note: str | None, source: str, fields: dict) -> m.Report:
        store = self._store
        machines = fields.get("machines")
        if machines and not fields.get("machine"):
            fields = {**fields, "machine": machines[0]["brand"], "machine_model": machines[0].get("model")}
        row = m.Report(
            id=store.next_id(),
            shop_id=int(shop_id),
            user_id=int(user_id) if user_id else None,
            user=store.users.get(str(user_id or "")),
            note=note,
            source=source,
            created_at=_now(),
            **{column: fields.get(column) for column in self._FOLD_COLUMNS},
        )
        store.reports.setdefault(str(shop_id), []).append(row)

        # Latest report wins: fold non-null fields into the shop record.
        shop = store.shops.get(str(shop_id))
        if shop:
            for column in self._FOLD_COLUMNS:
                value = getattr(row, column)
                if value is not None:
                    setattr(shop, column, value)
            shop.updated_at = row.created_at
        return row


class MemoryPhotoRepository:
    def __init__(self, store: MemoryStore):
        self._store = store

    def list(self, shop_id: str, limit: int | None = None) -> list[m.ShopPhoto]:
        photos = list(reversed(self._store.photos.get(str(shop_id), [])))
        return photos[:limit] if limit else photos

    def count(self, shop_id: str) -> int:
        return len(self._store.photos.get(str(shop_id), []))

    def add(self, shop_id: str, user_id: str | None, photos: list[dict]) -> list[m.ShopPhoto]:
        store = self._store
        added = [
            m.ShopPhoto(
                id=store.next_id(),
                shop_id=int(shop_id),
                user_id=int(user_id) if user_id else None,
                kind=p["kind"],
                data=p["data"],
                user=store.users.get(str(user_id or "")),
                created_at=_now(),
            )
            for p in photos
        ]
        store.photos.setdefault(str(shop_id), []).extend(added)
        return added
