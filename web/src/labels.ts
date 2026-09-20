import type { BeanSource, Coffee, CoffeeProcess, CoffeeType, MachineBrand, PhotoKind, RoastLevel } from './api'

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
  PRIVATE_LABEL: 'Private label',
  DISTRIBUTOR: 'Commercial distributor',
  UNKNOWN: 'Unknown',
}

// Common Bay Area milk brands, used for the filter and report suggestions.
export const MILK_BRANDS = ['Straus', 'Clover', 'Oatly', 'Minor Figures', 'Califia Farms', 'Pacific', 'Milkadamia']

export const COFFEE_TYPE_LABELS: Record<CoffeeType, string> = {
  SINGLE_ORIGIN: 'Single origin',
  BLEND: 'Blend',
}

export const PROCESS_LABELS: Record<CoffeeProcess, string> = {
  WASHED: 'Washed',
  NATURAL: 'Natural',
  HONEY: 'Honey',
  WET_HULLED: 'Wet-hulled',
  OTHER: 'Other',
}

// Fermentation is free text now; this maps legacy enum tokens for display.
export const FERMENTATION_LABELS: Record<string, string> = {
  ANAEROBIC: 'Anaerobic',
  CARBONIC_MACERATION: 'Carbonic maceration',
  CO_FERMENT: 'Co-ferment',
  THERMAL_SHOCK: 'Thermal shock',
  EXTENDED: 'Extended ferment',
}

// Typeahead suggestions for the report form; any text is allowed.
export const FERMENTATION_SUGGESTIONS = [
  'Anaerobic',
  'Carbonic maceration',
  'Co-ferment',
  'Thermal shock',
  'Extended ferment',
  'Lactic',
  'Koji',
  'Yeast inoculated',
]

export const ROAST_LEVEL_LABELS: Record<RoastLevel, string> = {
  LIGHT: 'Light',
  MEDIUM: 'Medium',
  DARK: 'Dark',
}

export const COFFEE_TYPES = Object.keys(COFFEE_TYPE_LABELS) as CoffeeType[]
export const COFFEE_PROCESSES = Object.keys(PROCESS_LABELS) as CoffeeProcess[]
export const ROAST_LEVELS = Object.keys(ROAST_LEVEL_LABELS) as RoastLevel[]

// Suggestions for origin chips; free text is always allowed alongside.
export const ORIGIN_COUNTRIES = ['Ethiopia', 'Colombia', 'Brazil', 'Guatemala', 'Kenya', 'Indonesia', 'Honduras', 'Peru']

// One-line summary for compact views (drawer rows, report history).
export function coffeeSummary(c: Coffee): string {
  return [[c.roaster, c.name].filter(Boolean).join(' — ') || null, ...coffeePills(c)].filter(Boolean).join(' · ')
}

// Attribute pills for one coffee, in display order, skipping unknowns.
export function coffeePills(c: Coffee): string[] {
  return [
    c.type && COFFEE_TYPE_LABELS[c.type],
    ...c.origins,
    c.process && PROCESS_LABELS[c.process],
    c.fermentation && (FERMENTATION_LABELS[c.fermentation] ?? c.fermentation),
    c.roastLevel && `${ROAST_LEVEL_LABELS[c.roastLevel]} roast`,
    ...c.varieties,
  ].filter((p): p is string => Boolean(p))
}

// Grinder brands for the report form; the model is free text alongside.
export const GRINDER_BRANDS = [
  'Mahlkönig',
  'Mazzer',
  'Victoria Arduino',
  'Ditting',
  'Anfim',
  'Weber Workshops',
  'Fellow',
  'Eureka',
  'Compak',
  'Ceado',
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
