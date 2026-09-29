"""Field resolvers for commerce GraphQL types, plus the marketplace fields
commerce contributes to CoffeeShop."""

from ariadne import ObjectType

from ...core.graphql import is_admin
from .seller import workload

product = ObjectType("Product")
order = ObjectType("Order")
order_item = ObjectType("OrderItem")
shipment = ObjectType("Shipment")
coffee_shop = ObjectType("CoffeeShop")


@product.field("lowStock")
def resolve_low_stock(product_row, _info):
    return product_row.stock_qty <= product_row.low_stock_threshold


@product.field("photos")
def resolve_product_photos(product_row, info):
    return info.context["repos"].product_photos.list(str(product_row.id))


@product.field("coverPhoto")
def resolve_product_cover_photo(product_row, info):
    return info.context["repos"].product_photos.cover(str(product_row.id))


@product.field("createdAt")
def resolve_product_created_at(product_row, _info):
    return product_row.created_at.isoformat()


@product.field("updatedAt")
def resolve_product_updated_at(product_row, _info):
    return product_row.updated_at.isoformat()


@order.field("shop")
def resolve_order_shop(order_row, info):
    user = info.context["user"]
    return info.context["repos"].shops.get(str(order_row.shop_id), user["id"] if user else None)


@order.field("buyer")
def resolve_buyer(order_row, _info):
    return order_row.buyer


@order.field("shipment")
def resolve_order_shipment(order_row, info):
    return info.context["repos"].shipments.for_order(str(order_row.id))


@order.field("createdAt")
def resolve_order_created_at(order_row, _info):
    return order_row.created_at.isoformat()


# Order items are stored jsonb snapshots with camelCase keys.
@order_item.field("productId")
def resolve_product_id(item, _info):
    return item["productId"]


@order_item.field("unitPrice")
def resolve_unit_price(item, _info):
    return item["unitPrice"]


@shipment.field("order")
def resolve_shipment_order(shipment_row, info):
    return info.context["repos"].orders.get(str(shipment_row.order_id))


@shipment.field("shipBy")
def resolve_ship_by(shipment_row, _info):
    return shipment_row.ship_by.isoformat() if shipment_row.ship_by else None


@shipment.field("createdAt")
def resolve_shipment_created_at(shipment_row, _info):
    return shipment_row.created_at.isoformat()


@shipment.field("updatedAt")
def resolve_shipment_updated_at(shipment_row, _info):
    return shipment_row.updated_at.isoformat()


@coffee_shop.field("products")
def resolve_shop_products(shop, info):
    # Buyer-facing storefront: active products only.
    return info.context["repos"].products.list(str(shop.id))


@coffee_shop.field("deliverySettings")
def resolve_delivery_settings(shop, _info):
    return {
        "shipping": shop.offers_shipping,
        "pickup": shop.offers_pickup,
        "pickup_instructions": shop.pickup_instructions,
    }


@coffee_shop.field("workload")
def resolve_shop_workload(shop, info):
    # Seller-only counts; buyers browsing the shop get null, not an error.
    user = info.context["user"]
    if not user or (str(shop.owner_user_id or "") != user["id"] and not is_admin(info, user)):
        return None
    return workload(info.context["repos"], [str(shop.id)])
