"""SQLAlchemy models, one module per table — the canonical table layer.
Resolvers map model attributes onto GraphQL fields at the entrypoint layer.
DDL ships as raw-SQL Alembic migrations; keep them in sync."""

from .address import Address
from .base import Base
from .bookmark import ShopBookmark
from .category import Category, CategoryAttribute, CategoryField, ProductAttribute, ProductAttributeOption
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
    AttributeSection,
    AttributeValueType,
    Carrier,
    Fulfillment,
    ListingStatus,
    OrderAction,
    OrderStatus,
    PaymentOperation,
    PaymentStatus,
    ShipmentStatus,
    ShipsTo,
)
from .order import Order
from .order_item import OrderEvent, OrderItem
from .payment import Payment, PaymentMethod, PaymentTransaction
from .photo import ShopPhoto
from .product import Product
from .product_photo import MAX_PHOTO_BYTES, MAX_PRODUCT_PHOTOS, ProductPhoto
from .report import Report
from .review import Review
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
    "Address",
    "AttributeSection",
    "AttributeValueType",
    "Base",
    "Carrier",
    "Category",
    "CategoryAttribute",
    "CategoryField",
    "Chain",
    "Fulfillment",
    "ListingStatus",
    "LoginCode",
    "Order",
    "OrderAction",
    "OrderEvent",
    "OrderItem",
    "OrderStatus",
    "Payment",
    "PaymentMethod",
    "PaymentOperation",
    "PaymentStatus",
    "PaymentTransaction",
    "Product",
    "ProductAttribute",
    "ProductAttributeOption",
    "ProductPhoto",
    "Report",
    "Review",
    "Shipment",
    "ShipmentStatus",
    "ShipsTo",
    "Shop",
    "ShopBookmark",
    "ShopClaim",
    "ShopPhoto",
    "ShopVisit",
    "User",
]
