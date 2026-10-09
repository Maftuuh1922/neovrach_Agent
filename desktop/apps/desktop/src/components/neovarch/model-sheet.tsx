/**
 * Header of the composer's model picker, styled like the phone's model
 * switcher sheet: a mono kicker naming whose model this is ("model · default
 * PC" for a new chat, "model · <agent>" for a session that has an Office
 * agent), the title "Pilih model", and an optional accessory slot.
 *
 * 9Router hook point: the router integration registers its status line
 * (state, "Jalankan", dashboard link) with `registerModelSheetAccessory`, so
 * the picker never imports the router store directly and either side can ship
 * without the other.
 */
import { useStore } from '@nanostores/react'
import { atom } from 'nanostores'
import type { ComponentType } from 'react'

import { agentForSession } from './agent-identity'
import { $office } from './office-store'

export const $modelSheetAccessory = atom<ComponentType | null>(null)

/** Register (or clear with `null`) the component shown under the sheet title. */
export function registerModelSheetAccessory(component: ComponentType | null): void {
  $modelSheetAccessory.set(component)
}

export function modelSheetKicker(agentName: null | string | undefined): string {
  return agentName ? `model · ${agentName}` : 'model · default PC'
}

export function ModelSheetHead({ sessionIds }: { sessionIds: (null | string)[] }) {
  const office = useStore($office)
  const Accessory = useStore($modelSheetAccessory)
  const agent = agentForSession(office, ...sessionIds)

  return (
    <div className="nv-model-sheet-head" data-slot="nv-model-sheet-head">
      <span aria-hidden="true" className="nv-model-sheet-grip" />
      <span className="nv-model-sheet-kicker">{modelSheetKicker(agent?.name)}</span>
      <span className="nv-model-sheet-title">Pilih model</span>
      {Accessory && <Accessory />}
    </div>
  )
}
