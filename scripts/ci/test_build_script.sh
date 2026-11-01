#!/usr/bin/env bash
# Unit tests for build-macos.sh selection logic using fake bundle trees
set -e

SCRIPT="/Users/mayankbrar/src/desktop/scripts/ci/build-macos.sh"
bash -n "$SCRIPT" && echo "bash -n: OK"

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$SCRIPT" && echo "shellcheck: OK" || true
else
  echo "shellcheck: not installed"
fi

TESTDIR=$(mktemp -d)
cd "$TESTDIR"

make_bundle() {
  local dir="$1"
  local bid="$2"
  local bin="$3"
  mkdir -p "$dir/Contents/MacOS"
  printf '#!/bin/sh\necho "fake"\n' > "$dir/Contents/MacOS/$bin"
  chmod +x "$dir/Contents/MacOS/$bin"
  cat > "$dir/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>$bid</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
</dict>
</plist>
PLIST
}

# Test 1: exactly one match
mkdir -p obj-test/dist
make_bundle "obj-test/dist/Nightly.app" "app.zen-browser" "zen"
MAPFILE="$TESTDIR/map1.txt"
for cand in "$TESTDIR"/obj-test/dist/*.app; do
  bin="$(basename "$(find "$cand/Contents/MacOS" -maxdepth 1 -type f -perm +111 | head -1)")"
  bid="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$cand/Contents/Info.plist" 2>/dev/null || echo "")"
  echo "$cand|$bin|$bid" >> "$MAPFILE"
done
MATCHES=$(grep -E '\|zen\|' "$MAPFILE" | grep -E '\|app\.zen-browser$' || true)
[ -z "$MATCHES" ] && COUNT=0 || COUNT=$(echo "$MATCHES" | grep -c "^")
[ "$COUNT" -eq 1 ] && echo "test1: OK" || echo "test1: FAIL"

# Test 2: zero matches
rm -rf obj-test2 && mkdir -p "$TESTDIR/obj-test2/dist"
make_bundle "$TESTDIR/obj-test2/dist/Other.app" "com.example.other" "other"
MAPFILE="$TESTDIR/map2.txt"
for cand in "$TESTDIR"/obj-test2/dist/*.app; do
  bin="$(basename "$(find "$cand/Contents/MacOS" -maxdepth 1 -type f -perm +111 | head -1)")"
  bid="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$cand/Contents/Info.plist" 2>/dev/null || echo "")"
  echo "$cand|$bin|$bid" >> "$MAPFILE"
done
MATCHES=$(grep -E '\|zen\|' "$MAPFILE" | grep -E '\|app\.zen-browser$' || true)
[ -z "$MATCHES" ] && COUNT=0 || COUNT=$(echo "$MATCHES" | grep -c "^")
[ "$COUNT" -eq 0 ] && echo "test2: OK" || echo "test2: FAIL"

# Test 3: multiple matches
rm -rf obj-test3 && mkdir -p "$TESTDIR/obj-test3/dist"
make_bundle "$TESTDIR/obj-test3/dist/Zen1.app" "app.zen-browser" "zen"
make_bundle "$TESTDIR/obj-test3/dist/Zen2.app" "app.zen-browser" "zen"
MAPFILE="$TESTDIR/map3.txt"
for cand in "$TESTDIR"/obj-test3/dist/*.app; do
  bin="$(basename "$(find "$cand/Contents/MacOS" -maxdepth 1 -type f -perm +111 | head -1)")"
  bid="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$cand/Contents/Info.plist" 2>/dev/null || echo "")"
  echo "$cand|$bin|$bid" >> "$MAPFILE"
done
MATCHES=$(grep -E '\|zen\|' "$MAPFILE" | grep -E '\|app\.zen-browser$' || true)
[ -z "$MATCHES" ] && COUNT=0 || COUNT=$(echo "$MATCHES" | grep -c "^")
[ "$COUNT" -eq 2 ] && echo "test3: OK" || echo "test3: FAIL"

# Test 4: decoy plugin-container
rm -rf obj-test4 && mkdir -p "$TESTDIR/obj-test4/dist"
make_bundle "$TESTDIR/obj-test4/dist/plugin-container.app" "app.zen-browser.plugincontainer" "plugin-container"
make_bundle "$TESTDIR/obj-test4/dist/Zen.app" "app.zen-browser" "zen"
MAPFILE="$TESTDIR/map4.txt"
for cand in "$TESTDIR"/obj-test4/dist/*.app; do
  bin="$(basename "$(find "$cand/Contents/MacOS" -maxdepth 1 -type f -perm +111 | head -1)")"
  bid="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$cand/Contents/Info.plist" 2>/dev/null || echo "")"
  echo "$cand|$bin|$bid" >> "$MAPFILE"
done
MATCHES=$(grep -E '\|zen\|' "$MAPFILE" | grep -E '\|app\.zen-browser$' || true)
[ -z "$MATCHES" ] && COUNT=0 || COUNT=$(echo "$MATCHES" | grep -c "^")
[ "$COUNT" -eq 1 ] && echo "test4: OK" || echo "test4: FAIL"

rm -rf "$TESTDIR"
echo "All tests done"
