"""Seller-hub and checkout mutations."""

from ariadne import MutationType
from graphql import GraphQLError

from ...core.errors import DomainError
from ...core.graphql import is_admin, require_shop_owner, require_user
from ...models import MAX_PHOTO_BYTES, MAX_PRODUCT_PHOTOS
from ...models.enums import Fulfillment, OrderStatus

mutation = MutationType()


def product_changes(input: dict) -> dict:
    """ProductInput keys -> products column values; only keys the client sent."""
    columns = {
        "name": "name",
        "variant": "variant",
        "price": "price",
        "stockQty": "stock_qty",
        "lowStockThreshold": "low_stock_threshold",
        "active": "active",
    }
    return {columns[key]: value for key, value in input.items() if key in columns}


def check_product_input(input: dict) -> None:
    if input.get("price") is not None and input["price"] < 0:
        raise GraphQLError("Price must not be negative.")
    if input.get("stockQty") is not None and input["stockQty"] < 0:
        raise GraphQLError("Stock must not be negative.")


@mutation.field("createProduct")
def resolve_create_product(_, info, shopId, input):
    require_shop_owner(info, shopId)
    if not input.get("name") or input.get("price") is None:
        raise GraphQLError("A new product needs a name and a price.")
    check_product_input(input)
    return info.context["repos"].products.create(shopId, product_changes(input))


@mutation.field("updateProduct")
def resolve_update_product(_, info, id, input):
    repos = info.context["repos"]
    product = repos.products.get(id)
    if not product:
        raise GraphQLError(f"Product {id} not found")
    require_shop_owner(info, str(product.shop_id))
    check_product_input(input)
    return repos.products.update(id, product_changes(input))


@mutation.field("deleteProduct")
def resolve_delete_product(_, info, id):
    repos = info.context["repos"]
    product = repos.products.get(id)
    if not product:
        raise GraphQLError(f"Product {id} not found")
    require_shop_owner(info, str(product.shop_id))
    return repos.products.delete(id)


@mutation.field("setProductPhotos")
def resolve_set_product_photos(_, info, productId, photos):
    repos = info.context["repos"]
    product = repos.products.get(productId)
    if not product:
        raise GraphQLError(f"Product {productId} not found")
    require_shop_owner(info, str(product.shop_id))
    if len(photos) > MAX_PRODUCT_PHOTOS:
        raise GraphQLError(f"A listing can have at most {MAX_PRODUCT_PHOTOS} photos.")
    for photo in photos:
        has_id, data = photo.get("id") is not None, photo.get("data")
        if has_id == bool(data):
            raise GraphQLError("Each photo needs either an id or a data URL, not both.")
        if data and not data.startswith("data:image/"):
            raise GraphQLError("Photos must be image data URLs.")
        # ~700KB data-URL cap keeps rows small; clients downscale before upload.
        if data and len(data) > MAX_PHOTO_BYTES:
            raise GraphQLError("A photo is too large. Please retry; it will be resized.")
    repos.product_photos.replace(productId, photos)
    return repos.products.get(productId)


@mutation.field("copyProducts")
def resolve_copy_products(_, info, fromShopId, toShopId, productIds=None):
    require_shop_owner(info, fromShopId)
    require_shop_owner(info, toShopId)
    if fromShopId == toShopId:
        raise GraphQLError("Pick a different shop to copy listings into.")
    repos = info.context["repos"]
    source = repos.products.list(fromShopId, include_inactive=True)
    if productIds is not None:
        wanted = {str(pid) for pid in productIds}
        source = [p for p in source if str(p.id) in wanted]
        if len(source) != len(wanted):
            raise GraphQLError("Some of those listings are not in the source shop.")
    copies = []
    for product in source:
        # Stock is physical per location, so copies start empty and hidden.
        copy = repos.products.create(
            toShopId,
            {
                "name": product.name,
                "variant": product.variant,
                "price": product.price,
                "low_stock_threshold": product.low_stock_threshold,
                "stock_qty": 0,
                "active": False,
            },
        )
        photos = repos.product_photos.list(str(product.id))
        if photos:
            repos.product_photos.replace(str(copy.id), [{"data": photo.data} for photo in photos])
        copies.append(copy)
    return copies


