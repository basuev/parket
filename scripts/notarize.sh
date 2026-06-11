#!/usr/bin/env bash
set -euo pipefail

: "${NOTARY_PROFILE:?set NOTARY_PROFILE to a notarytool keychain profile}"

make dist
xcrun notarytool submit parket.zip --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple parket.app
xcrun stapler validate parket.app
