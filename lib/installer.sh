#!/usr/bin/env bash
# SmartConnect — VPN Core installer (lib/installer.sh)

XRAY_INSTALL_DIR="/usr/local/bin"
XRAY_RELEASE_API="https://api.github.com/repos/XTLS/Xray-core/releases/latest"
SINGBOX_RELEASE_API="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
V2RAY_RELEASE_API="https://api.github.com/repos/v2fly/v2ray-core/releases/latest"

# ─── Detect arch ─────────────────────────────────────────────────────────────
get_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)   echo "64" ;;
        aarch64|arm64)  echo "arm64-v8a" ;;
        armv7*)          echo "arm32-v7a" ;;
        *)               echo "64" ;;
    esac
}

get_arch_singbox() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)   echo "amd64" ;;
        aarch64|arm64)  echo "arm64" ;;
        armv7*)          echo "armv7" ;;
        *)               echo "amd64" ;;
    esac
}

# ─── Check installed versions ────────────────────────────────────────────────
check_xray_version() {
    if command -v xray &>/dev/null; then
        xray version 2>/dev/null | head -1 | awk '{print $2}'
    else
        echo ""
    fi
}

check_singbox_version() {
    if command -v sing-box &>/dev/null; then
        sing-box version 2>/dev/null | head -1 | awk '{print $3}'
    else
        echo ""
    fi
}

check_v2ray_version() {
    if command -v v2ray &>/dev/null; then
        v2ray version 2>/dev/null | head -1 | awk '{print $2}'
    else
        echo ""
    fi
}

# ─── Install xray-core ───────────────────────────────────────────────────────
install_xray() {
    msg_step "${L_CORE_INSTALLING} xray-core..."
    local arch
    arch=$(get_arch)
    local tmpdir
    tmpdir=$(mktemp -d)

    # get latest release URL
    local release_url
    release_url=$(curl -s "$XRAY_RELEASE_API" | \
        grep "browser_download_url" | \
        grep -i "Xray-linux-${arch}\.zip" | \
        head -1 | \
        cut -d '"' -f 4)

    if [[ -z "$release_url" ]]; then
        msg_err "${L_CORE_FAILED}: could not fetch xray release URL"
        rm -rf "$tmpdir"
        return 1
    fi

    msg_step "Downloading: $release_url"
    wget -q --show-progress -O "${tmpdir}/xray.zip" "$release_url" || {
        msg_err "${L_CORE_FAILED}: download error"
        rm -rf "$tmpdir"
        return 1
    }

    unzip -q "${tmpdir}/xray.zip" -d "${tmpdir}/xray" || {
        msg_err "${L_CORE_FAILED}: unzip error"
        rm -rf "$tmpdir"
        return 1
    }

    sudo install -m 755 "${tmpdir}/xray/xray" "${XRAY_INSTALL_DIR}/xray" || {
        msg_err "${L_CORE_FAILED}: install error (need sudo)"
        rm -rf "$tmpdir"
        return 1
    }

    rm -rf "$tmpdir"
    msg_ok "${L_CORE_DONE}: xray $(check_xray_version)"
    log_sys "xray-core installed: $(check_xray_version)"
}

# ─── Install sing-box ────────────────────────────────────────────────────────
install_singbox() {
    msg_step "${L_CORE_INSTALLING} sing-box..."
    local arch
    arch=$(get_arch_singbox)
    local tmpdir
    tmpdir=$(mktemp -d)

    local release_json
    release_json=$(curl -s "$SINGBOX_RELEASE_API")
    local version
    version=$(echo "$release_json" | grep '"tag_name"' | head -1 | cut -d'"' -f4 | tr -d 'v')

    local release_url
    release_url=$(echo "$release_json" | \
        grep "browser_download_url" | \
        grep -i "linux-${arch}\.tar\.gz" | \
        head -1 | \
        cut -d '"' -f 4)

    if [[ -z "$release_url" ]]; then
        msg_err "${L_CORE_FAILED}: could not fetch sing-box release URL"
        rm -rf "$tmpdir"
        return 1
    fi

    msg_step "Downloading: $release_url"
    wget -q --show-progress -O "${tmpdir}/singbox.tar.gz" "$release_url" || {
        msg_err "${L_CORE_FAILED}: download error"
        rm -rf "$tmpdir"
        return 1
    }

    tar -xzf "${tmpdir}/singbox.tar.gz" -C "${tmpdir}/" || {
        msg_err "${L_CORE_FAILED}: extract error"
        rm -rf "$tmpdir"
        return 1
    }

    local binary
    binary=$(find "${tmpdir}" -name "sing-box" -type f | head -1)
    if [[ -z "$binary" ]]; then
        msg_err "${L_CORE_FAILED}: binary not found"
        rm -rf "$tmpdir"
        return 1
    fi

    sudo install -m 755 "$binary" "${XRAY_INSTALL_DIR}/sing-box" || {
        msg_err "${L_CORE_FAILED}: install error"
        rm -rf "$tmpdir"
        return 1
    }

    rm -rf "$tmpdir"
    msg_ok "${L_CORE_DONE}: sing-box $(check_singbox_version)"
    log_sys "sing-box installed: $(check_singbox_version)"
}

