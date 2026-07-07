#!/bin/bash
# Kighmu - Xray & V2Ray
# VMess, VLESS, Trojan, Shadowsocks + V2Ray TCP
set -uo pipefail

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
pause() { [[ -n "${SKIP_PAUSE:-}" ]] && return 0; echo; read -rp "Appuyez sur Entrée..."; }
check_root() { [[ $EUID -ne 0 ]] && { err "Root requis"; exit 1; } }

gen_uuid() { cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || echo "$(date +%s)-$$-$(openssl rand -hex 4)"; }
gen_pass() { openssl rand -base64 20 | tr -d '=/+' | head -c "$1"; }

# ================================================
# NFTABLES TUNNEL
# ================================================
deploy_nft_tunnel() {
    local name="$1" nft_src="$2"
    mkdir -p /etc/nftables; echo "$nft_src" > "/etc/nftables/${name}.nft"
    if nft -c -f "/etc/nftables/${name}.nft" 2>/dev/null; then
        systemctl enable --now "nftables-tunnel@${name}.service" 2>/dev/null || true
        systemctl restart "nftables-tunnel@${name}.service" 2>/dev/null || true
        log "nftables $name chargée"
    else err "nftables $name invalide"; rm -f "/etc/nftables/${name}.nft"; fi
}
remove_nft_tunnel() {
    local name="$1"
    systemctl disable --now "nftables-tunnel@${name}.service" 2>/dev/null || true
    rm -f "/etc/nftables/${name}.nft"; nft delete table inet "$name" 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
}

# ================================================
# XRAY - INSTALLATION COMPLÈTE
# ================================================
XRAY_BIN="/usr/local/bin/xray"
XRAY_CONFIG="/etc/xray/config.json"
XRAY_USERS="/etc/xray/users.json"
XRAY_DOMAIN="/etc/xray/domain"
XRAY_LOG="/var/log/xray"

xray_installed() { [[ -x "$XRAY_BIN" ]] && systemctl list-unit-files | grep -q "^xray.service"; }

xray_gen_config() {
    local domain="$1"
    cat > "$XRAY_CONFIG" << 'CONFEOF'
{
  "log": { "loglevel": "warning", "access": "/var/log/xray/access.log", "error": "/var/log/xray/error.log" },
  "inbounds": [
    {"tag":"VMess-TCP","port":10001,"listen":"127.0.0.1","protocol":"vmess","settings":{"clients":[]},"streamSettings":{"network":"tcp","security":"none"}},
    {"tag":"VMess-WS","port":10002,"listen":"127.0.0.1","protocol":"vmess","settings":{"clients":[]},"streamSettings":{"network":"ws","security":"none","wsSettings":{"path":"/vmess-ws","headers":{"Host":""}}}},
    {"tag":"VMess-TLS","port":10003,"listen":"127.0.0.1","protocol":"vmess","settings":{"clients":[]},"streamSettings":{"network":"tcp","security":"tls","tlsSettings":{"certificates":[{"certificateFile":"/etc/xray/xray.crt","keyFile":"/etc/xray/xray.key"}]}}},
    {"tag":"VMess-WSS","port":10004,"listen":"127.0.0.1","protocol":"vmess","settings":{"clients":[]},"streamSettings":{"network":"ws","security":"tls","tlsSettings":{"certificates":[{"certificateFile":"/etc/xray/xray.crt","keyFile":"/etc/xray/xray.key"}]},"wsSettings":{"path":"/vmess-wss","headers":{"Host":""}}}},
    {"tag":"VLESS-TCP","port":10005,"listen":"127.0.0.1","protocol":"vless","settings":{"clients":[],"decryption":"none"},"streamSettings":{"network":"tcp","security":"none"}},
    {"tag":"VLESS-WS","port":10006,"listen":"127.0.0.1","protocol":"vless","settings":{"clients":[],"decryption":"none"},"streamSettings":{"network":"ws","security":"none","wsSettings":{"path":"/vless-ws","headers":{"Host":""}}}},
    {"tag":"VLESS-TLS","port":10007,"listen":"127.0.0.1","protocol":"vless","settings":{"clients":[],"decryption":"none"},"streamSettings":{"network":"tcp","security":"tls","tlsSettings":{"certificates":[{"certificateFile":"/etc/xray/xray.crt","keyFile":"/etc/xray/xray.key"}]}}},
    {"tag":"VLESS-WSS","port":10008,"listen":"127.0.0.1","protocol":"vless","settings":{"clients":[],"decryption":"none"},"streamSettings":{"network":"ws","security":"tls","tlsSettings":{"certificates":[{"certificateFile":"/etc/xray/xray.crt","keyFile":"/etc/xray/xray.key"}]},"wsSettings":{"path":"/vless-wss","headers":{"Host":""}}}},
    {"tag":"Trojan-TCP","port":10009,"listen":"127.0.0.1","protocol":"trojan","settings":{"clients":[]},"streamSettings":{"network":"tcp","security":"tls","tlsSettings":{"certificates":[{"certificateFile":"/etc/xray/xray.crt","keyFile":"/etc/xray/xray.key"}]}}},
    {"tag":"Trojan-WS","port":10010,"listen":"127.0.0.1","protocol":"trojan","settings":{"clients":[]},"streamSettings":{"network":"ws","security":"tls","tlsSettings":{"certificates":[{"certificateFile":"/etc/xray/xray.crt","keyFile":"/etc/xray/xray.key"}]},"wsSettings":{"path":"/trojan-ws","headers":{"Host":""}}}},
    {"tag":"Shadowsocks","port":10011,"listen":"127.0.0.1","protocol":"shadowsocks","settings":{"clients":[],"network":"tcp,udp"},"streamSettings":{"network":"tcp","security":"none"}},
    {"tag":"VLESS-XHTTP","port":10012,"listen":"127.0.0.1","protocol":"vless","settings":{"clients":[],"decryption":"none"},"streamSettings":{"network":"xhttp","security":"tls","tlsSettings":{"certificates":[{"certificateFile":"/etc/xray/xray.crt","keyFile":"/etc/xray/xray.key"}]},"xhttpSettings":{"path":"/vless-xhttp","headers":{"Host":""}}}},
    {"tag":"VLESS-gRPC","port":10013,"listen":"127.0.0.1","protocol":"vless","settings":{"clients":[],"decryption":"none"},"streamSettings":{"network":"grpc","security":"tls","tlsSettings":{"certificates":[{"certificateFile":"/etc/xray/xray.crt","keyFile":"/etc/xray/xray.key"}]},"grpcSettings":{"serviceName":"vless-grpc"}}},
    {"tag":"VMess-XHTTP","port":10014,"listen":"127.0.0.1","protocol":"vmess","settings":{"clients":[]},"streamSettings":{"network":"xhttp","security":"tls","tlsSettings":{"certificates":[{"certificateFile":"/etc/xray/xray.crt","keyFile":"/etc/xray/xray.key"}]},"xhttpSettings":{"path":"/vmess-xhttp","headers":{"Host":""}}}},
    {"tag":"VMess-gRPC","port":10015,"listen":"127.0.0.1","protocol":"vmess","settings":{"clients":[]},"streamSettings":{"network":"grpc","security":"tls","tlsSettings":{"certificates":[{"certificateFile":"/etc/xray/xray.crt","keyFile":"/etc/xray/xray.key"}]},"grpcSettings":{"serviceName":"vmess-grpc"}}},
    {"tag":"Trojan-XHTTP","port":10016,"listen":"127.0.0.1","protocol":"trojan","settings":{"clients":[]},"streamSettings":{"network":"xhttp","security":"tls","tlsSettings":{"certificates":[{"certificateFile":"/etc/xray/xray.crt","keyFile":"/etc/xray/xray.key"}]},"xhttpSettings":{"path":"/trojan-xhttp","headers":{"Host":""}}}},
    {"tag":"Trojan-gRPC","port":10017,"listen":"127.0.0.1","protocol":"trojan","settings":{"clients":[]},"streamSettings":{"network":"grpc","security":"tls","tlsSettings":{"certificates":[{"certificateFile":"/etc/xray/xray.crt","keyFile":"/etc/xray/xray.key"}]},"grpcSettings":{"serviceName":"trojan-grpc"}}}
  ],
  "outbounds": [{"tag":"direct","protocol":"freedom","settings":{}}],
  "stats": {},
  "policy": { "levels": { "0": { "statsUserUplink": true, "statsUserDownlink": true } }, "system": { "statsInboundUplink": true, "statsInboundDownlink": true } },
  "api": { "tag": "api", "services": ["HandlerService","StatsService"] },
  "routing": { "rules": [{"type":"field","inboundTag":"api","outboundTag":"api"}] }
}
CONFEOF
}

