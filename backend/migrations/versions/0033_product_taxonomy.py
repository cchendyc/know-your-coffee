"""product taxonomy: categories, attribute definitions, per-category mapping

Categories and their fields are rows, not tables, so a new category is an
insert. Values live on products.attributes (jsonb keyed by attribute key)
and are validated against category_attributes by ProductService.

products.category_id stays nullable until the API requires categoryId on
create; a follow-up migration flips it to NOT NULL. Existing rows are
backfilled to Beans, with "N oz whole bean|ground" variants parsed into
weight_g / form.

Revision ID: 0033
Revises: 0032
Create Date: 2026-09-29

"""
from alembic import op

revision = "0033"
down_revision = "0032"
branch_labels = None
depends_on = None

# (key, label, value_type, unit, help)
ATTRIBUTES = [
    ("weight_g", "Weight", "INT", "g", "Stored in grams; clients convert oz."),
    ("form", "Form", "ENUM", None, None),
    ("grind", "Grind", "ENUM", None, "Only when form is GROUND."),
    ("roast_level", "Roast level", "ENUM", None, None),
    ("process", "Process", "ENUM", None, None),
    ("origin_country", "Origin", "TEXT", None, None),
    ("origin_region", "Region", "TEXT", None, None),
    ("producer", "Producer / lot", "TEXT", None, None),
    ("variety", "Variety", "TEXT", None, None),
    ("tasting_notes", "Tasting notes", "TEXT_LIST", None, "Comma-separated; shown as chips."),
    ("roasted_to_order", "Roasted to order", "BOOL", None, "Shows the 48h badge."),
    ("volume_ml", "Volume", "INT", "ml", None),
    ("serve", "Served", "ENUM", None, None),
    ("caffeine", "Caffeine", "ENUM", None, None),
    ("brand", "Brand", "TEXT", None, None),
    ("model", "Model", "TEXT", None, None),
    ("condition", "Condition", "ENUM", None, None),
    ("size", "Size", "TEXT", None, None),
    ("color", "Color", "TEXT", None, None),
    ("material", "Material", "TEXT", None, None),
]

OPTIONS = {
    "form": ["WHOLE_BEAN", "GROUND"],
    "grind": ["ESPRESSO", "FILTER", "FRENCH_PRESS", "COLD_BREW"],
    "roast_level": ["LIGHT", "MEDIUM", "MEDIUM_DARK", "DARK"],
    "process": ["WASHED", "NATURAL", "HONEY", "ANAEROBIC", "OTHER"],
    "serve": ["HOT", "ICED", "BOTTLED"],
    "caffeine": ["REGULAR", "DECAF", "NONE"],
    "condition": ["NEW", "OPEN_BOX", "USED"],
}

# (slug, label, subtitle_template, [(attribute_key, required, in_subtitle)])
CATEGORIES = [
    (
        "beans",
        "Beans",
        "{weight_g} {form} · {roast_level}",
        [
            ("weight_g", True, True),
            ("form", True, True),
            ("grind", False, False),
            ("roast_level", False, True),
            ("process", False, False),
            ("origin_country", False, False),
            ("origin_region", False, False),
            ("producer", False, False),
            ("variety", False, False),
            ("tasting_notes", False, False),
            ("roasted_to_order", False, False),
        ],
    ),
    (
        "drink",
        "Drink",
        "{volume_ml} {serve}",
        [("volume_ml", True, True), ("serve", True, True), ("caffeine", False, False)],
    ),
    (
        "gear",
        "Gear",
        "{brand} {model} · {condition}",
        [("brand", False, True), ("model", False, True), ("condition", True, True)],
    ),
    (
        "merch",
        "Merch",
        "{color} · {size}",
        [("size", False, True), ("color", False, True), ("material", False, False)],
    ),
]


def _q(value: str | None) -> str:
    return "NULL" if value is None else "'" + value.replace("'", "''") + "'"


