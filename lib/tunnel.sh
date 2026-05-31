#!/usr/bin/env bash
# SmartConnect — Tunnel management (lib/tunnel.sh)

# ─── Generate core config from active node ───────────────────────────────────
prepare_core_config() {
    local node_name
    node_name=$(get_active_node_name)
    if [[ -z "$node_name" ]]; then
        msg_err "$L_CONN_NO_NODE"
        return 1
    fi

    # Find node file
    local node_file
    node_file=$(find "$SC_NODES_DIR" -name "*.node" -exec grep -l "NODE_NAME=\"${node_name}\"" {} \; | head -1)
    if [[ -z "$node_file" ]]; then
        # fallback: match by filename fragment
        node_file=$(find "$SC_NODES_DIR" -name "*.node" | head -1)
    fi
    [[ -z "$node_file" ]] && msg_err "$L_CONN_NO_NODE" && return 1

    case "$SC_CORE" in
        xray)    gen_xray_config "$node_file" ;;
        singbox) gen_singbox_config "$node_file" ;;
        v2ray)   gen_v2ray_config "$node_file" ;;
    esac
}

# ─── Start VPN core ──────────────────────────────────────────────────────────
start_core() {
    case "$SC_CORE" in
        xray)
            if ! command -v xray &>/dev/null; then
                msg_err "${L_CONN_FAIL_CORE}: xray not installed"
                return 1
            fi
            xray run -config "$SC_XRAY_CONF" >> "$SC_CORE_LOG" 2>&1 &
            echo $! > "$SC_PID_FILE"
            ;;
        singbox)
            if ! command -v sing-box &>/dev/null; then
                msg_err "${L_CONN_FAIL_CORE}: sing-box not installed"
                return 1
            fi
            sing-box run -c "$SC_SINGBOX_CONF" >> "$SC_CORE_LOG" 2>&1 &
            echo $! > "$SC_PID_FILE"
            ;;
        v2ray)
            if ! command -v v2ray &>/dev/null; then
                msg_err "${L_CONN_FAIL_CORE}: v2ray not installed"
                return 1
            fi
            v2ray run -config "$SC_V2RAY_CONF" >> "$SC_CORE_LOG" 2>&1 &
            echo $! > "$SC_PID_FILE"
            ;;
    esac

    # Brief wait to check if process survived
    sleep 1
    if ! is_connected; then
        msg_err "$L_CONN_FAIL_CORE"
        rm -f "$SC_PID_FILE"
        return 1
    fi
    return 0
}

# ─── Stop VPN core ───────────────────────────────────────────────────────────
stop_core() {
    msg_step "$L_CONN_VLESS_DOWN"
    if [[ -f "$SC_PID_FILE" ]]; then
        local pid
        pid=$(cat "$SC_PID_FILE")
        if [[ -n "$pid" ]]; then
            kill "$pid" 2>/dev/null
            local tries=0
            while kill -0 "$pid" 2>/dev/null && (( tries < 10 )); do
                sleep 0.3; (( tries++ ))
            done
            kill -9 "$pid" 2>/dev/null
        fi
        rm -f "$SC_PID_FILE"
    fi
}

# ─── Start WireGuard ─────────────────────────────────────────────────────────
start_wireguard() {
    if [[ ! -f "$SC_WG_CONF" ]]; then
        msg_err "$L_CONN_NO_WG"
        return 1
    fi

    msg_step "$L_CONN_WG_UP"

    # Copy conf to /etc/wireguard with proper name
    local wg_sys_conf="/etc/wireguard/${SC_WG_IFACE}.conf"
    sudo cp "$SC_WG_CONF" "$wg_sys_conf" 2>/dev/null || {
        # Try without sudo (might be running as root)
        cp "$SC_WG_CONF" "$wg_sys_conf" 2>/dev/null || {
            msg_err "$L_CONN_FAIL_WG: cannot copy to /etc/wireguard/ (need sudo)"
            return 1
        }
    }
    sudo chmod 600 "$wg_sys_conf" 2>/dev/null

    if sudo wg-quick up "$SC_WG_IFACE" 2>> "$SC_SYS_LOG"; then
        return 0
    else
        msg_err "$L_CONN_FAIL_WG"
        return 1
    fi
}

# ─── Stop WireGuard ──────────────────────────────────────────────────────────
stop_wireguard() {
    msg_step "$L_CONN_WG_DOWN"
    sudo wg-quick down "$SC_WG_IFACE" 2>> "$SC_SYS_LOG" || true
}

