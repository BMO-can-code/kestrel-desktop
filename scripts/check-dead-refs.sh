#!/usr/bin/env bash
set -e
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

FORBIDDEN=( "ZenModsMarketplace" "ZenModsMarketplaceChild" "ZenModsMarketplaceParent" )
FOUND=0
for term in "${FORBIDDEN[@]}"; do
  if grep -rn "$term" . --include="*.mjs" --include="*.js" --include="*.sys.mjs" --include="*.patch" --include="*.mozbuild" --include="moz.build" --include="*.yaml" --include="*.yml" 2>/dev/null | grep -v "node_modules" | grep -v "engine" | grep -v ".git" | grep -v "docs/" | grep -v "scripts/check-dead-refs.sh"; then
    echo "FAIL: found $term" >&2
    FOUND=1
  fi
done
if [ $FOUND -ne 0 ]; then
  echo "FAIL" >&2
  exit 1
fi
echo "PASS: no dead refs"
exit 0
