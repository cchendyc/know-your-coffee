import type { ShopPageData } from '../api'
import { Chip, InfoCard, Row } from './bits'

export function MenuSection({ shop }: { shop: ShopPageData }) {
  return (
    <InfoCard eyebrow="Menu">
      <div className="grid md:grid-cols-2 md:gap-x-8">
        {shop.drinks.map((d) => (
          <Row key={d.name} label={d.name}>
            {d.price != null && <Chip>${d.price.toFixed(2)}</Chip>}
          </Row>
        ))}
      </div>
    </InfoCard>
  )
}
