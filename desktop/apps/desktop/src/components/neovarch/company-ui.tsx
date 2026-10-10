import { useCallback, useState } from 'react'

/** Runs an action, shows its error inline instead of throwing into React. */
export function useAction(): [null | string, (fn: () => Promise<unknown>) => Promise<boolean>, boolean] {
  const [error, setError] = useState<null | string>(null)
  const [busy, setBusy] = useState(false)

  const run = useCallback(async (fn: () => Promise<unknown>) => {
    setBusy(true)
    setError(null)

    try {
      await fn()

      return true
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))

      return false
    } finally {
      setBusy(false)
    }
  }, [])

  return [error, run, busy]
}

export function ErrorLine({ error }: { error: null | string }) {
  return error ? (
    <p className="nv-co-error" role="alert">
      {error}
    </p>
  ) : null
}

/** "" → null, anything else → a number (select values carry ids as strings). */
export function idOrNull(value: string): null | number {
  return value ? Number(value) : null
}

/** A whole, non-negative number from a text field ("" → 0). NaN / negative → null (invalid). */
export function wholeOrNull(value: string): null | number {
  const trimmed = value.trim()

  if (!trimmed) {
    return 0
  }

  const n = Number(trimmed)

  return Number.isFinite(n) && n >= 0 ? Math.round(n) : null
}
