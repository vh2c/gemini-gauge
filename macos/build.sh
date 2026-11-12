#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_BUNDLE="${SCRIPT_DIR}/Gemini Gauge.app"
BIN_DIR="${APP_BUNDLE}/Contents/MacOS"
RES_DIR="${APP_BUNDLE}/Contents/Resources"

mkdir -p "${BIN_DIR}" "${RES_DIR}/core"

echo "🔨 Compiling Swift binary for Gemini Gauge..."
swiftc -O -target arm64-apple-macos11.0 "${SCRIPT_DIR}/src/QuotaHubApp.swift" -o "${BIN_DIR}/GeminiGauge"

echo "📦 Bundling core engine & assets..."
cp -r "${REPO_DIR}/core/"* "${RES_DIR}/core/"

if [ -f "${REPO_DIR}/assets/AppIcon.icns" ]; then
    cp "${REPO_DIR}/assets/AppIcon.icns" "${RES_DIR}/AppIcon.icns"
fi

cat << 'PLIST' > "${APP_BUNDLE}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Gemini Gauge</string>
    <key>CFBundleDisplayName</key>
    <string>Gemini Gauge</string>
    <key>CFBundleIdentifier</key>
    <string>br.com.vh2c.gemini-gauge</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>GeminiGauge</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "✅ App bundle created at ${APP_BUNDLE}"
