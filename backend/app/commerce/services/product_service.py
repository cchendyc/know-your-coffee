"""Listings: category field validation and the buyer-facing subtitle."""

import re
from decimal import Decimal, InvalidOperation
from typing import Any

from ... import models as m
from ...core.errors import InvalidListingError
from ...models.enums import AttributeValueType

TOKEN = re.compile(r"\{(\w+)\}")
SEGMENT_SEPARATOR = " · "


class ProductService:
    def __init__(self, categories):
        self._categories = categories

    def clean_attributes(self, category_id: str, attributes: dict[str, Any]) -> dict[str, Any]:
        """Coerce values to their field's type and drop blanks. Unknown keys,
        bad enum values, and missing required fields are rejected."""
        category = self._categories.get(category_id)
        if not category or not category.is_visible:
            raise InvalidListingError("Pick a category for this listing.")
        fields = {f.key: f for f in self._categories.fields(category_id)}
        unknown = set(attributes) - set(fields)
        if unknown:
            raise InvalidListingError(f"{category.label} listings have no field {sorted(unknown)[0]}.")
        cleaned = {}
        for key, field in fields.items():
            value = clean_value(field, attributes.get(key))
            if value is None:
                if field.required:
                    raise InvalidListingError(f"{field.label} is required for {category.label.lower()} listings.")
                continue
            cleaned[key] = value
        return cleaned

    def subtitle(self, product: m.Product) -> str | None:
        """Fill the category's template from the listing's attributes.
        Segments (split on " · ") whose every token is empty are dropped."""
        category = self._categories.get(str(product.category_id))
        if not category or not category.subtitle_template:
            return None
        fields = {f.key: f for f in self._categories.fields(str(product.category_id))}
        segments = []
        for segment in category.subtitle_template.split(SEGMENT_SEPARATOR):
            filled = [display_value(fields[key], product.attributes.get(key)) for key in TOKEN.findall(segment) if key in fields]
            if not any(filled):
                continue
            text = TOKEN.sub(lambda match: display_value(fields[match.group(1)], product.attributes.get(match.group(1))), segment)
            segments.append(" ".join(text.split()))
        return SEGMENT_SEPARATOR.join(segments) or None


def clean_value(field: m.CategoryField, value: Any) -> Any:
    if value is None or value == "" or value == []:
        return None
    kind = field.value_type
    try:
        if kind is AttributeValueType.TEXT:
            return str(value).strip() or None
        if kind is AttributeValueType.INT:
            number = int(value)
            check_range(field, number)
            return number
        if kind is AttributeValueType.DECIMAL:
            number = float(Decimal(str(value)))
            check_range(field, number)
            return number
        if kind is AttributeValueType.BOOL:
            if not isinstance(value, bool):
                raise ValueError
            return value
        if kind is AttributeValueType.ENUM:
            return check_option(field, str(value))
        if kind is AttributeValueType.ENUM_MULTI:
            return [check_option(field, str(v)) for v in as_list(value)] or None
        if kind is AttributeValueType.TEXT_LIST:
            return [str(v).strip() for v in as_list(value) if str(v).strip()] or None
    except (TypeError, ValueError, InvalidOperation):
        raise InvalidListingError(f"{field.label} is not a valid {kind.value.lower().replace('_', ' ')}.")
    raise InvalidListingError(f"{field.label} has an unsupported type.")


def as_list(value: Any) -> list:
    if isinstance(value, str):
        return [part for part in value.split(",")]
    if not isinstance(value, list):
        raise ValueError
    return value


def check_option(field: m.CategoryField, value: str) -> str:
    if value not in {o.value for o in field.options}:
        raise InvalidListingError(f"{value} is not a {field.label.lower()} option.")
    return value


def check_range(field: m.CategoryField, number: float) -> None:
    # No min/max in ProductAttribute.validation yet; negatives are never a size.
    if number < 0:
        raise InvalidListingError(f"{field.label} must not be negative.")


def display_value(field: m.CategoryField, value: Any) -> str:
    if value is None or value == "" or value == []:
        return ""
    kind = field.value_type
    if kind is AttributeValueType.ENUM:
        return field.option_label(str(value))
    if kind is AttributeValueType.ENUM_MULTI:
        return ", ".join(field.option_label(str(v)) for v in value)
    if kind is AttributeValueType.TEXT_LIST:
        return ", ".join(str(v) for v in value)
    if kind is AttributeValueType.BOOL:
        return field.label if value else ""
    if kind in (AttributeValueType.INT, AttributeValueType.DECIMAL) and field.unit:
        return f"{value:g} {field.unit}" if isinstance(value, float) else f"{value} {field.unit}"
    return str(value)
