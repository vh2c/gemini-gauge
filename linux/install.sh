#!/usr/bin/env bash
set -e

echo "=========================================================="
echo " ⚡ Gemini Gauge - AI Quota Monitor (Linux Auto-Installer)"
echo " Developed by VH2C • https://vh2c.com.br"
echo "=========================================================="
echo ""

TARGET_DIR="${HOME}/.local/share/universal-ai-quota"
BIN_DIR="${HOME}/.local/bin"
APP_DIR="${HOME}/.local/share/applications"
ICON_DIR="${HOME}/.local/share/icons/hicolor/512x512/apps"

mkdir -p "${TARGET_DIR}" "${TARGET_DIR}/bin" "${BIN_DIR}" "${APP_DIR}" "${ICON_DIR}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 1. Detect architecture
ARCH_RAW="$(uname -m)"
case "${ARCH_RAW}" in
    x86_64) ARCH="x64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    armv7l) ARCH="armv7l" ;;
    *) ARCH="x64" ;;
esac

# 2. Helper to run commands with sudo if not root
run_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        echo "🔐 Solicitando permissão de administrador (sudo) para instalar dependências..."
        sudo "$@"
    else
        echo "❌ Permissão de root/sudo necessária para instalar pacotes do sistema."
        return 1
    fi
}

# 3. Detect Distro Package Manager
PKG_MANAGER=""
if command -v apt-get >/dev/null 2>&1; then
    PKG_MANAGER="apt"
elif command -v dnf >/dev/null 2>&1; then
    PKG_MANAGER="dnf"
elif command -v pacman >/dev/null 2>&1; then
    PKG_MANAGER="pacman"
elif command -v zypper >/dev/null 2>&1; then
    PKG_MANAGER="zypper"
fi

# 4. Check and install Python 3
if ! command -v python3 >/dev/null 2>&1; then
    echo "📦 Python 3 não encontrado. Instalando..."
    case "${PKG_MANAGER}" in
        apt) run_as_root apt-get update && run_as_root apt-get install -y python3 ;;
        dnf) run_as_root dnf install -y python3 ;;
        pacman) run_as_root pacman -S --noconfirm python ;;
        zypper) run_as_root zypper install -y python3 ;;
        *) echo "⚠️ Não foi possível identificar o gerenciador de pacotes para instalar python3." ;;
    esac
else
    echo "✅ Python 3 detectado: $(python3 --version)"
fi

# 5. Check and install Python Tkinter (required for GUI)
if ! python3 -c "import tkinter" >/dev/null 2>&1; then
    echo "📦 Interface gráfica (Tkinter) não encontrada. Instalando python3-tk..."
    case "${PKG_MANAGER}" in
        apt) run_as_root apt-get update && run_as_root apt-get install -y python3-tk ;;
        dnf) run_as_root dnf install -y python3-tkinter ;;
        pacman) run_as_root pacman -S --noconfirm tk ;;
        zypper) run_as_root zypper install -y python3-tk ;;
        *) echo "⚠️ Instale o pacote Tkinter manualmente para sua distribuição (ex: sudo apt install python3-tk)." ;;
    esac
else
    echo "✅ Tkinter (GUI) detectado e funcionando."
fi

# 6. Check and configure Node.js (multi-provider engine)
NODE_AVAILABLE=0
if command -v node >/dev/null 2>&1; then
    NODE_VER="$(node -v 2>/dev/null || echo '')"
    echo "✅ Node.js detectado no sistema: ${NODE_VER}"
    NODE_AVAILABLE=1
elif [ -x "${TARGET_DIR}/bin/node" ]; then
    echo "✅ Node.js portátil detectado em ${TARGET_DIR}/bin/node"
    NODE_AVAILABLE=1
fi

