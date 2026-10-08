import type { ComponentProps } from 'react'

import { cn } from '@/lib/utils'

/**
 * The Neovarch halo — a thin ring with a solid core, used wherever Hermes put
 * its dithered square bullet. Flat strokes only (no gradients, no glow).
 */
export function HaloMark({ className, ...props }: ComponentProps<'svg'>) {
  return (
    <svg
      aria-hidden="true"
      className={cn('nv-halo inline-block size-2.5 shrink-0', className)}
      fill="none"
      viewBox="0 0 16 16"
      {...props}
    >
      <circle cx="8" cy="8" r="6.6" stroke="currentColor" strokeWidth="1.6" />
      <circle cx="8" cy="8" fill="currentColor" r="2.2" />
    </svg>
  )
}

/**
 * Quiet placeholder label (empty zones, logs, connecting states): serif italic
 * word beside a halo. Replaces the Hermes scramble-decode header — static, so
 * it costs no timers.
 */
export function NeoLabel({
  className,
  text,
  ...props
}: Omit<ComponentProps<'span'>, 'children'> & { text: string }) {
  return (
    <span className={cn('nv-label inline-flex items-center gap-2', className)} data-slot="nv-label" {...props}>
      <HaloMark className="size-3 text-(--nv-red)" />
      <span className="nv-label-text">{text}</span>
    </span>
  )
}

/** Serif NEOVARCH wordmark with the mono AGENT tag. `compact` drops the tag. */
export function NeovarchWordmark({
  className,
  compact = false,
  ...props
}: ComponentProps<'span'> & { compact?: boolean }) {
  return (
    <span
      aria-label="NEOVARCH AGENT"
      className={cn('nv-wordmark inline-flex items-baseline gap-1.5 leading-none', className)}
      data-slot="nv-wordmark"
      role="img"
      {...props}
    >
      <span aria-hidden="true" className="nv-wordmark-serif">
        NEOVARCH
      </span>
      {!compact && (
        <span aria-hidden="true" className="nv-wordmark-tag">
          AGENT
        </span>
      )}
    </span>
  )
}
