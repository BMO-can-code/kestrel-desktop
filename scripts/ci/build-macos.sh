#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# CI-agnostic macOS build script. Driven by env vars only.
# No $GITHUB_* dependencies. Runs on Actions, Buildkite, CircleCI, or rented Mac over SSH.

set -euo pipefail

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$REPO_DIR"

# Env vars (with sensible defaults)
BRANCH="${BRANCH:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)}"
RELEASE_MODE="${RELEASE_MODE:-true}"
DISABLE_LTO="${DISABLE_LTO:-true}"
ARTIFACT_NAME="${ARTIFACT_NAME:-zen-stock-dev-arm64.zip}"
EXPECTED_BINARY="${EXPECTED_BINARY:-zen}"

# Read bundle id from config (branding output; changes at M5)
EXPECTED_BUNDLE_ID="${EXPECTED_BUNDLE_ID:-}"
if [ -z "$EXPECTED_BUNDLE_ID" ] && [ -f "$REPO_DIR/surfer.json" ]; then
  EXPECTED_BUNDLE_ID="$(python3 -c "import json; d=json.load(open('$REPO_DIR/surfer.json')); print(d.get('appId') or d.get('bundleId') or d.get('id') or '')" 2>/dev/null || echo "")"
fi
if [ -z "$EXPECTED_BUNDLE_ID" ]; then
  echo "ERROR: EXPECTED_BUNDLE_ID unset and not found in surfer.json (appId/bundleId/id). Bundle id is branding output and must be provided." >&2
  exit 1
fi

echo "==> Build starting"
echo "REPO_DIR=$REPO_DIR"
echo "BRANCH=$BRANCH"
echo "RELEASE_MODE=$RELEASE_MODE"
echo "DISABLE_LTO=$DISABLE_LTO"

# Ensure we have engine
if [ ! -d "$REPO_DIR/engine" ]; then
  echo "ERROR: engine/ not found. Run npm run download/import first." >&2
  exit 1
fi

# Navigate to engine
cd "$REPO_DIR/engine"

# Configure if needed
if [ ! -f ".mozconfig" ] && [ ! -f "mozconfig" ]; then
  echo "==> No mozconfig found, using surfer defaults"
  # Try to use surfer
  if command -v npx >/dev/null 2>&1; then
    npx surfer ci --brand alpha 2>&1 | tail -20 || true
  fi
fi

# Build
echo "==> Building"
if [ "$DISABLE_LTO" = "true" ]; then
  export MOZ_LTO=0
fi
./mach build 2>&1 | tail -30

# Package
echo "==> Packaging"
./mach package 2>&1 | tail -20

# Find browser app by identity (not name)
echo "==> Finding browser app by identity"
APP=""
MAPFILE="/tmp/app_candidates_$$.txt"
find obj-*/dist -maxdepth 4 -name '*.app' -type d | while read -r cand; do
  bin="$(basename "$(find "$cand/Contents/MacOS" -maxdepth 1 -type f -perm +111 2>/dev/null | head -1)")"
  bid="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$cand/Contents/Info.plist" 2>/dev/null || echo "")"
  echo "$cand|$bin|$bid" >> "$MAPFILE"
done

# Select matching bundle
if [ -f "$MAPFILE" ]; then
  MATCHES=$(grep "|${EXPECTED_BINARY}|" "$MAPFILE" | grep "|${EXPECTED_BUNDLE_ID}$" || true)
  COUNT=$(echo "$MATCHES" | grep -c "^" || echo 0)
  if [ "$COUNT" -eq 1 ] && [ -n "$MATCHES" ]; then
    APP=$(echo "$MATCHES" | cut -d'|' -f1)
  elif [ "$COUNT" -gt 1 ]; then
    echo "ERROR: multiple matches for bundle id $EXPECTED_BUNDLE_ID with binary $EXPECTED_BINARY" >&2
    cat "$MAPFILE" >&2
    exit 1
  else
    echo "ERROR: no match for bundle id $EXPECTED_BUNDLE_ID with binary $EXPECTED_BINARY" >&2
    cat "$MAPFILE" >&2
    exit 1
  fi
else
  echo "ERROR: no app candidates found" >&2
  exit 1
fi

echo "APP=$APP"
test -n "$APP"
test -d "$APP"

BIN="$APP/Contents/MacOS/$EXPECTED_BINARY"
test -f "$BIN"
test -x "$BIN"

# Ad-hoc signing
echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP" 2>&1 | tail -5
codesign --verify --deep --strict "$APP" 2>&1 | tail -2
plutil -lint "$APP/Contents/Info.plist" >/dev/null && echo "plutil: OK"

# Create artifact
OUT="$REPO_DIR/$ARTIFACT_NAME"
rm -f "$OUT"
echo "==> Creating artifact: $OUT"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT"
ls -lh "$OUT"

# Verify artifact
echo "==> Verifying artifact"
TMPDIR_VERIFY="/tmp/verify_$$"
mkdir -p "$TMPDIR_VERIFY"
cd "$TMPDIR_VERIFY"
ditto -x -k "$OUT" . >/dev/null
APP2=$(find . -name '*.app' -type d | grep -v plugin-container | grep -v updater | grep -v gpu-helper | grep -v media-plugin | head -1)
test -n "$APP2"
BIN2="$APP2/Contents/MacOS/$EXPECTED_BINARY"
test -f "$BIN2"
test -x "$BIN2"
"$BIN2" --version 2>&1 | head -2
unzip -l "$OUT" | grep "Contents/MacOS/$EXPECTED_BINARY" | head -1

# Generate manifest
echo "==> Generating manifest"
MANIFEST="$REPO_DIR/artifact-manifest.json"
BID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Contents/Info.plist" 2>/dev/null || echo "")
VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || echo "")
BVER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist" 2>/dev/null || echo "")
ARCHS=$(lipo -archs "$BIN" 2>&1 || echo "unknown")
SIZE=$(stat -f%z "$OUT" 2>/dev/null || stat -c%s "$OUT" 2>/dev/null || echo 0)
SHA256=$(shasum -a 256 "$OUT" | awk '{print $1}')
GIT_SHA="$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || echo "unknown")"
FF_VER=""
if [ -f "$REPO_DIR/engine/browser/config/version.txt" ]; then FF_VER=$(cat "$REPO_DIR/engine/browser/config/version.txt"); fi
RUNNER_IMAGE="${RUNNER_IMAGE:-${ImageOS:-unknown}}"
BUILD_FLAGS="ZEN_RELEASE=$RELEASE_MODE LTO=$([ "$DISABLE_LTO" = "true" ] && echo off || echo on)"

cat > "$MANIFEST" << EOF
{
  "bundle_id": "$BID",
  "version": "$VER",
  "build_version": "$BVER",
  "binary": "$EXPECTED_BINARY",
  "archs": "$ARCHS",
  "size_bytes": $SIZE,
  "sha256": "$SHA256",
  "app_path": "$APP",
  "artifact": "$OUT",
  "git_sha": "$GIT_SHA",
  "firefox_version": "$FF_VER",
  "build_flags": "$BUILD_FLAGS",
  "runner_image": "$RUNNER_IMAGE",
  "built_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
{
  "bundle_id": "$BID",
  "version": "$VER",
  "binary": "$EXPECTED_BINARY",
  "archs": "$ARCHS",
  "size_bytes": $SIZE,
  "sha256": "$SHA256",
  "app_path": "$APP",
  "artifact": "$OUT",
  "built_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
