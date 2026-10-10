/**
 * Core answers are not always the shape a page expects: an older core, a
 * quiet stub or the catch-all fallback (`{ ok: false, items: [], results: [] }`)
 * returned an object where a list was expected and pages crashed with
 * "e.filter is not a function". Every list read goes through this instead.
 */
export function asArray<T>(value: unknown, ...keys: string[]): T[] {
  if (Array.isArray(value)) {
    return value.filter(item => item !== null && item !== undefined) as T[]
  }

  if (value && typeof value === 'object') {
    const record = value as Record<string, unknown>

    for (const key of [...keys, 'items', 'results', 'data']) {
      if (Array.isArray(record[key])) {
        return (record[key] as unknown[]).filter(item => item !== null && item !== undefined) as T[]
      }
    }
  }

  return []
}
