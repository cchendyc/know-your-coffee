"""SQLAlchemy models, one module per table — the canonical table layer.
Resolvers map model attributes onto GraphQL fields at the entrypoint layer.
DDL ships as raw-SQL Alembic migrations; keep them in sync."""

from .base import Base
from .bookmark import ShopBookmark
from .chain import Chain
from .claim import ShopClaim
from .enums import (
    BEAN_SOURCES,
    CLAIM_STATUSES,
    COFFEE_PROCESSES,
    COFFEE_TYPES,
    MACHINE_BRANDS,
    ORDER_STATUSES,
    PHOTO_KINDS,
    REPORT_SOURCES,
    ROAST_LEVELS,
    SHIPMENT_STATUSES,
    USER_ROLES,
    Fulfillment,
    ListingStatus,
    OrderStatus,
    ShipmentStatus,
)
from .order import Order
from .photo import ShopPhoto
from .product import Product
from .product_photo import MAX_PHOTO_BYTES, MAX_PRODUCT_PHOTOS, ProductPhoto
from .report import Report
from .shipment import Shipment
from .shop import Shop
from .user import LoginCode, User
from .visit import ShopVisit

__all__ = [
    "BEAN_SOURCES",
    "CLAIM_STATUSES",
    "COFFEE_PROCESSES",
    "COFFEE_TYPES",
    "MACHINE_BRANDS",
    "MAX_PHOTO_BYTES",
    "MAX_PRODUCT_PHOTOS",
    "ORDER_STATUSES",
    "PHOTO_KINDS",
    "REPORT_SOURCES",
    "ROAST_LEVELS",
    "SHIPMENT_STATUSES",
    "USER_ROLES",
    "Base",
    "Chain",
    "Fulfillment",
    "ListingStatus",
    "LoginCode",
    "Order",
    "OrderStatus",
    "Product",
    "ProductPhoto",
    "Report",
    "Shipment",
    "ShipmentStatus",
    "Shop",
    "ShopBookmark",
    "ShopClaim",
    "ShopPhoto",
    "ShopVisit",
    "User",
]
