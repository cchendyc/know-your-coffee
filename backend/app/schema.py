"""Executable schema: schema.graphql plus every domain's bindables.

Output fields without an explicit resolver fall back to the snake_case
model attribute; domains bind resolvers only for computed fields."""

from pathlib import Path

from ariadne import (
    EnumType,
    convert_camel_case_to_snake,
    load_schema_from_path,
    make_executable_schema,
)
from graphql import GraphQLInputObjectType, GraphQLSchema

from .accounts.graphql import bindables as accounts_bindables
from .claims.graphql import bindables as claims_bindables
from .commerce.graphql import bindables as commerce_bindables
from .models.enums import Fulfillment, ListingStatus, OrderStatus, ShipmentStatus
from .shops.graphql import bindables as shops_bindables


def snake_case_output_fields(name: str, schema: GraphQLSchema, path: tuple[str, ...]) -> str:
    """Convert output field names only. Resolver kwargs and input dict keys
    stay camelCase: inputs feed stored-jsonb documents that keep that shape."""
    is_argument = len(path) == 3
    if is_argument or isinstance(schema.type_map.get(path[0]), GraphQLInputObjectType):
        return name
    return convert_camel_case_to_snake(name)


def create_schema():
    type_defs = load_schema_from_path(Path(__file__).resolve().parents[1] / "schema.graphql")
    # Resolvers receive these arguments as enum members, not strings.
    enum_types = [
        EnumType("OrderStatus", OrderStatus),
        EnumType("Fulfillment", Fulfillment),
        EnumType("ShipmentStatus", ShipmentStatus),
        EnumType("ListingStatus", ListingStatus),
    ]
    return make_executable_schema(
        type_defs,
        *shops_bindables,
        *accounts_bindables,
        *claims_bindables,
        *commerce_bindables,
        *enum_types,
        convert_names_case=snake_case_output_fields,
    )
