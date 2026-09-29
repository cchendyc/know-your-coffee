"""shops table. Per-user relationships live in bookmark.py and visit.py."""

from __future__ import annotations

from datetime import datetime
from typing import Any

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import ARRAY, ENUM, JSONB
from sqlalchemy.orm import Mapped, mapped_column

from .base import Base, IntId
from .enums import BEAN_SOURCES, MACHINE_BRANDS


machine_brand = ENUM(*MACHINE_BRANDS, name="machine_brand", create_type=False)
bean_source = ENUM(*BEAN_SOURCES, name="bean_source", create_type=False)


class Shop(Base):
    __tablename__ = "shops"

    id: Mapped[int] = mapped_column(IntId, sa.Identity(), primary_key=True)
    name: Mapped[str] = mapped_column()
    address: Mapped[str] = mapped_column()
    city: Mapped[str] = mapped_column()
    lat: Mapped[float] = mapped_column()
    lng: Mapped[float] = mapped_column()
    chain_id: Mapped[int | None] = mapped_column(IntId)
    # The scalar primary machine mirrors machines[0]; kept for cheap filters.
    machine: Mapped[str] = mapped_column(machine_brand, default="UNKNOWN", server_default=sa.text("'UNKNOWN'"))
    machine_model: Mapped[str | None] = mapped_column()
    machines: Mapped[list[Any]] = mapped_column(JSONB, default=list, server_default=sa.text("'[]'::jsonb"))
    bean_source: Mapped[str] = mapped_column(bean_source, default="UNKNOWN", server_default=sa.text("'UNKNOWN'"))
    roaster: Mapped[str | None] = mapped_column()
    bean_origins: Mapped[list[str]] = mapped_column(ARRAY(sa.Text), default=list, server_default=sa.text("'{}'::text[]"))
    coffees: Mapped[list[Any]] = mapped_column(JSONB, default=list, server_default=sa.text("'[]'::jsonb"))
    grinders: Mapped[list[str]] = mapped_column(ARRAY(sa.Text), default=list, server_default=sa.text("'{}'::text[]"))
    drinks: Mapped[list[Any]] = mapped_column(JSONB, default=list, server_default=sa.text("'[]'::jsonb"))
    milk_brands: Mapped[list[str]] = mapped_column(ARRAY(sa.Text), default=list, server_default=sa.text("'{}'::text[]"))
    vibe: Mapped[str | None] = mapped_column()
    dog_friendly: Mapped[bool | None] = mapped_column()
    wifi: Mapped[bool | None] = mapped_column()
    outdoor_seating: Mapped[bool | None] = mapped_column()
    photo_url: Mapped[str | None] = mapped_column()
    website: Mapped[str | None] = mapped_column()
    # Set once an ownership claim is approved; owner edits outrank reports.
    owner_user_id: Mapped[int | None] = mapped_column(IntId)
    # When the owner finished the seller walkthrough; null = hub shows it first.
    seller_onboarded_at: Mapped[datetime | None] = mapped_column(sa.DateTime(timezone=True))
    # CHECK shops_offers_fulfillment keeps at least one of these on.
    offers_shipping: Mapped[bool] = mapped_column(default=True, server_default=sa.text("true"))
    offers_pickup: Mapped[bool] = mapped_column(default=False, server_default=sa.text("false"))
    pickup_instructions: Mapped[str | None] = mapped_column()
    updated_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), server_default=sa.text("now()"))

    # Per-viewer flags from shop_bookmarks/shop_visits; plain attributes, not
    # columns. ShopRepository sets them on instances it returns.
    saved_by_me = False
    been_by_me = False
