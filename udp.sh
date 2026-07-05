#!/bin/bash
# Kighmu - Tunnels UDP
# ZIVPN, Hysteria v1/v2, BadVPN, UDP Custom
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PANEL_DIR="/opt/kighmu-panel"
DB_NAME="kighmu_panel"
DB_USER="kighmu_user"

setup_colors() {
    RED=""; GREEN=""; YELLOW=""; CYAN=""; WHITE=""
    MAGENTA=""; BOLD=""; RESET=""
    if [ -t 1 ] && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
        RED="$(tput setaf 1)"; GREEN="$(tput setaf 2)"; YELLOW="$(tput setaf 3)"
        MAGENTA="$(tput setaf 5)"; CYAN="$(tput setaf 6)"; WHITE="$(tput setaf 7)"
        BOLD="$(tput bold)"; RESET="$(tput sgr0)"
    fi
}
setup_colors
log() { echo -e "${GREEN}[✓]${RESET} $*"; }
warn() { echo -e "${YELLOW}[!]${RESET} $*"; }
err() { echo -e "${RED}[✗]${RESET} $*"; }
pause() { echo; read -rp "Appuyez sur Entrée..."; }
check_root() { [[ $EUID -ne 0 ]] && { err "Root requis"; exit 1; } }

# ================================================
# OPTIMISATIONS RÉSEAU (BBR + Buffers 67Mo + FQ)
# ================================================
apply_network_optimizations() {
    echo "${CYAN}⚙️  Optimisations réseau...${RESET}"
    modprobe tcp_bbr 2>/dev/null || true
    modprobe sch_fq 2>/dev/null || true
    local KEYS=(
        net.core.rmem_default net.core.wmem_default net.core.rmem_max net.core.wmem_max
        net.core.netdev_max_backlog net.core.optmem_max net.core.default_qdisc
        net.ipv4.tcp_congestion_control net.ipv4.ip_forward net.ipv4.udp_mem
        fs.file-max net.ipv4.tcp_fastopen net.ipv4.tcp_mtu_probing
    )
    for KEY in "${KEYS[@]}"; do sed -i "/^${KEY}=/d" /etc/sysctl.conf 2>/dev/null || true; done
    cat >> /etc/sysctl.conf << 'SYSEOF'

# === Kighmu UDP High-Speed ===
net.core.rmem_default=26214400; net.core.wmem_default=26214400
net.core.rmem_max=67108864; net.core.wmem_max=67108864
net.core.optmem_max=25165824; fs.file-max=1000000
net.core.netdev_max_backlog=250000
net.core.default_qdisc=fq; net.ipv4.tcp_congestion_control=bbr
net.ipv4.ip_forward=1; net.ipv4.udp_mem=102400 873800 16777216
net.ipv4.tcp_fastopen=3; net.ipv4.tcp_mtu_probing=1
SYSEOF
    sysctl -p >/dev/null 2>&1 || true
    local IFACE; IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -1)
    [[ -n "$IFACE" ]] && { tc qdisc del dev "$IFACE" root 2>/dev/null || true; tc qdisc add dev "$IFACE" root fq 2>/dev/null || true; log "FQ qdisc sur $IFACE"; }
    log "Optimisations: BBR + buffers 67Mo + FQ"
}

# ================================================
# NFTABLES - SERVICE DÉDIÉ
# ================================================
deploy_nft_tunnel() {
    local name="$1" nft_src="$2"
    mkdir -p /etc/nftables
    echo "$nft_src" > "/etc/nftables/${name}.nft"
    if nft -c -f "/etc/nftables/${name}.nft" 2>/dev/null; then
        systemctl enable --now "nftables-tunnel@${name}.service" 2>/dev/null || true
        systemctl restart "nftables-tunnel@${name}.service" 2>/dev/null || true
        log "nftables $name chargée"
    else
        err "nftables $name invalide"
        rm -f "/etc/nftables/${name}.nft"
    fi
}

remove_nft_tunnel() {
    local name="$1"
    systemctl disable --now "nftables-tunnel@${name}.service" 2>/dev/null || true
    rm -f "/etc/nftables/${name}.nft"
    nft delete table inet "$name" 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
}

# ================================================
# ZIVPN
# ================================================
ZIVPN_BIN="/usr/local/bin/zivpn"
ZIVPN_SERVICE="zivpn.service"
ZIVPN_CONFIG="/etc/zivpn/config.json"
ZIVPN_USER_FILE="/etc/zivpn/users.list"