# ─── Full connect ─────────────────────────────────────────────────────────────
do_connect() {
    if is_connected; then
        msg_warn "$L_CONN_ALREADY"
        press_enter; return
    fi

    draw_header
    printf "\n${C_BBLUE}  %s${C_RESET}\n\n" "$L_CONN_STARTING"

    # 1. Prepare config
    msg_step "Generating core config..."
    prepare_core_config || { press_enter; return; }

    # 2. Start VLESS core (SOCKS5 proxy)
    msg_step "$L_CONN_VLESS_UP"
    start_core || { press_enter; return; }
    msg_ok "VLESS core started (PID: $(cat "$SC_PID_FILE"))"

    # 3. Start WireGuard (routes through SOCKS5 via wg endpoint)
    start_wireguard || {
        stop_core
        press_enter; return
    }
    msg_ok "WireGuard up"

    local node_name
    node_name=$(get_active_node_name)
    log_sys "Connected — node: ${node_name}, core: ${SC_CORE}, WG: ${SC_WG_IFACE}"

    printf "\n"
    draw_line "─"
    msg_ok "${C_BGREEN}${L_CONN_READY}${C_RESET}"
    printf "  ${C_CYAN}SOCKS5:${C_RESET}  127.0.0.1:${SC_SOCKS_PORT}\n"
    printf "  ${C_CYAN}HTTP:${C_RESET}    127.0.0.1:${SC_HTTP_PORT}\n"
    draw_line "─"

    press_enter
}

# ─── Full disconnect ──────────────────────────────────────────────────────────
do_disconnect() {
    draw_header
    printf "\n${C_BBLUE}  %s${C_RESET}\n\n" "$L_CONN_STOPPING"

    stop_wireguard
    stop_core
    log_sys "Disconnected"

    msg_ok "$L_CONN_STOPPED"
    press_enter
}

# ─── Status screen ────────────────────────────────────────────────────────────
show_status() {
    draw_header

    printf "\n"
    if is_connected; then
        printf "  ${C_BGREEN}${L_STATUS_CONNECTED}${C_RESET}\n"

        # Uptime
        if [[ -f "$SC_PID_FILE" ]]; then
            local pid
            pid=$(cat "$SC_PID_FILE")
            local uptime_sec
            uptime_sec=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ')
            if [[ -n "$uptime_sec" ]]; then
                local h=$((uptime_sec/3600)) m=$(( (uptime_sec%3600)/60 )) s=$((uptime_sec%60))
                printf "  ${C_CYAN}${L_STATUS_UPTIME}:${C_RESET}        %02d:%02d:%02d\n" "$h" "$m" "$s"
            fi
        fi

        # External IP via SOCKS5
        printf "  ${C_CYAN}${L_CONN_CHECKING}${C_RESET}\n"
        local ext_ip
        ext_ip=$(curl -s --socks5 "127.0.0.1:${SC_SOCKS_PORT}" --max-time 5 \
            "https://api.ipify.org" 2>/dev/null || echo "—")
        printf "  ${C_CYAN}${L_CONN_IP}:${C_RESET}       ${C_BWHITE}%s${C_RESET}\n" "$ext_ip"
    else
        printf "  ${C_RED}${L_STATUS_DISCONNECTED}${C_RESET}\n"
    fi

    draw_line "─"
    printf "  ${C_CYAN}${L_STATUS_ACTIVE_NODE}:${C_RESET}  %s\n" "$(get_active_node_name || echo "${L_STATUS_NONE}")"
    printf "  ${C_CYAN}${L_STATUS_CORE}:${C_RESET}         %s\n" "$SC_CORE"
    printf "  ${C_CYAN}${L_STATUS_WG_IFACE}:${C_RESET}  %s\n" "$SC_WG_IFACE"
    printf "  ${C_CYAN}${L_STATUS_LOCAL_SOCKS}:${C_RESET}  127.0.0.1:%s\n" "$SC_SOCKS_PORT"
    printf "  ${C_CYAN}${L_STATUS_LOCAL_HTTP}:${C_RESET}   127.0.0.1:%s\n" "$SC_HTTP_PORT"
    printf "  ${C_CYAN}${L_STATUS_AUTOSTART}:${C_RESET}    %s\n" \
        "$([[ "$SC_AUTOSTART" == "true" ]] && echo "${C_BGREEN}${L_STATUS_ON}${C_RESET}" || echo "${C_DIM}${L_STATUS_OFF}${C_RESET}")"
    printf "  ${C_CYAN}${L_STATUS_LANGUAGE}:${C_RESET}      %s\n" "$SC_LANG"
    draw_line "─"

    press_enter
}
