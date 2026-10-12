"""Field resolvers for commerce GraphQL types, plus the marketplace fields
commerce contributes to CoffeeShop.

Lookups that fan out per list item (a shop's products, a product's cover,
an order's shop) go through info.context["loaders"]; single-row fields
run in a worker thread."""

import asyncio

from ariadne import ObjectType

from starlette.concurrency import run_in_threadpool

from ...core.graphql import is_admin, threaded

category = ObjectType("Category")
product = ObjectType("Product")
order = ObjectType("Order")
order_item = ObjectType("OrderItem")
shipment = ObjectType("Shipment")
coffee_shop = ObjectType("CoffeeShop")


@category.field("fields")
def resolve_category_fields(category_row, info):
    return info.context["loaders"].category_fields.load(str(category_row.id))


@product.field("category")
def resolve_product_category(product_row, info):
    return info.context["loaders"].category.load(str(product_row.category_id))


@product.field("subtitle")
async def resolve_product_subtitle(product_row, info):
    # The feed asks for this on every product; the category and its fields
    # come from loaders so a page costs two catalog queries, not 3 per product.
    loaders = info.context["loaders"]
    category_id = str(product_row.category_id)
    category, fields = await asyncio.gather(loaders.category.load(category_id), loaders.category_fields.load(category_id))
    return info.context["services"].products.render_subtitle(product_row, category, fields)


@product.field("lowStock")
def resolve_low_stock(product_row, _info):
    return product_row.quantity <= product_row.low_stock_threshold


@product.field("photos")
@threaded
def resolve_product_photos(product_row, info):
    return info.context["repos"].product_photos.list(str(product_row.id))


@product.field("coverPhoto")
def resolve_product_cover_photo(product_row, info):
    return info.context["loaders"].product_cover.load(str(product_row.id))


@product.field("createdAt")
def resolve_product_created_at(product_row, _info):
    return product_row.created_at.isoformat()


@product.field("updatedAt")
def resolve_product_updated_at(product_row, _info):
    return product_row.updated_at.isoformat()


@order.field("shop")
def resolve_order_shop(order_row, info):
    return info.context["loaders"].shop.load(str(order_row.shop_id))


@order.field("buyer")
def resolve_buyer(order_row, _info):
    return order_row.buyer


@order.field("shipment")
def resolve_order_shipment(order_row, info):
    return info.context["loaders"].order_shipment.load(str(order_row.id))


@order.field("createdAt")
def resolve_order_created_at(order_row, _info):
    return order_row.created_at.isoformat()


@order_item.field("qty")
def resolve_item_qty(item, _info):
    return item.quantity


@order_item.field("unitPrice")
def resolve_unit_price(item, _info):
    return item.unit_price_cents / 100


@shipment.field("order")
def resolve_shipment_order(shipment_row, info):
    return info.context["loaders"].order.load(str(shipment_row.order_id))


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
    # Buyer-facing storefront: active products only. Batched because the
    # feed and map ask for it on every shop in the page.
    return info.context["loaders"].shop_products.load(str(shop.id))


@coffee_shop.field("deliverySettings")
def resolve_delivery_settings(shop, _info):
    return {
        "shipping": shop.offers_shipping,
        "pickup": shop.offers_pickup,
        "pickup_instructions": shop.pickup_instructions,
    }


@coffee_shop.field("workload")
async def resolve_shop_workload(shop, info):
    # Seller-only counts; buyers browsing the shop get null, not an error.
    # Batched: mySeller asks for this on every owned shop.
    user = info.context["user"]
    if not user:
        return None
    if str(shop.owner_user_id or "") != user["id"] and not await run_in_threadpool(is_admin, info, user):
        return None
    return await info.context["loaders"].shop_workload.load(str(shop.id))
