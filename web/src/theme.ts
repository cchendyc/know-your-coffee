// Theme preference: 'system' follows prefers-color-scheme, 'light'/'dark' force it.
// The resolved theme lands on <html data-theme="...">, which index.css uses to
// override the Tailwind color variables (Dark Roast palette).
export type ThemePref = 'system' | 'light' | 'dark'

export const THEME_KEY = 'kyc-theme'

const media = window.matchMedia('(prefers-color-scheme: dark)')

export function getThemePref(): ThemePref {
  const stored = localStorage.getItem(THEME_KEY)
  return stored === 'light' || stored === 'dark' ? stored : 'system'
}

function resolve(pref: ThemePref): 'light' | 'dark' {
  return pref === 'system' ? (media.matches ? 'dark' : 'light') : pref
}

export function applyThemePref(pref: ThemePref) {
  document.documentElement.dataset.theme = resolve(pref)
}

export function setThemePref(pref: ThemePref) {
  if (pref === 'system') localStorage.removeItem(THEME_KEY)
  else localStorage.setItem(THEME_KEY, pref)
  applyThemePref(pref)
}

// Track OS appearance changes while in system mode.
media.addEventListener('change', () => applyThemePref(getThemePref()))

// Runs on import, before React renders, so there is no light flash.
applyThemePref(getThemePref())
