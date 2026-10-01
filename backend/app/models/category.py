"""Product taxonomy: categories, attribute definitions, and which attributes
each category uses. Values are stored on products.attributes (jsonb keyed by
ProductAttribute.key); adding a category or field is a row insert."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from .base import Base, CreatedAtMixin, IntId, pg_enum
from .enums import AttributeSection, AttributeValueType


class Category(Base, CreatedAtMixin):
    __tablename__ = "categories"

    id: Mapped[int] = mapped_column(IntId, sa.Identity(), primary_key=True)
    parent_id: Mapped[int | None] = mapped_column(IntId)
    slug: Mapped[str] = mapped_column(unique=True)
    label: Mapped[str] = mapped_column()
    position: Mapped[int] = mapped_column(default=0, server_default=sa.text("0"))
    is_visible: Mapped[bool] = mapped_column(default=True, server_default=sa.text("true"))
    # "{weight_g} {form} · {roast_level}"; keys resolve against products.attributes.
    subtitle_template: Mapped[str | None] = mapped_column()


class ProductAttribute(Base, CreatedAtMixin):
    __tablename__ = "product_attributes"

    id: Mapped[int] = mapped_column(IntId, sa.Identity(), primary_key=True)
    key: Mapped[str] = mapped_column(unique=True)
    label: Mapped[str] = mapped_column()
    value_type: Mapped[AttributeValueType] = mapped_column(pg_enum(AttributeValueType, "attribute_value_type"))
    unit: Mapped[str | None] = mapped_column()
    # e.g. {"min": 1, "max": 5000}; interpreted per value_type by the service.
    validation: Mapped[dict[str, Any]] = mapped_column(JSONB, default=dict, server_default=sa.text("'{}'::jsonb"))
    help: Mapped[str | None] = mapped_column()


class ProductAttributeOption(Base):
    __tablename__ = "product_attribute_options"
    __table_args__ = (sa.UniqueConstraint("attribute_id", "value"),)

    id: Mapped[int] = mapped_column(IntId, sa.Identity(), primary_key=True)
    attribute_id: Mapped[int] = mapped_column(IntId)
    value: Mapped[str] = mapped_column()
    label: Mapped[str] = mapped_column()
    position: Mapped[int] = mapped_column(default=0, server_default=sa.text("0"))
    is_active: Mapped[bool] = mapped_column(default=True, server_default=sa.text("true"))


class CategoryAttribute(Base):
    __tablename__ = "category_attributes"
    __table_args__ = (sa.UniqueConstraint("category_id", "attribute_id"),)

    id: Mapped[int] = mapped_column(IntId, sa.Identity(), primary_key=True)
    category_id: Mapped[int] = mapped_column(IntId)
    attribute_id: Mapped[int] = mapped_column(IntId)
    position: Mapped[int] = mapped_column(default=0, server_default=sa.text("0"))
    is_required: Mapped[bool] = mapped_column(default=False, server_default=sa.text("false"))
    show_in_subtitle: Mapped[bool] = mapped_column(default=False, server_default=sa.text("false"))
    section: Mapped[AttributeSection] = mapped_column(
        pg_enum(AttributeSection, "attribute_section"),
        default=AttributeSection.DETAILS,
        server_default=sa.text("'DETAILS'"),
    )


@dataclass(frozen=True)
class CategoryField:
    """Read model, not a table: one attribute as one category uses it
    (CategoryAttribute + ProductAttribute + active options). What the
    listing form renders and what ProductService validates against."""

    key: str
    label: str
    value_type: AttributeValueType
    unit: str | None
    help: str | None
    required: bool
    show_in_subtitle: bool
    section: AttributeSection
    options: list[ProductAttributeOption] = field(default_factory=list)

    def option_label(self, value: str) -> str:
        return next((o.label for o in self.options if o.value == value), value)
