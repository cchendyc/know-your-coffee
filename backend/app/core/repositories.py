"""Repository wiring. Postgres when DATABASE_URL is set; otherwise the
in-memory repositories keep local development working without a database."""

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class Repositories:
    shops: Any
    chains: Any
    reports: Any
    reviews: Any
    photos: Any
    users: Any
    claims: Any
    categories: Any
    products: Any
    product_photos: Any
    orders: Any
    shipments: Any
    addresses: Any


def create_repositories() -> Repositories:
    from .. import settings

    if settings.DATABASE_URL:
        from ..accounts.repositories.user_repository import UserRepository
        from ..claims.repositories.claim_repository import ClaimRepository
        from ..commerce.repositories.address_repository import AddressRepository
        from ..commerce.repositories.category_repository import CategoryRepository
        from ..commerce.repositories.order_repository import OrderRepository
        from ..commerce.repositories.product_photo_repository import ProductPhotoRepository
        from ..commerce.repositories.product_repository import ProductRepository
        from ..commerce.repositories.shipment_repository import ShipmentRepository
        from ..shops.repositories.chain_repository import ChainRepository
        from ..shops.repositories.photo_repository import PhotoRepository
        from ..shops.repositories.report_repository import ReportRepository
        from ..shops.repositories.review_repository import ReviewRepository
        from ..shops.repositories.shop_repository import ShopRepository
        from .db import create_session_factory

        print("repository: Postgres (DATABASE_URL set)")
        session = create_session_factory(settings.DATABASE_URL)
        return Repositories(
            shops=ShopRepository(session),
            chains=ChainRepository(session),
            reports=ReportRepository(session),
            reviews=ReviewRepository(session),
            photos=PhotoRepository(session),
            users=UserRepository(session),
            claims=ClaimRepository(session),
            categories=CategoryRepository(session),
            products=ProductRepository(session),
            product_photos=ProductPhotoRepository(session),
            orders=OrderRepository(session),
            shipments=ShipmentRepository(session),
            addresses=AddressRepository(session),
        )

    from .memory import MemoryStore

    print("repository: in-memory, non-persistent (set DATABASE_URL to use Neon)")
    return create_memory_repositories(MemoryStore())


def create_memory_repositories(store) -> Repositories:
    """Also used by tests that need to seed the store directly."""
    from ..accounts.repositories.memory import MemoryUserRepository
    from ..claims.repositories.memory import MemoryClaimRepository
    from ..commerce.repositories.memory import (
        MemoryAddressRepository,
        MemoryCategoryRepository,
        MemoryOrderRepository,
        MemoryProductPhotoRepository,
        MemoryProductRepository,
        MemoryShipmentRepository,
    )
    from ..shops.repositories.memory import (
        MemoryChainRepository,
        MemoryPhotoRepository,
        MemoryReportRepository,
        MemoryReviewRepository,
        MemoryShopRepository,
    )

    return Repositories(
        shops=MemoryShopRepository(store),
        chains=MemoryChainRepository(store),
        reports=MemoryReportRepository(store),
        reviews=MemoryReviewRepository(store),
        photos=MemoryPhotoRepository(store),
        users=MemoryUserRepository(store),
        claims=MemoryClaimRepository(store),
        categories=MemoryCategoryRepository(store),
        products=MemoryProductRepository(store),
        product_photos=MemoryProductPhotoRepository(store),
        orders=MemoryOrderRepository(store),
        shipments=MemoryShipmentRepository(store),
        addresses=MemoryAddressRepository(store),
    )
