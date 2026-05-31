#!/usr/bin/env bash
# SmartConnect — Settings & autostart (lib/settings.sh)

# ─── Autostart via .bashrc / .bash_profile ───────────────────────────────────
AUTOSTART_MARKER="# smartconnect-autostart"
AUTOSTART_SNIPPET="${AUTOSTART_MARKER}
if command -v smartconnect &>/dev/null; then
    smartconnect
fi"

enable_autostart() {
    local shell_rc
    shell_rc=$(detect_shell_rc)

    # Remove any existing block first
    disable_autostart_silent

    printf '\n%s\n' "$AUTOSTART_SNIPPET" >> "$shell_rc"
    msg_ok "$L_SET_AUTOSTART_ON"
    log_sys "Autostart enabled in $shell_rc"
}

disable_autostart_silent() {
    local shell_rc
    shell_rc=$(detect_shell_rc)
    [[ ! -f "$shell_rc" ]] && return

    # Remove block between marker and closing fi
    local tmp
    tmp=$(mktemp)
    awk "/${AUTOSTART_MARKER//\//\\/}/{found=1} !found{print} /^fi$/{if(found) found=0}" \
        "$shell_rc" > "$tmp" && mv "$tmp" "$shell_rc"
}

disable_autostart() {
    disable_autostart_silent
    msg_ok "$L_SET_AUTOSTART_OFF"
    log_sys "Autostart disabled"
}

detect_shell_rc() {
    local shell_name
    shell_name=$(basename "${SHELL:-/bin/bash}")
    case "$shell_name" in
        zsh)   echo "${ZDOTDIR:-$HOME}/.zshrc" ;;
        fish)  echo "${HOME}/.config/fish/config.fish" ;;
        *)     echo "${HOME}/.bashrc" ;;
    esac
}

check_autostart_enabled() {
    local shell_rc
    shell_rc=$(detect_shell_rc)
    [[ -f "$shell_rc" ]] && grep -q "$AUTOSTART_MARKER" "$shell_rc"
}

# ─── Custom MOTD ─────────────────────────────────────────────────────────────
MOTD_SCRIPT="/etc/profile.d/smartconnect-motd.sh"
MOTD_USER_SCRIPT="${HOME}/.smartconnect/motd.sh"

