import type { BeanSource, MachineBrand, PhotoKind } from './api'

export const PHOTO_KIND_LABELS: Record<PhotoKind, string> = {
  MACHINE: 'Machine',
  BEANS: 'Beans',
  DRINKS: 'Drinks',
  MENU: 'Menu',
  VIBE: 'Vibe',
  OTHER: 'Other',
}

export const PHOTO_KINDS = Object.keys(PHOTO_KIND_LABELS) as PhotoKind[]

export const MACHINE_LABELS: Record<MachineBrand, string> = {
  LA_MARZOCCO: 'La Marzocco',
  SLAYER: 'Slayer',
  SYNESSO: 'Synesso',
  KEES_VAN_DER_WESTEN: 'Kees van der Westen',
  VICTORIA_ARDUINO: 'Victoria Arduino',
  NUOVA_SIMONELLI: 'Nuova Simonelli',
  MODBAR: 'Modbar',
  ROCKET: 'Rocket',
  RANCILIO: 'Rancilio',
  BREVILLE: 'Breville',
  DECENT: 'Decent',
  FAEMA: 'Faema',
  OTHER: 'Other',
  UNKNOWN: 'Unknown',
}

// OTHER models carry their brand as a prefix ("Astoria Storm"), so a
// leading "Other" is noise.
export function machineDisplay(machine: MachineBrand, model: string | null): string {
  if (machine === 'OTHER' && model) return model
  return `${MACHINE_LABELS[machine]}${model ? ` ${model}` : ''}`
}

export const BEAN_SOURCE_LABELS: Record<BeanSource, string> = {
  IN_HOUSE_ROAST: 'Roasts in-house',
  LOCAL_ROASTER: 'Local roaster',
  NATIONAL_ROASTER: 'National roaster',
  MULTI_ROASTER: 'Multi-roaster',
  UNKNOWN: 'Unknown',
}

// Common Bay Area milk brands, used for the filter and report suggestions.
export const MILK_BRANDS = ['Straus', 'Clover', 'Oatly', 'Minor Figures', 'Califia Farms', 'Pacific', 'Milkadamia']

// Suggestions for report chips; free text is always allowed alongside.
export const BEAN_ORIGINS = [
  'Single origin',
  'Blend',
  'Seasonal rotation',
  'Ethiopia',
  'Colombia',
  'Brazil',
  'Guatemala',
  'Kenya',
  'Indonesia',
]

export const GRINDERS = [
  'Mahlkönig EK43',
  'Mahlkönig E65S',
  'Mythos One',
  'Mazzer Robur',
  'Mazzer Major',
  'Ditting 807',
  'Anfim Pratica',
  'Weber EG-1',
  'Fellow Ode',
]

export const DRINKS = [
  'Espresso',
  'Latte',
  'Cappuccino',
  'Mocha',
  'Matcha latte',
  'Chai latte',
  'Drip',
  'Pour over',
  'Cold brew',
  'Hojicha',
]

export const MACHINE_BRANDS = Object.keys(MACHINE_LABELS) as MachineBrand[]
export const BEAN_SOURCES = Object.keys(BEAN_SOURCE_LABELS) as BeanSource[]

// Tri-state shop amenities (true / false / null = unknown).
export const AMENITIES = [
  { key: 'dogFriendly', label: 'Dog friendly', no: 'No dogs' },
  { key: 'wifi', label: 'Wi-Fi', no: 'No Wi-Fi' },
  { key: 'outdoorSeating', label: 'Outdoor seating', no: 'No outdoor seating' },
] as const

export type AmenityKey = (typeof AMENITIES)[number]['key']
