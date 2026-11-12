#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${SCRIPT_DIR}/build.sh"

echo "📲 Installing into /Applications..."
cp -R "${SCRIPT_DIR}/Universal AI Quota.app" /Applications/

echo "✅ Universal AI Quota is now installed in /Applications!"
