#!/bin/bash
# ================================================================
# xray-fix.sh — Diagnostic + Réparation + Watchdog Permanent pour Xray
# Utilisation : bash xray-fix.sh
# ================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
XRAY_BIN="/usr/local/bin/xray"
XRAY_CONFIG="/etc/xray/config.json"
XRAY_USERS="/etc/xray/users.json"
XRAY_LOG="/var/log/xray"
XRAY_SERVICE="/etc/systemd/system/xray.service"
XRAY_DOMAIN_FILE="/etc/xray/domain"

# ── Couleurs ──
RED='\e[91m'; GREEN='\e[92m'; YELLOW='\e[93m'; CYAN='\e[96m'; WHITE='\e[97m'; BOLD='\e[1m'; RESET='\e[0m'
log()  { echo -e "${GREEN}[✓]${RESET} $*"; }
warn() { echo -e "${YELLOW}[!]${RESET} $*"; }
err()  { echo -e "${RED}[✗]${RESET} $*"; }
info() { echo -e "${CYAN}[→]${RESET} $*"; }
HL()   { echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }

check_root() { [[ $EUID -ne 0 ]] && { err "Root requis"; exit 1; }; }

# ================================================================
# ÉTAPE 1 — DIAGNOSTIC COMPLET
# ================================================================
diagnostic() {
    local errors=0 fixes=0

    HL
    echo -e "${BOLD}${CYAN}  🔍 DIAGNOSTIC XRAY — RECHERCHE DES PROBLÈMES${RESET}"
    HL

    # ── 1.1 Binary ──
    echo -e "\n${BOLD}1. Binaire Xray${RESET}"
    if [[ -x "$XRAY_BIN" ]]; then
        local ver; ver=$("$XRAY_BIN" version 2>/dev/null | head -1)
        log "Binaire trouvé : ${ver:-version inconnue}"
    else
        err "Binaire manquant ou non exécutable : $XRAY_BIN"
        ((errors++))
    fi

    # ── 1.2 Config JSON ──
    echo -e "\n${BOLD}2. Fichier de configuration${RESET}"
    if [[ -f "$XRAY_CONFIG" ]]; then
        if jq empty "$XRAY_CONFIG" 2>/dev/null; then
            log "Config JSON valide"
            local inbound_count; inbound_count=$(jq '[.inbounds[] | select(.tag != "api")] | length' "$XRAY_CONFIG" 2>/dev/null || echo 0)
            local api_inbound; api_inbound=$(jq '.inbounds[] | select(.tag == "api") | .port' "$XRAY_CONFIG" 2>/dev/null || echo "absent")
            log "  → ${inbound_count} inbounds actifs, API port: ${api_inbound}"
        else
            err "Config JSON invalide ! $(jq empty "$XRAY_CONFIG" 2>&1)"
            ((errors++))
        fi
    else
        err "Fichier config manquant : $XRAY_CONFIG"
        ((errors++))
    fi

    # ── 1.3 Users JSON ──
    echo -e "\n${BOLD}3. Fichier utilisateurs${RESET}"
    if [[ -f "$XRAY_USERS" ]]; then
        if jq empty "$XRAY_USERS" 2>/dev/null; then
            local total; total=$(jq '[.vmess[], .vless[], .trojan[], .shadow[]] | length' "$XRAY_USERS" 2>/dev/null || echo 0)
            log "Users JSON valide — ${total} utilisateur(s) configuré(s)"
        else
            err "Users JSON invalide !"
            ((errors++))
        fi
    else
        warn "Fichier users.json manquant — création du fichier vide"
        echo '{"vmess":[],"vless":[],"trojan":[],"shadow":[]}' > "$XRAY_USERS"
        log "Fichier users.json créé"
        ((fixes++))
    fi

    # ── 1.4 Certificats TLS ──
    echo -e "\n${BOLD}4. Certificats TLS${RESET}"
    local cert_issues=0
    for f in /etc/xray/xray.crt /etc/xray/xray.key /etc/xray/xray.pem; do
        if [[ -f "$f" ]]; then
            local perm; perm=$(stat -c "%a" "$f" 2>/dev/null || echo "?")
            log "  ${f} (perm: ${perm})"
        else
            warn "  Fichier manquant : $f"
            ((cert_issues++))
        fi
    done
    if [[ -f /etc/xray/xray.crt && -f /etc/xray/xray.key ]]; then
        if openssl x509 -checkend 0 -noout -in /etc/xray/xray.crt 2>/dev/null; then
            local exp; exp=$(openssl x509 -enddate -noout -in /etc/xray/xray.crt 2>/dev/null | cut -d= -f2)
            log "  Certificat valide jusqu'à : ${exp}"
        else
            warn "  Certificat expiré ou invalide — regénération..."
            regen_certs
            ((fixes++))
        fi
    fi
    [[ $cert_issues -gt 0 ]] && { ((errors+=cert_issues)); }

    # ── 1.5 Service systemd ──
    echo -e "\n${BOLD}5. Service systemd${RESET}"
    if [[ -f "$XRAY_SERVICE" ]]; then
        log "Fichier service présent"
        local status; status=$(systemctl is-active xray 2>/dev/null || echo "inactif")
        local enabled; enabled=$(systemctl is-enabled xray 2>/dev/null || echo "désactivé")
        log "  Statut : ${status} | Démarrage automatique : ${enabled}"
        if [[ "$status" != "active" ]]; then
            warn "  Xray n'est pas actif — collecte des logs d'erreur..."
            local logs; logs=$(journalctl -u xray -n 30 --no-pager 2>/dev/null || echo "  (aucun log)")
            echo -e "  ${YELLOW}Dernières lignes de log :${RESET}"
            echo "$logs" | while IFS= read -r line; do echo -e "    ${DIM}$line${RESET}"; done
        fi
    else
        err "Fichier service manquant : $XRAY_SERVICE"
        ((errors++))
    fi

    # ── 1.6 Ports ──
    echo -e "\n${BOLD}6. Ports Xray (inbounds)${RESET}"
    if [[ -f "$XRAY_CONFIG" ]] && jq empty "$XRAY_CONFIG" 2>/dev/null; then
        local port_conflicts=0
        while IFS= read -r port; do
            [[ -z "$port" ]] && continue
            if ss -tlnp | grep -q ":$port "; then
                local proc; proc=$(ss -tlnp | grep ":$port " | grep -oP 'users:\(\(\K[^)]+' | head -1)
                warn "  Port ${port} occupé par : ${proc:-processus inconnu}"
                ((port_conflicts++))
            else
                log "  Port ${port} libre"
            fi
        done < <(jq -r '.inbounds[] | select(.tag != "api") | .port' "$XRAY_CONFIG" 2>/dev/null)
        local api_port; api_port=$(jq -r '.inbounds[] | select(.tag == "api") | .port' "$XRAY_CONFIG" 2>/dev/null)
        if [[ -n "$api_port" ]]; then
            if ss -tlnp | grep -q ":$api_port "; then
                local proc2; proc2=$(ss -tlnp | grep ":$api_port " | grep -oP 'users:\(\( \K[^)]+' | head -1)
                warn "  Port API ${api_port} occupé par : ${proc2:-processus inconnu}"
                ((port_conflicts++))
            else
                log "  Port API ${api_port} libre"
            fi
        fi
        [[ $port_conflicts -eq 0 ]] && log "  Tous les ports sont libres"
    fi

    # ── 1.7 HAProxy ──
    echo -e "\n${BOLD}7. HAProxy${RESET}"
    if systemctl is-active --quiet haproxy 2>/dev/null; then
        log "HAProxy actif"
        local haproxy_ports; haproxy_ports=$(ss -tlnp | grep haproxy | grep -oP ':\K\d+' | sort -u | tr '\n' ' ')
        log "  Ports HAProxy : ${haproxy_ports}"
    else
        warn "HAProxy n'est pas actif — Xray sera inaccessible sur les ports publics (8880/8443/9898)"
    fi

    # ── 1.8 Domaine ──
    echo -e "\n${BOLD}8. Domaine${RESET}"
    if [[ -f "$XRAY_DOMAIN_FILE" ]]; then
        local domain; domain=$(cat "$XRAY_DOMAIN_FILE")
        log "Domaine configuré : ${domain}"
    else
        warn "Aucun domaine configuré — utilisation de l'IP brute"
    fi

    HL
    echo -e "\n${BOLD}RÉSULTAT DU DIAGNOSTIC :${RESET}"
    if [[ $errors -eq 0 ]]; then
        echo -e "${GREEN}  ✅ Aucun problème critique détecté${RESET}"
    else
        echo -e "${RED}  ❌ ${errors} problème(s) détecté(s)${RESET}"
    fi
    echo -e "${CYAN}  🔧 ${fixes} correction(s) automatique(s) appliquée(s)${RESET}"
    echo

    return $errors
}

