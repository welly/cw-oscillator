#!/usr/bin/env bash
# Builds CW Training Oscillator.app into ./build (universal with Xcode, this Mac only with the Command Line Tools).
# --install also copies it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/CW Training Oscillator.app"
VERSION="${VERSION:-0.1.0}"

# Universal builds need Xcode's build system; with only the Command Line Tools, build for this Mac.
if [[ "$(xcode-select -p)" == *CommandLineTools* ]]; then
    ARCHS=()
    echo "Command Line Tools only: building for $(uname -m) (install Xcode for a universal build)."
else
    ARCHS=(--arch arm64 --arch x86_64)
fi
swift build -c release ${ARCHS[@]+"${ARCHS[@]}"}
BIN="$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/OscillatorApp"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/OscillatorApp"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>CW Training Oscillator</string>
    <key>CFBundleDisplayName</key><string>CW Training Oscillator</string>
    <key>CFBundleIdentifier</key><string>radio.g3ajm.Oscillator</string>
    <key>CFBundleExecutable</key><string>OscillatorApp</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.education</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Alastair Moore, G3AJM. Licensed under the GNU GPL v3 or later.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature so Gatekeeper lets it run locally. Use a Developer ID to distribute.
codesign --force --deep --sign - "$APP"
echo "Built: $APP"

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/CW Training Oscillator.app"
    cp -R "$APP" "$HOME/Applications/"
    echo "Installed: $HOME/Applications/CW Training Oscillator.app"
fi
