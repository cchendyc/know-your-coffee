"""payment_methods, payments and payment_transactions tables.

No card data is stored: payment_methods keeps the gateway token plus what
the UI shows (brand, last4, expiry). Payment is the current state of one
order's charge; PaymentTransaction is the append-only record of each
gateway call, kept for disputes and reconciliation."""

from __future__ import annotations

from typing import Any

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from .base import Base, CreatedAtMixin, IntId, TimestampedMixin, pg_enum
from .enums import PaymentOperation, PaymentStatus


class PaymentMethod(Base, CreatedAtMixin):
    __tablename__ = "payment_methods"
    __table_args__ = (sa.UniqueConstraint("gateway", "gateway_method_id"),)

    id: Mapped[int] = mapped_column(IntId, sa.Identity(), primary_key=True)
    user_id: Mapped[int] = mapped_column(IntId)
    gateway: Mapped[str] = mapped_column(default="stripe", server_default=sa.text("'stripe'"))
    gateway_method_id: Mapped[str] = mapped_column()  # Stripe pm_...
    brand: Mapped[str] = mapped_column()  # visa, mastercard, ...
    last4: Mapped[str] = mapped_column()
    exp_month: Mapped[int] = mapped_column(sa.SmallInteger)
    exp_year: Mapped[int] = mapped_column(sa.SmallInteger)
    # Gateway card fingerprint; same card re-added dedupes on it.
    fingerprint: Mapped[str | None] = mapped_column()
    billing_address_id: Mapped[int | None] = mapped_column(IntId)
    is_default: Mapped[bool] = mapped_column(default=False, server_default=sa.text("false"))
    deleted: Mapped[bool] = mapped_column(default=False, server_default=sa.text("false"))


class Payment(Base, TimestampedMixin):
    __tablename__ = "payments"

    id: Mapped[int] = mapped_column(IntId, sa.Identity(), primary_key=True)
    order_id: Mapped[int] = mapped_column(IntId, unique=True)
    user_id: Mapped[int] = mapped_column(IntId)
    gateway: Mapped[str] = mapped_column(default="stripe", server_default=sa.text("'stripe'"))
    gateway_intent_id: Mapped[str | None] = mapped_column(unique=True)  # Stripe pi_...
    payment_method_id: Mapped[int | None] = mapped_column(IntId)
    amount_authorized_cents: Mapped[int] = mapped_column(default=0, server_default=sa.text("0"))
    amount_captured_cents: Mapped[int] = mapped_column(default=0, server_default=sa.text("0"))
    amount_refunded_cents: Mapped[int] = mapped_column(default=0, server_default=sa.text("0"))
    currency: Mapped[str] = mapped_column(default="USD", server_default=sa.text("'USD'"))
    # "Visa ·· 4242", frozen so receipts survive the method being deleted.
    method_display: Mapped[str | None] = mapped_column()
    status: Mapped[PaymentStatus] = mapped_column(pg_enum(PaymentStatus, "payment_status"))
    failure_reason: Mapped[str | None] = mapped_column()


class PaymentTransaction(Base, CreatedAtMixin):
    __tablename__ = "payment_transactions"

    id: Mapped[int] = mapped_column(IntId, sa.Identity(), primary_key=True)
    payment_id: Mapped[int] = mapped_column(IntId)
    operation: Mapped[PaymentOperation] = mapped_column(pg_enum(PaymentOperation, "payment_operation"))
    amount_cents: Mapped[int] = mapped_column()
    currency: Mapped[str] = mapped_column(default="USD", server_default=sa.text("'USD'"))
    gateway_entity_id: Mapped[str | None] = mapped_column()  # Stripe ch_/re_...
    gateway_status: Mapped[str | None] = mapped_column()
    request: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
    response: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
