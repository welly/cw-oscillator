#!/usr/bin/env bash
# Builds the iOS app and runs it in a Simulator (default: iPhone 17 Pro).
#   ./scripts/run-ios-sim.sh ["iPhone 17"]
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE="${1:-iPhone 17 Pro}"
xcodebuild -project iOS/OscillatoriOS.xcodeproj -scheme OscillatoriOS \
    -destination "platform=iOS Simulator,name=$DEVICE" \
    -derivedDataPath .build/xcode-ios -quiet build
xcrun simctl boot "$DEVICE" 2>/dev/null || true
open -a Simulator
xcrun simctl install "$DEVICE" ".build/xcode-ios/Build/Products/Debug-iphonesimulator/CW Training Oscillator.app"
xcrun simctl launch --terminate-running-process "$DEVICE" radio.g3ajm.Oscillator
