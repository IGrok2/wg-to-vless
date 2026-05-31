#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════╗
# ║  SmartConnect — One-line Installer                                   ║
# ║                                                                      ║
# ║  curl -fsSL https://raw.githubusercontent.com/IGrok2/wg-to-vless/  ║
# ║       main/install.sh | bash                                         ║
# ╚══════════════════════════════════════════════════════════════════════╝
set -euo pipefail

REPO="IGrok2/wg-to-vless"
BRANCH="main"
INSTALL_DIR="/usr/local/lib/smartconnect"
BIN_LINK="/usr/local/bin/smartconnect"
ARCHIVE_URL="https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz"

# ─── Colors ──────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    R='\033[0m' B='\033[1m' G='\033[1;32m' C='\033[1;36m'
    Y='\033[1;33m' RED='\033[1;31m' DIM='\033[2m'
else
    R='' B='' G='' C='' Y='' RED='' DIM=''
fi

step() { printf "${C}  →${R}  %s\n" "$*"; }
ok()   { printf "${G}  ✓${R}  %s\n" "$*"; }
err()  { printf "${RED}  ✗${R}  %s\n" "$*" >&2; exit 1; }
warn() { printf "${Y}  !${R}  %s\n" "$*"; }
nl()   { echo ""; }

# ─── Banner ──────────────────────────────────────────────────────────────────
nl
printf "${C}${B}  ╔══════════════════════════════════════════╗\n"
printf       "  ║   SmartConnect  —  Installer              ║\n"
printf       "  ║   WireGuard → VLESS Tunnel Manager        ║\n"
printf       "  ╚══════════════════════════════════════════╝${R}\n"
nl

# ─── Sudo ────────────────────────────────────────────────────────────────────
SUDO=""
if [[ $EUID -ne 0 ]]; then
    command -v sudo &>/dev/null && SUDO="sudo" && sudo -v 2>/dev/null || true
fi

# ─── OS / package manager detection ─────────────────────────────────────────
OS_ID="linux"
[[ -f /etc/os-release ]] && source /etc/os-release && OS_ID="${ID:-linux}"
[[ "$(uname)" == "Darwin" ]] && OS_ID="macos"

PM="unknown"
for _pm in apt-get dnf yum pacman apk brew; do
    command -v "$_pm" &>/dev/null && PM="$_pm" && break
done

ARCH=$(uname -m)
step "OS: ${OS_ID}  arch: ${ARCH}  pkg: ${PM}"

# ─── System dependencies ─────────────────────────────────────────────────────
install_system_deps() {
    local pkgs=(curl wget jq unzip python3 wireguard-tools)
    step "Installing system packages: ${pkgs[*]}"
    case "$PM" in
        apt-get) $SUDO apt-get update -qq && $SUDO apt-get install -y "${pkgs[@]}" ;;
        dnf)     $SUDO dnf install -y "${pkgs[@]}" ;;
        yum)     $SUDO yum install -y "${pkgs[@]}" ;;
        pacman)  $SUDO pacman -Sy --noconfirm "${pkgs[@]}" ;;
        apk)     $SUDO apk add --no-cache "${pkgs[@]}" ;;
        brew)    brew install "${pkgs[@]}" 2>/dev/null || true ;;
        *)       warn "Unknown package manager — install manually: ${pkgs[*]}" ;;
    esac
    ok "System deps ready"
}

# ─── Download & install SmartConnect ─────────────────────────────────────────
install_smartconnect() {
    step "Downloading SmartConnect from GitHub (${REPO})..."
    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT

    if command -v curl &>/dev/null; then
        curl -fsSL "$ARCHIVE_URL" -o "${tmpdir}/sc.tar.gz" || err "Download failed"
    else
        wget -q "$ARCHIVE_URL" -O "${tmpdir}/sc.tar.gz" || err "Download failed"
    fi

    step "Extracting..."
    tar -xzf "${tmpdir}/sc.tar.gz" -C "${tmpdir}/"

    local src
    src=$(find "${tmpdir}" -maxdepth 1 -type d -name "wg-to-vless-*" | head -1)
    [[ -z "$src" ]] && err "Cannot find extracted directory"

    step "Installing to ${INSTALL_DIR}..."
    $SUDO mkdir -p "$INSTALL_DIR"
    $SUDO cp -r "${src}/lib"    "${INSTALL_DIR}/"
    $SUDO cp -r "${src}/locale" "${INSTALL_DIR}/"
    $SUDO cp    "${src}/smartconnect" "${INSTALL_DIR}/smartconnect"

    # systemd unit
    if command -v systemctl &>/dev/null && [[ -d /etc/systemd/system ]]; then
        $SUDO cp "${src}/systemd/smartconnect@.service" /etc/systemd/system/ 2>/dev/null && \
            $SUDO systemctl daemon-reload 2>/dev/null || true
    fi

    $SUDO chmod +x "${INSTALL_DIR}/smartconnect"
    $SUDO chmod +x "${INSTALL_DIR}/lib/"*.sh
    $SUDO chmod +x "${INSTALL_DIR}/locale/"*.sh
    $SUDO ln -sf "${INSTALL_DIR}/smartconnect" "$BIN_LINK"
    ok "SmartConnect → ${BIN_LINK}"
}

