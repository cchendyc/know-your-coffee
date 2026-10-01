"""Read-only taxonomy: categories and the fields each one renders."""

import sqlalchemy as sa
from sqlalchemy.orm import sessionmaker

from ... import models as m


class CategoryRepository:
    def __init__(self, session: sessionmaker):
        self._session = session

    def list(self) -> list[m.Category]:
        stmt = sa.select(m.Category).where(m.Category.is_visible.is_(True)).order_by(m.Category.position, m.Category.id)
        with self._session() as s:
            return list(s.scalars(stmt))

    def get(self, category_id: str) -> m.Category | None:
        with self._session() as s:
            return s.get(m.Category, category_id)

    def fields(self, category_id: str) -> list[m.CategoryField]:
        """CategoryAttribute joined to ProductAttribute, with active options, in display order."""
        stmt = (
            sa.select(m.CategoryAttribute, m.ProductAttribute)
            .join(m.ProductAttribute, m.ProductAttribute.id == m.CategoryAttribute.attribute_id)
            .where(m.CategoryAttribute.category_id == category_id)
            .order_by(m.CategoryAttribute.position, m.CategoryAttribute.id)
        )
        with self._session() as s:
            rows = s.execute(stmt).all()
            attribute_ids = [attribute.id for _, attribute in rows]
            options = s.scalars(
                sa.select(m.ProductAttributeOption)
                .where(m.ProductAttributeOption.attribute_id.in_(attribute_ids), m.ProductAttributeOption.is_active.is_(True))
                .order_by(m.ProductAttributeOption.position, m.ProductAttributeOption.id)
            ).all() if attribute_ids else []
        options_by_attribute: dict[int, list[m.ProductAttributeOption]] = {}
        for option in options:
            options_by_attribute.setdefault(option.attribute_id, []).append(option)
        return [
            m.CategoryField(
                key=attribute.key,
                label=attribute.label,
                value_type=attribute.value_type,
                unit=attribute.unit,
                help=attribute.help,
                required=mapping.is_required,
                show_in_subtitle=mapping.show_in_subtitle,
                section=mapping.section,
                options=options_by_attribute.get(attribute.id, []),
            )
            for mapping, attribute in rows
        ]
