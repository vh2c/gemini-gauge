#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "⚡ Building Gemini Gauge for macOS..."
"${SCRIPT_DIR}/build.sh"

echo "📲 Installing into /Applications..."
# Remove older version if present
rm -rf "/Applications/Gemini Gauge.app" 2>/dev/null || true
cp -R "${SCRIPT_DIR}/Gemini Gauge.app" /Applications/

# Clear quarantine bit
xattr -cr "/Applications/Gemini Gauge.app" 2>/dev/null || true

# Package ZIP for Downloads
mkdir -p "${REPO_DIR}/dist" "${HOME}/Downloads"
(cd "${SCRIPT_DIR}" && zip -r -y "${REPO_DIR}/dist/Gemini-Gauge-macOS-vh2c.zip" "Gemini Gauge.app")
cp "${REPO_DIR}/dist/Gemini-Gauge-macOS-vh2c.zip" "${HOME}/Downloads/"

echo ""
echo "=========================================================="
echo " ✅ Gemini Gauge instalado com sucesso em /Applications!"
echo " 📦 Arquivo ZIP copiado para: ~/Downloads/Gemini-Gauge-macOS-vh2c.zip"
echo "=========================================================="
