#!/usr/bin/env bash
# SmartConnect — Subscription manager (lib/subscriptions.sh)

# ─── Parse VLESS URI ─────────────────────────────────────────────────────────
# vless://uuid@host:port?params#name
parse_vless_uri() {
    local uri="$1"
    local out_file="$2"   # path to write .node file

    # Strip prefix
    local body="${uri#vless://}"

    # Extract fragment (name)
    local name=""
    if [[ "$body" == *"#"* ]]; then
        name="${body##*#}"
        name=$(printf '%s' "$name" | python3 -c "import sys,urllib.parse; print(urllib.parse.unquote(sys.stdin.read().strip()))" 2>/dev/null || echo "$name")
        body="${body%#*}"
    fi

    # uuid@host:port?params
    local userinfo="${body%%@*}"
    local rest="${body#*@}"

    local host_port="${rest%%\?*}"
    local params=""
    [[ "$rest" == *"?"* ]] && params="${rest#*\?}"

    local uuid="$userinfo"
    local host="${host_port%:*}"
    local port="${host_port##*:}"

    # Parse query params
    local security="" type="" sni="" fp="" pbk="" sid="" path="" flow="" alpn=""
    while IFS='=' read -r k v; do
        v=$(printf '%s' "$v" | python3 -c "import sys,urllib.parse; print(urllib.parse.unquote(sys.stdin.read().strip()))" 2>/dev/null || echo "$v")
        case "$k" in
            security) security="$v" ;;
            type)     type="$v" ;;
            sni)      sni="$v" ;;
            fp)       fp="$v" ;;
            pbk)      pbk="$v" ;;
            sid)      sid="$v" ;;
            path)     path="$v" ;;
            flow)     flow="$v" ;;
            alpn)     alpn="$v" ;;
        esac
    done < <(echo "$params" | tr '&' '\n' | grep '=')

    [[ -z "$name" ]] && name="${host}:${port}"

    # sanitize name for filename
    local safe_name
    safe_name=$(echo "$name" | tr -cd '[:alnum:]._-' | cut -c1-80)
    [[ -z "$safe_name" ]] && safe_name="node_$(date +%s%N | md5sum | cut -c1-8)"

    cat > "${out_file}" <<NODEEOF
NODE_NAME="${name}"
NODE_UUID="${uuid}"
NODE_HOST="${host}"
NODE_PORT="${port}"
NODE_SECURITY="${security}"
NODE_TYPE="${type}"
NODE_SNI="${sni}"
NODE_FP="${fp}"
NODE_PBK="${pbk}"
NODE_SID="${sid}"
NODE_PATH="${path}"
NODE_FLOW="${flow}"
NODE_ALPN="${alpn}"
NODE_URI="${uri}"
NODEEOF

    echo "$safe_name"
}

