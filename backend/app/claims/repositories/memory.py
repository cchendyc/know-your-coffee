"""In-memory claim repository, mirroring the Postgres behavior."""

from datetime import UTC, datetime

from ... import models as m
from ...core.memory import MemoryStore


class MemoryClaimRepository:
    def __init__(self, store: MemoryStore):
        self._store = store

    def create(self, user_id: str, shop_id: str, application: dict) -> m.ShopClaim:
        store = self._store
        pending = next(
            (
                c for c in store.claims.values()
                if str(c.user_id) == user_id and str(c.shop_id) == shop_id and c.status == "PENDING"
            ),
            None,
        )
        if pending:
            return pending
        claim = m.ShopClaim(
            id=store.next_id(),
            shop_id=int(shop_id),
            user_id=int(user_id),
            status="PENDING",
            business_role=application.get("business_role"),
            contact=application.get("contact"),
            website=application.get("website"),
            note=application.get("note"),
            resolved_at=None,
            user=store.users.get(user_id),
            created_at=datetime.now(UTC),
        )
        store.claims[str(claim.id)] = claim
        return claim

    def list(self, user_id: str | None = None, status: str | None = None) -> list[m.ShopClaim]:
        claims = [
            c for c in self._store.claims.values()
            if (user_id is None or str(c.user_id) == user_id) and (status is None or c.status == status)
        ]
        # Support reviews oldest first; a user's own list shows newest first.
        return sorted(claims, key=lambda c: c.created_at, reverse=status != "PENDING")

    def resolve(self, claim_id: str, approve: bool) -> m.ShopClaim | None:
        claim = self._store.claims.get(str(claim_id))
        if not claim or claim.status != "PENDING":
            return None
        claim.status = "APPROVED" if approve else "REJECTED"
        claim.resolved_at = datetime.now(UTC)
        if approve and (shop := self._store.shops.get(str(claim.shop_id))):
            shop.owner_user_id = claim.user_id
        return claim
