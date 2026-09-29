"""Search, ranking, and import-dedup clauses over the shops table, composed
from SQLAlchemy expressions so list_shops and find_matching_shop can stack
them with plain filters."""

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB

from .. import models as m

_EMPTY_JSONB = sa.cast(sa.literal("[]"), JSONB)


def _any_item(col, pred):
    """EXISTS over a jsonb array of objects; pred receives one jsonb item."""
    # render_derived emits AS anon(item); without it Postgres keeps the
    # function's own output column name (value) and anon.item does not exist.
    items = sa.func.jsonb_array_elements(sa.func.coalesce(col, _EMPTY_JSONB)).table_valued(
        sa.column("item", JSONB)
    ).render_derived()
    return sa.exists(sa.select(sa.literal(1)).select_from(items).where(pred(items.c.item)))


def _any_text(expr, like: str):
    """EXISTS over a jsonb array of strings matching an ILIKE pattern."""
    items = sa.func.jsonb_array_elements_text(sa.func.coalesce(expr, _EMPTY_JSONB)).table_valued(
        "item"
    ).render_derived()
    return sa.exists(sa.select(sa.literal(1)).select_from(items).where(items.c.item.ilike(like)))


def _coffee_matches(coffee, like: str):
    return sa.or_(
        coffee["name"].astext.ilike(like),
        coffee["roaster"].astext.ilike(like),
        coffee["fermentation"].astext.ilike(like),
        _any_text(coffee["origins"], like),
        _any_text(coffee["varieties"], like),
        _any_text(coffee["tastingNotes"], like),
    )


def matches_token(token: str):
    """One search token. list_shops ANDs one clause per token so a free-form
    query like "gesha in oakland" must match across fields."""
    like = f"%{token}%"
    return sa.or_(
        m.Shop.name.ilike(like),
        m.Shop.city.ilike(like),
        m.Shop.address.ilike(like),
        m.Shop.roaster.ilike(like),
        m.Shop.machine.cast(sa.Text).ilike(like),
        m.Shop.machine_model.ilike(like),
        sa.func.array_to_string(m.Shop.bean_origins, " ").ilike(like),
        sa.func.array_to_string(m.Shop.grinders, " ").ilike(like),
        sa.func.array_to_string(m.Shop.milk_brands, " ").ilike(like),
        m.Shop.vibe.ilike(like),
        _any_item(m.Shop.drinks, lambda d: d["name"].astext.ilike(like)),
        _any_item(
            m.Shop.machines,
            lambda mc: sa.or_(mc["brand"].astext.ilike(like), mc["model"].astext.ilike(like)),
        ),
        _any_item(m.Shop.coffees, lambda c: _coffee_matches(c, like)),
    )


def _known(cond) -> sa.ColumnElement[int]:
    return sa.cast(cond, sa.Integer)


# Completeness-weighted rank: known machine dominates (it is the app's core
# data point), then other filled fields. Amenities count when known either way.
_COMPLETENESS = (
    _known(m.Shop.machine != "UNKNOWN") * 8
    + _known(m.Shop.machine_model.is_not(None)) * 2
    + _known(m.Shop.bean_source != "UNKNOWN") * 2
    + _known(m.Shop.roaster.is_not(None)) * 2
    + _known(sa.func.cardinality(m.Shop.grinders) > 0)
    + _known(sa.func.jsonb_array_length(m.Shop.coffees) > 0)
    + _known(sa.func.jsonb_array_length(sa.func.coalesce(m.Shop.drinks, _EMPTY_JSONB)) > 0)
    + _known(sa.func.cardinality(m.Shop.milk_brands) > 0)
    + _known(m.Shop.vibe.is_not(None))
    + _known(m.Shop.dog_friendly.is_not(None))
    + _known(m.Shop.wifi.is_not(None))
    + _known(m.Shop.outdoor_seating.is_not(None))
)


def completeness_order():
    """Rank desc, then recency. Name last keeps offset pagination stable
    within equal ranks."""
    return (_COMPLETENESS.desc(), m.Shop.updated_at.desc(), m.Shop.name.asc())


def _normalized(expr):
    return sa.func.regexp_replace(sa.func.lower(sa.func.unaccent(expr)), "[^a-z0-9]", "", "g")


def same_shop_clause(name: str, lat: float, lng: float):
    """Sources format addresses differently ("7th St" vs "Seventh Street"), so
    imports dedup by normalized name within ~300m. Prefix match catches suffix
    variants like "Crema Coffee Roasting Company"."""
    target = _normalized(sa.literal(name))
    ours = _normalized(m.Shop.name)
    return sa.and_(
        sa.or_(ours.like(target.concat("%")), target.like(ours.concat("%"))),
        sa.func.least(sa.func.length(ours), sa.func.length(target)) >= 6,
        sa.func.abs(m.Shop.lat - lat) < 0.003,
        sa.func.abs(m.Shop.lng - lng) < 0.004,
    )
