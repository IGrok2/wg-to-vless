#!/usr/bin/env bash
# SmartConnect — Config generators + WireGuard (lib/configs.sh)

# ─── xray-core JSON config ────────────────────────────────────────────────────
gen_xray_config() {
    local node_file="$1"
    source "$node_file" 2>/dev/null

    local stream_settings
    stream_settings=$(gen_xray_stream)

    cat > "$SC_XRAY_CONF" <<XRAYJSON
{
  "log": {
    "access": "${SC_CORE_LOG}",
    "error": "${SC_CORE_LOG}",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "socks-in",
      "port": ${SC_SOCKS_PORT},
      "listen": "127.0.0.1",
      "protocol": "socks",
      "settings": { "auth": "noauth", "udp": true }
    },
    {
      "tag": "http-in",
      "port": ${SC_HTTP_PORT},
      "listen": "127.0.0.1",
      "protocol": "http",
      "settings": {}
    }
  ],
  "outbounds": [
    {
      "tag": "vless-out",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "${NODE_HOST}",
            "port": ${NODE_PORT},
            "users": [
              {
                "id": "${NODE_UUID}",
                "encryption": "none",
                "flow": "${NODE_FLOW}"
              }
            ]
          }
        ]
      },
      "streamSettings": ${stream_settings}
    },
    {
      "tag": "direct",
      "protocol": "freedom"
    },
    {
      "tag": "block",
      "protocol": "blackhole"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "direct"
      }
    ]
  }
}
XRAYJSON
    chmod 600 "$SC_XRAY_CONF"
}

gen_xray_stream() {
    local security="${NODE_SECURITY:-none}"
    local type="${NODE_TYPE:-tcp}"

    local tls_block=""
    local reality_block=""
    local net_block=""

    case "$type" in
        ws)
            net_block='"wsSettings": {"path": "'"${NODE_PATH:-/}"'", "headers": {"Host": "'"${NODE_SNI:-$NODE_HOST}"'"}}'
            ;;
        grpc)
            net_block='"grpcSettings": {"serviceName": "'"${NODE_PATH}"'"}'
            ;;
        tcp) net_block="" ;;
        *)   net_block="" ;;
    esac

    case "$security" in
        tls)
            tls_block='"tlsSettings": {"serverName": "'"${NODE_SNI:-$NODE_HOST}"'", "allowInsecure": false, "fingerprint": "'"${NODE_FP:-chrome}"'"}'
            ;;
        reality)
            reality_block='"realitySettings": {"serverName": "'"${NODE_SNI:-$NODE_HOST}"'", "fingerprint": "'"${NODE_FP:-chrome}"'", "publicKey": "'"${NODE_PBK}"'", "shortId": "'"${NODE_SID}"'"}'
            ;;
    esac

    local extras=""
    [[ -n "$tls_block" ]]     && extras=", ${tls_block}"
    [[ -n "$reality_block" ]] && extras=", ${reality_block}"
    [[ -n "$net_block" ]]     && extras="${extras}, ${net_block}"

    echo '{"network": "'"${type:-tcp}"'", "security": "'"${security:-none}"'"'"${extras}"'}'
}

# ─── sing-box JSON config ─────────────────────────────────────────────────────
gen_singbox_config() {
    local node_file="$1"
    source "$node_file" 2>/dev/null

    local tls_block='{"enabled": false}'
    local transport_block="null"

    if [[ "$NODE_SECURITY" == "tls" ]]; then
        tls_block='{"enabled": true, "server_name": "'"${NODE_SNI:-$NODE_HOST}"'", "utls": {"enabled": true, "fingerprint": "'"${NODE_FP:-chrome}"'"}}'
    elif [[ "$NODE_SECURITY" == "reality" ]]; then
        tls_block='{"enabled": true, "server_name": "'"${NODE_SNI:-$NODE_HOST}"'", "reality": {"enabled": true, "public_key": "'"${NODE_PBK}"'", "short_id": "'"${NODE_SID}"'"}, "utls": {"enabled": true, "fingerprint": "'"${NODE_FP:-chrome}"'"}}'
    fi

    if [[ "$NODE_TYPE" == "ws" ]]; then
        transport_block='{"type": "ws", "path": "'"${NODE_PATH:-/}"'", "headers": {"Host": "'"${NODE_SNI:-$NODE_HOST}"'"}}'
    elif [[ "$NODE_TYPE" == "grpc" ]]; then
        transport_block='{"type": "grpc", "service_name": "'"${NODE_PATH}"'"}'
    fi

    cat > "$SC_SINGBOX_CONF" <<SBCONF
{
  "log": {"level": "warn", "output": "${SC_CORE_LOG}"},
  "inbounds": [
    {
      "type": "socks",
      "tag": "socks-in",
      "listen": "127.0.0.1",
      "listen_port": ${SC_SOCKS_PORT},
      "sniff": true
    },
    {
      "type": "http",
      "tag": "http-in",
      "listen": "127.0.0.1",
      "listen_port": ${SC_HTTP_PORT}
    }
  ],
  "outbounds": [
    {
      "type": "vless",
      "tag": "vless-out",
      "server": "${NODE_HOST}",
      "server_port": ${NODE_PORT},
      "uuid": "${NODE_UUID}",
      "flow": "${NODE_FLOW}",
      "tls": ${tls_block},
      "transport": ${transport_block:-null}
    },
    {"type": "direct", "tag": "direct"},
    {"type": "block", "tag": "block"}
  ],
  "route": {
    "rules": [
      {"ip_cidr": ["0.0.0.0/8","10.0.0.0/8","127.0.0.0/8","172.16.0.0/12","192.168.0.0/16"], "outbound": "direct"}
    ],
    "final": "vless-out"
  }
}
SBCONF
    chmod 600 "$SC_SINGBOX_CONF"
}