write_motd_script() {
    cat > "$MOTD_USER_SCRIPT" <<'MOTDEOF'
#!/usr/bin/env bash
# SmartConnect MOTD — auto-generated

SC_CONFIG="${HOME}/.smartconnect/config"
SC_PID_FILE="${HOME}/.smartconnect/run/core.pid"
SC_ACTIVE_NODE="${HOME}/.smartconnect/active_node"

load_config() {
    SC_LANG="en"; SC_CORE="xray"; SC_SOCKS_PORT="10808"; SC_HTTP_PORT="10809"
    [[ -f "$SC_CONFIG" ]] && source "$SC_CONFIG"
}

is_connected() {
    [[ -f "$SC_PID_FILE" ]] || return 1
    local pid; pid=$(cat "$SC_PID_FILE" 2>/dev/null)
    [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

load_config

# Colors
R='\033[0m'; B='\033[1m'; G='\033[1;32m'; C='\033[1;36m'; Y='\033[1;33m'; RED='\033[1;31m'

echo ""
echo -e "${C}╔══════════════════════════════════════╗${R}"
echo -e "${C}║${B}       SmartConnect                   ${C}║${R}"
echo -e "${C}║${R}  WireGuard → VLESS Tunnel Manager    ${C}║${R}"
echo -e "${C}╚══════════════════════════════════════╝${R}"
echo ""

if is_connected; then
    echo -e "  Status:  ${G}● CONNECTED${R}"
else
    echo -e "  Status:  ${RED}○ DISCONNECTED${R}"
fi

node=$(cat "$SC_ACTIVE_NODE" 2>/dev/null || echo "—")
echo -e "  Node:    ${C}${node}${R}"
echo -e "  Core:    ${Y}${SC_CORE}${R}"
echo -e "  SOCKS5:  127.0.0.1:${SC_SOCKS_PORT}"
echo -e "  HTTP:    127.0.0.1:${SC_HTTP_PORT}"
echo ""
echo -e "  ${B}Run 'smartconnect' to open the manager${R}"
echo ""
MOTDEOF
    chmod +x "$MOTD_USER_SCRIPT"
}

enable_motd() {
    write_motd_script

    # Hook into shell rc
    local shell_rc
    shell_rc=$(detect_shell_rc)
    local marker="# smartconnect-motd"

    if ! grep -q "$marker" "$shell_rc" 2>/dev/null; then
        cat >> "$shell_rc" <<MOTDHOOK

${marker}
[[ -f "${MOTD_USER_SCRIPT}" ]] && bash "${MOTD_USER_SCRIPT}"
MOTDHOOK
    fi

    msg_ok "$L_SET_MOTD_ON"
    log_sys "MOTD enabled"
}

disable_motd() {
    local shell_rc
    shell_rc=$(detect_shell_rc)
    local marker="# smartconnect-motd"

    if grep -q "$marker" "$shell_rc" 2>/dev/null; then
        local tmp
        tmp=$(mktemp)
        grep -v "$marker\|MOTD_USER_SCRIPT\|smartconnect/motd.sh" "$shell_rc" > "$tmp" && mv "$tmp" "$shell_rc"
    fi

    msg_ok "$L_SET_MOTD_OFF"
    log_sys "MOTD disabled"
}

# ─── Logs menu ───────────────────────────────────────────────────────────────
menu_logs() {
    while true; do
        draw_header
        draw_status_bar
        printf "\n${C_BBLUE}  %s${C_RESET}\n\n" "$L_LOG_TITLE"

        printf "  ${C_BYELLOW}1${C_RESET}  %s\n" "$L_LOG_CORE"
        printf "  ${C_BYELLOW}2${C_RESET}  %s\n" "$L_LOG_SYS"
        printf "  ${C_BYELLOW}3${C_RESET}  %s\n" "$L_LOG_CLEAR"
        printf "  ${C_BYELLOW}0${C_RESET}  %s\n\n" "$L_MENU_BACK"

        menu_prompt "$L_MENU_CHOOSE"
        read -r choice
        case "$choice" in
            1)
                printf "${C_BCYAN}${L_LOG_ENTER_N}${C_RESET} "
                read -r n; n="${n:-50}"
                draw_header
                printf "\n${C_BBLUE}[Core Log — last %s lines]${C_RESET}\n" "$n"
                draw_line "─"
                if [[ -f "$SC_CORE_LOG" ]] && [[ -s "$SC_CORE_LOG" ]]; then
                    tail -n "$n" "$SC_CORE_LOG"
                else
                    printf "${C_DIM}%s${C_RESET}\n" "$L_LOG_EMPTY"
                fi
                draw_line "─"
                press_enter
                ;;
            2)
                printf "${C_BCYAN}${L_LOG_ENTER_N}${C_RESET} "
                read -r n; n="${n:-50}"
                draw_header
                printf "\n${C_BBLUE}[System Log — last %s lines]${C_RESET}\n" "$n"
                draw_line "─"
                if [[ -f "$SC_SYS_LOG" ]] && [[ -s "$SC_SYS_LOG" ]]; then
                    tail -n "$n" "$SC_SYS_LOG"
                else
                    printf "${C_DIM}%s${C_RESET}\n" "$L_LOG_EMPTY"
                fi
                draw_line "─"
                press_enter
                ;;
            3)
                if confirm "$L_CONFIRM"; then
                    > "$SC_CORE_LOG" 2>/dev/null
                    > "$SC_SYS_LOG" 2>/dev/null
                    msg_ok "$L_LOG_CLEARED"
                fi
                press_enter
                ;;
            0|"") return ;;
            *) msg_warn "$L_INVALID"; sleep 1 ;;
        esac
    done
}

