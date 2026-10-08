import { type CSSProperties, type ReactNode, useCallback, useLayoutEffect, useRef, useState } from 'react'

import { useResizeObserver } from '@/hooks/use-resize-observer'
import { cn } from '@/lib/utils'

/** The solid rule drawn on a clipped edge (Neovarch: no gradient fades). */
const RULE = '1px solid var(--ui-stroke-secondary)'
const NO_RULE = '1px solid transparent'

export interface FadeEdges {
  above: boolean
  below: boolean
}

/**
 * Neovarch draws clipped edges as solid hairlines, never as a gradient mask,
 * so there is no mask to hand out: always `undefined`. Kept for SDK callers.
 */
export function edgeMask(_edges: FadeEdges, _axis: 'x' | 'y' = 'y'): string | undefined {
  return undefined
}

/**
 * Border styles marking which edges of a scroller have content clipped behind
 * them: a solid 1px rule on a clipped side, a transparent one otherwise (so
 * the box never shifts). Nothing clipped → no visible rule at all.
 */
export function edgeRules({ above, below }: FadeEdges, axis: 'x' | 'y' = 'y'): CSSProperties {
  return axis === 'x'
    ? { borderLeft: above ? RULE : NO_RULE, borderRight: below ? RULE : NO_RULE }
    : { borderBottom: below ? RULE : NO_RULE, borderTop: above ? RULE : NO_RULE }
}

/** Which edges of a scroller currently have content clipped behind them. */
export function scrollEdges(el: Pick<HTMLElement, 'clientHeight' | 'scrollHeight' | 'scrollTop'>): FadeEdges {
  return {
    above: el.scrollTop > 1,
    below: el.scrollTop + el.clientHeight < el.scrollHeight - 1
  }
}

/**
 * A height-capped scroller whose clipped edges get a solid hairline.
 *
 * EDGE-AWARE — a side only shows its rule when it actually has content clipped
 * behind it, so a list that fits shows no rule at all and a list scrolled to
 * the bottom drops its bottom rule. Flat colour only (no mask fade). That state is tracked on
 * scroll and on resize (via the app's shared observer, so N of these cost one
 * delivery per frame rather than N).
 *
 * `deps` re-pins the scroller to the bottom when it changes — newest-at-bottom
 * feeds want that; a plain list should leave it unset.
 */
export function FadeScroll({
  children,
  className,
  deps,
  maxHeight = '9rem'
}: {
  children: ReactNode
  className?: string
  deps?: unknown
  maxHeight?: string
}) {
  const ref = useRef<HTMLDivElement>(null)
  const [edges, setEdges] = useState({ above: false, below: false })

  const measure = useCallback(() => {
    const el = ref.current

    if (!el) {
      return
    }

    const next = scrollEdges(el)

    setEdges(prev => (prev.above === next.above && prev.below === next.below ? prev : next))
  }, [])

  useLayoutEffect(() => {
    if (deps !== undefined && ref.current) {
      ref.current.scrollTop = ref.current.scrollHeight
    }

    measure()
  }, [deps, measure])

  useResizeObserver(measure, ref)

  return (
    <div
      className={cn('overflow-y-auto overscroll-contain', className)}
      onScroll={measure}
      ref={ref}
      style={{ ...edgeRules(edges), maxHeight }}
    >
      {children}
    </div>
  )
}
