import type { Category, CategoryField, ProductAttributes } from './api'

// Form state for category fields: strings while typing, booleans for BOOL,
// string[] for ENUM_MULTI. Converted to typed attributes on save.
export type FieldValue = string | boolean | string[]
export type FieldValues = Record<string, FieldValue>

export function fromAttributes(fields: CategoryField[], attributes: ProductAttributes): FieldValues {
  const values: FieldValues = {}
  for (const f of fields) {
    const v = attributes[f.key]
    if (v === undefined || v === null) continue
    if (f.valueType === 'BOOL') values[f.key] = Boolean(v)
    else if (f.valueType === 'ENUM_MULTI') values[f.key] = Array.isArray(v) ? v.map(String) : [String(v)]
    else if (f.valueType === 'TEXT_LIST') values[f.key] = Array.isArray(v) ? v.join(', ') : String(v)
    else values[f.key] = String(v)
  }
  return values
}

// Typed payload for ProductInput.attributes. Blank values are omitted; the
// server enforces required fields and option values again.
export function toAttributes(fields: CategoryField[], values: FieldValues): ProductAttributes {
  const out: ProductAttributes = {}
  for (const f of fields) {
    const v = values[f.key]
    if (v === undefined) continue
    switch (f.valueType) {
      case 'BOOL':
        if (v === true) out[f.key] = true
        break
      case 'INT': {
        const n = parseInt(String(v), 10)
        if (!Number.isNaN(n)) out[f.key] = n
        break
      }
      case 'DECIMAL': {
        const n = parseFloat(String(v))
        if (!Number.isNaN(n)) out[f.key] = n
        break
      }
      case 'ENUM_MULTI':
        if (Array.isArray(v) && v.length) out[f.key] = v
        break
      case 'TEXT_LIST': {
        const parts = String(v)
          .split(',')
          .map((s) => s.trim())
          .filter(Boolean)
        if (parts.length) out[f.key] = parts
        break
      }
      default: {
        const s = String(v).trim()
        if (s) out[f.key] = s
      }
    }
  }
  return out
}

// First problem with the form, or null. Mirrors the server's checks so the
// seller sees it before the round trip.
export function fieldProblem(fields: CategoryField[], values: FieldValues): string | null {
  const attrs = toAttributes(fields, values)
  for (const f of fields) {
    const raw = values[f.key]
    const typed = raw !== undefined && raw !== '' && !(Array.isArray(raw) && raw.length === 0)
    if (f.required && attrs[f.key] === undefined) return `${f.label} is required.`
    if ((f.valueType === 'INT' || f.valueType === 'DECIMAL') && typed && attrs[f.key] === undefined)
      return `${f.label} must be a number.`
    if (typeof attrs[f.key] === 'number' && (attrs[f.key] as number) < 0) return `${f.label} must not be negative.`
  }
  return null
}

// Buyer-facing text for one value; same rules as the server's display_value.
export function displayValue(f: CategoryField, v: unknown): string {
  if (v === undefined || v === null || v === '' || (Array.isArray(v) && v.length === 0)) return ''
  switch (f.valueType) {
    case 'ENUM':
      return f.options.find((o) => o.value === v)?.label ?? String(v)
    case 'ENUM_MULTI':
      return (v as string[]).map((x) => f.options.find((o) => o.value === x)?.label ?? x).join(', ')
    case 'TEXT_LIST':
      return (v as string[]).join(', ')
    case 'BOOL':
      return v ? f.label : ''
    case 'INT':
    case 'DECIMAL':
      return f.unit ? `${v} ${f.unit}` : String(v)
    default:
      return String(v)
  }
}

const SEGMENT = ' · '

// Fill the category's subtitle template the way the server does, for the live preview.
export function previewSubtitle(category: Category, attributes: ProductAttributes): string {
  if (!category.subtitleTemplate) return ''
  const byKey = new Map(category.fields.map((f) => [f.key, f]))
  const segments: string[] = []
  for (const segment of category.subtitleTemplate.split(SEGMENT)) {
    let any = false
    const text = segment.replace(/\{(\w+)\}/g, (_, key: string) => {
      const f = byKey.get(key)
      const rendered = f ? displayValue(f, attributes[key]) : ''
      if (rendered) any = true
      return rendered
    })
    if (any) segments.push(text.replace(/\s+/g, ' ').trim())
  }
  return segments.join(SEGMENT)
}

// Grams and millilitres are stored; US sellers think in ounces.
export function unitHint(f: CategoryField, raw: string): string | null {
  const n = parseFloat(raw)
  if (Number.isNaN(n) || n <= 0) return null
  if (f.unit === 'g') return `≈ ${(n / 28.3495).toFixed(n >= 1000 ? 0 : 1).replace(/\.0$/, '')} oz`
  if (f.unit === 'ml') return `≈ ${(n / 29.5735).toFixed(1).replace(/\.0$/, '')} fl oz`
  return null
}