# ─── Settings menu ────────────────────────────────────────────────────────────
menu_settings() {
    while true; do
        draw_header
        draw_status_bar
        printf "\n${C_BBLUE}  %s${C_RESET}\n\n" "$L_SET_TITLE"

        local autostart_state motd_state
        check_autostart_enabled && autostart_state="${C_BGREEN}${L_STATUS_ON}${C_RESET}" || autostart_state="${C_DIM}${L_STATUS_OFF}${C_RESET}"
        [[ "$SC_MOTD" == "true" ]] && motd_state="${C_BGREEN}${L_STATUS_ON}${C_RESET}" || motd_state="${C_DIM}${L_STATUS_OFF}${C_RESET}"

        printf "  ${C_BYELLOW}1${C_RESET}  %-35s [%b]\n" "$L_SET_AUTOSTART"   "$autostart_state"
        printf "  ${C_BYELLOW}2${C_RESET}  %-35s [%b]\n" "$L_SET_MOTD"        "$motd_state"
        printf "  ${C_BYELLOW}3${C_RESET}  %-35s [${C_CYAN}%s${C_RESET}]\n"   "$L_SET_LANGUAGE"    "$SC_LANG"
        printf "  ${C_BYELLOW}4${C_RESET}  %-35s [${C_CYAN}%s${C_RESET}]\n"   "$L_SET_CORE"        "$SC_CORE"
        printf "  ${C_BYELLOW}5${C_RESET}  %-35s [${C_CYAN}%s${C_RESET}]\n"   "$L_SET_SOCKS_PORT"  "$SC_SOCKS_PORT"
        printf "  ${C_BYELLOW}6${C_RESET}  %-35s [${C_CYAN}%s${C_RESET}]\n"   "$L_SET_HTTP_PORT"   "$SC_HTTP_PORT"
        printf "  ${C_BYELLOW}0${C_RESET}  %s\n\n" "$L_MENU_BACK"

        menu_prompt "$L_MENU_CHOOSE"
        read -r choice
        case "$choice" in
            1)
                if check_autostart_enabled; then
                    disable_autostart
                    SC_AUTOSTART="false"
                else
                    enable_autostart
                    SC_AUTOSTART="true"
                fi
                save_config
                press_enter
                ;;
            2)
                if [[ "$SC_MOTD" == "true" ]]; then
                    disable_motd
                    SC_MOTD="false"
                else
                    enable_motd
                    SC_MOTD="true"
                fi
                save_config
                press_enter
                ;;
            3)
                printf "\n  ${C_BYELLOW}1${C_RESET}  English\n  ${C_BYELLOW}2${C_RESET}  Русский\n\n"
                menu_prompt "$L_MENU_CHOOSE"
                read -r lc
                case "$lc" in
                    1) SC_LANG="en" ;;
                    2) SC_LANG="ru" ;;
                    *) msg_warn "$L_INVALID"; sleep 1; continue ;;
                esac
                save_config
                load_locale
                msg_ok "$L_SET_SAVED"
                sleep 1
                ;;
            4)
                printf "\n  ${C_BYELLOW}1${C_RESET}  xray\n  ${C_BYELLOW}2${C_RESET}  singbox\n  ${C_BYELLOW}3${C_RESET}  v2ray\n\n"
                menu_prompt "$L_MENU_CHOOSE"
                read -r cc
                case "$cc" in
                    1) SC_CORE="xray" ;;
                    2) SC_CORE="singbox" ;;
                    3) SC_CORE="v2ray" ;;
                    *) msg_warn "$L_INVALID"; sleep 1; continue ;;
                esac
                save_config; msg_ok "$L_SET_SAVED"; sleep 1
                ;;
            5)
                printf "${C_BCYAN}${L_SET_ENTER_PORT}${C_RESET} "
                read -r p
                [[ "$p" =~ ^[0-9]+$ ]] && SC_SOCKS_PORT="$p" && save_config && msg_ok "$L_SET_SAVED" || msg_warn "$L_INVALID"
                sleep 1
                ;;
            6)
                printf "${C_BCYAN}${L_SET_ENTER_PORT}${C_RESET} "
                read -r p
                [[ "$p" =~ ^[0-9]+$ ]] && SC_HTTP_PORT="$p" && save_config && msg_ok "$L_SET_SAVED" || msg_warn "$L_INVALID"
                sleep 1
                ;;
            0|"") return ;;
            *) msg_warn "$L_INVALID"; sleep 1 ;;
        esac
    done
}