@mutation.field("updateDeliverySettings")
def resolve_update_delivery_settings(_, info, shopId, input):
    require_shop_owner(info, shopId)
    repos = info.context["repos"]
    shop = repos.shops.get(shopId)
    changes = {}
    if input.get("shipping") is not None:
        changes["offers_shipping"] = input["shipping"]
    if input.get("pickup") is not None:
        changes["offers_pickup"] = input["pickup"]
    if "pickupInstructions" in input:
        changes["pickup_instructions"] = (input["pickupInstructions"] or "").strip() or None
    shipping = changes.get("offers_shipping", shop.offers_shipping)
    pickup = changes.get("offers_pickup", shop.offers_pickup)
    if not (shipping or pickup):
        raise GraphQLError("Offer at least one of shipping or pickup.")
    return repos.shops.update_delivery_settings(shopId, changes)


@mutation.field("placeOrder")
def resolve_place_order(_, info, shopId, items, fulfillment=Fulfillment.SHIP):
    user = require_user(info)
    context = info.context
    shop = context["repos"].shops.get(shopId)
    if not shop:
        raise GraphQLError(f"Shop {shopId} not found")
    try:
        return context["services"].checkout.place_order(shop, user["id"], items, fulfillment)
    except DomainError as e:
        raise GraphQLError(str(e))


@mutation.field("cancelOrder")
def resolve_cancel_order(_, info, id):
    user = require_user(info)
    repos = info.context["repos"]
    order = repos.orders.get(id)
    if not order:
        raise GraphQLError(f"Order {id} not found")
    shop = repos.shops.get(str(order.shop_id))
    is_buyer = str(order.buyer_user_id or "") == user["id"]
    is_owner = bool(shop and str(shop.owner_user_id or "") == user["id"])
    if not (is_buyer or is_owner or is_admin(info, user)):
        raise GraphQLError("Only the buyer or the shop owner can cancel an order.")
    canceled = repos.orders.cancel(id)
    if not canceled:
        raise GraphQLError("Only orders that have not shipped or been picked up can be canceled.")
    return canceled


def advance_pickup(info, order_id, from_status, to_status):
    repos = info.context["repos"]
    order = repos.orders.get(order_id)
    if not order:
        raise GraphQLError(f"Order {order_id} not found")
    require_shop_owner(info, str(order.shop_id))
    if order.fulfillment is not Fulfillment.PICKUP:
        raise GraphQLError("This order ships; update its shipment instead.")
    updated = repos.orders.transition(order_id, from_status, to_status)
    if not updated:
        raise GraphQLError(f"Order #{order.number} is {order.status}, not {from_status}.")
    return updated


@mutation.field("markReadyForPickup")
def resolve_mark_ready_for_pickup(_, info, id):
    return advance_pickup(info, id, OrderStatus.PLACED, OrderStatus.READY_FOR_PICKUP)


@mutation.field("markPickedUp")
def resolve_mark_picked_up(_, info, id):
    return advance_pickup(info, id, OrderStatus.READY_FOR_PICKUP, OrderStatus.PICKED_UP)


@mutation.field("updateShipment")
def resolve_update_shipment(_, info, id, carrier=None, tracking=None, status=None):
    repos = info.context["repos"]
    shipment = repos.shipments.get(id)
    if not shipment:
        raise GraphQLError(f"Shipment {id} not found")
    order = repos.orders.get(str(shipment.order_id))
    require_shop_owner(info, str(order.shop_id))
    changes = {
        column: value
        for column, value in (("carrier", carrier), ("tracking", tracking), ("status", status))
        if value is not None
    }
    return repos.shipments.update(id, changes)
