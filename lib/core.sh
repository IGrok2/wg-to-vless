#!/usr/bin/env bash
# SmartConnect — Core library (lib/core.sh)

# ─── Paths ──────────────────────────────────────────────────────────────────
SC_DIR="${HOME}/.smartconnect"
SC_CONFIG="${SC_DIR}/config"
SC_NODES_DIR="${SC_DIR}/nodes"
SC_SUBS_DIR="${SC_DIR}/subscriptions"
SC_WG_DIR="${SC_DIR}/wireguard"
SC_RUN_DIR="${SC_DIR}/run"
SC_LOG_DIR="${SC_DIR}/logs"
SC_CORE_LOG="${SC_LOG_DIR}/core.log"
SC_SYS_LOG="${SC_LOG_DIR}/system.log"
SC_PID_FILE="${SC_RUN_DIR}/core.pid"
SC_WG_CONF="${SC_WG_DIR}/wg0.conf"
SC_ACTIVE_NODE="${SC_DIR}/active_node"
SC_XRAY_CONF="${SC_RUN_DIR}/xray.json"
SC_SINGBOX_CONF="${SC_RUN_DIR}/singbox.json"
SC_V2RAY_CONF="${SC_RUN_DIR}/v2ray.json"
SC_VERSION="1.0.0"

# ─── Colors ─────────────────────────────────────────────────────────────────
setup_colors() {
    if [[ -t 1 ]]; then
        C_RESET='\033[0m'
        C_BOLD='\033[1m'
        C_DIM='\033[2m'
        C_RED='\033[0;31m'
        C_GREEN='\033[0;32m'
        C_YELLOW='\033[0;33m'
        C_BLUE='\033[0;34m'
        C_MAGENTA='\033[0;35m'
        C_CYAN='\033[0;36m'
        C_WHITE='\033[0;37m'
        C_BRED='\033[1;31m'
        C_BGREEN='\033[1;32m'
        C_BYELLOW='\033[1;33m'
        C_BBLUE='\033[1;34m'
        C_BCYAN='\033[1;36m'
        C_BWHITE='\033[1;37m'
        C_BG_BLUE='\033[44m'
        C_BG_DARK='\033[40m'
    else
        C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW=''
        C_BLUE='' C_MAGENTA='' C_CYAN='' C_WHITE=''
        C_BRED='' C_BGREEN='' C_BYELLOW='' C_BBLUE='' C_BCYAN='' C_BWHITE=''
        C_BG_BLUE='' C_BG_DARK=''
    fi
}

# ─── Init dirs ───────────────────────────────────────────────────────────────
init_dirs() {
    mkdir -p "$SC_DIR" "$SC_NODES_DIR" "$SC_SUBS_DIR" \
             "$SC_WG_DIR" "$SC_RUN_DIR" "$SC_LOG_DIR"
    chmod 700 "$SC_DIR" "$SC_WG_DIR"
}

# ─── Config load/save ────────────────────────────────────────────────────────
load_config() {
    # Defaults
    SC_LANG="en"
    SC_CORE="xray"
    SC_SOCKS_PORT="10808"
    SC_HTTP_PORT="10809"
    SC_AUTOSTART="false"
    SC_MOTD="true"
    SC_WG_IFACE="wg0"

    [[ -f "$SC_CONFIG" ]] && source "$SC_CONFIG"
}

save_config() {
    cat > "$SC_CONFIG" <<EOF
SC_LANG="${SC_LANG}"
SC_CORE="${SC_CORE}"
SC_SOCKS_PORT="${SC_SOCKS_PORT}"
SC_HTTP_PORT="${SC_HTTP_PORT}"
SC_AUTOSTART="${SC_AUTOSTART}"
SC_MOTD="${SC_MOTD}"
SC_WG_IFACE="${SC_WG_IFACE}"
EOF
    chmod 600 "$SC_CONFIG"
}

# ─── Locale ──────────────────────────────────────────────────────────────────
load_locale() {
    local locale_file
    locale_file="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../locale/${SC_LANG}.sh"
    if [[ -f "$locale_file" ]]; then
        source "$locale_file"
    else
        source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../locale/en.sh"
    fi
}

# ─── UI primitives ───────────────────────────────────────────────────────────
term_width() { tput cols 2>/dev/null || echo 80; }

draw_line() {
    local char="${1:-─}"
    local width
    width=$(term_width)
    printf '%s' "${C_DIM}"
    printf '%*s' "$width" '' | tr ' ' "$char"
    printf '%s\n' "${C_RESET}"
}

draw_header() {
    local tw
    tw=$(term_width)
    clear
    printf '%s' "${C_BG_DARK}${C_BCYAN}"
    draw_line "═"
    printf "  %-${tw}s\n" "  ${C_BOLD}${L_TITLE}${C_RESET}${C_BG_DARK}${C_CYAN}  —  ${L_SUBTITLE}"
    printf "  ${C_DIM}${L_VERSION} ${SC_VERSION}%$((tw - ${#SC_VERSION} - ${#L_VERSION} - 4))s\n" ""
    draw_line "═"
    printf '%s' "${C_RESET}"
}