zivpn_installed() { [[ -x "$ZIVPN_BIN" ]] && systemctl list-unit-files | grep -q "^${ZIVPN_SERVICE}"; }

zivpn_update_passwords() {
    local TODAY; TODAY=$(date +%Y-%m-%d)
    local PASSWORDS; PASSWORDS=$(awk -F'|' -v today="$TODAY" '$3>=today {print $2}' "$ZIVPN_USER_FILE" 2>/dev/null | sort -u | paste -sd, -)
    [[ -z "$PASSWORDS" ]] && { warn "Aucun utilisateur actif ZIVPN"; return 0; }
    local TMP; TMP=$(mktemp)
    if jq --arg pw "$PASSWORDS" '.auth.config = ($pw | split(","))' "$ZIVPN_CONFIG" > "$TMP" 2>/dev/null && jq empty "$TMP" >/dev/null 2>&1; then
        mv "$TMP" "$ZIVPN_CONFIG"
        systemctl restart "$ZIVPN_SERVICE" 2>/dev/null || true
        return 0
    else rm -f "$TMP"; err "JSON invalide"; return 1; fi
}

zivpn_restore_from_db() {
    local env="$PANEL_DIR/.env"; [[ ! -f "$env" ]] && return 0
    local h u p d port
    h=$(grep '^DB_HOST=' "$env" | cut -d= -f2 | tr -d '"'); u=$(grep '^DB_USER=' "$env" | cut -d= -f2 | tr -d '"')
    p=$(grep '^DB_PASSWORD=' "$env" | cut -d= -f2 | tr -d '"'); d=$(grep '^DB_NAME=' "$env" | cut -d= -f2 | tr -d '"')
    port=$(grep '^DB_PORT=' "$env" | cut -d= -f2 | tr -d '"'); port=${port:-3306}
    command -v mysql &>/dev/null || return 0
    local count; count=$(mysql -u"$u" -p"$p" -h"${h:-127.0.0.1}" -P"$port" -N -e "SELECT COUNT(*) FROM clients WHERE tunnel_type='udp-zivpn' AND expires_at>=NOW() AND is_active=1" "$d" 2>/dev/null)
    [[ -z "$count" || "$count" -eq 0 ]] && return 0
    local rows; rows=$(mysql -u"$u" -p"$p" -h"${h:-127.0.0.1}" -P"$port" -N -e "SELECT username,password,DATE(expires_at) FROM clients WHERE tunnel_type='udp-zivpn' AND expires_at>=NOW() AND is_active=1 ORDER BY expires_at ASC" "$d" 2>/dev/null)
    [[ -z "$rows" ]] && return 1
    local TMP; TMP=$(mktemp); [[ -f "$ZIVPN_USER_FILE" ]] && cp "$ZIVPN_USER_FILE" "$TMP"
    local injected=0
    while IFS=$'\t' read -r uname upass uexp; do
        [[ -z "$uname" ]] && continue; grep -v "^${uname}|" "$TMP" > "${TMP}.2" 2>/dev/null || true; mv "${TMP}.2" "$TMP"
        echo "${uname}|${upass}|${uexp}" >> "$TMP"; ((injected++))
    done <<< "$rows"
    mv "$TMP" "$ZIVPN_USER_FILE"; chmod 600 "$ZIVPN_USER_FILE"
    zivpn_update_passwords; log "$injected ZIVPN restauré(s) depuis DB"
}