xray_gen_haproxy() {
    local domain="$1"
    cat > /etc/haproxy/haproxy.cfg << 'HAPEOF'
global
    daemon
    maxconn 65535
    nbproc 1
    tune.ssl.default-dh-param 2048
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384
    ssl-default-bind-options no-sslv3 no-tlsv10 no-tlsv11

defaults
    mode tcp
    log global
    option tcplog
    option dontlognull
    timeout connect 5s
    timeout client 86400s
    timeout server 86400s
    retries 3

# NTLS (Non-TLS) frontend :8880
frontend xray-ntls
    bind *:8880
    use_backend xray-vmess-tcp  if { dst_port 8880 }
    use_backend xray-vmess-ws   if { path_beg /vmess-ws }
    use_backend xray-vless-tcp  if { dst_port 8880 }
    use_backend xray-vless-ws   if { path_beg /vless-ws }
    default_backend xray-vmess-tcp

# TLS Frontend :8443
frontend xray-tls
    bind *:8443 ssl crt /etc/xray/xray.pem alpn h2,http/1.1
    use_backend xray-vmess-tls  if { dst_port 8443 }
    use_backend xray-vmess-wss  if { path_beg /vmess-wss }
    use_backend xray-vless-tls  if { dst_port 8443 }
    use_backend xray-vless-main-wss if { path_beg /vless-wss }
    use_backend xray-trojan-tcp if { dst_port 8443 }
    default_backend xray-vmess-tls

# gRPC + XHTTP
frontend xray-advanced
    bind *:9898 ssl crt /etc/xray/xray.pem alpn h2,http/1.1
    use_backend xray-vless-grpc   if { ssl_fc_alpn h2 }
    use_backend xray-vmess-grpc   if { ssl_fc_alpn h2 }
    use_backend xray-trojan-grpc  if { ssl_fc_alpn h2 }
    default_backend xray-vless-xhttp

# Backends
backend xray-vmess-tcp
    server s1 127.0.0.1:10001 send-proxy
backend xray-vmess-ws
    server s1 127.0.0.1:10002
backend xray-vmess-tls
    server s1 127.0.0.1:10003
backend xray-vmess-wss
    server s1 127.0.0.1:10004
backend xray-vless-tcp
    server s1 127.0.0.1:10005 send-proxy
backend xray-vless-ws
    server s1 127.0.0.1:10006
backend xray-vless-tls
    server s1 127.0.0.1:10007
backend xray-vless-main-wss
    server s1 127.0.0.1:10008
backend xray-trojan-tcp
    server s1 127.0.0.1:10009
backend xray-trojan-ws
    server s1 127.0.0.1:10010
backend xray-ss
    server s1 127.0.0.1:10011
backend xray-vless-xhttp
    server s1 127.0.0.1:10012
backend xray-vless-grpc
    server s1 127.0.0.1:10013
backend xray-vmess-xhttp
    server s1 127.0.0.1:10014
backend xray-vmess-grpc
    server s1 127.0.0.1:10015
backend xray-trojan-xhttp
    server s1 127.0.0.1:10016
backend xray-trojan-grpc
    server s1 127.0.0.1:10017
HAPEOF
}

