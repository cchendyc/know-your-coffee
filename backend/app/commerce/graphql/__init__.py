from .mutations import mutation
from .queries import query
from .seller import seller
from .types import coffee_shop, order, order_item, product, shipment

bindables = [query, mutation, product, order, order_item, shipment, coffee_shop, seller]
