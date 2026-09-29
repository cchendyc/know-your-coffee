"""shops table access, including the viewer's bookmark/visit flags.

Every dict argument here uses column names; entrypoints translate GraphQL
input keys before calling in."""

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import sessionmaker

from ... import models as m
from ...core.db import now
from ..search import completeness_order, matches_token, same_shop_clause
from ..text import split_search


def viewer_has(edge: type[m.ShopBookmark] | type[m.ShopVisit], viewer_id: str):
    """EXISTS: viewer_id has a row in edge for the outer shop."""
    return sa.exists().where(edge.user_id == viewer_id, edge.shop_id == m.Shop.id)


def shops_stmt(viewer_id: str | None):
    """SELECT shops plus the viewer's saved/been flags when signed in."""
    if viewer_id:
        return sa.select(m.Shop, viewer_has(m.ShopBookmark, viewer_id), viewer_has(m.ShopVisit, viewer_id))
    return sa.select(m.Shop, sa.false(), sa.false())


def shop_from_row(row) -> m.Shop:
    shop = row[0]
    shop.saved_by_me = bool(row[1])
    shop.been_by_me = bool(row[2])
    return shop


class ShopRepository:
    def __init__(self, session: sessionmaker):
        self._session = session

    def list(self, filter: dict, viewer_id: str | None = None) -> tuple[list[m.Shop], int]:
        conditions = []
        if filter.get("machine"):
            # Match the primary or any machine on the bar (jsonb @>).
            conditions.append(
                sa.or_(
                    m.Shop.machine == filter["machine"],
                    m.Shop.machines.contains([{"brand": filter["machine"]}]),
                )
            )
        if filter.get("city"):
            conditions.append(m.Shop.city.ilike(filter["city"]))
        if filter.get("saved") and viewer_id:
            conditions.append(viewer_has(m.ShopBookmark, viewer_id))
        if filter.get("been") and viewer_id:
            conditions.append(viewer_has(m.ShopVisit, viewer_id))
        if filter.get("search"):
            tokens, amenities = split_search(filter["search"])
            conditions.extend(matches_token(token) for token in tokens)
            conditions.extend(getattr(m.Shop, column).is_(True) for column in amenities)

        limit = filter.get("limit") or 24
        offset = filter.get("offset") or 0
        page = (
            shops_stmt(viewer_id)
            .add_columns(sa.func.count().over().label("total"))
            .where(*conditions)
            .order_by(*completeness_order())
            .limit(limit)
            .offset(offset)
        )
        with self._session() as s:
            rows = s.execute(page).all()
            total = rows[0][-1] if rows else 0
            # count(*) OVER() is 0-row-safe only when a page has rows; recount otherwise.
            if not rows and offset > 0:
                total = s.scalar(sa.select(sa.func.count()).select_from(m.Shop).where(*conditions)) or 0
            return [shop_from_row(r) for r in rows], total

    def get(self, shop_id: str, viewer_id: str | None = None) -> m.Shop | None:
        with self._session() as s:
            row = s.execute(shops_stmt(viewer_id).where(m.Shop.id == shop_id)).first()
            return shop_from_row(row) if row else None

    def list_owned(self, owner_id: str) -> list[m.Shop]:
        with self._session() as s:
            rows = s.execute(
                shops_stmt(owner_id).where(m.Shop.owner_user_id == owner_id).order_by(m.Shop.name.asc())
            ).all()
            return [shop_from_row(r) for r in rows]

    def cities(self) -> list[str]:
        with self._session() as s:
            return list(s.scalars(sa.select(m.Shop.city).distinct().order_by(m.Shop.city.asc())))

    def find_matching(self, name: str, lat: float, lng: float) -> m.Shop | None:
        with self._session() as s:
            return s.scalars(sa.select(m.Shop).where(same_shop_clause(name, lat, lng)).limit(1)).first()

    def insert(self, values: dict) -> m.Shop:
        with self._session.begin() as s:
            shop = m.Shop(**values)
            s.add(shop)
            s.flush()
            s.refresh(shop)  # load server defaults before the row detaches
            return shop

    def update_profile(self, shop_id: str, changes: dict) -> None:
        """changes: vibe, website; patch semantics."""
        with self._session.begin() as s:
            shop = s.get(m.Shop, shop_id)
            if not shop:
                return
            for column, value in changes.items():
                setattr(shop, column, value)
            shop.updated_at = now()

    def complete_seller_onboarding(self, shop_id: str) -> None:
        """Idempotent: keeps the first completion timestamp."""
        with self._session.begin() as s:
            shop = s.get(m.Shop, shop_id)
            if shop and shop.seller_onboarded_at is None:
                shop.seller_onboarded_at = now()

    def update_delivery_settings(self, shop_id: str, changes: dict) -> m.Shop | None:
        """changes: offers_shipping, offers_pickup, pickup_instructions; patch semantics."""
        with self._session.begin() as s:
            shop = s.get(m.Shop, shop_id)
            if not shop:
                return None
            for column, value in changes.items():
                setattr(shop, column, value)
            shop.updated_at = now()
            return shop

    def enrich(self, shop_id: str, patch: dict) -> None:
        """Review-derived data. Only fills fields that are still UNKNOWN/null/empty,
        so it never overwrites community reports."""
        with self._session.begin() as s:
            shop = s.get(m.Shop, shop_id)
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
            shop.updated_at = now()

    def set_meta(self, shop_id: str, photo_url: str | None, website: str | None) -> None:
        with self._session.begin() as s:
            shop = s.get(m.Shop, shop_id)
            if not shop:
                return
            shop.photo_url = photo_url or shop.photo_url
            shop.website = website or shop.website

    def delete(self, shop_id: str) -> bool:
        # No FK constraints, so no cascade: remove every row that points at the shop.
        with self._session.begin() as s:
            order_ids = sa.select(m.Order.id).where(m.Order.shop_id == shop_id)
            s.execute(sa.delete(m.Shipment).where(m.Shipment.order_id.in_(order_ids)))
            product_ids = sa.select(m.Product.id).where(m.Product.shop_id == shop_id)
            s.execute(sa.delete(m.ProductPhoto).where(m.ProductPhoto.product_id.in_(product_ids)))
            for model in (m.Order, m.Product, m.ShopPhoto, m.ShopBookmark, m.ShopVisit, m.Report, m.ShopClaim):
                s.execute(sa.delete(model).where(model.shop_id == shop_id))
            row = s.execute(sa.delete(m.Shop).where(m.Shop.id == shop_id).returning(m.Shop.id)).first()
        return bool(row)

    # ------------------------------------------------------- saved / been

    def set_status(self, viewer_id: str, shop_id: str, saved: bool | None, been: bool | None) -> None:
        # Re-saving keeps the original created_at; unsaving deletes the row.
        with self._session.begin() as s:
            for edge, on in ((m.ShopBookmark, saved), (m.ShopVisit, been)):
                if on:
                    s.execute(pg_insert(edge).values(user_id=viewer_id, shop_id=shop_id).on_conflict_do_nothing())
                elif on is False:
                    s.execute(sa.delete(edge).where(edge.user_id == viewer_id, edge.shop_id == shop_id))

    def viewer_stats(self, viewer_id: str) -> dict:
        def count(edge):
            return sa.select(sa.func.count()).where(edge.user_id == viewer_id).scalar_subquery()

        with self._session() as s:
            row = s.execute(
                sa.select(count(m.ShopBookmark).label("saved"), count(m.ShopVisit).label("been"))
            ).one()
            return {"saved": row.saved, "been": row.been}
