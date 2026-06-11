#!/usr/bin/env bash
set -euo pipefail

bundle=.build/fixtures/ParketHarnessApp.app
macos="$bundle/Contents/MacOS"

mkdir -p "$macos"
cp Tests/Fixtures/ParketHarnessApp/Info.plist "$bundle/Contents/Info.plist"
swiftc -swift-version 6 \
    -parse-as-library \
    Tests/Fixtures/ParketHarnessApp/main.swift \
    -o "$macos/ParketHarnessApp" \
    -framework AppKit
codesign --force --sign - "$bundle"
echo "$bundle"
