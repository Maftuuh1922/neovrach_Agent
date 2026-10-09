/**
 * Mini Kantor at the bottom of the right sidebar: the same three.js room as
 * the full Kantor, rendered as a thumbnail (low pixel ratio, ~12 fps, no
 * shadows, no orbit). Agents sit and work live from the office snapshot.
 * Rendering pauses while the thumbnail is offscreen, the window is hidden or
 * the sidebar is closed (unmounted). Clicking opens the full Kantor.
 */
import { useEffect, useMemo, useRef, useState } from 'react'

import { sceneAgentsFromSnapshot } from './office3d-model'
import type { OfficeScene } from './office3d-scene'
import { hasWebGL, loadOfficeScene } from './office-3d'
import type { OfficeSnapshot } from './office-store'

export const MINI_OFFICE_FPS = 12
export const MINI_OFFICE_PIXEL_RATIO = 0.75

/** Visible = on screen and the document is not hidden. */
export function useOnScreen(ref: React.RefObject<HTMLElement | null>): boolean {
  const [inView, setInView] = useState(true)
  const [pageVisible, setPageVisible] = useState(() => typeof document === 'undefined' || !document.hidden)

  useEffect(() => {
    const el = ref.current

    if (!el || typeof IntersectionObserver === 'undefined') {
      return
    }

    const observer = new IntersectionObserver(entries => {
      const entry = entries[entries.length - 1]

      if (entry) {
        setInView(entry.isIntersecting)
      }
    })

    observer.observe(el)

    return () => observer.disconnect()
  }, [ref])

  useEffect(() => {
    const onVisibility = () => setPageVisible(!document.hidden)

    document.addEventListener('visibilitychange', onVisibility)

    return () => document.removeEventListener('visibilitychange', onVisibility)
  }, [])

  return inView && pageVisible
}

export function MiniOffice3D({ office }: { office: null | OfficeSnapshot }) {
  const supported = useMemo(() => hasWebGL(), [])
  const stageRef = useRef<HTMLDivElement>(null)
  const [scene, setScene] = useState<null | OfficeScene>(null)
  const visible = useOnScreen(stageRef)
  const sceneAgents = useMemo(() => sceneAgentsFromSnapshot(office), [office])

  useEffect(() => {
    if (!supported || !stageRef.current) {
      return
    }

    let cancelled = false
    let created: null | OfficeScene = null
    const container = stageRef.current

    loadOfficeScene()
      .then(({ createOfficeScene }) => {
        if (cancelled) {
          return
        }

        created = createOfficeScene({
          container,
          reducedMotion: window.matchMedia?.('(prefers-reduced-motion: reduce)').matches ?? false,
          thumbnail: { fps: MINI_OFFICE_FPS, pixelRatio: MINI_OFFICE_PIXEL_RATIO }
        })
        setScene(created)
      })
      .catch(() => undefined)

    return () => {
      cancelled = true
      created?.dispose()
      setScene(null)
    }
  }, [supported])

  useEffect(() => {
    scene?.setAgents(sceneAgents)
  }, [scene, sceneAgents])

  useEffect(() => {
    scene?.setPaused(!visible)
  }, [scene, visible])

  if (!supported) {
    return null
  }

  return (
    <span
      aria-hidden="true"
      className="nv-office-mini3d"
      data-paused={!visible || undefined}
      data-slot="nv-office-mini3d"
      ref={stageRef}
    />
  )
}