install_xray() {
    xray_installed && { warn "Xray déjà installé"; pause; return; }
    echo "${CYAN}━━━ Installation Xray + HAProxy + Nginx ━━━${RESET}"
    apt-get update -qq 2>/dev/null
    apt-get install -y -qq nginx haproxy curl socat xz-utils wget unzip jq ca-certificates lsof 2>/dev/null
    systemctl stop nginx haproxy xray 2>/dev/null || true

    local IP DOMAIN; IP=$(hostname -I | awk '{print $1}')
    if [[ -n "${SKIP_PAUSE:-}" ]]; then DOMAIN="$IP"; else read -rp "Domaine (pour TLS): " DOMAIN; DOMAIN=${DOMAIN:-$IP}; fi
    echo "$DOMAIN" > "$XRAY_DOMAIN"

    # Xray binary
    local VER="26.1.23"
    rm -rf /tmp/xray_inst; mkdir -p /tmp/xray_inst; cd /tmp/xray_inst
    curl -L -o xray.zip "https://github.com/XTLS/Xray-core/releases/download/v${VER}/xray-linux-64.zip" 2>/dev/null || \
        curl -L -o xray.zip "https://github.com/XTLS/Xray-core/releases/latest/download/xray-linux-64.zip" 2>/dev/null
    unzip -o xray.zip >/dev/null 2>&1; mv -f xray "$XRAY_BIN"; chmod +x "$XRAY_BIN"
    setcap 'cap_net_bind_service=+ep' "$XRAY_BIN" 2>/dev/null || true
    mkdir -p "$XRAY_LOG" /etc/xray; touch "$XRAY_LOG/access.log" "$XRAY_LOG/error.log"

    # TLS cert
    if [[ "$DOMAIN" != "$IP" ]] && [[ "$DOMAIN" =~ \. ]]; then
        if ! command -v acme.sh &>/dev/null; then
            curl -fsSL https://get.acme.sh | bash 2>/dev/null || true
        fi
        mkdir -p /var/www/html/.well-known/acme-challenge
        cat > /etc/nginx/conf.d/acme-challenge.conf << 'ACME'
server { listen 80; listen [::]:80; server_name _; root /var/www/html; location /.well-known/acme-challenge/ { allow all; } }
ACME
        systemctl start nginx 2>/dev/null || true
        ~/.acme.sh/acme.sh --issue --webroot /var/www/html -d "$DOMAIN" --keylength ec-256 2>/dev/null || true
        ~/.acme.sh/acme.sh --installcert -d "$DOMAIN" --fullchainpath /etc/xray/xray.crt --keypath /etc/xray/xray.key --ecc 2>/dev/null || true
        rm -f /etc/nginx/conf.d/acme-challenge.conf
    else
        openssl req -x509 -newkey rsa:2048 -keyout /etc/xray/xray.key -out /etc/xray/xray.crt -nodes -days 3650 -subj "/CN=$DOMAIN" 2>/dev/null
    fi
    cat /etc/xray/xray.crt /etc/xray/xray.key > /etc/xray/xray.pem
    chmod 600 /etc/xray/xray.key /etc/xray/xray.pem

    xray_gen_config "$DOMAIN"
    xray_gen_haproxy "$DOMAIN"

    echo '{"vmess":[],"vless":[],"trojan":[],"shadow":[]}' > "$XRAY_USERS"

    # Xray systemd
    cat > /etc/systemd/system/xray.service << 'XSVCEOF'
[Unit]
Description=Xray Service
After=network-online.target nss-lookup.target
Wants=network-online.target
StartLimitIntervalSec=0
[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray -config /etc/xray/config.json
Restart=always
RestartSec=5s
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
XSVCEOF

    mkdir -p /etc/systemd/system/nginx.service.d /etc/systemd/system/haproxy.service.d
    printf '[Service]\nRestart=always\nStartLimitIntervalSec=0\n' > /etc/systemd/system/nginx.service.d/override.conf
    printf '[Service]\nRestart=always\nStartLimitIntervalSec=0\n' > /etc/systemd/system/haproxy.service.d/override.conf

    systemctl daemon-reload
    systemctl enable --now xray nginx haproxy 2>/dev/null || true
    sleep 2

    # Watchdogs
    (crontab -l 2>/dev/null | grep -v xray-watchdog | crontab - 2>/dev/null || true)
    (crontab -l 2>/dev/null; echo "*/15 * * * * systemctl is-active --quiet xray || systemctl restart xray >> /var/log/xray-watchdog.log 2>&1"; echo "*/5 * * * * systemctl is-active --quiet haproxy || systemctl restart haproxy >> /var/log/haproxy-watchdog.log 2>&1") | crontab - 2>/dev/null || true

    log "Xray installé: 8880 (NTLS), 8443 (TLS), 9898 (gRPC/XHTTP)"
    IP=$(hostname -I | awk '{print $1}')
    echo "   VMess/VLESS/Trojan/Shadowsocks disponibles"
    pause
}

# ================================================
# XRAY - GÉNÉRATION CONFIG AVEC USERS
# ================================================
xray_build_config() {
    local domain; domain=$(cat "$XRAY_DOMAIN" 2>/dev/null || hostname -I | awk '{print $1}')
    local config; config=$(cat "$XRAY_CONFIG")
    local users; users=$(cat "$XRAY_USERS" 2>/dev/null || echo '{"vmess":[],"vless":[],"trojan":[],"shadow":[]}')
    local tmp; tmp=$(mktemp)

    # Sanitize: convert "uuid" → "id" (bug legacy panel), ensure trojan has "password"
    local sanitized; sanitized=$(echo "$users" | jq '
        .vmess |= map(if has("uuid") then .id = .uuid | del(.uuid) else . end) |
        .vless |= map(if has("uuid") then .id = .uuid | del(.uuid) else . end) |
        .trojan |= map(if has("uuid") then .password = .uuid | del(.uuid) else . end)
    ' 2>/dev/null || echo "$users")

    # Update each inbound with the clients array
    echo "$config" | jq --argjson users "$sanitized" '
        (.inbounds[] | select(.tag == "VMess-TCP")   .settings.clients) = $users.vmess |
        (.inbounds[] | select(.tag == "VMess-WS")    .settings.clients) = $users.vmess |
        (.inbounds[] | select(.tag == "VMess-TLS")   .settings.clients) = $users.vmess |
        (.inbounds[] | select(.tag == "VMess-WSS")   .settings.clients) = $users.vmess |
        (.inbounds[] | select(.tag == "VMess-XHTTP") .settings.clients) = $users.vmess |
        (.inbounds[] | select(.tag == "VMess-gRPC")  .settings.clients) = $users.vmess |
        (.inbounds[] | select(.tag == "VLESS-TCP")   .settings.clients) = $users.vless |
        (.inbounds[] | select(.tag == "VLESS-WS")    .settings.clients) = $users.vless |
        (.inbounds[] | select(.tag == "VLESS-TLS")   .settings.clients) = $users.vless |
        (.inbounds[] | select(.tag == "VLESS-WSS")   .settings.clients) = $users.vless |
        (.inbounds[] | select(.tag == "VLESS-XHTTP") .settings.clients) = $users.vless |
        (.inbounds[] | select(.tag == "VLESS-gRPC")  .settings.clients) = $users.vless |
        (.inbounds[] | select(.tag == "Trojan-TCP")  .settings.clients) = $users.trojan |
        (.inbounds[] | select(.tag == "Trojan-WS")   .settings.clients) = $users.trojan |
        (.inbounds[] | select(.tag == "Trojan-XHTTP").settings.clients) = $users.trojan |
        (.inbounds[] | select(.tag == "Trojan-gRPC") .settings.clients) = $users.trojan |
        (.inbounds[] | select(.tag == "Shadowsocks") .settings.clients) = $users.shadow |
        .outbounds[0].settings = {}
    ' > "$tmp" 2>/dev/null && jq empty "$tmp" >/dev/null 2>&1 && mv "$tmp" "$XRAY_CONFIG" && systemctl restart xray 2>/dev/null || true
}

add_xray_user() {
    systemctl is-active --quiet xray 2>/dev/null || { err "Xray inactif"; pause; return; }
    echo "${CYAN}━━━ Ajout utilisateur Xray ━━━${RESET}"
    echo "Protocoles: 1=VMess, 2=VLESS, 3=Trojan, 4=Shadowsocks"
    read -rp "Protocole (1-4): " PROTO
    read -rp "Username (email): " EMAIL; [[ -z "$EMAIL" ]] && return
    read -rp "Durée (jours): " DAYS; [[ ! "$DAYS" =~ ^[0-9]+$ ]] && return
    local EXPIRE; EXPIRE=$(date -d "+${DAYS} days" '+%Y-%m-%d')
    local ID; ID=$(gen_uuid); local PW; PW=$(gen_pass 16)

    local KEY; case $PROTO in 1) KEY="vmess" ;; 2) KEY="vless" ;; 3) KEY="trojan" ;; 4) KEY="shadow"; ID=$PW ;; *) err "Invalide"; return ;; esac
    local entry
    if [[ "$KEY" == "shadow" ]]; then
        entry="{\"password\":\"$PW\",\"email\":\"$EMAIL\",\"level\":0,\"expire\":\"$EXPIRE\",\"method\":\"chacha20-ietf-poly1305\"}"
    elif [[ "$KEY" == "trojan" ]]; then
        entry="{\"password\":\"$PW\",\"email\":\"$EMAIL\",\"level\":0,\"expire\":\"$EXPIRE\"}"
    else
        entry="{\"id\":\"$ID\",\"email\":\"$EMAIL\",\"level\":0,\"expire\":\"$EXPIRE\"}"
    fi

    local TMP; TMP=$(mktemp)
    jq ".${KEY} += [$entry]" "$XRAY_USERS" > "$TMP" 2>/dev/null && mv "$TMP" "$XRAY_USERS" || { rm -f "$TMP"; err "Erreur"; return; }
    xray_build_config

    local IP; IP=$(hostname -I | awk '{print $1}'); local DOM; DOM=$(cat "$XRAY_DOMAIN" 2>/dev/null || echo "$IP")
    echo "✅ $EMAIL ajouté"
    case $PROTO in
        1) echo "   VMess: $ID | $DOM:8880/8443 | ws /vmess-ws ou /vmess-wss" ;;
        2) echo "   VLESS: $ID | $DOM:8880/8443/9898 | ws/xhttp/grpc" ;;
        3) echo "   Trojan: $PW | $DOM:8443" ;;
        4) echo "   Shadowsocks: $PW@$DOM:8880 | chacha20-ietf-poly1305" ;;
    esac
    pause
}