# ─── Fetch subscription ───────────────────────────────────────────────────────
fetch_subscription() {
    local url="$1"
    local sub_name="$2"
    local sub_dir="${SC_SUBS_DIR}/${sub_name}"

    mkdir -p "$sub_dir"
    msg_info "$L_SUB_FETCHING"

    local raw
    raw=$(curl -fsSL --max-time 15 "$url" 2>/dev/null)
    if [[ -z "$raw" ]]; then
        msg_err "$L_ERROR: failed to fetch $url"
        return 1
    fi

    # Try base64 decode (standard subscription format)
    local decoded
    if decoded=$(echo "$raw" | base64 -d 2>/dev/null) && echo "$decoded" | grep -q "vless://"; then
        raw="$decoded"
    fi

    # Count vless entries
    local count=0
    while IFS= read -r line; do
        line="${line// /}"
        [[ "$line" == vless://* ]] || continue
        local node_file="${sub_dir}/node_${count}.node"
        local safe_name
        safe_name=$(parse_vless_uri "$line" "$node_file")
        # rename with safe name if unique
        local dest="${SC_NODES_DIR}/${sub_name}__${safe_name}.node"
        mv "$node_file" "$dest"
        (( count++ ))
    done <<< "$raw"

    msg_ok "${count} ${L_SUB_NODES_FOUND}"
    echo "$count"
}

# ─── List subscriptions ───────────────────────────────────────────────────────
list_subscriptions() {
    local subs_meta="${SC_SUBS_DIR}/subs.list"
    [[ -f "$subs_meta" ]] && cat "$subs_meta" || echo ""
}

add_subscription() {
    local url="$1"
    local name="$2"
    local subs_meta="${SC_SUBS_DIR}/subs.list"

    # check duplicate
    if grep -q "^${name}|" "$subs_meta" 2>/dev/null; then
        msg_warn "Subscription '${name}' already exists. Updating..."
    else
        echo "${name}|${url}" >> "$subs_meta"
    fi

    fetch_subscription "$url" "$name"
}

remove_subscription() {
    local name="$1"
    local subs_meta="${SC_SUBS_DIR}/subs.list"

    # Remove nodes
    rm -f "${SC_NODES_DIR}/${name}__"*.node 2>/dev/null
    # Remove from list
    if check_cmd gsed; then
        gsed -i "/^${name}|/d" "$subs_meta" 2>/dev/null
    else
        sed -i "/^${name}|/d" "$subs_meta" 2>/dev/null
    fi
    msg_ok "$L_SUB_REMOVED: $name"
}

update_all_subscriptions() {
    local subs_meta="${SC_SUBS_DIR}/subs.list"
    [[ ! -f "$subs_meta" ]] && msg_warn "$L_SUB_EMPTY" && return

    msg_info "$L_UPDATING"
    while IFS='|' read -r name url; do
        [[ -z "$name" ]] && continue
        msg_step "Updating: $name"
        # Remove old nodes for this sub
        rm -f "${SC_NODES_DIR}/${name}__"*.node 2>/dev/null
        fetch_subscription "$url" "$name"
    done < "$subs_meta"
    msg_ok "$L_SUB_UPDATED"
}

# ─── List nodes ───────────────────────────────────────────────────────────────
list_nodes() {
    find "$SC_NODES_DIR" -name "*.node" -type f 2>/dev/null | sort
}

get_node_display_name() {
    local node_file="$1"
    source "$node_file" 2>/dev/null
    echo "${NODE_NAME:-$(basename "$node_file" .node)}"
}

# ─── Ping node ────────────────────────────────────────────────────────────────
ping_node() {
    local host="$1"
    local port="$2"
    local result
    result=$(timeout 3 bash -c "time (echo >/dev/tcp/${host}/${port}) 2>&1" 2>/dev/null | \
        grep real | awk '{print $2}' | sed 's/[ms]/ /g' | awk '{print int($1*60000 + $2*1000 + $3)}')
    echo "${result:-9999}"
}

# ─── Menu: subscriptions ─────────────────────────────────────────────────────
menu_subscriptions() {
    while true; do
        draw_header
        draw_status_bar
        printf "\n${C_BBLUE}  %s${C_RESET}\n\n" "$L_SUB_TITLE"

        printf "  ${C_BYELLOW}1${C_RESET}  %s\n" "$L_SUB_ADD"
        printf "  ${C_BYELLOW}2${C_RESET}  %s\n" "$L_SUB_REMOVE"
        printf "  ${C_BYELLOW}3${C_RESET}  %s\n" "$L_SUB_UPDATE"
        printf "  ${C_BYELLOW}4${C_RESET}  %s\n" "$L_SUB_LIST"
        printf "  ${C_BYELLOW}0${C_RESET}  %s\n\n" "$L_MENU_BACK"

        menu_prompt "$L_MENU_CHOOSE"
        read -r choice
        case "$choice" in
            1)
                draw_header
                printf "\n${C_BCYAN}%s${C_RESET}\n" "$L_SUB_ENTER_NAME"
                read -r sub_name
                [[ -z "$sub_name" ]] && continue
                printf "${C_BCYAN}%s${C_RESET}\n" "$L_SUB_ENTER_URL"
                read -r sub_url
                [[ -z "$sub_url" ]] && continue
                add_subscription "$sub_url" "$sub_name"
                press_enter
                ;;
            2)
                draw_header
                printf "\n${C_BBLUE}  %s${C_RESET}\n\n" "$L_SUB_TITLE"
                local subs_meta="${SC_SUBS_DIR}/subs.list"
                if [[ ! -f "$subs_meta" ]] || [[ ! -s "$subs_meta" ]]; then
                    msg_warn "$L_SUB_EMPTY"
                    press_enter; continue
                fi
                local i=1 names=()
                while IFS='|' read -r name url; do
                    [[ -z "$name" ]] && continue
                    node_count=$(find "$SC_NODES_DIR" -name "${name}__*.node" 2>/dev/null | wc -l)
                    printf "  ${C_BYELLOW}%2d${C_RESET}  %-30s ${C_DIM}(%d nodes)${C_RESET}\n" "$i" "$name" "$node_count"
                    names+=("$name")
                    (( i++ ))
                done < "$subs_meta"
                printf "  ${C_BYELLOW} 0${C_RESET}  %s\n\n" "$L_MENU_BACK"
                menu_prompt "$L_MENU_CHOOSE"
                read -r idx
                [[ "$idx" == "0" || -z "$idx" ]] && continue
                local sel_name="${names[$((idx-1))]}"
                [[ -z "$sel_name" ]] && msg_warn "$L_INVALID" && sleep 1 && continue
                if confirm "${L_CONFIRM}: remove '${sel_name}'?"; then
                    remove_subscription "$sel_name"
                fi
                press_enter
                ;;
            3)
                update_all_subscriptions
                press_enter
                ;;
            4)
                draw_header
                printf "\n${C_BBLUE}  %s${C_RESET}\n\n" "$L_SUB_TITLE"
                local subs_meta="${SC_SUBS_DIR}/subs.list"
                if [[ ! -f "$subs_meta" ]] || [[ ! -s "$subs_meta" ]]; then
                    msg_warn "$L_SUB_EMPTY"
                else
                    while IFS='|' read -r name url; do
                        [[ -z "$name" ]] && continue
                        local nc
                        nc=$(find "$SC_NODES_DIR" -name "${name}__*.node" 2>/dev/null | wc -l)
                        printf "  ${C_BGREEN}%-30s${C_RESET}  ${C_DIM}%d nodes${C_RESET}  ${C_CYAN}%s${C_RESET}\n" \
                            "$name" "$nc" "$url"
                    done < "$subs_meta"
                fi
                press_enter
                ;;
            0|"") return ;;
            *) msg_warn "$L_INVALID"; sleep 1 ;;
        esac
    done
}

