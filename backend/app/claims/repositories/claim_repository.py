"""Seller applications (shop_claims), resolved manually by support."""

import sqlalchemy as sa
from sqlalchemy.orm import contains_eager, sessionmaker

from ... import models as m
from ...core.db import now


class ClaimRepository:
    def __init__(self, session: sessionmaker):
        self._session = session

    def create(self, user_id: str, shop_id: str, application: dict) -> m.ShopClaim:
        """application: shop_claims column names -> values (business_role, contact, website, note)."""
        with self._session.begin() as s:
            pending = s.scalars(
                sa.select(m.ShopClaim).where(
                    m.ShopClaim.user_id == user_id,
                    m.ShopClaim.shop_id == shop_id,
                    m.ShopClaim.status == "PENDING",
                )
            ).first()
            if pending:
                _ = pending.user
                return pending
            claim = m.ShopClaim(shop_id=shop_id, user_id=user_id, **application)
            s.add(claim)
            s.flush()
            # Load server defaults and the applicant before the row detaches.
            s.refresh(claim)
            _ = claim.user
            return claim

    def list(self, user_id: str | None = None, status: str | None = None) -> list[m.ShopClaim]:
        stmt = sa.select(m.ShopClaim).outerjoin(m.ShopClaim.user).options(contains_eager(m.ShopClaim.user))
        if user_id:
            stmt = stmt.where(m.ShopClaim.user_id == user_id)
        if status:
            stmt = stmt.where(m.ShopClaim.status == status)
        # Support reviews oldest first; a user's own list shows newest first.
        order = m.ShopClaim.created_at.asc() if status == "PENDING" else m.ShopClaim.created_at.desc()
        with self._session() as s:
            return list(s.scalars(stmt.order_by(order)))

    def resolve(self, claim_id: str, approve: bool) -> m.ShopClaim | None:
        with self._session.begin() as s:
            claim = s.scalars(
                sa.select(m.ShopClaim)
                .where(m.ShopClaim.id == claim_id, m.ShopClaim.status == "PENDING")
                .with_for_update()
            ).first()
            if not claim:
                return None
            claim.status = "APPROVED" if approve else "REJECTED"
            claim.resolved_at = now()
            if approve:
                s.execute(
                    sa.update(m.Shop).where(m.Shop.id == claim.shop_id).values(owner_user_id=claim.user_id)
                )
            _ = claim.user
            return claim