delete_xray_user() {
    systemctl is-active --quiet xray 2>/dev/null || { err "Xray inactif"; pause; return; }
    echo "${CYAN}━━━ Suppression utilisateur Xray ━━━${RESET}"
    echo "Protocoles: 1=VMess, 2=VLESS, 3=Trojan, 4=Shadowsocks"
    read -rp "Protocole (1-4): " PROTO
    local KEY; case $PROTO in 1) KEY="vmess" ;; 2) KEY="vless" ;; 3) KEY="trojan" ;; 4) KEY="shadow" ;; *) return ;; esac
    local count; count=$(jq ".${KEY} | length" "$XRAY_USERS" 2>/dev/null || echo 0)
    [[ "$count" -eq 0 ]] && { err "Aucun utilisateur"; pause; return; }
    echo "Utilisateurs ${KEY}:"; jq -r ".${KEY}[] | \"\(.email // .password) | expire: \(.expire // \"-\") | id: \(.id // .password)\"" "$XRAY_USERS" 2>/dev/null | nl
    read -rp "Numéro à supprimer: " N; [[ ! "$N" =~ ^[0-9]+$ || "$N" -lt 1 || "$N" -gt "$count" ]] && return
    local TMP; TMP=$(mktemp)
    jq "del(.${KEY}[$((N-1))])" "$XRAY_USERS" > "$TMP" 2>/dev/null && mv "$TMP" "$XRAY_USERS" || { rm -f "$TMP"; return; }
    xray_build_config; echo "✅ Supprimé"; pause
}