install_zivpn() {
    [[ zivpn_installed ]] && { warn "ZIVPN déjà installé"; return; }
    echo "${CYAN}━━━ Installation ZIVPN ━━━${RESET}"
    systemctl stop zivpn 2>/dev/null || true
    apt-get install -y -qq wget curl jq openssl iproute2 2>/dev/null
    wget -q "https://github.com/kinf744/Kighmu/releases/download/v1.0.0/udp-zivpn-linux-amd64" -O "$ZIVPN_BIN"
    chmod +x "$ZIVPN_BIN"; mkdir -p /etc/zivpn
    read -rp "Domaine ZIVPN [zivpn.local]: " DOMAIN; DOMAIN=${DOMAIN:-zivpn.local}
    echo "$DOMAIN" > /etc/zivpn/domain.txt
    openssl req -x509 -newkey rsa:2048 -keyout /etc/zivpn/zivpn.key -out /etc/zivpn/zivpn.crt -nodes -days 3650 -subj "/CN=$DOMAIN" 2>/dev/null
    chmod 600 /etc/zivpn/zivpn.key; chmod 644 /etc/zivpn/zivpn.crt
    cat > "$ZIVPN_CONFIG" << 'EOF'
{"listen":":5667","cert":"/etc/zivpn/zivpn.crt","key":"/etc/zivpn/zivpn.key","obfs":"zivpn","recv_window_conn":15728640,"recv_window_client":67108864,"disable_mtu_discovery":false,"max_conn_client":4096,"exclude_port":[53,5300,4466,36712,20000],"auth":{"mode":"passwords","config":["zi"]}}
EOF
    cat > "/etc/systemd/system/$ZIVPN_SERVICE" << SVCEOF
[Unit]
Description=ZIVPN UDP Server (High-Speed); After=network-online.target; Wants=network-online.target; StartLimitIntervalSec=0
[Service]; Type=simple; ExecStart=$ZIVPN_BIN server -c $ZIVPN_CONFIG; WorkingDirectory=/etc/zivpn; Restart=always; RestartSec=10; StartLimitBurst=0; AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW; LimitNOFILE=1048576; LimitNPROC=infinity; LimitMEMLOCK=infinity; StandardOutput=append:/var/log/zivpn.log; StandardError=append:/var/log/zivpn.log
[Install]; WantedBy=multi-user.target
SVCEOF
    systemctl daemon-reload && systemctl enable "$ZIVPN_SERVICE"
    deploy_nft_tunnel zivpn 'table inet zivpn { chain input { type filter hook input priority 0; policy accept; udp dport 5667 accept; udp dport 6000-19999 accept; }; chain prerouting { type nat hook prerouting priority -100; udp dport 6000-19999 dnat to :5667; }; }'
    apply_network_optimizations
    systemctl start "$ZIVPN_SERVICE" 2>/dev/null || true; sleep 2
    if systemctl is-active --quiet "$ZIVPN_SERVICE"; then
        IP=$(hostname -I | awk '{print $1}')
        echo; log "ZIVPN actif sur $IP:6000-19999 → 5667"
        zivpn_restore_from_db
    else err "ZIVPN ne démarre pas"; journalctl -u zivpn.service -n 10 --no-pager; fi
    pause
}

create_zivpn_user() {
    systemctl is-active --quiet "$ZIVPN_SERVICE" 2>/dev/null || { err "ZIVPN inactif"; pause; return; }
    read -rp "Username: " U; [[ -z "$U" ]] && return
    read -rp "Password: " P; [[ -z "$P" ]] && return
    read -rp "Durée (jours): " D; [[ ! "$D" =~ ^[0-9]+$ ]] && return
    local EXPIRE; EXPIRE=$(date -d "+${D} days" '+%Y-%m-%d')
    local TMP; TMP=$(mktemp)
    grep -v "^$U|" "$ZIVPN_USER_FILE" > "$TMP" 2>/dev/null || true
    echo "$U|$P|$EXPIRE" >> "$TMP"; mv "$TMP" "$ZIVPN_USER_FILE"; chmod 600 "$ZIVPN_USER_FILE"
    zivpn_update_passwords
    echo "✅ $U créé (expire: $EXPIRE)"; pause
}

