#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Gate: fail if any removed Zen-operated hostname reappears in the tree.
# Removed at M1 per ADR-0006. Must catch substrings *.zen-browser.app and *.zen-browser.github.io

set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

# Catch any zen-browser.app or zen-browser.github.io as substring
if grep -rE "zen-browser\.app|zen-browser\.github\.io" src/ prefs/ configs/ surfer.json .github/workflows/ scripts/ 2>/dev/null | grep -v "check-removed-hostnames.sh"; then
  echo "ERROR: removed hostname pattern found" >&2
  exit 1
fi

echo "Removed-hostname gate passed"
exit 0
