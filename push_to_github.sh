#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo "🚀 Enviando código para o GitHub (vh2c/gemini-gauge)..."
git push -u origin main

echo "🏷️ Criando tag v1.0.0..."
git tag -f v1.0.0
git push -f origin v1.0.0

echo "✅ Código e tags enviados com sucesso!"