# ================================================================
# ÉTAPE 2 — RÉPARATION AUTOMATIQUE
# ================================================================
regen_certs() {
    local domain; domain=$(cat "$XRAY_DOMAIN_FILE" 2>/dev/null || hostname -I | awk '{print $1}')
    info "Regénération des certificats TLS pour : ${domain}"
    openssl req -x509 -newkey rsa:2048 -keyout /etc/xray/xray.key -out /etc/xray/xray.crt -nodes -days 3650 -subj "/CN=${domain}" 2>/dev/null
    cat /etc/xray/xray.crt /etc/xray/xray.key > /etc/xray/xray.pem
    chmod 600 /etc/xray/xray.key /etc/xray/xray.pem
    log "Certificats regénérés (expire dans 10 ans)"
}

repair_config() {
    info "Régénération de la configuration Xray de base..."
    local domain; domain=$(cat "$XRAY_DOMAIN_FILE" 2>/dev/null || hostname -I | awk '{print $1}')

    # Sauvegarde de l'ancienne config
    [[ -f "$XRAY_CONFIG" ]] && cp "$XRAY_CONFIG" "${XRAY_CONFIG}.bak.$(date +%s)"

    # Récupérer les clients existants depuis la config actuelle (si elle est lisible)
    local vmess_clients='[]' vless_clients='[]' trojan_clients='[]' shadow_clients='[]'
    if [[ -f "$XRAY_CONFIG" ]] && jq empty "$XRAY_CONFIG" 2>/dev/null; then
        vmess_clients=$(jq '[.inbounds[] | select(.tag | test("VMess")) | .settings.clients[]] | unique' "$XRAY_CONFIG" 2>/dev/null || echo '[]')
        vless_clients=$(jq '[.inbounds[] | select(.tag | test("VLESS")) | .settings.clients[]] | unique' "$XRAY_CONFIG" 2>/dev/null || echo '[]')
        trojan_clients=$(jq '[.inbounds[] | select(.tag | test("Trojan")) | .settings.clients[]] | unique' "$XRAY_CONFIG" 2>/dev/null || echo '[]')
        shadow_clients=$(jq '[.inbounds[] | select(.tag | test("Shadowsocks")) | .settings.clients[]] | unique' "$XRAY_CONFIG" 2>/dev/null || echo '[]')
        info "Clients existants préservés depuis l'ancienne config"
    fi

    # Utiliser xray_gen_config depuis xray-v2ray.sh ou générer directement
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

    # Injecter les clients existants
    local tmp; tmp=$(mktemp)
    jq --argjson vmess "$vmess_clients" --argjson vless "$vless_clients" --argjson trojan "$trojan_clients" --argjson shadow "$shadow_clients" '
        (.inbounds[] | select(.tag | test("VMess"))   | .settings.clients) = $vmess  |
        (.inbounds[] | select(.tag | test("VLESS"))   | .settings.clients) = $vless  |
        (.inbounds[] | select(.tag | test("Trojan"))  | .settings.clients) = $trojan |
        (.inbounds[] | select(.tag | test("Shadowsocks")) | .settings.clients) = $shadow
    ' "$XRAY_CONFIG" > "$tmp" 2>/dev/null && jq empty "$tmp" >/dev/null 2>&1 && mv "$tmp" "$XRAY_CONFIG"

    chmod 644 "$XRAY_CONFIG"
    log "Configuration regénérée avec succès"
}

