"""chains table access. Clusters are rebuilt from shop names and websites."""

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import sessionmaker

from ... import models as m
from ..text import brand_name, cluster_shops, slugify_brand
from .shop_repository import shop_from_row, shops_stmt


class ChainRepository:
    def __init__(self, session: sessionmaker):
        self._session = session

    def get(self, chain_id: str) -> m.Chain | None:
        with self._session() as s:
            return s.get(m.Chain, chain_id)

    def list_shops(self, chain_id: str, viewer_id: str | None = None) -> list[m.Shop]:
        with self._session() as s:
            rows = s.execute(
                shops_stmt(viewer_id)
                .where(m.Shop.chain_id == chain_id)
                .order_by(m.Shop.city.asc(), m.Shop.name.asc())
            ).all()
            return [shop_from_row(r) for r in rows]

    def relink(self) -> int:
        """Rebuild chain assignments; returns how many shops belong to a chain."""
        with self._session.begin() as s:
            rows = s.execute(sa.select(m.Shop.id, m.Shop.name, m.Shop.website, m.Shop.chain_id)).all()
            clusters = cluster_shops([dict(r._mapping) for r in rows])
            assigned = 0
            keep: list[str] = []
            for members in clusters:
                existing = [str(mem["chain_id"]) for mem in members if mem.get("chain_id")]
                name = min((brand_name(mem["name"]) for mem in members), key=len)
                slug = slugify_brand(name)
                website = next((mem["website"] for mem in members if mem.get("website")), None)
                chain_id = None
                if existing:
                    chain = s.get(m.Chain, existing[0])
                    if chain:
                        chain_id = existing[0]
                        chain.name = name
                        chain.website = website or chain.website
                if chain_id is None:
                    stmt = pg_insert(m.Chain).values(name=name, slug=slug, website=website)
                    stmt = stmt.on_conflict_do_update(
                        index_elements=[m.Chain.slug],
                        set_={
                            "name": stmt.excluded.name,
                            "website": sa.func.coalesce(stmt.excluded.website, m.Chain.website),
                        },
                    ).returning(m.Chain.id)
                    chain_id = str(s.execute(stmt).scalar_one())
                ids = [str(mem["id"]) for mem in members]
                s.execute(sa.update(m.Shop).where(m.Shop.id.in_(ids)).values(chain_id=chain_id))
                keep.append(chain_id)
                assigned += len(members)
            if keep:
                s.execute(
                    sa.update(m.Shop)
                    .where(m.Shop.chain_id.is_not(None), m.Shop.chain_id.not_in(keep))
                    .values(chain_id=None)
                )
                s.execute(sa.delete(m.Chain).where(m.Chain.id.not_in(keep)))
            else:
                s.execute(sa.update(m.Shop).where(m.Shop.chain_id.is_not(None)).values(chain_id=None))
                s.execute(sa.delete(m.Chain))
        return assigned
