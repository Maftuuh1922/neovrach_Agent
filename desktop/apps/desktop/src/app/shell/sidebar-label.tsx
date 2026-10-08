import type * as React from 'react'

import { HaloMark } from '@/components/neovarch/halo-mark'
import { cn } from '@/lib/utils'

interface SidebarPanelLabelProps extends React.ComponentProps<'span'> {
  dotClassName?: string
}

export function SidebarPanelLabel({ children, className, dotClassName, ...props }: SidebarPanelLabelProps) {
  return (
    <span
      className={cn(
        'nv-panel-label flex min-w-0 items-center gap-2 pl-2 text-[0.64rem] font-semibold uppercase tracking-[0.16em] text-(--theme-primary)',
        className
      )}
      {...props}
    >
      {dotClassName ? (
        // Callers passing a status colour get a flat round status dot.
        <span aria-hidden="true" className={cn('inline-block size-2 shrink-0 rounded-full', dotClassName)} />
      ) : (
        <HaloMark className="size-2.5" />
      )}
      <span className="min-w-0 truncate leading-none">{children}</span>
    </span>
  )
}
