#!/usr/bin/env bash
set -e

echo "⚡ Installing Universal AI Quota Hub for Linux..."

# Check prerequisites
MISSING_DEPS=0
if ! command -v python3 >/dev/null 2>&1; then
    echo "⚠️  Python 3 is required. Please install python3 (e.g. sudo apt install python3)"
    MISSING_DEPS=1
fi

if ! python3 -c "import tkinter" >/dev/null 2>&1; then
    echo "⚠️  Tkinter is required for the GUI. Run: sudo apt install python3-tk (Ubuntu/Debian) or sudo dnf install python3-tkinter (Fedora)"
fi

if ! command -v node >/dev/null 2>&1; then
    echo "⚠️  Node.js (v18+) is required for the multi-provider aggregation engine."
    echo "   Install via: sudo apt install nodejs npm  OR  https://nodejs.org"
fi

TARGET_DIR="${HOME}/.local/share/universal-ai-quota"
BIN_DIR="${HOME}/.local/bin"
APP_DIR="${HOME}/.local/share/applications"

mkdir -p "${TARGET_DIR}" "${BIN_DIR}" "${APP_DIR}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cp -r "${REPO_DIR}/core" "${TARGET_DIR}/"
cp "${SCRIPT_DIR}/quota-hub.py" "${TARGET_DIR}/"
cp "${SCRIPT_DIR}/quota-hub" "${TARGET_DIR}/"
chmod +x "${TARGET_DIR}/quota-hub" "${TARGET_DIR}/quota-hub.py"

ln -sf "${TARGET_DIR}/quota-hub" "${BIN_DIR}/quota-hub"

sed -e "s|^Exec=.*|Exec=${BIN_DIR}/quota-hub|" \
    "${SCRIPT_DIR}/quota-hub.desktop" > "${APP_DIR}/quota-hub.desktop"
chmod +x "${APP_DIR}/quota-hub.desktop"

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "${APP_DIR}" || true
fi

echo ""
echo "✅ Installed successfully in ${TARGET_DIR}!"
echo "👉 Run via terminal: quota-hub  (or quota-hub --cli)"
if [[ ":$PATH:" != *":${HOME}/.local/bin:"* ]]; then
    echo "💡 Note: Add ~/.local/bin to your PATH if not already present:"
    echo '   export PATH="$HOME/.local/bin:$PATH"'
fi

