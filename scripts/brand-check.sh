#!/usr/bin/env bash
# Brand check: /hermes/i must not grow in the core or in the built desktop bundle.
# NOTICE and LICENSE files are exempt (attribution). Counts are compared with
# scripts/brand-baseline.txt, a ratchet that may only go down (target: 0).
#   scripts/brand-check.sh [--update]      (run from the repo root, after the desktop build)
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
count() {
  grep -rIoi hermes "$@" --exclude='NOTICE*' --exclude='LICENSE*' \
    --exclude-dir=__pycache__ --exclude-dir=.pytest_cache 2>/dev/null | wc -l | tr -d ' '
}
core=$(count core)
bundle_dir=desktop/apps/desktop/dist
if [ -d "$bundle_dir" ]; then bundle=$(count "$bundle_dir"); else bundle=skip; fi
echo "core: $core   desktop bundle: $bundle"
if [ "${1:-}" = "--update" ]; then
  printf 'core=%s\nbundle=%s\n' "$core" "$bundle" > scripts/brand-baseline.txt
  echo "baseline updated"
  exit 0
fi
core_base=$(sed -n 's/^core=//p' scripts/brand-baseline.txt)
bundle_base=$(sed -n 's/^bundle=//p' scripts/brand-baseline.txt)
fail=0
if [ "$core" -gt "$core_base" ]; then
  echo "::error::core mentions hermes $core times (baseline $core_base)"; fail=1
fi
if [ "$bundle" != skip ] && [ "$bundle_base" != skip ] && [ "$bundle" -gt "$bundle_base" ]; then
  echo "::error::desktop bundle mentions hermes $bundle times (baseline $bundle_base)"; fail=1
fi
if [ $fail = 0 ]; then
  echo "brand check ok (the count may only go down; lower scripts/brand-baseline.txt when it does)"
fi
exit $fail