repair_binary() {
    info "Téléchargement de la dernière version de Xray..."
    rm -rf /tmp/xray_fix_inst; mkdir -p /tmp/xray_fix_inst; cd /tmp/xray_fix_inst
    curl -L -o xray.zip "https://github.com/XTLS/Xray-core/releases/latest/download/xray-linux-64.zip" 2>/dev/null
    if [[ -f xray.zip ]]; then
        unzip -o xray.zip >/dev/null 2>&1
        if [[ -f xray ]]; then
            mv -f xray "$XRAY_BIN"
            chmod +x "$XRAY_BIN"
            setcap 'cap_net_bind_service=+ep' "$XRAY_BIN" 2>/dev/null || true
            local ver; ver=$("$XRAY_BIN" version 2>/dev/null | head -1)
            log "Binaire mis à jour : ${ver:-version inconnue}"
        else
            err "Échec extraction du binaire Xray"
        fi
    else
        err "Échec téléchargement Xray"
    fi
    rm -rf /tmp/xray_fix_inst
}

repair_service_file() {
    info "Réparation du fichier service systemd..."
    mkdir -p /var/log/xray
    cat > "$XRAY_SERVICE" << 'UNIT'
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
UNIT
    systemctl daemon-reload
    log "Fichier service réparé"
}