# ================================================
# XRAY - DIAGNOSTIC + RÉPARATION + WATCHDOG
# ================================================
xray_gen_service() {
    cat > /etc/systemd/system/xray.service << 'XSVCEOF'
[Unit]
Description=Xray Service; After=network-online.target nss-lookup.target; Wants=network-online.target; StartLimitIntervalSec=0
[Service]
User=root; CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE; AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true; ExecStart=/usr/local/bin/xray -config /etc/xray/config.json; Restart=always; RestartSec=5s; LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
XSVCEOF
}
xray_diagnostic() {
    local errors=0 fixes=0
    echo -e "${BOLD}${CYAN}  ━━━ DIAGNOSTIC XRAY ━━━${RESET}"
    if [[ ! -x "$XRAY_BIN" ]]; then err "Binaire manquant"; ((errors++)); fi
    if [[ -f "$XRAY_CONFIG" ]]; then
        jq empty "$XRAY_CONFIG" 2>/dev/null && log "Config JSON valide" || { err "Config JSON invalide"; ((errors++)); }
    else err "Config manquante"; ((errors++)); fi
    if [[ -f "$XRAY_USERS" ]]; then
        jq empty "$XRAY_USERS" 2>/dev/null && log "Users JSON valide" || { err "Users JSON invalide"; ((errors++)); }
    else warn "Users.json manquant — création"; echo '{"vmess":[],"vless":[],"trojan":[],"shadow":[]}' > "$XRAY_USERS"; ((fixes++)); fi
    for f in /etc/xray/xray.crt /etc/xray/xray.key /etc/xray/xray.pem; do
        [[ -f "$f" ]] && log "  ${f} présent" || warn "  ${f} manquant"
    done
    if [[ -f /etc/xray/xray.crt ]] && openssl x509 -checkend 0 -noout -in /etc/xray/xray.crt 2>/dev/null; then
        local exp; exp=$(openssl x509 -enddate -noout -in /etc/xray/xray.crt 2>/dev/null | cut -d= -f2)
        log "  Certificat valide jusqu'à : ${exp}"
    else warn "  Certificat expiré ou invalide"; fi
    local status; status=$(systemctl is-active xray 2>/dev/null || echo "inactif")
    local enabled; enabled=$(systemctl is-enabled xray 2>/dev/null || echo "désactivé")
    log "Xray: ${status} | Démarrage auto: ${enabled}"
    if [[ $errors -eq 0 ]]; then echo -e "${GREEN}  ✅ Aucun problème critique${RESET}"
    else echo -e "${RED}  ❌ ${errors} problème(s), ${fixes} correction(s)${RESET}"; fi
    return $errors
}

xray_repair_binary() {
    info "Mise à jour du binaire Xray..."
    rm -rf /tmp/xray_rep; mkdir -p /tmp/xray_rep; cd /tmp/xray_rep
    curl -L -o xray.zip "https://github.com/XTLS/Xray-core/releases/latest/download/xray-linux-64.zip" 2>/dev/null
    if [[ -f xray.zip ]]; then
        unzip -o xray.zip >/dev/null 2>&1
        if [[ -f xray ]]; then mv -f xray "$XRAY_BIN"; chmod +x "$XRAY_BIN"; setcap 'cap_net_bind_service=+ep' "$XRAY_BIN" 2>/dev/null || true
            log "Binaire mis à jour : $("$XRAY_BIN" version 2>/dev/null | head -1)"
        else err "Extraction échouée"; fi
    else err "Téléchargement échoué"; fi
    rm -rf /tmp/xray_rep
}