if [ "${NODE_AVAILABLE}" -eq 0 ]; then
    echo ""
    echo "📦 Node.js não foi encontrado no sistema."
    echo "⚡ Baixando versão portátil do Node.js v20 LTS diretamente para a pasta do Gemini Gauge..."
    echo "   (Zero interferência no sistema e não requer senha de sudo!)"
    
    NODE_VERSION="v20.18.0"
    NODE_URL="https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-${ARCH}.tar.xz"
    TMP_DIR="$(mktemp -d)"
    
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "${NODE_URL}" -o "${TMP_DIR}/node.tar.xz"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "${TMP_DIR}/node.tar.xz" "${NODE_URL}"
    else
        echo "❌ curl ou wget necessário para baixar o Node.js portátil."
    fi

    if [ -f "${TMP_DIR}/node.tar.xz" ]; then
        tar -xJf "${TMP_DIR}/node.tar.xz" -C "${TARGET_DIR}/bin" --strip-components=2 "node-${NODE_VERSION}-linux-${ARCH}/bin/node" || true
        rm -rf "${TMP_DIR}"
        chmod +x "${TARGET_DIR}/bin/node"
        echo "✅ Node.js portátil v20 configurado com sucesso em ${TARGET_DIR}/bin/node!"
    else
        echo "⚠️ Tentando instalar via gerenciador de pacotes do sistema..."
        case "${PKG_MANAGER}" in
            apt) run_as_root apt-get update && run_as_root apt-get install -y nodejs ;;
            dnf) run_as_root dnf install -y nodejs ;;
            pacman) run_as_root pacman -S --noconfirm nodejs ;;
            zypper) run_as_root zypper install -y nodejs ;;
        esac
    fi
fi

# 7. Install Gemini Gauge application files
echo ""
echo "🚀 Instalando arquivos do Gemini Gauge..."
cp -r "${REPO_DIR}/core" "${TARGET_DIR}/"
cp "${SCRIPT_DIR}/quota-hub.py" "${TARGET_DIR}/"
cp "${SCRIPT_DIR}/quota-hub" "${TARGET_DIR}/"

if [ -f "${SCRIPT_DIR}/icon.png" ]; then
    cp "${SCRIPT_DIR}/icon.png" "${TARGET_DIR}/icon.png"
    cp "${SCRIPT_DIR}/icon.png" "${ICON_DIR}/gemini-gauge.png"
elif [ -f "${REPO_DIR}/assets/icon.png" ]; then
    cp "${REPO_DIR}/assets/icon.png" "${TARGET_DIR}/icon.png"
    cp "${REPO_DIR}/assets/icon.png" "${ICON_DIR}/gemini-gauge.png"
fi

chmod +x "${TARGET_DIR}/quota-hub" "${TARGET_DIR}/quota-hub.py"

# Symlink to ~/.local/bin/quota-hub and ~/.local/bin/gemini-gauge
ln -sf "${TARGET_DIR}/quota-hub" "${BIN_DIR}/quota-hub"
ln -sf "${TARGET_DIR}/quota-hub" "${BIN_DIR}/gemini-gauge"

# Desktop launcher entry
sed -e "s|^Exec=.*|Exec=${BIN_DIR}/gemini-gauge|" \
    -e "s|^Icon=.*|Icon=${TARGET_DIR}/icon.png|" \
    "${SCRIPT_DIR}/quota-hub.desktop" > "${APP_DIR}/gemini-gauge.desktop"
chmod +x "${APP_DIR}/gemini-gauge.desktop"

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "${APP_DIR}" || true
fi

echo ""
echo "=========================================================="
echo " 🎉 Instalação concluída com sucesso!"
echo "=========================================================="
echo "👉 Para abrir a interface gráfica:"
echo "   - Clique no ícone 'Gemini Gauge' no menu de aplicativos do Linux"
echo "   - Ou digite no terminal: gemini-gauge (ou quota-hub)"
echo ""
echo "👉 Para ver as cotas no terminal (modo texto rápido / SSH):"
echo "   gemini-gauge --cli"
echo "=========================================================="
if [[ ":$PATH:" != *":${HOME}/.local/bin:"* ]]; then
    echo "💡 Dica: Adicione ~/.local/bin ao seu PATH no terminal se ainda não estiver:"
    echo '   export PATH="$HOME/.local/bin:$PATH"'
fi
echo ""