draw_status_bar() {
    local connected
    connected=$(is_connected && echo true || echo false)
    printf '%s' "${C_BG_DARK}"
    if [[ "$connected" == "true" ]]; then
        printf " ${C_BGREEN}${L_STATUS_CONNECTED}${C_RESET}${C_BG_DARK}"
    else
        printf " ${C_RED}${L_STATUS_DISCONNECTED}${C_RESET}${C_BG_DARK}"
    fi
    local node
    node=$(get_active_node_name)
    [[ -n "$node" ]] && printf "  ${C_DIM}│${C_RESET}${C_BG_DARK} ${C_CYAN}${L_STATUS_ACTIVE_NODE}:${C_RESET} ${node}"
    printf '%s\n' "${C_RESET}"
    draw_line "─"
}

menu_prompt() {
    local prompt="${1:-$L_MENU_CHOOSE}"
    printf "\n${C_BYELLOW}[?]${C_RESET} ${prompt}: "
}

msg_ok()   { printf "${C_BGREEN}[✓]${C_RESET} %s\n" "$*"; }
msg_err()  { printf "${C_BRED}[✗]${C_RESET} %s\n" "$*" >&2; }
msg_warn() { printf "${C_BYELLOW}[!]${C_RESET} %s\n" "$*"; }
msg_info() { printf "${C_BCYAN}[i]${C_RESET} %s\n" "$*"; }
msg_step() { printf "${C_BBLUE}[→]${C_RESET} %s\n" "$*"; }

press_enter() {
    printf "\n${C_DIM}${L_PRESS_ENTER}${C_RESET}"
    read -r
}

confirm() {
    local prompt="${1:-$L_CONFIRM?}"
    printf "${C_BYELLOW}[?]${C_RESET} ${prompt} [${C_GREEN}${L_YES}${C_RESET}/${C_RED}${L_NO}${C_RESET}]: "
    read -r ans
    [[ "$ans" =~ ^[YyДд]$ ]]
}

numbered_menu() {
    # Usage: numbered_menu "Title" item1 item2 ...
    local title="$1"; shift
    local items=("$@")
    printf "\n${C_BBLUE}  %s${C_RESET}\n\n" "$title"
    local i=1
    for item in "${items[@]}"; do
        printf "  ${C_BYELLOW}%2d${C_RESET}  %s\n" "$i" "$item"
        (( i++ ))
    done
    printf "\n"
}

# ─── Dependency checks ───────────────────────────────────────────────────────
check_cmd() { command -v "$1" &>/dev/null; }

require_root() {
    if [[ $EUID -ne 0 ]]; then
        msg_err "This operation requires root privileges. Run with sudo."
        return 1
    fi
}

check_deps() {
    local missing=()
    for cmd in curl wget jq wg wg-quick; do
        check_cmd "$cmd" || missing+=("$cmd")
    done
    echo "${missing[@]}"
}

install_deps() {
    local missing=("$@")
    [[ ${#missing[@]} -eq 0 ]] && return 0
    msg_step "Installing missing dependencies: ${missing[*]}"

    # pkg map
    declare -A PKG_MAP=(
        [wg]="wireguard-tools"
        [wg-quick]="wireguard-tools"
        [jq]="jq"
        [curl]="curl"
        [wget]="wget"
    )

    local pkgs=()
    for cmd in "${missing[@]}"; do
        pkg="${PKG_MAP[$cmd]:-$cmd}"
        pkgs+=("$pkg")
    done

    # deduplicate
    local -A seen; local unique=()
    for p in "${pkgs[@]}"; do
        [[ -z "${seen[$p]}" ]] && unique+=("$p") && seen[$p]=1
    done

    if check_cmd apt-get; then
        sudo apt-get update -qq && sudo apt-get install -y "${unique[@]}"
    elif check_cmd dnf; then
        sudo dnf install -y "${unique[@]}"
    elif check_cmd yum; then
        sudo yum install -y "${unique[@]}"
    elif check_cmd pacman; then
        sudo pacman -Sy --noconfirm "${unique[@]}"
    elif check_cmd apk; then
        sudo apk add "${unique[@]}"
    else
        msg_err "Cannot detect package manager. Install manually: ${unique[*]}"
        return 1
    fi
}

# ─── Node helpers ────────────────────────────────────────────────────────────
get_active_node_name() {
    [[ -f "$SC_ACTIVE_NODE" ]] && cat "$SC_ACTIVE_NODE" || echo ""
}

set_active_node() {
    echo "$1" > "$SC_ACTIVE_NODE"
}

load_node() {
    local name="$1"
    local file="${SC_NODES_DIR}/${name}.node"
    [[ -f "$file" ]] && source "$file"
}

# ─── Connection status ───────────────────────────────────────────────────────
is_connected() {
    [[ -f "$SC_PID_FILE" ]] || return 1
    local pid
    pid=$(cat "$SC_PID_FILE" 2>/dev/null)
    [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

# ─── Logging ────────────────────────────────────────────────────────────────
log_sys() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$SC_SYS_LOG"
}
