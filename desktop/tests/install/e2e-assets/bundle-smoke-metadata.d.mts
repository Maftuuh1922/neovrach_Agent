// Type declarations for bundle-smoke-metadata.mjs (Neovarch: added so the
// desktop electron typecheck can resolve the .mjs import under allowJs=false).
export function bundleIdentity(commit: string, tag?: string, channelRequest?: unknown): unknown
export function verifyBundleStamp(
  stamp: unknown,
  options: { commit: string; tag?: string; platform: string; channelRequest?: unknown }
): string
export function verifyMacMetadata(plist: unknown, stamp: unknown, options: { commit: string; tag?: string; channelRequest?: unknown }): unknown
