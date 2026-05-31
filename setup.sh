#!/usr/bin/env bash
# SmartConnect — Setup & install script
set -euo pipefail

INSTALL_DIR="/usr/local/lib/smartconnect"
BIN_LINK="/usr/local/bin/smartconnect"
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# Colors
R='\033[0m'; B='\033[1m'; G='\033[1;32m'; C='\033[1;36m'; Y='\033[1;33m'; RED='\033[1;31m'

step() { printf "${C}[→]${R} %s\n" "$*"; }
ok()   { printf "${G}[✓]${R} %s\n" "$*"; }
err()  { printf "${RED}[✗]${R} %s\n" "$*" >&2; exit 1; }
warn() { printf "${Y}[!]${R} %s\n" "$*"; }

echo ""
echo -e "${C}╔══════════════════════════════════════╗${R}"
echo -e "${C}║  SmartConnect — Installer             ║${R}"
echo -e "${C}║  WireGuard → VLESS Tunnel Manager     ║${R}"
echo -e "${C}╚══════════════════════════════════════╝${R}"
echo ""

# ─── Check argument ──────────────────────────────────────────────────────────
ACTION="${1:-install}"

case "$ACTION" in
    install|update)
        step "Installing SmartConnect to ${INSTALL_DIR}..."

        # Create install dir
        sudo mkdir -p "$INSTALL_DIR"
        sudo cp -r "${SCRIPT_DIR}/lib"    "${INSTALL_DIR}/"
        sudo cp -r "${SCRIPT_DIR}/locale" "${INSTALL_DIR}/"
        sudo cp    "${SCRIPT_DIR}/smartconnect" "${INSTALL_DIR}/smartconnect"
        sudo chmod +x "${INSTALL_DIR}/smartconnect"
        sudo chmod +x "${INSTALL_DIR}/lib/"*.sh
        sudo chmod +x "${INSTALL_DIR}/locale/"*.sh

        # Symlink binary
        sudo ln -sf "${INSTALL_DIR}/smartconnect" "$BIN_LINK"
        ok "Binary linked: $BIN_LINK"

        echo ""
        ok "SmartConnect installed successfully!"
        echo ""
        printf "  Run ${C}smartconnect${R} to start.\n\n"
        ;;

    uninstall)
        warn "Uninstalling SmartConnect..."
        sudo rm -f "$BIN_LINK"
        sudo rm -rf "$INSTALL_DIR"
        # Remove MOTD/autostart hooks from shell rc
        for rc in "${HOME}/.bashrc" "${HOME}/.zshrc"; do
            [[ -f "$rc" ]] && sed -i '/smartconnect-autostart/,/^fi$/d; /smartconnect-motd/d; /smartconnect\/motd/d' "$rc" 2>/dev/null || true
        done
        ok "SmartConnect removed."
        echo ""
        ;;

    *)
        echo "Usage: $0 [install|update|uninstall]"
        exit 1
        ;;
esac
