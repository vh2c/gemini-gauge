#!/usr/bin/env bash
set -e

echo "⚡ Installing Universal AI Quota Hub for Linux..."

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

echo "✅ Installed successfully!"
echo "👉 Run via terminal: 'quota-hub' (or 'quota-hub --cli')"