# ─── v2ray-core JSON config ───────────────────────────────────────────────────
gen_v2ray_config() {
    # v2ray uses same format as xray for vless; reuse xray gen
    gen_xray_config "$1"
    cp "$SC_XRAY_CONF" "$SC_V2RAY_CONF"
}

# ─── WireGuard menu ───────────────────────────────────────────────────────────
menu_wireguard() {
    while true; do
        draw_header
        draw_status_bar
        printf "\n${C_BBLUE}  %s${C_RESET}\n\n" "$L_WG_TITLE"

        if [[ -f "$SC_WG_CONF" ]]; then
            local iface
            iface=$(grep -m1 '^\[Interface\]' -A10 "$SC_WG_CONF" | grep -i 'address' | head -1 | awk '{print $3}')
            printf "  ${C_BGREEN}✓${C_RESET}  ${L_STATUS_WG_IFACE}: ${C_CYAN}${SC_WG_IFACE}${C_RESET}  ${C_DIM}(${iface})${C_RESET}\n\n"
        else
            printf "  ${C_RED}✗${C_RESET}  ${L_WG_NOT_FOUND}\n\n"
        fi

        printf "  ${C_BYELLOW}1${C_RESET}  %s\n" "$L_WG_IMPORT"
        printf "  ${C_BYELLOW}2${C_RESET}  %s\n" "$L_WG_PASTE"
        printf "  ${C_BYELLOW}3${C_RESET}  %s\n" "$L_WG_SHOW"
        printf "  ${C_BYELLOW}4${C_RESET}  %s\n" "$L_WG_REMOVE"
        printf "  ${C_BYELLOW}0${C_RESET}  %s\n\n" "$L_MENU_BACK"

        menu_prompt "$L_MENU_CHOOSE"
        read -r choice
        case "$choice" in
            1)
                printf "\n${C_BCYAN}%s${C_RESET}\n" "$L_WG_ENTER_PATH"
                read -r wg_path
                if [[ -f "$wg_path" ]]; then
                    cp "$wg_path" "$SC_WG_CONF"
                    chmod 600 "$SC_WG_CONF"
                    msg_ok "$L_WG_SAVED"
                    log_sys "WireGuard config imported from $wg_path"
                else
                    msg_err "$L_ERROR: file not found: $wg_path"
                fi
                press_enter
                ;;
            2)
                printf "\n${C_BCYAN}%s${C_RESET}\n" "$L_WG_PASTE_HINT"
                local wg_content=""
                while IFS= read -r line; do
                    [[ "$line" == "EOF" ]] && break
                    wg_content+="${line}"$'\n'
                done
                if [[ -n "$wg_content" ]]; then
                    echo "$wg_content" > "$SC_WG_CONF"
                    chmod 600 "$SC_WG_CONF"
                    msg_ok "$L_WG_SAVED"
                    log_sys "WireGuard config pasted manually"
                else
                    msg_warn "$L_CANCEL"
                fi
                press_enter
                ;;
            3)
                if [[ -f "$SC_WG_CONF" ]]; then
                    draw_header
                    printf "\n${C_BCYAN}[WireGuard Config]${C_RESET}\n"
                    draw_line "─"
                    # Mask private key for display
                    sed 's/\(PrivateKey\s*=\s*\).*/\1[HIDDEN]/' "$SC_WG_CONF"
                    draw_line "─"
                else
                    msg_warn "$L_WG_NOT_FOUND"
                fi
                press_enter
                ;;
            4)
                if confirm "$L_CONFIRM"; then
                    rm -f "$SC_WG_CONF"
                    msg_ok "$L_WG_REMOVED"
                    log_sys "WireGuard config removed"
                fi
                press_enter
                ;;
            0|"") return ;;
            *) msg_warn "$L_INVALID"; sleep 1 ;;
        esac
    done
}
