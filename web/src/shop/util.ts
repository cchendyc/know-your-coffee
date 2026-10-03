export type Section = 'about' | 'shop' | 'reviews' | 'photos'

export const SECTION_LABELS: Record<Section, string> = {
  about: 'About',
  shop: 'Shop',
  reviews: 'Reviews',
  photos: 'Photos',
}

export const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? '' : 's'}`

export const initials = (name: string) =>
  name
    .split(/\s+/)
    .slice(0, 2)
    .map((w) => w[0]?.toUpperCase() ?? '')
    .join('')