repair_logs() {
    mkdir -p "$XRAY_LOG"
    touch "$XRAY_LOG/access.log" "$XRAY_LOG/error.log"
    chmod 755 "$XRAY_LOG"
}

# ================================================================
# ÉTAPE 3 — INSTALLATION WATCHDOG PERMANENT (multi-couche)
# ================================================================
install_watchdog() {
    HL
    echo -e "${BOLD}${CYAN}  🛡️ INSTALLATION WATCHDOG PERMANENT (3 COUCHES)${RESET}"
    HL

    # ── Couche 1 : systemd service avec Restart=always (déjà en place) ──
    info "Couche 1 : systemd Restart=always ✓ (déjà actif)"

    # ── Couche 2 : Watchdog shell script (toutes les 60s) ──
    info "Couche 2 : Script watchdog toutes les 60 secondes..."

    mkdir -p /etc/kighmu

    cat > /etc/kighmu/xray-watchdog.sh << 'WDEOF'
#!/bin/bash
# Xray Watchdog — vérifie et répare Xray toutes les 60s
# Installé par xray-fix.sh

XRAY_BIN="/usr/local/bin/xray"
XRAY_CONFIG="/etc/xray/config.json"
XRAY_LOG="/var/log/xray"
WATCHDOG_LOG="/var/log/xray-watchdog.log"
MAX_RESTART=5
RESTART_WINDOW=300  # 5 minutes

mkdir -p "$XRAY_LOG"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$WATCHDOG_LOG"; }

# Vérifier si Xray tourne
if systemctl is-active --quiet xray 2>/dev/null; then
    exit 0
fi

log "[WATCHDOG] Xray INACTIF — tentative de réparation..."

# 1. Vérifier le binary
if [[ ! -x "$XRAY_BIN" ]]; then
    log "Binaire Xray manquant !"
    exit 1
fi

# 2. Vérifier la config
if [[ -f "$XRAY_CONFIG" ]] && ! jq empty "$XRAY_CONFIG" 2>/dev/null; then
    log "Config JSON invalide ! Sauvegarde et restauration..."
    cp "$XRAY_CONFIG" "${XRAY_CONFIG}.corrupted.$(date +%s)"
fi

# 3. Vérifier les certificats TLS
if [[ -f /etc/xray/xray.crt ]] && [[ -f /etc/xray/xray.key ]]; then
    if ! openssl x509 -checkend 0 -noout -in /etc/xray/xray.crt 2>/dev/null; then
        log "Certificat TLS expiré — regénération..."
        local domain; domain=$(cat /etc/xray/domain 2>/dev/null || hostname -I | awk '{print $1}')
        openssl req -x509 -newkey rsa:2048 -keyout /etc/xray/xray.key -out /etc/xray/xray.crt -nodes -days 3650 -subj "/CN=${domain}" 2>/dev/null
        cat /etc/xray/xray.crt /etc/xray/xray.key > /etc/xray/xray.pem
        chmod 600 /etc/xray/xray.key /etc/xray/xray.pem
    fi
fi

# 4. Vérifier les ports — tuer les processus qui bloquent nos ports
for port in 10001 10002 10003 10004 10005 10006 10007 10008 10009 10010 10011 10012 10013 10014 10015 10016 10017 10085; do
    local pid; pid=$(ss -tlnp | grep ":$port " | grep -v xray | grep -oP 'pid=\K[0-9]+' | head -1)
    if [[ -n "$pid" ]]; then
        log "Port $port bloqué par PID $pid — libération..."
        kill "$pid" 2>/dev/null || true
        sleep 1
    fi
done

# 5. Démarrer Xray
log "Démarrage de Xray..."
systemctl start xray 2>/dev/null
sleep 3

if systemctl is-active --quiet xray 2>/dev/null; then
    log "[WATCHDOG] Xray redémarré avec succès !"
else
    log "[WATCHDOG] ÉCHEC démarrage Xray — logs:"
    journalctl -u xray -n 20 --no-pager >> "$WATCHDOG_LOG" 2>/dev/null
fi
WDEOF
    chmod +x /etc/kighmu/xray-watchdog.sh
    log "Script watchdog créé : /etc/kighmu/xray-watchdog.sh"

    # Nettoyer l'ancien cron watchdog (toutes les 15 min)
    crontab -l 2>/dev/null | grep -v "xray-watchdog\|xray.*is-active" | crontab - 2>/dev/null || true

    # Ajouter le nouveau cron (toutes les minutes)
    (crontab -l 2>/dev/null; echo "* * * * * /etc/kighmu/xray-watchdog.sh") | crontab - 2>/dev/null
    log "Cron ajouté : * * * * * /etc/kighmu/xray-watchdog.sh (toutes les minutes)"

    # ── Couche 3 : systemd timer (toutes les 2 minutes) ──
    info "Couche 3 : systemd timer (toutes les 2 min)..."

    cat > /etc/systemd/system/xray-watchdog.service << 'SVCEOF'
[Unit]
Description=Xray Watchdog Service
After=network.target

[Service]
Type=oneshot
ExecStart=/etc/kighmu/xray-watchdog.sh
User=root
Group=root
SVCEOF

    cat > /etc/systemd/system/xray-watchdog.timer << 'TMREOF'
[Unit]
Description=Xray Watchdog Timer (toutes les 2 minutes)
Requires=xray-watchdog.service

[Timer]
OnBootSec=30
OnUnitActiveSec=120
Unit=xray-watchdog.service

[Install]
WantedBy=timers.target
TMREOF

    systemctl daemon-reload
    systemctl enable --now xray-watchdog.timer 2>/dev/null || true
    log "systemd timer xray-watchdog.timer activé (toutes les 2min)"

    # ── Couche 4 : Xray auto-heal au boot via rc.local ──
    info "Couche 4 : Auto-heal au boot..."
    if ! grep -q "xray-watchdog" /etc/rc.local 2>/dev/null; then
        mkdir -p /etc
        if [[ ! -f /etc/rc.local ]]; then
            echo '#!/bin/bash' > /etc/rc.local
            echo 'exit 0' >> /etc/rc.local
            chmod +x /etc/rc.local
        fi
        sed -i '/^exit 0/i # Xray auto-heal au boot\n/etc/kighmu/xray-watchdog.sh' /etc/rc.local 2>/dev/null || true
        log "/etc/rc.local mis à jour"
    fi

    # Nettoyer les logs watchdog (garder 7 jours)
    cat > /etc/logrotate.d/xray-watchdog << 'LOGREOF'
/var/log/xray-watchdog.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
LOGREOF
    log "Logrotate configuré pour le watchdog"

    HL
    echo -e "${GREEN}  ✅ Watchdog multicouche installé !${RESET}"
    echo -e "  ${CYAN}Couche 1 :${RESET} systemd Restart=always (instantané)"
    echo -e "  ${CYAN}Couche 2 :${RESET} Cron toutes les 60s"
    echo -e "  ${CYAN}Couche 3 :${RESET} systemd timer toutes les 2min"
    echo -e "  ${CYAN}Couche 4 :${RESET} rc.local au boot"
    echo -e "  ${CYAN}Logs :${RESET} /var/log/xray-watchdog.log"
    HL
}