xray_repair_config() {
    local domain; domain=$(cat "$XRAY_DOMAIN" 2>/dev/null || hostname -I | awk '{print $1}')
    info "Régénération de la configuration Xray..."
    [[ -f "$XRAY_CONFIG" ]] && cp "$XRAY_CONFIG" "${XRAY_CONFIG}.bak.$(date +%s)"
    local vmess_clients='[]' vless_clients='[]' trojan_clients='[]' shadow_clients='[]'
    if [[ -f "$XRAY_CONFIG" ]] && jq empty "$XRAY_CONFIG" 2>/dev/null; then
        vmess_clients=$(jq '[.inbounds[] | select(.tag | test("VMess")) | .settings.clients[]] | unique' "$XRAY_CONFIG" 2>/dev/null || echo '[]')
        vless_clients=$(jq '[.inbounds[] | select(.tag | test("VLESS")) | .settings.clients[]] | unique' "$XRAY_CONFIG" 2>/dev/null || echo '[]')
        trojan_clients=$(jq '[.inbounds[] | select(.tag | test("Trojan")) | .settings.clients[]] | unique' "$XRAY_CONFIG" 2>/dev/null || echo '[]')
        shadow_clients=$(jq '[.inbounds[] | select(.tag | test("Shadowsocks")) | .settings.clients[]] | unique' "$XRAY_CONFIG" 2>/dev/null || echo '[]')
    fi
    xray_gen_config "$domain"
    local tmp; tmp=$(mktemp)
    jq --argjson vmess "$vmess_clients" --argjson vless "$vless_clients" --argjson trojan "$trojan_clients" --argjson shadow "$shadow_clients" '
        (.inbounds[] | select(.tag | test("VMess"))   | .settings.clients) = $vmess |
        (.inbounds[] | select(.tag | test("VLESS"))   | .settings.clients) = $vless |
        (.inbounds[] | select(.tag | test("Trojan"))  | .settings.clients) = $trojan |
        (.inbounds[] | select(.tag | test("Shadowsocks")) | .settings.clients) = $shadow
    ' "$XRAY_CONFIG" > "$tmp" 2>/dev/null && jq empty "$tmp" >/dev/null 2>&1 && mv "$tmp" "$XRAY_CONFIG"
    chmod 644 "$XRAY_CONFIG"; log "Configuration regénérée"
}

xray_install_watchdog() {
    echo -e "${BOLD}${CYAN}  ━━━ INSTALLATION WATCHDOG XRAY (4 COUCHES) ━━━${RESET}"
    mkdir -p /etc/kighmu
    cat > /etc/kighmu/xray-watchdog.sh << 'WDEOF'
#!/bin/bash
XRAY_BIN="/usr/local/bin/xray"; XRAY_CONFIG="/etc/xray/config.json"; WATCHDOG_LOG="/var/log/xray-watchdog.log"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$WATCHDOG_LOG"; }
systemctl is-active --quiet xray 2>/dev/null && exit 0
log "[WATCHDOG] Xray INACTIF — réparation..."
[[ ! -x "$XRAY_BIN" ]] && { log "Binaire manquant"; exit 1; }
[[ -f "$XRAY_CONFIG" ]] && ! jq empty "$XRAY_CONFIG" 2>/dev/null && { cp "$XRAY_CONFIG" "${XRAY_CONFIG}.corrupted.$(date +%s)"; log "Config corrompue"; }
for port in 10001 10002 10003 10004 10005 10006 10007 10008 10009 10010 10011 10012 10013 10014 10015 10016 10017 10085; do
    local pid; pid=$(ss -tlnp | grep ":$port " | grep -v xray | grep -oP 'pid=\K[0-9]+' | head -1)
    [[ -n "$pid" ]] && { kill "$pid" 2>/dev/null || true; log "Port $port libéré (PID $pid)"; }
done
systemctl start xray 2>/dev/null; sleep 3
systemctl is-active --quiet xray 2>/dev/null && log "[WATCHDOG] Xray redémarré !" || log "[WATCHDOG] Échec démarrage"
WDEOF
    chmod +x /etc/kighmu/xray-watchdog.sh; log "Script watchdog créé"
    crontab -l 2>/dev/null | grep -v "xray-watchdog" | crontab - 2>/dev/null || true
    (crontab -l 2>/dev/null; echo "* * * * * /etc/kighmu/xray-watchdog.sh") | crontab - 2>/dev/null; log "Cron ajouté (toutes les minutes)"
    cat > /etc/systemd/system/xray-watchdog.service << 'SVCEOF'
[Unit]
Description=Xray Watchdog Service; After=network.target
[Service]
Type=oneshot; ExecStart=/etc/kighmu/xray-watchdog.sh; User=root
SVCEOF
    cat > /etc/systemd/system/xray-watchdog.timer << 'TMREOF'
[Unit]
Description=Xray Watchdog Timer; Requires=xray-watchdog.service
[Timer]
OnBootSec=30; OnUnitActiveSec=120; Unit=xray-watchdog.service
[Install]
WantedBy=timers.target
TMREOF
    systemctl daemon-reload; systemctl enable --now xray-watchdog.timer 2>/dev/null || true; log "systemd timer activé"
    if ! grep -q "xray-watchdog" /etc/rc.local 2>/dev/null; then
        mkdir -p /etc; [[ ! -f /etc/rc.local ]] && echo '#!/bin/bash\nexit 0' > /etc/rc.local && chmod +x /etc/rc.local
        sed -i '/^exit 0/i /etc/kighmu/xray-watchdog.sh' /etc/rc.local 2>/dev/null || true; log "rc.local mis à jour"
    fi
    echo -e "${GREEN}  ✅ Watchdog 4 couches installé :${RESET}"
    echo "   Couche 1: systemd Restart=always | Couche 2: Cron (60s)"
    echo "   Couche 3: systemd timer (2min)  | Couche 4: rc.local (boot)"
}