# ─── Menu: select node ────────────────────────────────────────────────────────
menu_select_node() {
    local node_files=()
    while IFS= read -r f; do
        node_files+=("$f")
    done < <(list_nodes)

    if [[ ${#node_files[@]} -eq 0 ]]; then
        draw_header; draw_status_bar
        msg_warn "$L_NODE_EMPTY"
        press_enter; return
    fi

    while true; do
        draw_header
        draw_status_bar
        printf "\n${C_BBLUE}  %s${C_RESET}\n\n" "$L_NODE_TITLE"

        local current_node
        current_node=$(get_active_node_name)

        local i=1
        for f in "${node_files[@]}"; do
            local disp
            disp=$(get_node_display_name "$f")
            local marker="  "
            [[ "$disp" == "$current_node" ]] && marker="${C_BGREEN}▶ ${C_RESET}"
            printf "  %b${C_BYELLOW}%3d${C_RESET}  %s\n" "$marker" "$i" "$disp"
            (( i++ ))
        done

        printf "\n  ${C_BYELLOW}  p${C_RESET}  ${L_NODE_TESTING}\n"
        printf   "  ${C_BYELLOW}  0${C_RESET}  %s\n\n" "$L_MENU_BACK"

        menu_prompt "$L_MENU_CHOOSE"
        read -r choice

        case "$choice" in
            0|"") return ;;
            p|P|п|П)
                # Ping all
                printf "\n${C_BYELLOW}%s${C_RESET}\n\n" "$L_NODE_TESTING"
                local pi=1
                for f in "${node_files[@]}"; do
                    source "$f" 2>/dev/null
                    local ms
                    ms=$(ping_node "$NODE_HOST" "$NODE_PORT")
                    local col
                    (( ms < 200 )) && col="$C_BGREEN" || (( ms < 500 )) && col="$C_BYELLOW" || col="$C_RED"
                    printf "  %3d  %-40s  %b%s ms${C_RESET}\n" \
                        "$pi" "${NODE_NAME:-$NODE_HOST}" "$col" "$ms"
                    (( pi++ ))
                done
                press_enter
                ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#node_files[@]} )); then
                    local sel_file="${node_files[$((choice-1))]}"
                    source "$sel_file" 2>/dev/null
                    set_active_node "${NODE_NAME}"
                    msg_ok "${L_NODE_SELECTED}: ${NODE_NAME}"
                    log_sys "Node selected: ${NODE_NAME}"
                    sleep 1
                    return
                else
                    msg_warn "$L_INVALID"; sleep 1
                fi
                ;;
        esac
    done
}
