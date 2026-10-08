import { cn } from '@/lib/utils'

import type { StackItem } from './social-store'
import { TECH_ALIASES, TECH_ICONS, type TechIconData } from './tech-icons.gen'

/** Icon for a GitHub linguist / agent language name, or undefined (fallback glyph). */
export function techIconFor(name: string): TechIconData | undefined {
  const k = name.trim().toLowerCase()

  return TECH_ICONS[TECH_ALIASES[k] ?? k] ?? TECH_ICONS[k.replace(/[^a-z0-9]/g, '')]
}

/** Simple Icons logo (CC0, bundled path data) — monochrome in the accent, or brand colour. */
export function TechLogo({ brand = false, name, size = 16 }: { brand?: boolean; name: string; size?: number }) {
  const icon = techIconFor(name)

  return (
    <svg
      aria-label={icon?.title ?? name}
      className="nv-tech-logo"
      data-tech={icon?.slug ?? 'unknown'}
      height={size}
      role="img"
      style={brand && icon ? { color: `#${icon.hex}` } : undefined}
      viewBox="0 0 24 24"
      width={size}
    >
      {icon ? (
        <path d={icon.path} fill="currentColor" />
      ) : (
        <path
          d="M8.5 6.5 3 12l5.5 5.5M15.5 6.5 21 12l-5.5 5.5M13.5 4l-3 16"
          fill="none"
          stroke="currentColor"
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeWidth="2"
        />
      )}
    </svg>
  )
}

/** Glass chips with the logo; the name is the tooltip (and a small caption when `caption`). */
export function TechStackChips({ caption = true, items }: { caption?: boolean; items: StackItem[] }) {
  if (!items.length) {
    return null
  }

  return (
    <ul className="nv-social-chips">
      {items.map(item => {
        const title = techIconFor(item.name)?.title ?? item.name

        return (
          <li
            className={cn('nv-social-chip nv-tech-chip', !caption && 'nv-tech-chip-icon')}
            data-source={item.source}
            key={item.name}
            title={`${title} · ${Math.round(item.share * 100)}%`}
          >
            <TechLogo name={item.name} size={16} />
            {caption && <span>{title}</span>}
            <span className="nv-social-chip-share">{Math.round(item.share * 100)}%</span>
          </li>
        )
      })}
    </ul>
  )
}