fix_xray() {
    xray_diagnostic; local rc=$?
    if [[ $rc -gt 0 ]]; then
        echo -e "\n${BOLD}${YELLOW}  🛠️  RÉPARATION AUTOMATIQUE${RESET}"
        [[ ! -x "$XRAY_BIN" ]] && xray_repair_binary
        [[ ! -f "$XRAY_CONFIG" ]] || ! jq empty "$XRAY_CONFIG" 2>/dev/null && xray_repair_config
        [[ ! -f /etc/systemd/system/xray.service ]] && xray_gen_service
        mkdir -p "$XRAY_LOG"; touch "$XRAY_LOG/access.log" "$XRAY_LOG/error.log"
        systemctl daemon-reload; systemctl enable xray 2>/dev/null || true; systemctl start xray 2>/dev/null; sleep 3
        if ! systemctl is-active --quiet xray 2>/dev/null; then
            local test_result; test_result=$("$XRAY_BIN" -test -config "$XRAY_CONFIG" 2>&1)
            if echo "$test_result" | grep -q "Configuration OK"; then
                systemctl start xray 2>/dev/null; sleep 3
            else err "Configuration invalide — régénération..."; xray_repair_config
                systemctl start xray 2>/dev/null; sleep 3
            fi
        fi
    fi
    xray_install_watchdog
    sleep 2
    if systemctl is-active --quiet xray 2>/dev/null; then
        log "Xray actif : $("$XRAY_BIN" version 2>/dev/null | head -1 | head -c 60)"
    else err "Xray toujours inactif — vérifiez: journalctl -u xray -n 50 --no-pager"; fi
    echo -e "${GREEN}  ✅ XRAY RÉPARÉ — WATCHDOG ACTIF${RESET}"
    pause
}

uninstall_xray() {
    read -rp "Confirmer ? (o/N): " C; [[ "$C" =~ ^[oO]$ ]] || return
    systemctl stop xray nginx haproxy 2>/dev/null || true
    systemctl disable xray nginx haproxy 2>/dev/null || true
    rm -f /etc/systemd/system/xray.service
    rm -rf /etc/systemd/system/nginx.service.d /etc/systemd/system/haproxy.service.d
    rm -f "$XRAY_BIN"; rm -rf /etc/xray /var/log/xray
    systemctl daemon-reload
    crontab -l 2>/dev/null | grep -v "xray-watchdog\|haproxy-watchdog" | crontab - 2>/dev/null || true
    log "Xray supprimé"; pause
}

# ================================================
# V2RAY
# ================================================
V2RAY_BIN="/usr/local/bin/v2ray"
V2RAY_CONFIG="/etc/v2ray/config.json"

v2ray_installed() { [[ -x "$V2RAY_BIN" ]] && systemctl list-unit-files | grep -q "^v2ray.service"; }

install_v2ray() {
    v2ray_installed && { warn "V2Ray déjà installé"; pause; return; }
    echo "${CYAN}━━━ Installation V2Ray ━━━${RESET}"
    apt-get install -y -qq jq unzip 2>/dev/null
    local tmp; tmp=$(mktemp)
    wget -q "https://github.com/v2fly/v2ray-core/releases/latest/download/v2ray-linux-64.zip" -O "$tmp"
    rm -rf /tmp/v2ray; unzip -o "$tmp" -d /tmp/v2ray >/dev/null 2>&1
    mv /tmp/v2ray/v2ray "$V2RAY_BIN"; chmod +x "$V2RAY_BIN"; mkdir -p /etc/v2ray

    if [[ -n "${SKIP_PAUSE:-}" ]]; then DOMAIN=$(hostname -I | awk '{print $1}'); else read -rp "Domaine: " DOMAIN; DOMAIN=${DOMAIN:-$(hostname -I | awk '{print $1}')}; fi
    echo "$DOMAIN" > /etc/v2ray/domain.txt

    # Kernel tuning
    cat > /etc/sysctl.d/99-v2ray.conf << 'V2SYSEOF'
net.core.rmem_max = 16777216; net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216; net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_keepalive_time = 60; net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6; net.ipv4.tcp_retries2 = 8
net.ipv4.tcp_syn_retries = 3; net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 4096; net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15; net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
V2SYSEOF
    sysctl -p /etc/sysctl.d/99-v2ray.conf >/dev/null 2>&1 || true

    # Generate UUID + config
    local UUID; UUID=$(gen_uuid)
    cat > "$V2RAY_CONFIG" << V2CONFEOF
{
  "log": {"loglevel":"warning","access":"/var/log/v2ray/access.log","error":"/var/log/v2ray/error.log"},
  "inbounds": [{
    "port": 5401, "listen": "0.0.0.0", "protocol": "vless",
    "settings": {"clients": [{"id":"$UUID","email":"default@v2ray","level":0}],"decryption":"none"},
    "streamSettings": {"network":"tcp","security":"none"},
    "tag": "VLESS-TCP"
  }],
  "outbounds": [{"protocol":"freedom","settings":{}}],
  "stats": {},
  "policy": {"levels":{"0":{"statsUserUplink":true,"statsUserDownlink":true}},"system":{"statsInboundUplink":true,"statsInboundDownlink":true}},
  "api": {"tag":"api","services":["HandlerService","StatsService"]},
  "routing": {"rules":[{"type":"field","inboundTag":"api","outboundTag":"api"}]}
}
V2CONFEOF
    echo '{"vless":[]}' > /etc/v2ray/users.json

    cat > /etc/systemd/system/v2ray.service << 'V2SVCEOF'
[Unit]
Description=V2Ray Service
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/v2ray run -config /etc/v2ray/config.json
Restart=always
RestartSec=5
StartLimitBurst=0
LimitNOFILE=65536
KillMode=process
KillSignal=SIGTERM
TimeoutStopSec=10
[Install]
WantedBy=multi-user.target
V2SVCEOF

    systemctl daemon-reload && systemctl enable --now v2ray 2>/dev/null || true
    deploy_nft_tunnel v2ray 'table inet v2ray { chain input { type filter hook input priority 0; policy accept; tcp dport 5401 accept; }; chain output { type filter hook output priority 0; policy accept; tcp sport 5401 accept; }; }'

    # Watchdog
    (crontab -l 2>/dev/null | grep -v v2ray_watchdog | crontab - 2>/dev/null || true)
    (crontab -l 2>/dev/null; echo "*/15 * * * * systemctl is-active --quiet v2ray || systemctl restart v2ray >> /var/log/v2ray_watchdog.log 2>&1") | crontab - 2>/dev/null || true

    log "V2Ray installé (port 5401, VLESS TCP)"
    pause
}