# ─── Install xray-core ───────────────────────────────────────────────────────
install_xray() {
    step "Installing xray-core (latest)..."
    local arch_str
    case "$ARCH" in
        x86_64|amd64)  arch_str="64" ;;
        aarch64|arm64) arch_str="arm64-v8a" ;;
        armv7*)        arch_str="arm32-v7a" ;;
        *)             arch_str="64" ;;
    esac

    local api="https://api.github.com/repos/XTLS/Xray-core/releases/latest"
    local url
    url=$(curl -fsSL "$api" 2>/dev/null | \
        grep "browser_download_url" | \
        grep -i "Xray-linux-${arch_str}\.zip" | \
        head -1 | cut -d'"' -f4)

    [[ -z "$url" ]] && warn "Cannot fetch xray URL — install later from menu (option 8)" && return

    local tmpdir
    tmpdir=$(mktemp -d)
    curl -fsSL "$url" -o "${tmpdir}/xray.zip" || { warn "xray download failed"; rm -rf "$tmpdir"; return; }
    unzip -q "${tmpdir}/xray.zip" -d "${tmpdir}/xray"
    $SUDO install -m755 "${tmpdir}/xray/xray" /usr/local/bin/xray
    rm -rf "$tmpdir"
    ok "xray-core installed: $(xray version 2>/dev/null | head -1 || echo 'ok')"
}

# ─── Init user config ────────────────────────────────────────────────────────
init_config() {
    local d="${HOME}/.smartconnect"
    mkdir -p "${d}/nodes" "${d}/subscriptions" "${d}/wireguard" "${d}/run" "${d}/logs"
    chmod 700 "$d" "${d}/wireguard"
    if [[ ! -f "${d}/config" ]]; then
        cat > "${d}/config" <<'CFG'
SC_LANG="en"
SC_CORE="xray"
SC_SOCKS_PORT="10808"
SC_HTTP_PORT="10809"
SC_AUTOSTART="false"
SC_MOTD="false"
SC_WG_IFACE="wg0"
CFG
        chmod 600 "${d}/config"
    fi
    ok "Config: ${d}"
}

# ─── Done ────────────────────────────────────────────────────────────────────
print_done() {
    nl
    printf "${G}${B}  ╔══════════════════════════════════════════╗\n"
    printf         "  ║   Installation complete!  ✓               ║\n"
    printf         "  ╚══════════════════════════════════════════╝${R}\n"
    nl
    printf "  Run: ${C}${B}smartconnect${R}\n"
    nl
    printf "  ${DIM}CLI shortcuts:${R}\n"
    printf "  ${DIM}  smartconnect connect     — connect tunnel${R}\n"
    printf "  ${DIM}  smartconnect disconnect  — disconnect${R}\n"
    printf "  ${DIM}  smartconnect status      — show status${R}\n"
    nl
}

# ─── Entry point ─────────────────────────────────────────────────────────────
ACTION="${1:-install}"

case "$ACTION" in
    update)
        nl; step "Updating SmartConnect..."
        install_smartconnect
        ok "Update complete"; nl; exit 0 ;;
    uninstall)
        nl; step "Uninstalling SmartConnect..."
        $SUDO rm -f "$BIN_LINK"
        $SUDO rm -rf "$INSTALL_DIR"
        for rc in "${HOME}/.bashrc" "${HOME}/.zshrc"; do
            [[ -f "$rc" ]] && \
                sed -i '/smartconnect-autostart/,/^fi$/d; /smartconnect-motd/d; /smartconnect\/motd/d' \
                "$rc" 2>/dev/null || true
        done
        ok "Removed"; nl; exit 0 ;;
    install)
        install_system_deps
        install_smartconnect
        install_xray
        init_config
        print_done ;;
    *)
        printf "Usage: bash install.sh [install|update|uninstall]\n"; exit 1 ;;
esac