# ================================================================
# ÉTAPE 4 — VÉRIFICATION FINALE
# ================================================================
verification_finale() {
    HL
    echo -e "${BOLD}${CYAN}  ✅ VÉRIFICATION FINALE${RESET}"
    HL

    sleep 2

    if systemctl is-active --quiet xray 2>/dev/null; then
        local ver; ver=$("$XRAY_BIN" version 2>/dev/null | head -1 | head -c 60)
        log "Xray actif : ${ver}"
        
        # Vérifier que l'API répond
        local api_port; api_port=$(jq -r '.inbounds[] | select(.tag == "api") | .port' "$XRAY_CONFIG" 2>/dev/null || echo 10085)
        if "$XRAY_BIN" api statsquery --server="127.0.0.1:${api_port}" 2>/dev/null | jq empty 2>/dev/null; then
            log "API Xray opérationnelle (port ${api_port})"
        else
            warn "API Xray ne répond pas — le trafic ne sera pas collecté"
        fi
    else
        err "Xray toujours inactif après réparation"
        info "Vérifiez les logs : journalctl -u xray -n 50 --no-pager"
        info "Ou exécutez : /usr/local/bin/xray -test -config /etc/xray/config.json"
        return 1
    fi

    # Vérifier le watchdog
    if crontab -l 2>/dev/null | grep -q "xray-watchdog"; then
        log "Watchdog cron actif"
    else
        warn "Watchdog cron manquant"
    fi
    if systemctl is-active --quiet xray-watchdog.timer 2>/dev/null; then
        log "Watchdog timer systemd actif"
    else
        warn "Watchdog timer systemd inactif"
    fi

    HL
    echo -e "${GREEN}  ✅ XRAY FONCTIONNEL — PLUS AUCUNE PANNE ANNONCÉE${RESET}"
    HL
}