add_v2ray_user() {
    systemctl is-active --quiet v2ray 2>/dev/null || { err "V2Ray inactif"; pause; return; }
    read -rp "Username: " EMAIL; [[ -z "$EMAIL" ]] && return
    read -rp "Durée (jours): " DAYS; [[ ! "$DAYS" =~ ^[0-9]+$ ]] && return
    local UUID; UUID=$(gen_uuid); local EXPIRE; EXPIRE=$(date -d "+${DAYS} days" '+%Y-%m-%d')
    local TMP; TMP=$(mktemp)
    jq ".vless += [{\"id\":\"$UUID\",\"email\":\"$EMAIL\",\"level\":0,\"expire\":\"$EXPIRE\"}]" /etc/v2ray/users.json > "$TMP" 2>/dev/null && mv "$TMP" /etc/v2ray/users.json
    local users; users=$(cat /etc/v2ray/users.json)
    # Update config
    cat "$V2RAY_CONFIG" | jq --argjson users "$(echo "$users" | jq '.vless')" '.inbounds[0].settings.clients = $users' > "$TMP" 2>/dev/null && mv "$TMP" "$V2RAY_CONFIG"
    systemctl restart v2ray 2>/dev/null || true
    local IP; IP=$(hostname -I | awk '{print $1}')
    echo "✅ $EMAIL ajouté (VLESS TCP, $IP:5401, id: $UUID)"
    pause
}

delete_v2ray_user() {
    systemctl is-active --quiet v2ray 2>/dev/null || { err "V2Ray inactif"; pause; return; }
    local count; count=$(jq '.vless | length' /etc/v2ray/users.json 2>/dev/null || echo 0)
    [[ "$count" -eq 0 ]] && { err "Aucun utilisateur"; pause; return; }
    jq -r '.vless[] | "\(.email) | expire: \(.expire // "-")"' /etc/v2ray/users.json 2>/dev/null | nl
    read -rp "Numéro: " N; [[ ! "$N" =~ ^[0-9]+$ || "$N" -lt 1 || "$N" -gt "$count" ]] && return
    local TMP; TMP=$(mktemp)
    jq "del(.vless[$((N-1))])" /etc/v2ray/users.json > "$TMP" 2>/dev/null && mv "$TMP" /etc/v2ray/users.json
    local users; users=$(cat /etc/v2ray/users.json)
    cat "$V2RAY_CONFIG" | jq --argjson users "$(echo "$users" | jq '.vless')" '.inbounds[0].settings.clients = $users' > "$TMP" 2>/dev/null && mv "$TMP" "$V2RAY_CONFIG"
    systemctl restart v2ray 2>/dev/null || true; echo "✅ Supprimé"; pause
}

fix_v2ray() {
    systemctl reset-failed v2ray 2>/dev/null || true; systemctl restart v2ray 2>/dev/null || true
    systemctl is-active --quiet v2ray && log "V2Ray redémarré" || err "V2Ray inactif"; pause
}

uninstall_v2ray() {
    read -rp "Confirmer ? (o/N): " C; [[ "$C" =~ ^[oO]$ ]] || return
    systemctl stop v2ray 2>/dev/null || true; systemctl disable v2ray 2>/dev/null || true
    rm -f /etc/systemd/system/v2ray.service "$V2RAY_BIN"; rm -rf /etc/v2ray /var/log/v2ray
    remove_nft_tunnel v2ray; systemctl daemon-reload
    crontab -l 2>/dev/null | grep -v v2ray_watchdog | crontab - 2>/dev/null || true
    log "V2Ray supprimé"; pause
}

# ================================================
# MENU XRAY/V2RAY
# ================================================
main_menu() {
    while true; do
        clear
        echo "${CYAN}${BOLD}╔═══════════════════════════════════════╗${RESET}"
        echo "${CYAN}║      XRAY & V2RAY - KIGHMU             ║${RESET}"
        echo "${CYAN}╚═══════════════════════════════════════╝${RESET}"
        echo
        echo "${WHITE}1. Xray (VMess/VLESS/Trojan/Shadowsocks)${RESET}"
        echo "   ${GREEN}[1a]${RESET} Installer    ${GREEN}[1b]${RESET} Ajouter user  ${GREEN}[1c]${RESET} Supprimer user"
        echo "   ${GREEN}[1d]${RESET} Fix/Réparer  ${GREEN}[1e]${RESET} Désinstaller  ${GREEN}[1f]${RESET} Watchdog"
        echo
        echo "${WHITE}2. V2Ray (VLESS TCP)${RESET}"
        echo "   ${GREEN}[2a]${RESET} Installer    ${GREEN}[2b]${RESET} Ajouter user  ${GREEN}[2c]${RESET} Supprimer user"
        echo "   ${GREEN}[2d]${RESET} Fix          ${GREEN}[2e]${RESET} Désinstaller"
        echo
        echo "  ${RED}[0]${RESET} Retour"
        echo
        echo -n "Choix: "
        read -r C
         case $C in
            1a) install_xray ;; 1b) add_xray_user ;; 1c) delete_xray_user ;;
            1d) fix_xray ;; 1e) uninstall_xray ;; 1f) xray_install_watchdog; pause ;;
            2a) install_v2ray ;; 2b) add_v2ray_user ;; 2c) delete_v2ray_user ;;
            2d) fix_v2ray ;; 2e) uninstall_v2ray ;;
            0) exit 0 ;;
            *) ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_root
    main_menu
fi