def upgrade() -> None:
    op.execute("CREATE TYPE attribute_value_type AS ENUM ('TEXT', 'INT', 'DECIMAL', 'BOOL', 'ENUM', 'ENUM_MULTI', 'TEXT_LIST')")
    op.execute(
        """
        CREATE TABLE categories (
            id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            parent_id bigint,
            slug text NOT NULL UNIQUE,
            label text NOT NULL,
            position int NOT NULL DEFAULT 0,
            is_visible boolean NOT NULL DEFAULT true,
            subtitle_template text,
            created_at timestamptz NOT NULL DEFAULT now()
        )
        """
    )
    op.execute(
        """
        CREATE TABLE product_attributes (
            id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            key text NOT NULL UNIQUE,
            label text NOT NULL,
            value_type attribute_value_type NOT NULL,
            unit text,
            validation jsonb NOT NULL DEFAULT '{}'::jsonb,
            help text,
            created_at timestamptz NOT NULL DEFAULT now()
        )
        """
    )
    op.execute(
        """
        CREATE TABLE product_attribute_options (
            id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            attribute_id bigint NOT NULL,
            value text NOT NULL,
            label text NOT NULL,
            position int NOT NULL DEFAULT 0,
            is_active boolean NOT NULL DEFAULT true,
            UNIQUE (attribute_id, value)
        )
        """
    )
    op.execute(
        """
        CREATE TABLE category_attributes (
            id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            category_id bigint NOT NULL,
            attribute_id bigint NOT NULL,
            position int NOT NULL DEFAULT 0,
            is_required boolean NOT NULL DEFAULT false,
            show_in_subtitle boolean NOT NULL DEFAULT false,
            UNIQUE (category_id, attribute_id)
        )
        """
    )

    op.execute("ALTER TABLE products ADD COLUMN category_id bigint")
    op.execute("ALTER TABLE products ADD COLUMN attributes jsonb NOT NULL DEFAULT '{}'::jsonb")
    op.execute("ALTER TABLE products ADD COLUMN description text")
    op.execute("ALTER TABLE products ADD COLUMN sold_count int NOT NULL DEFAULT 0")
    op.execute("CREATE INDEX products_category_idx ON products (category_id)")
    op.execute("CREATE INDEX products_attributes_idx ON products USING gin (attributes)")

    for key, label, value_type, unit, help_text in ATTRIBUTES:
        op.execute(
            f"INSERT INTO product_attributes (key, label, value_type, unit, help) "
            f"VALUES ({_q(key)}, {_q(label)}, '{value_type}', {_q(unit)}, {_q(help_text)})"
        )
    for key, values in OPTIONS.items():
        for position, value in enumerate(values):
            label = value.replace("_", " ").capitalize()
            op.execute(
                "INSERT INTO product_attribute_options (attribute_id, value, label, position) "
                f"SELECT id, {_q(value)}, {_q(label)}, {position} FROM product_attributes WHERE key = {_q(key)}"
            )
    for position, (slug, label, template, fields) in enumerate(CATEGORIES):
        op.execute(
            f"INSERT INTO categories (slug, label, position, subtitle_template) "
            f"VALUES ({_q(slug)}, {_q(label)}, {position}, {_q(template)})"
        )
        for field_position, (key, required, in_subtitle) in enumerate(fields):
            op.execute(
                "INSERT INTO category_attributes (category_id, attribute_id, position, is_required, show_in_subtitle) "
                f"SELECT c.id, a.id, {field_position}, {str(required).lower()}, {str(in_subtitle).lower()} "
                f"FROM categories c, product_attributes a WHERE c.slug = {_q(slug)} AND a.key = {_q(key)}"
            )

    # Backfill: every existing listing is a bag of beans. Variants shaped like
    # "12 oz whole bean" or "250 g ground" become weight_g / form; anything
    # else keeps its variant text until the seller edits the listing.
    op.execute("UPDATE products SET category_id = (SELECT id FROM categories WHERE slug = 'beans')")
    op.execute(
        r"""
        UPDATE products SET attributes = attributes
            || CASE
                 WHEN variant ~* '(\d+(\.\d+)?)\s*oz' THEN jsonb_build_object(
                    'weight_g', round((substring(variant from '(?i)(\d+(?:\.\d+)?)\s*oz'))::numeric * 28.3495))
                 WHEN variant ~* '(\d+)\s*g\b' THEN jsonb_build_object(
                    'weight_g', (substring(variant from '(?i)(\d+)\s*g\b'))::int)
                 ELSE '{}'::jsonb
               END
            || CASE
                 WHEN variant ~* 'whole' THEN '{"form": "WHOLE_BEAN"}'::jsonb
                 WHEN variant ~* 'ground' THEN '{"form": "GROUND"}'::jsonb
                 ELSE '{}'::jsonb
               END
        WHERE variant IS NOT NULL
        """
    )


def downgrade() -> None:
    op.execute("DROP INDEX products_attributes_idx")
    op.execute("DROP INDEX products_category_idx")
    op.execute("ALTER TABLE products DROP COLUMN sold_count, DROP COLUMN description, DROP COLUMN attributes, DROP COLUMN category_id")
    op.execute("DROP TABLE category_attributes")
    op.execute("DROP TABLE product_attribute_options")
    op.execute("DROP TABLE product_attributes")
    op.execute("DROP TABLE categories")
    op.execute("DROP TYPE attribute_value_type")