# ─── Install v2ray-core ──────────────────────────────────────────────────────
install_v2ray() {
    msg_step "${L_CORE_INSTALLING} v2ray-core..."
    local arch
    arch=$(get_arch)
    local tmpdir
    tmpdir=$(mktemp -d)

    local release_url
    release_url=$(curl -s "$V2RAY_RELEASE_API" | \
        grep "browser_download_url" | \
        grep -i "v2ray-linux-${arch}\.zip" | \
        head -1 | \
        cut -d '"' -f 4)

    if [[ -z "$release_url" ]]; then
        msg_err "${L_CORE_FAILED}: could not fetch v2ray release URL"
        rm -rf "$tmpdir"
        return 1
    fi

    msg_step "Downloading: $release_url"
    wget -q --show-progress -O "${tmpdir}/v2ray.zip" "$release_url" || {
        msg_err "${L_CORE_FAILED}: download error"
        rm -rf "$tmpdir"
        return 1
    }

    unzip -q "${tmpdir}/v2ray.zip" -d "${tmpdir}/v2ray" || {
        msg_err "${L_CORE_FAILED}: unzip error"
        rm -rf "$tmpdir"
        return 1
    }

    sudo install -m 755 "${tmpdir}/v2ray/v2ray" "${XRAY_INSTALL_DIR}/v2ray" || {
        msg_err "${L_CORE_FAILED}: install error"
        rm -rf "$tmpdir"
        return 1
    }

    rm -rf "$tmpdir"
    msg_ok "${L_CORE_DONE}: v2ray $(check_v2ray_version)"
    log_sys "v2ray installed: $(check_v2ray_version)"
}

# ─── Menu: install core ──────────────────────────────────────────────────────
menu_install_core() {
    while true; do
        draw_header
        draw_status_bar
        printf "\n${C_BBLUE}  %s${C_RESET}\n\n" "$L_CORE_TITLE"

        msg_info "$L_CORE_CHECKING"
        local xv sv vv
        xv=$(check_xray_version)
        sv=$(check_singbox_version)
        vv=$(check_v2ray_version)

        local xs ss vs
        [[ -n "$xv" ]] && xs="${C_GREEN}${L_CORE_INSTALLED} (${xv})${C_RESET}" || xs="${C_RED}${L_CORE_NOT_INSTALLED}${C_RESET}"
        [[ -n "$sv" ]] && ss="${C_GREEN}${L_CORE_INSTALLED} (${sv})${C_RESET}" || ss="${C_RED}${L_CORE_NOT_INSTALLED}${C_RESET}"
        [[ -n "$vv" ]] && vs="${C_GREEN}${L_CORE_INSTALLED} (${vv})${C_RESET}" || vs="${C_RED}${L_CORE_NOT_INSTALLED}${C_RESET}"

        printf "  ${C_BYELLOW}1${C_RESET}  %-30s %b\n" "${L_CORE_XRAY}" "$xs"
        printf "  ${C_BYELLOW}2${C_RESET}  %-30s %b\n" "${L_CORE_SINGBOX}" "$ss"
        printf "  ${C_BYELLOW}3${C_RESET}  %-30s %b\n" "${L_CORE_V2RAY}" "$vs"
        printf "  ${C_BYELLOW}4${C_RESET}  %s\n" "${L_CORE_ALL}"
        printf "  ${C_BYELLOW}0${C_RESET}  %s\n\n" "${L_MENU_BACK}"

        menu_prompt "$L_MENU_CHOOSE"
        read -r choice
        case "$choice" in
            1) install_xray; press_enter ;;
            2) install_singbox; press_enter ;;
            3) install_v2ray; press_enter ;;
            4) install_xray; install_singbox; install_v2ray; press_enter ;;
            0|"") return ;;
            *) msg_warn "$L_INVALID"; sleep 1 ;;
        esac
    done
}