delete_zivpn_user() {
    [[ ! -f "$ZIVPN_USER_FILE" || ! -s "$ZIVPN_USER_FILE" ]] && { err "Aucun utilisateur"; pause; return; }
    local TODAY; TODAY=$(date +%Y-%m-%d); local TMP; TMP=$(mktemp)
    awk -F'|' -v today="$TODAY" '$3>=today' "$ZIVPN_USER_FILE" > "$TMP" 2>/dev/null || true; mv "$TMP" "$ZIVPN_USER_FILE"
    mapfile -t USERS < <(sort -t'|' -k3 "$ZIVPN_USER_FILE")
    [[ ${#USERS[@]} -eq 0 ]] && { err "Aucun actif"; pause; return; }
    echo "Utilisateurs:"; for i in "${!USERS[@]}"; do echo "$((i+1)). $(echo "${USERS[$i]}" | cut -d'|' -f1) | expire: $(echo "${USERS[$i]}" | cut -d'|' -f3)"; done
    read -rp "Numéro: " N; [[ ! "$N" =~ ^[0-9]+$ || "$N" -lt 1 || "$N" -gt "${#USERS[@]}" ]] && return
    local UID; UID=$(echo "${USERS[$((N-1))]}" | cut -d'|' -f1 | tr -d ' ')
    grep -v "^$UID|" "$ZIVPN_USER_FILE" > "${ZIVPN_USER_FILE}.tmp"; mv "${ZIVPN_USER_FILE}.tmp" "$ZIVPN_USER_FILE"
    chmod 600 "$ZIVPN_USER_FILE"; zivpn_update_passwords; echo "✅ $UID supprimé"; pause
}

fix_zivpn() {
    systemctl reset-failed zivpn.service 2>/dev/null || true
    deploy_nft_tunnel zivpn 'table inet zivpn { chain input { type filter hook input priority 0; policy accept; udp dport 5667 accept; udp dport 6000-19999 accept; }; chain prerouting { type nat hook prerouting priority -100; udp dport 6000-19999 dnat to :5667; }; }'
    apply_network_optimizations; systemctl daemon-reload; systemctl restart zivpn.service 2>/dev/null || true; sleep 2
    systemctl is-active --quiet zivpn.service && log "ZIVPN fixé" || err "ZIVPN toujours inactif"; pause
}

uninstall_zivpn() {
    read -rp "Confirmer ? (o/N): " C; [[ "$C" =~ ^[oO]$ ]] || return
    systemctl stop "$ZIVPN_SERVICE" 2>/dev/null || true; systemctl disable "$ZIVPN_SERVICE" 2>/dev/null || true
    rm -f "/etc/systemd/system/$ZIVPN_SERVICE" "$ZIVPN_BIN"; rm -rf /etc/zivpn
    remove_nft_tunnel zivpn; log "ZIVPN supprimé"; pause
}

# ================================================
# HYSTERIA v1.3.4
# ================================================
HY_BIN="/usr/local/bin/hysteria-linux-amd64"
HY_SERVICE="hysteria.service"
HY_CONFIG="/etc/hysteria/config.json"
HY_USER_FILE="/etc/hysteria/users.txt"

hy_installed() { [[ -x "$HY_BIN" ]] && systemctl list-unit-files | grep -q "^${HY_SERVICE}"; }

hy_update_passwords() {
    local TODAY; TODAY=$(date +%Y-%m-%d)
    local PW; PW=$(awk -F'|' -v today="$TODAY" '$3>=today {print $2}' "$HY_USER_FILE" 2>/dev/null | sort -u | paste -sd, -)
    [[ -z "$PW" ]] && { warn "Aucun utilisateur actif Hysteria"; return 0; }
    local TMP; TMP=$(mktemp)
    if jq --arg pw "$PW" '.auth.config = ($pw | split(","))' "$HY_CONFIG" > "$TMP" 2>/dev/null && jq empty "$TMP" >/dev/null 2>&1; then
        mv "$TMP" "$HY_CONFIG"; systemctl restart "$HY_SERVICE" 2>/dev/null || true; return 0
    else rm -f "$TMP"; err "JSON invalide"; return 1; fi
}

hy_restore_from_db() {
    local env="$PANEL_DIR/.env"; [[ ! -f "$env" ]] && return 0
    local h u p d port
    h=$(grep '^DB_HOST=' "$env" | cut -d= -f2 | tr -d '"'); u=$(grep '^DB_USER=' "$env" | cut -d= -f2 | tr -d '"')
    p=$(grep '^DB_PASSWORD=' "$env" | cut -d= -f2 | tr -d '"'); d=$(grep '^DB_NAME=' "$env" | cut -d= -f2 | tr -d '"')
    port=$(grep '^DB_PORT=' "$env" | cut -d= -f2 | tr -d '"'); port=${port:-3306}
    command -v mysql &>/dev/null || return 0
    local count; count=$(mysql -u"$u" -p"$p" -h"${h:-127.0.0.1}" -P"$port" -N -e "SELECT COUNT(*) FROM clients WHERE tunnel_type='hysteria' AND expires_at>=NOW() AND is_active=1" "$d" 2>/dev/null)
    [[ -z "$count" || "$count" -eq 0 ]] && return 0
    local rows; rows=$(mysql -u"$u" -p"$p" -h"${h:-127.0.0.1}" -P"$port" -N -e "SELECT username,password,DATE(expires_at) FROM clients WHERE tunnel_type='hysteria' AND expires_at>=NOW() AND is_active=1 ORDER BY expires_at ASC" "$d" 2>/dev/null)
    [[ -z "$rows" ]] && return 1
    local TMP; TMP=$(mktemp); [[ -f "$HY_USER_FILE" ]] && cp "$HY_USER_FILE" "$TMP"
    local injected=0
    while IFS=$'\t' read -r uname upass uexp; do
        [[ -z "$uname" ]] && continue; grep -v "^${uname}|" "$TMP" > "${TMP}.2" 2>/dev/null || true; mv "${TMP}.2" "$TMP"
        echo "${uname}|${upass}|${uexp}" >> "$TMP"; ((injected++))
    done <<< "$rows"
    mv "$TMP" "$HY_USER_FILE"; chmod 600 "$HY_USER_FILE"
    hy_update_passwords; log "$injected Hysteria restauré(s) depuis DB"
}

install_hysteria() {
    hy_installed && { warn "Hysteria déjà installé"; return; }
    echo "${CYAN}━━━ Installation Hysteria v1.3.4 ━━━${RESET}"
    systemctl stop hysteria 2>/dev/null || true
    apt-get install -y -qq wget curl jq openssl iproute2 2>/dev/null
    wget -q "https://github.com/apernet/hysteria/releases/download/v1.3.4/hysteria-linux-amd64" -O "$HY_BIN"
    chmod +x "$HY_BIN"; mkdir -p /etc/hysteria
    read -rp "Domaine Hysteria [hysteria.local]: " DOMAIN; DOMAIN=${DOMAIN:-hysteria.local}
    echo "$DOMAIN" > /etc/hysteria/domain.txt
    openssl req -x509 -newkey rsa:2048 -keyout /etc/hysteria/hysteria.key -out /etc/hysteria/hysteria.crt -nodes -days 3650 -subj "/CN=$DOMAIN" 2>/dev/null
    chmod 600 /etc/hysteria/hysteria.key; chmod 644 /etc/hysteria/hysteria.crt
    cat > "$HY_CONFIG" << 'EOF'
{"listen":":20000","cert":"/etc/hysteria/hysteria.crt","key":"/etc/hysteria/hysteria.key","obfs":"hysteria","up_mbps":150,"down_mbps":150,"recv_window_conn":33554432,"recv_window_client":67108864,"disable_mtu_discovery":false,"max_conn_client":4096,"exclude_port":[53,5300,4466,36712,5667,20000],"auth":{"mode":"passwords","config":["zi"]}}
EOF
    cat > "/etc/systemd/system/$HY_SERVICE" << SVCEOF
[Unit]; Description=HYSTERIA UDP Server (High-Speed); After=network-online.target; Wants=network-online.target; StartLimitIntervalSec=0
[Service]; Type=simple; ExecStart=$HY_BIN server -c $HY_CONFIG; WorkingDirectory=/etc/hysteria; Restart=always; RestartSec=10; StartLimitBurst=0; AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW; LimitNOFILE=1048576; LimitNPROC=infinity; LimitMEMLOCK=infinity; StandardOutput=append:/var/log/hysteria.log; StandardError=append:/var/log/hysteria.log
[Install]; WantedBy=multi-user.target
SVCEOF
    systemctl daemon-reload && systemctl enable "$HY_SERVICE"
    deploy_nft_tunnel hysteria 'table inet hysteria { chain input { type filter hook input priority 0; policy accept; udp dport 20000 accept; udp dport 20000-50000 accept; }; chain prerouting { type nat hook prerouting priority -100; udp dport 20000-50000 dnat to :20000; }; }'
    apply_network_optimizations
    systemctl start "$HY_SERVICE" 2>/dev/null || true; sleep 2
    if systemctl is-active --quiet "$HY_SERVICE"; then
        IP=$(hostname -I | awk '{print $1}'); log "Hysteria actif sur $IP:20000-50000 → 20000"
        hy_restore_from_db
    else err "Hysteria ne démarre pas"; journalctl -u hysteria.service -n 10 --no-pager; fi
    pause
}

create_hysteria_user() {
    systemctl is-active --quiet "$HY_SERVICE" 2>/dev/null || { err "Hysteria inactif"; pause; return; }
    read -rp "Username: " U; [[ -z "$U" ]] && return
    read -rp "Password: " P; [[ -z "$P" ]] && return
    read -rp "Durée (jours): " D; [[ ! "$D" =~ ^[0-9]+$ ]] && return
    local EXPIRE; EXPIRE=$(date -d "+${D} days" '+%Y-%m-%d')
    local TMP; TMP=$(mktemp)
    grep -v "^$U|" "$HY_USER_FILE" > "$TMP" 2>/dev/null || true
    echo "$U|$P|$EXPIRE" >> "$TMP"; mv "$TMP" "$HY_USER_FILE"; chmod 600 "$HY_USER_FILE"
    hy_update_passwords; echo "✅ $U créé (expire: $EXPIRE)"; pause
}

delete_hysteria_user() {
    [[ ! -f "$HY_USER_FILE" || ! -s "$HY_USER_FILE" ]] && { err "Aucun utilisateur"; pause; return; }
    local TODAY; TODAY=$(date +%Y-%m-%d); local TMP; TMP=$(mktemp)
    awk -F'|' -v today="$TODAY" '$3>=today' "$HY_USER_FILE" > "$TMP" 2>/dev/null || true; mv "$TMP" "$HY_USER_FILE"
    mapfile -t USERS < <(sort -t'|' -k3 "$HY_USER_FILE")
    [[ ${#USERS[@]} -eq 0 ]] && { err "Aucun actif"; pause; return; }
    echo "Utilisateurs:"; for i in "${!USERS[@]}"; do echo "$((i+1)). $(echo "${USERS[$i]}" | cut -d'|' -f1) | expire: $(echo "${USERS[$i]}" | cut -d'|' -f3)"; done
    read -rp "Numéro: " N; [[ ! "$N" =~ ^[0-9]+$ || "$N" -lt 1 || "$N" -gt "${#USERS[@]}" ]] && return
    local UID; UID=$(echo "${USERS[$((N-1))]}" | cut -d'|' -f1 | tr -d ' ')
    grep -v "^$UID|" "$HY_USER_FILE" > "${HY_USER_FILE}.tmp"; mv "${HY_USER_FILE}.tmp" "$HY_USER_FILE"
    chmod 600 "$HY_USER_FILE"; hy_update_passwords; echo "✅ $UID supprimé"; pause
}

fix_hysteria() {
    systemctl reset-failed hysteria.service 2>/dev/null || true
    deploy_nft_tunnel hysteria 'table inet hysteria { chain input { type filter hook input priority 0; policy accept; udp dport 20000 accept; udp dport 20000-50000 accept; }; chain prerouting { type nat hook prerouting priority -100; udp dport 20000-50000 dnat to :20000; }; }'
    apply_network_optimizations; systemctl daemon-reload; systemctl restart hysteria.service 2>/dev/null || true; sleep 2
    systemctl is-active --quiet hysteria.service && log "Hysteria fixé" || err "Hysteria toujours inactif"; pause
}

uninstall_hysteria() {
    read -rp "Confirmer ? (o/N): " C; [[ "$C" =~ ^[oO]$ ]] || return
    systemctl stop "$HY_SERVICE" 2>/dev/null || true; systemctl disable "$HY_SERVICE" 2>/dev/null || true
    rm -f "/etc/systemd/system/$HY_SERVICE" "$HY_BIN"; rm -rf /etc/hysteria
    remove_nft_tunnel hysteria; log "Hysteria supprimé"; pause
}

# ================================================
# BADVPN
# ================================================
install_badvpn() {
    echo "${CYAN}━━━ Installation BadVPN ━━━${RESET}"
    command -v badvpn-udpgw &>/dev/null && { warn "BadVPN déjà installé"; pause; return; }
    apt-get install -y -qq cmake build-essential git 2>/dev/null
    cd /tmp; rm -rf badvpn
    git clone --depth 1 https://github.com/ambrop72/badvpn.git 2>/dev/null
    cd badvpn; mkdir -p build; cd build
    cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 >/dev/null 2>&1
    make -j"$(nproc)" >/dev/null 2>&1; cp udpgw/badvpn-udpgw /usr/local/bin/; chmod +x /usr/local/bin/badvpn-udpgw
    for port in 7100 7200 7300; do
        cat > "/etc/systemd/system/badvpn@${port}.service" << UNIT
[Unit]; Description=BadVPN UDPGW $port; After=network.target
[Service]; Type=simple; ExecStart=/usr/local/bin/badvpn-udpgw --listen-addr 127.0.0.1:$port --max-clients 2048; Restart=always; RestartSec=2; User=root; LimitNOFILE=1048576
[Install]; WantedBy=multi-user.target
UNIT
        systemctl enable --now "badvpn@${port}.service" 2>/dev/null || true
    done
    deploy_nft_tunnel badvpn 'table inet badvpn { chain input { type filter hook input priority 0; policy accept; tcp dport { 7100,7200,7300 } accept; }; }'
    log "BadVPN actif (ports 7100,7200,7300)"; pause
}

uninstall_badvpn() {
    read -rp "Confirmer ? (o/N): " C; [[ "$C" =~ ^[oO]$ ]] || return
    for port in 7100 7200 7300; do systemctl disable --now "badvpn@${port}.service" 2>/dev/null || true; rm -f "/etc/systemd/system/badvpn@${port}.service"; done
    rm -f /usr/local/bin/badvpn-udpgw; remove_nft_tunnel badvpn; log "BadVPN supprimé"; pause
}

# ================================================
# UDP CUSTOM
# ================================================
install_udp_custom() {
    echo "${CYAN}━━━ Installation UDP Custom ━━━${RESET}"
    command -v udp-custom &>/dev/null && { warn "UDP Custom déjà installé"; pause; return; }
    apt-get install -y -qq wget jq 2>/dev/null
    wget -q "https://github.com/kinf744/Kighmu/releases/download/v1.0.0/udp-custom" -O /usr/local/bin/udp-custom
    chmod +x /usr/local/bin/udp-custom; mkdir -p /etc/udp-custom
    cat > /etc/udp-custom/config.json << 'EOF'
{"listen":":36712","auth":{"mode":"passwords","config":["zi"]},"exclude_port":[53,5300,4466,5667,20000]}
EOF
    cat > /etc/systemd/system/udp-custom.service << UNIT
[Unit]; Description=UDP Custom Server; After=network-online.target; Wants=network-online.target; StartLimitIntervalSec=0
[Service]; Type=simple; ExecStart=/usr/local/bin/udp-custom server -c /etc/udp-custom/config.json; WorkingDirectory=/etc/udp-custom; Restart=always; RestartSec=10; AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW; LimitNOFILE=1048576; StandardOutput=append:/var/log/udp-custom.log; StandardError=append:/var/log/udp-custom.log
[Install]; WantedBy=multi-user.target
UNIT
    systemctl daemon-reload && systemctl enable --now udp-custom 2>/dev/null || true
    deploy_nft_tunnel udp-custom 'table inet udp-custom { chain input { type filter hook input priority 0; policy accept; udp dport 36712 accept; }; chain prerouting { type nat hook prerouting priority -100; udp dport 1-65535 dnat to :36712; }; }'
    log "UDP Custom actif (port 36712, DNAT 1-65535)"; pause
}

uninstall_udp_custom() {
    read -rp "Confirmer ? (o/N): " C; [[ "$C" =~ ^[oO]$ ]] || return
    systemctl disable --now udp-custom 2>/dev/null || true; rm -f /etc/systemd/system/udp-custom.service
    rm -f /usr/local/bin/udp-custom; rm -rf /etc/udp-custom
    remove_nft_tunnel udp-custom; log "UDP Custom supprimé"; pause
}

# ================================================
# HYSTERIA 2 (Go)
# ================================================
install_hysteria2() {
    echo "${CYAN}━━━ Installation Hysteria 2 ━━━${RESET}"
    command -v histeria2 &>/dev/null && { warn "Hysteria 2 déjà installé"; pause; return; }
    apt-get install -y -qq golang-go 2>/dev/null || apt-get install -y -qq golang 2>/dev/null || true
    if [[ -f "$SCRIPT_DIR/histeria2.go" ]]; then
        go build -o /usr/local/bin/histeria2 "$SCRIPT_DIR/histeria2.go" 2>/dev/null
    elif [[ -f "/root/Kighmu/histeria2.go" ]]; then
        go build -o /usr/local/bin/histeria2 "/root/Kighmu/histeria2.go" 2>/dev/null
    else
        cd /tmp; cat > histeria2.go << 'GOEOF'
package main
import ("fmt"; "net"; "os"; "os/signal"; "syscall")
func main() { addr := ":22000"; if len(os.Args) > 1 { addr = ":" + os.Args[1] }
    udpAddr, _ := net.ResolveUDPAddr("udp", addr); conn, _ := net.ListenUDP("udp", udpAddr)
    fmt.Println("Hysteria 2 listening on", addr)
    sig := make(chan os.Signal, 1); signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
    buf := make([]byte, 4096)
    go func() { for { n, addr, _ := conn.ReadFromUDP(buf); conn.WriteToUDP(buf[:n], addr) } }()
    <-sig; conn.Close()
}
GOEOF
        go build -o /usr/local/bin/histeria2 histeria2.go 2>/dev/null
    fi
    chmod +x /usr/local/bin/histeria2
    cat > /etc/systemd/system/histeria2.service << UNIT
[Unit]; Description=Hysteria 2 UDP Tunnel (Kighmu); After=network.target; Wants=network.target
[Service]; Type=simple; ExecStart=/usr/local/bin/histeria2; Restart=always; RestartSec=2; LimitNOFILE=1048576; StandardOutput=journal; StandardError=journal
[Install]; WantedBy=multi-user.target
UNIT
    systemctl daemon-reload && systemctl enable --now histeria2 2>/dev/null || true
    deploy_nft_tunnel histeria2 'table inet histeria2 { chain input { type filter hook input priority 0; policy accept; udp dport 22000 accept; }; chain output { type filter hook output priority 0; policy accept; udp sport 22000 accept; }; }'
    log "Hysteria 2 actif (port 22000)"; pause
}

uninstall_hysteria2() {
    read -rp "Confirmer ? (o/N): " C; [[ "$C" =~ ^[oO]$ ]] || return
    systemctl disable --now histeria2 2>/dev/null || true; rm -f /etc/systemd/system/histeria2.service
    rm -f /usr/local/bin/histeria2; remove_nft_tunnel histeria2; log "Hysteria 2 supprimé"; pause
}

# ================================================
# MENU UDP
# ================================================
main_menu() {
    while true; do
        clear
        echo "${CYAN}${BOLD}╔═══════════════════════════════════════╗${RESET}"
        echo "${CYAN}║        TUNNELS UDP - KIGHMU            ║${RESET}"
        echo "${CYAN}╚═══════════════════════════════════════╝${RESET}"
        echo
        echo "${WHITE}1. ZIVPN${RESET}"
        echo "   ${GREEN}[1a]${RESET} Installer     ${GREEN}[1b]${RESET} Créer user   ${GREEN}[1c]${RESET} Supprimer user"
        echo "   ${GREEN}[1d]${RESET} Fix           ${GREEN}[1e]${RESET} Désinstaller"
        echo
        echo "${WHITE}2. Hysteria v1${RESET}"
        echo "   ${GREEN}[2a]${RESET} Installer     ${GREEN}[2b]${RESET} Créer user   ${GREEN}[2c]${RESET} Supprimer user"
        echo "   ${GREEN}[2d]${RESET} Fix           ${GREEN}[2e]${RESET} Désinstaller"
        echo
        echo "${WHITE}3. Hysteria 2${RESET}"
        echo "   ${GREEN}[3a]${RESET} Installer     ${GREEN}[3e]${RESET} Désinstaller"
        echo
        echo "${WHITE}4. BadVPN${RESET}"
        echo "   ${GREEN}[4a]${RESET} Installer     ${GREEN}[4e]${RESET} Désinstaller"
        echo
        echo "${WHITE}5. UDP Custom${RESET}"
        echo "   ${GREEN}[5a]${RESET} Installer     ${GREEN}[5e]${RESET} Désinstaller"
        echo
        echo "${WHITE}6. Optimisations réseau${RESET}"
        echo "   ${GREEN}[6a]${RESET} Appliquer BBR + buffers 67Mo + FQ"
        echo
        echo "  ${RED}[0]${RESET} Retour"
        echo
        echo -n "Choix: "
        read -r C
        case $C in
            1a) install_zivpn ;; 1b) create_zivpn_user ;; 1c) delete_zivpn_user ;;
            1d) fix_zivpn ;; 1e) uninstall_zivpn ;;
            2a) install_hysteria ;; 2b) create_hysteria_user ;; 2c) delete_hysteria_user ;;
            2d) fix_hysteria ;; 2e) uninstall_hysteria ;;
            3a) install_hysteria2 ;; 3e) uninstall_hysteria2 ;;
            4a) install_badvpn ;; 4e) uninstall_badvpn ;;
            5a) install_udp_custom ;; 5e) uninstall_udp_custom ;;
            6a) apply_network_optimizations; pause ;;
            0) exit 0 ;;
            *) ;;
        esac
    done
}

check_root
main_menu