# ================================================================
# MAIN
# ================================================================
check_root

clear
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}║${RESET}  ${BOLD}${WHITE}      XRAY FIX — DIAGNOSTIC + RÉPARATION + WATCHDOG${RESET}      ${CYAN}║${RESET}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${RESET}"
echo

# Étape 1 : Diagnostic
diagnostic
local diag_result=$?

if [[ $diag_result -gt 0 ]]; then
    echo
    HL
    echo -e "${BOLD}${YELLOW}  🛠️ LANCEMENT DE LA RÉPARATION AUTOMATIQUE${RESET}"
    HL

    # Binary
    if [[ ! -x "$XRAY_BIN" ]]; then
        repair_binary
    fi

    # Config
    if [[ ! -f "$XRAY_CONFIG" ]] || ! jq empty "$XRAY_CONFIG" 2>/dev/null; then
        repair_config
    fi

    # Service file
    if [[ ! -f "$XRAY_SERVICE" ]]; then
        repair_service_file
    fi

    # Logs
    repair_logs

    # Tentative de démarrage
    info "Tentative de démarrage de Xray..."
    systemctl daemon-reload
    systemctl enable xray 2>/dev/null || true
    systemctl start xray 2>/dev/null
    sleep 3

    # Si toujours pas actif, essai avec -test
    if ! systemctl is-active --quiet xray 2>/dev/null; then
        info "Test de la configuration : /usr/local/bin/xray -test -config /etc/xray/config.json"
        local test_result; test_result=$("$XRAY_BIN" -test -config "$XRAY_CONFIG" 2>&1)
        if echo "$test_result" | grep -q "Configuration OK"; then
            log "Configuration valide — nouvelle tentative de démarrage..."
            systemctl start xray 2>/dev/null
            sleep 3
        else
            err "Configuration invalide :"
            echo "$test_result" | while IFS= read -r line; do echo -e "  ${RED}${line}${RESET}"; done
            info "Régénération de la config de base..."
            repair_config
            systemctl start xray 2>/dev/null
            sleep 3
        fi
    fi
fi

# Installer le watchdog dans tous les cas
echo
install_watchdog

# Vérification finale
echo
verification_finale

# Résumé
echo
HL
echo -e "${BOLD}${GREEN}  🔧 RÉSUMÉ DES OPÉRATIONS${RESET}"
HL
echo -e "  ${WHITE}Script exécuté :${RESET} $(basename "$0")"
echo -e "  ${WHITE}Binaire Xray :${RESET} $("$XRAY_BIN" version 2>/dev/null | head -1 | head -c 60)"
echo -e "  ${WHITE}Statut :${RESET} $(systemctl is-active xray 2>/dev/null)"
echo -e "  ${WHITE}Watchdog cron :${RESET} $(crontab -l 2>/dev/null | grep -c 'xray-watchdog') entrée(s)"
echo -e "  ${WHITE}Watchdog timer :${RESET} $(systemctl is-active xray-watchdog.timer 2>/dev/null || echo 'inactif')"
echo -e "  ${WHITE}Log watchdog :${RESET} /var/log/xray-watchdog.log"
echo
info "Pour vérifier en temps réel : tail -f /var/log/xray-watchdog.log"
HL
