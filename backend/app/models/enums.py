from enum import StrEnum

MACHINE_BRANDS = [
    "LA_MARZOCCO",
    "SLAYER",
    "SYNESSO",
    "KEES_VAN_DER_WESTEN",
    "VICTORIA_ARDUINO",
    "NUOVA_SIMONELLI",
    "MODBAR",
    "ROCKET",
    "RANCILIO",
    "BREVILLE",
    "DECENT",
    "FAEMA",
    "OTHER",
    "UNKNOWN",
]

BEAN_SOURCES = [
    "IN_HOUSE_ROAST",
    "LOCAL_ROASTER",
    "NATIONAL_ROASTER",
    "MULTI_ROASTER",
    "PRIVATE_LABEL",
    "DISTRIBUTOR",
    "UNKNOWN",
]

REPORT_SOURCES = ["TEXT", "PHOTO"]

COFFEE_TYPES = ["SINGLE_ORIGIN", "BLEND"]

# Primary post-harvest route. Fermentation styles (anaerobic etc.) layer on
# top of one of these; fermentation is free text since techniques outpace
# any fixed list.
COFFEE_PROCESSES = ["WASHED", "NATURAL", "HONEY", "WET_HULLED", "OTHER"]

ROAST_LEVELS = ["LIGHT", "MEDIUM", "DARK"]

PHOTO_KINDS = ["MACHINE", "BEANS", "DRINKS", "MENU", "VIBE", "OTHER"]

USER_ROLES = ["USER", "ADMIN"]

CLAIM_STATUSES = ["PENDING", "APPROVED", "REJECTED"]

# Orders are auto-accepted at checkout; sellers never accept or decline.
# SHIP orders go PLACED > SHIPPED > DELIVERED via their shipment.
# PICKUP orders go PLACED > READY_FOR_PICKUP > PICKED_UP and have no shipment.
class OrderStatus(StrEnum):
    PLACED = "PLACED"
    SHIPPED = "SHIPPED"
    DELIVERED = "DELIVERED"
    READY_FOR_PICKUP = "READY_FOR_PICKUP"
    PICKED_UP = "PICKED_UP"
    CANCELED = "CANCELED"


class Fulfillment(StrEnum):
    SHIP = "SHIP"
    PICKUP = "PICKUP"


class ShipmentStatus(StrEnum):
    LABEL_READY = "LABEL_READY"
    READY_FOR_DROPOFF = "READY_FOR_DROPOFF"
    IN_TRANSIT = "IN_TRANSIT"
    DELIVERED = "DELIVERED"


# Derived from products.active and stock_qty vs low_stock_threshold; not stored.
class ListingStatus(StrEnum):
    IN_STOCK = "IN_STOCK"
    LOW_STOCK = "LOW_STOCK"
    HIDDEN = "HIDDEN"


ORDER_STATUSES = list(OrderStatus)
FULFILLMENTS = list(Fulfillment)
SHIPMENT_STATUSES = list(ShipmentStatus)
# A no-show pickup can still be canceled after it is packed.
CANCELABLE_STATUSES = (OrderStatus.PLACED, OrderStatus.READY_FOR_PICKUP)
# Carrier scans on a shipment move its order forward.
SHIPMENT_TO_ORDER_STATUS = {
    ShipmentStatus.IN_TRANSIT: OrderStatus.SHIPPED,
    ShipmentStatus.DELIVERED: OrderStatus.DELIVERED,
}
