#!/usr/bin/env bash
set -e
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"
# Fail if injection actor registration exists
if grep -rn "ZenModsMarketplace" src/zen/common/sys/ZenActorsManager.sys.mjs src/zen/mods/ 2>/dev/null | grep -v "^$"; then
  echo "ERROR: injection/mods marketplace actor still present" >&2
  exit 1
fi
echo "Injection check passed"
exit 0
