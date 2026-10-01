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
    PACKED = "PACKED"
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


class AttributeValueType(StrEnum):
    TEXT = "TEXT"
    INT = "INT"
    DECIMAL = "DECIMAL"
    BOOL = "BOOL"
    ENUM = "ENUM"
    ENUM_MULTI = "ENUM_MULTI"
    TEXT_LIST = "TEXT_LIST"


class PaymentStatus(StrEnum):
    REQUIRES_ACTION = "REQUIRES_ACTION"
    AUTHORIZED = "AUTHORIZED"
    CAPTURED = "CAPTURED"
    PARTIALLY_REFUNDED = "PARTIALLY_REFUNDED"
    REFUNDED = "REFUNDED"
    FAILED = "FAILED"
    CANCELED = "CANCELED"


class PaymentOperation(StrEnum):
    AUTHORIZE = "AUTHORIZE"
    CAPTURE = "CAPTURE"
    REFUND = "REFUND"
    VOID = "VOID"


class ShipsTo(StrEnum):
    CA = "CA"
    US = "US"


# Which card of the listing editor shows a category attribute.
class AttributeSection(StrEnum):
    DETAILS = "DETAILS"
    FORMAT = "FORMAT"


class Carrier(StrEnum):
    USPS = "USPS"
    UPS = "UPS"
    FEDEX = "FEDEX"
    OTHER = "OTHER"


# What a seller can do to an order next; the server lists them per order so
# clients never derive buttons from status themselves.
class OrderAction(StrEnum):
    MARK_PACKED = "MARK_PACKED"
    MARK_SHIPPED = "MARK_SHIPPED"
    MARK_DELIVERED = "MARK_DELIVERED"
    MARK_READY_FOR_PICKUP = "MARK_READY_FOR_PICKUP"
    MARK_PICKED_UP = "MARK_PICKED_UP"
    CANCEL = "CANCEL"


# Derived from products.active and quantity vs low_stock_threshold; not stored.
class ListingStatus(StrEnum):
    IN_STOCK = "IN_STOCK"
    LOW_STOCK = "LOW_STOCK"
    HIDDEN = "HIDDEN"


ORDER_STATUSES = list(OrderStatus)
FULFILLMENTS = list(Fulfillment)
SHIPMENT_STATUSES = list(ShipmentStatus)
# Anything not yet handed to the buyer or a carrier can still be canceled.
CANCELABLE_STATUSES = (OrderStatus.PLACED, OrderStatus.PACKED, OrderStatus.READY_FOR_PICKUP)
# Orders that still need the seller: the hub's "to fulfill" count.
OPEN_STATUSES = CANCELABLE_STATUSES
# The status track shown on the order page, per fulfillment.
ORDER_TRACK = {
    Fulfillment.SHIP: (OrderStatus.PLACED, OrderStatus.PACKED, OrderStatus.SHIPPED, OrderStatus.DELIVERED),
    Fulfillment.PICKUP: (OrderStatus.PLACED, OrderStatus.READY_FOR_PICKUP, OrderStatus.PICKED_UP),
}
# Carrier scans on a shipment move its order forward.
SHIPMENT_TO_ORDER_STATUS = {
    ShipmentStatus.IN_TRANSIT: OrderStatus.SHIPPED,
    ShipmentStatus.DELIVERED: OrderStatus.DELIVERED,
}
# The forward step each action takes; CANCEL is handled separately.
ACTION_TRANSITIONS = {
    OrderAction.MARK_PACKED: (Fulfillment.SHIP, OrderStatus.PLACED, OrderStatus.PACKED),
    OrderAction.MARK_SHIPPED: (Fulfillment.SHIP, OrderStatus.PACKED, OrderStatus.SHIPPED),
    OrderAction.MARK_DELIVERED: (Fulfillment.SHIP, OrderStatus.SHIPPED, OrderStatus.DELIVERED),
    OrderAction.MARK_READY_FOR_PICKUP: (Fulfillment.PICKUP, OrderStatus.PLACED, OrderStatus.READY_FOR_PICKUP),
    OrderAction.MARK_PICKED_UP: (Fulfillment.PICKUP, OrderStatus.READY_FOR_PICKUP, OrderStatus.PICKED_UP),
}
# Order status changes that also move the shipment.
ORDER_TO_SHIPMENT_STATUS = {
    OrderStatus.PACKED: ShipmentStatus.READY_FOR_DROPOFF,
    OrderStatus.SHIPPED: ShipmentStatus.IN_TRANSIT,
    OrderStatus.DELIVERED: ShipmentStatus.DELIVERED,
}
