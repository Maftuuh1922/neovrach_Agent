import { MODEL_MENU_ROW_AREA, type ModelMenuRowContribution } from '@/app/shell/model-menu-row-decorations'
import { registry } from '@/contrib/registry'

/** True for a 9Router model served free (OpenCode Free, alias `oc/`). */
export function isFreeRouterModel(provider: string, model: string): boolean {
  return provider === '9router' && model.startsWith('oc/')
}

/** "Gratis" chip on 9Router's free models in the composer model picker. */
export const router9RowBadge: ModelMenuRowContribution = {
  decorate: ({ model, provider }) => (isFreeRouterModel(provider, model) ? { badge: 'Gratis' } : null)
}

let registered = false

export function registerRouter9RowBadge(): void {
  if (registered) {
    return
  }

  registered = true
  registry.register({ area: MODEL_MENU_ROW_AREA, data: router9RowBadge, id: 'neovarch.router9.free-badge' })
}
