#!/usr/bin/env bash
set -euo pipefail

app_name=parket
bundle="$app_name.app"
zip_file="$app_name.zip"
binary="$bundle/Contents/MacOS/$app_name"

make dist

test -d "$bundle"
test -f "$bundle/Contents/Info.plist"
test -x "$binary"
test -f "$zip_file"

bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Contents/Info.plist")
if [ "$bundle_id" != "com.parket.app" ]; then
    echo "unexpected bundle id: $bundle_id" >&2
    exit 1
fi

lsui=$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$bundle/Contents/Info.plist")
if [ "$lsui" != "true" ]; then
    echo "LSUIElement must be true" >&2
    exit 1
fi

codesign --verify --deep --strict "$bundle"
requirement=$(codesign -d -r- "$bundle" 2>&1)
printf '%s\n' "$requirement"
printf '%s\n' "$requirement" | grep -F 'identifier "com.parket.app"' >/dev/null

spctl --assess -vv "$bundle" || true
shasum -a 256 "$zip_file"
