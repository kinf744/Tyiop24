#!/bin/bash
# Kighmu Panel - Auto-Installation Commercial 4-en-1
# Sécure, optimisé, haute performance
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PANEL_DIR="/opt/kighmu-panel"
KIGHMU_DIR="/root/Kighmu"
DB_NAME="kighmu_panel"
DB_USER="kighmu_user"

# ================================================
# COULEURS
# ================================================
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

pause() { echo; read -rp "Appuyez sur Entrée pour continuer..."; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        err "Ce script doit être lancé en root."
        exit 1
    fi
}

gen_pass() { openssl rand -base64 20 | tr -d '=/+' | head -c "$1"; }

# ================================================
# ÉTAPE 1 : DÉPENDANCES SYSTÈME
# ================================================
install_system_deps() {
    echo "${CYAN}━━━ Installation des dépendances système ━━━${RESET}"
    apt-get update -qq 2>/dev/null
    apt-get upgrade -y -qq 2>/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        curl wget jq openssl nftables iproute2 \
        xz-utils unzip zip sudo ufw \
        apt-transport-https gnupg lsb-release \
        cron bash-completion ca-certificates lsof \
        build-essential cmake python3 python3-pip \
        git nginx 2>/dev/null
    log "Dépendances système installées"
}

# ================================================
# ÉTAPE 2 : NODE.JS 20 + PM2
# ================================================
install_nodejs() {
    echo "${CYAN}━━━ Installation Node.js 20 + PM2 ━━━${RESET}"
    if command -v node &>/dev/null && [[ "$(node -v)" =~ ^v20 ]]; then
        log "Node.js $(node -v) déjà installé"
    else
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
        apt-get install -y -qq nodejs 2>/dev/null
        log "Node.js $(node -v) installé"
    fi
    npm install -g pm2 --quiet 2>/dev/null || true
    log "PM2 $(pm2 -v 2>/dev/null || echo '?') installé"
}

# ================================================
# ÉTAPE 3 : MYSQL + BASE DE DONNÉES
# ================================================
install_mysql() {
    echo "${CYAN}━━━ Installation MySQL ━━━${RESET}"
    if ! command -v mysql &>/dev/null; then
        apt-get install -y -qq mysql-server 2>/dev/null
        systemctl start mysql 2>/dev/null || true
        systemctl enable mysql 2>/dev/null || true
        log "MySQL installé"
    else
        log "MySQL déjà installé"
    fi
    systemctl start mysql 2>/dev/null || true

    DB_PASS=$(grep '^DB_PASSWORD=' "$PANEL_DIR/.env" 2>/dev/null | cut -d= -f2 || gen_pass 24)
    JWT_SECRET=$(grep '^JWT_SECRET=' "$PANEL_DIR/.env" 2>/dev/null | cut -d= -f2 || openssl rand -base64 64 | tr -d '=/+\n' | head -c 72)
    REPORT_SECRET=$(grep '^REPORT_SECRET=' "$PANEL_DIR/.env" 2>/dev/null | cut -d= -f2 || gen_pass 40)

    mysql -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null
    mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';" 2>/dev/null
    mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost'; FLUSH PRIVILEGES;" 2>/dev/null

    if [[ -f "$SCRIPT_DIR/schema.sql" ]]; then
        mysql "${DB_NAME}" < "$SCRIPT_DIR/schema.sql" 2>/dev/null && log "Schema importé" || warn "Schema déjà présent"
    fi

    log "Base de données configurée"
}

# ================================================
# ÉTAPE 4 : DÉPLOIEMENT DU PANEL
# ================================================
deploy_panel_files() {
    echo "${CYAN}━━━ Déploiement du Panel ━━━${RESET}"
    mkdir -p "$PANEL_DIR/frontend/admin" "$PANEL_DIR/frontend/reseller" "$KIGHMU_DIR"

    for f in server.js admin.html reseller.html; do
        if [[ -f "$SCRIPT_DIR/$f" ]]; then
            cp "$SCRIPT_DIR/$f" "$PANEL_DIR/$f"
        elif [[ -f "$KIGHMU_DIR/$f" ]]; then
            cp "$KIGHMU_DIR/$f" "$PANEL_DIR/$f"
        fi
    done

    cp "$PANEL_DIR/server.js" "$PANEL_DIR/server.js" 2>/dev/null || true

    if [[ -f "$PANEL_DIR/server.js" ]]; then
        mv "$PANEL_DIR/server.js" "$PANEL_DIR/server.js" 2>/dev/null || true
    fi
    for f in admin.html reseller.html; do
        if [[ -f "$PANEL_DIR/$f" ]]; then
            dir_name="${f%.html}"
            cp "$PANEL_DIR/$f" "$PANEL_DIR/frontend/$dir_name/index.html"
        fi
    done

    # Landing page
    if [[ ! -f "$PANEL_DIR/frontend/index.html" ]]; then
        IP=$(hostname -I | awk '{print $1}')
        cat > "$PANEL_DIR/frontend/index.html" << EOF
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Kighmu Panel</title>
<meta http-equiv="refresh" content="0;url=/admin/"></head>
<body><h1>Kighmu Panel</h1><p>Accès admin: <a href="/admin/">/admin/</a></p></body></html>
EOF
    fi

    log "Fichiers du panel déployés"
}

# ================================================
# ÉTAPE 5 : CONFIG .ENV
# ================================================
configure_env() {
    echo "${CYAN}━━━ Configuration .env ━━━${RESET}"
    if [[ -f "$PANEL_DIR/.env" ]]; then
        log ".env déjà présent"
        return
    fi

    DB_PASS=${DB_PASS:-$(gen_pass 24)}
    JWT_SECRET=${JWT_SECRET:-$(openssl rand -base64 64 | tr -d '=/+\n' | head -c 72)}
    REPORT_SECRET=${REPORT_SECRET:-$(gen_pass 40)}

    cat > "$PANEL_DIR/.env" << ENVEOF
PORT=3000
NODE_ENV=production
DB_HOST=127.0.0.1
DB_PORT=3306
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASS}
JWT_SECRET=${JWT_SECRET}
JWT_EXPIRES_IN=8h
BCRYPT_ROUNDS=12
MAX_LOGIN_ATTEMPTS=5
BLOCK_DURATION_MINUTES=30
REPORT_SECRET=${REPORT_SECRET}
XRAY_CONFIG=/etc/xray/config.json
V2RAY_CONFIG=/etc/v2ray/config.json
HYSTERIA_USERS=/etc/hysteria/users.txt
ZIVPN_USERS=/etc/zivpn/users.list
ENVEOF
    chmod 600 "$PANEL_DIR/.env"
    log ".env créé"
}

# ================================================
# ÉTAPE 6 : INSTALLATION NPM + PM2
# ================================================
install_npm_panel() {
    echo "${CYAN}━━━ Installation des modules Node.js ━━━${RESET}"
    cd "$PANEL_DIR"
    if [[ ! -d node_modules ]]; then
        NODE_OPTIONS="--dns-result-order=ipv4first" npm install --production --quiet 2>/dev/null || {
            warn "npm install échoué, réessai..."
            npm install --production --quiet 2>/dev/null
        }
        log "Modules Node.js installés"
    else
        log "Modules déjà présents"
    fi

    pm2 delete kighmu-panel 2>/dev/null || true
    cd "$PANEL_DIR"
    pm2 start server.js --name kighmu-panel --time --cwd "$PANEL_DIR" 2>/dev/null
    pm2 save --force >/dev/null 2>&1
    PM2_STARTUP=$(pm2 startup 2>/dev/null | grep "sudo" | head -1)
    eval "$PM2_STARTUP" >/dev/null 2>&1 || true
    log "Panel démarré via PM2"
}

# ================================================
# ÉTAPE 7 : ADMIN + MOT DE PASSE
# ================================================
create_admin_user() {
    echo "${CYAN}━━━ Création administrateur ━━━${RESET}"
    local user pass
    read -rp "Nom admin [admin]: " user; user=${user:-admin}
    read -rsp "Mot de passe [laissé vide = généré]: " pass; echo

    if [[ -z "$pass" ]]; then
        pass=$(gen_pass 12)
        echo "${YELLOW}Mot de passe généré : $pass${RESET}"
    fi

    node -e "
    const mysql = require('mysql2/promise');
    const bcrypt = require('bcryptjs');
    (async () => {
        const conn = await mysql.createConnection({ host:'127.0.0.1', user:'${DB_USER}', password:'${DB_PASS}', database:'${DB_NAME}' });
        const hash = await bcrypt.hash('$pass', 12);
        await conn.execute('INSERT INTO admins (username, password) VALUES (?,?) ON DUPLICATE KEY UPDATE password=VALUES(password)', ['$user', hash]);
        await conn.end();
        console.log('Admin $user créé');
    })();
    " 2>/dev/null || {
        warn "Impossible de créer l'admin — vérifie MySQL"
    }
    log "Admin '$user' configuré"
}

# ================================================
# ÉTAPE 8 : NGINX
# ================================================
configure_nginx() {
    echo "${CYAN}━━━ Configuration Nginx ━━━${RESET}"
    local IP DOMAIN
    IP=$(hostname -I | awk '{print $1}')
    read -rp "Domaine/IP pour le panel [$IP]: " DOMAIN; DOMAIN=${DOMAIN:-$IP}
    echo "$DOMAIN" > /etc/kighmu/domain.txt 2>/dev/null || true

    systemctl stop nginx 2>/dev/null || true
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

    cat > /etc/nginx/sites-available/kighmu << 'NGXEOF'
server {
    listen 8585;
    server_name _;
    client_max_body_size 32m;
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 86400;
    }
}
NGXEOF
    ln -sf /etc/nginx/sites-available/kighmu /etc/nginx/sites-enabled/
    nginx -t 2>/dev/null && systemctl start nginx && log "Nginx configuré (port 8585)" || err "Nginx config invalide"
}

# ================================================
# ÉTAPE 9 : NFTABLES
# ================================================
setup_nftables() {
    echo "${CYAN}━━━ Configuration nftables ━━━${RESET}"
    systemctl enable --now nftables 2>/dev/null || true

    cat > /usr/local/bin/init-nftables.sh << 'INITEOF'
#!/bin/bash
# Initialise nftables + template tunnel service
mkdir -p /etc/nftables
if ! nft list tables 2>/dev/null | grep -q .; then
    echo "flush ruleset" > /etc/nftables.conf
    systemctl restart nftables 2>/dev/null || true
fi

# Template systemd pour les tunnels nftables
cat > /etc/systemd/system/nftables-tunnel@.service << 'UNIT'
[Unit]
Description=nftables tunnel %i
Before=nftables.service
PartOf=nftables.service
ReloadPropagatedFrom=nftables.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/nft -f /etc/nftables/%i.nft
ExecStop=/usr/sbin/nft delete table inet %i
[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload 2>/dev/null || true
INITEOF
    chmod +x /usr/local/bin/init-nftables.sh
    bash /usr/local/bin/init-nftables.sh

    # Ports panel
    cat > /etc/nftables/kighmu-panel.nft << 'PNLEOF'
table inet kighmu-panel {
    chain input {
        type filter hook input priority 0; policy accept;
        tcp dport { 8585, 8587 } accept
    }
}
PNLEOF
    nft -c -f /etc/nftables/kighmu-panel.nft 2>/dev/null && {
        systemctl enable --now nftables-tunnel@kighmu-panel.service 2>/dev/null || true
        log "nftables panel configuré"
    } || warn "Erreur nftables panel"

    log "nftables initialisé"
}

# ================================================
# ÉTAPE 10 : TRAFFIC COLLECTION
# ================================================
setup_traffic_collection() {
    echo "${CYAN}━━━ Scripts de collecte de trafic ━━━${RESET}"
    mkdir -p /etc/kighmu /var/log/kighmu /var/lib/kighmu/ssh-counters

    REPORT_SECRET=${REPORT_SECRET:-$(grep '^REPORT_SECRET=' "$PANEL_DIR/.env" 2>/dev/null | cut -d= -f2 || echo "")}

    cat > /etc/kighmu/traffic-collect.sh << 'TCEOF'
#!/bin/bash
PANEL_URL="http://127.0.0.1:3000"
SECRET="__REPORT_SECRET__"
XRAY_BIN="${XRAY_BIN:-/usr/local/bin/xray}"
XRAY_API="${XRAY_API:-127.0.0.1:10085}"
V2RAY_BIN="${V2RAY_BIN:-/usr/local/bin/v2ray}"
V2RAY_API="${V2RAY_API:-127.0.0.1:10086}"
DELTA_DIR="/var/lib/kighmu/ssh-counters"
USER_FILE="/etc/kighmu/users.list"
NFT="nft"
TS="$(date '+%Y-%m-%d %H:%M:%S')"

mkdir -p "$DELTA_DIR"

send_stats() {
    local resp
    resp=$(curl -s --max-time 10 -X POST "${PANEL_URL}/api/report/traffic" \
        -H "Content-Type: application/json" \
        -H "x-report-secret: ${SECRET}" \
        -d "$1" 2>/dev/null)
    echo "[${TS}] → ${resp:-no response}"
}

_read_nft_counter() {
    ${NFT} list counter inet kighmu "$1" 2>/dev/null | grep -oP 'bytes \K\d+' || echo 0
}

collect_xray() {
    [ ! -x "$XRAY_BIN" ] && return
    local raw
    raw=$("$XRAY_BIN" api statsquery --server="$XRAY_API" 2>/dev/null) || return
    [[ -z "$raw" ]] && { echo "[${TS}] [XRAY] Aucune stat"; return; }
    local json='{"stats":['
    local first=1 has_data=0
    while IFS='|' read -r name value; do
        local user="${name%%>>>*}"
        local traffic="${name##*>>>}"
        [[ "$user" =~ ^(default|)$ ]] && continue
        [[ "$value" == "0" ]] && continue
        [[ $first -eq 0 ]] && json+=','
        if [[ "$traffic" == "uplink" ]]; then
            json+="{\"username\":\"${user}\",\"upload_bytes\":${value},\"download_bytes\":0}"
        else
            json+="{\"username\":\"${user}\",\"upload_bytes\":0,\"download_bytes\":${value}}"
        fi
        first=0; has_data=1
    done < <(echo "$raw" | jq -r '.stat[]? | select(.name | test("user>>>")) | "\(.name)|\(.value)"' 2>/dev/null)
    json+=']}'
    if [[ $has_data -eq 1 ]]; then
        echo "[${TS}] [XRAY] Envoi stats..."
        send_stats "$json"
    else
        echo "[${TS}] [XRAY] Aucune stat"
    fi
}

collect_v2ray() {
    [ ! -x "$V2RAY_BIN" ] && return
    local raw
    raw=$("$V2RAY_BIN" api stats --server="$V2RAY_API" 2>/dev/null) || return
    [[ -z "$raw" ]] && { echo "[${TS}] [V2RAY] Aucune stat"; return; }
    local json='{"stats":['
    local first=1 has_data=0
    while IFS='|' read -r user up down; do
        [[ -z "$user" ]] && continue
        [[ "$up" == "0" && "$down" == "0" ]] && continue
        [[ $first -eq 0 ]] && json+=','
        json+="{\"username\":\"${user}\",\"upload_bytes\":${up},\"download_bytes\":${down}}"
        first=0; has_data=1
    done < <(echo "$raw" | jq -r '.stat[]? | select(.name | test("user>>>")) | (.name / ">>>") as $p | "\($p[0])|\($p[2]//0)|\($p[3]//0)"' 2>/dev/null)
    json+=']}'
    if [[ $has_data -eq 1 ]]; then
        echo "[${TS}] [V2RAY] Envoi stats..."
        send_stats "$json"
    else
        echo "[${TS}] [V2RAY] Aucune stat"
    fi
}

collect_ssh() {
    [ ! -f "$USER_FILE" ] && return
    command -v nft &>/dev/null || return
    if ! nft list table inet kighmu &>/dev/null; then
        echo "[${TS}] [SSH] Table kighmu absente"
        return
    fi
    local json='{"stats":[' first=1 has_data=0
    while IFS='|' read -r username _rest; do
        [ -z "$username" ] && continue
        local uid
        uid=$(id -u "$username" 2>/dev/null) || continue
        local tag="ssh_${uid}"
        local cur_out cur_in
        cur_out=$(_read_nft_counter "${tag}_out")
        cur_in=$(_read_nft_counter "${tag}_in")
        local prev_out=0 prev_in=0
        [ -f "${DELTA_DIR}/${username}.out" ] && prev_out=$(< "${DELTA_DIR}/${username}.out")
        [ -f "${DELTA_DIR}/${username}.in"  ] && prev_in=$(< "${DELTA_DIR}/${username}.in")
        local delta_out=$(( cur_out - prev_out ))
        local delta_in=$(( cur_in - prev_in ))
        (( delta_out < 0 )) && delta_out=$cur_out
        (( delta_in < 0 )) && delta_in=$cur_in
        if (( delta_out > 0 || delta_in > 0 )); then
            echo "$cur_out" > "${DELTA_DIR}/${username}.out"
            echo "$cur_in"  > "${DELTA_DIR}/${username}.in"
            [[ $first -eq 0 ]] && json+=','
            json+="{\"username\":\"${username}\",\"upload_bytes\":${delta_in},\"download_bytes\":${delta_out}}"
            first=0; has_data=1
        fi
    done < <(cat "$USER_FILE" 2>/dev/null)
    json+=']}'
    if [[ $has_data -eq 1 ]]; then
        echo "[${TS}] [SSH] Envoi stats SSH..."
        send_stats "$json"
    else
        echo "[${TS}] [SSH] Aucun trafic SSH"
    fi
}

echo "[${TS}] === Collecte trafic KIGHMU démarrée ==="
collect_xray
collect_v2ray
collect_ssh
echo "[${TS}] === Terminé ==="
TCEOF
    sed -i "s/__REPORT_SECRET__/${REPORT_SECRET}/g" /etc/kighmu/traffic-collect.sh
    chmod +x /etc/kighmu/traffic-collect.sh

    crontab -l 2>/dev/null | grep -v "traffic-collect\|Auto-clean" | crontab - 2>/dev/null || true
    (crontab -l 2>/dev/null; echo "*/2 * * * * /etc/kighmu/traffic-collect.sh >> /var/log/kighmu-traffic.log 2>&1"; echo "*/10 * * * * ${KIGHMU_DIR}/Auto-clean.sh >> /var/log/auto-clean.log 2>&1") | crontab - 2>/dev/null || true

    log "Collecte de trafic configurée (cron toutes les 2min)"
}

# ================================================
# ÉTAPE 11 : SERVICE BANDWIDTH SSH
# ================================================
setup_bandwidth_service() {
    echo "${CYAN}━━━ Service Bandwidth SSH ━━━${RESET}"
    mkdir -p /var/lib/kighmu

    cat > /usr/local/bin/kighmu-bandwidth.sh << 'BWEOF'
#!/bin/bash
PANEL_URL="http://127.0.0.1:3000"
SECRET="__REPORT_SECRET__"
DELTA_DIR="/var/lib/kighmu/ssh-counters"
USER_FILE="/etc/kighmu/users.list"
NFT="nft"
mkdir -p "$DELTA_DIR"

_read_nft_counter() {
    ${NFT} list counter inet kighmu "$1" 2>/dev/null | grep -oP 'bytes \K\d+' || echo 0
}

_ensure_counter() {
    local name="$1"
    if ! ${NFT} list counter inet kighmu "$name" &>/dev/null; then
        ${NFT} add counter inet kighmu "$name" 2>/dev/null || true
    fi
}

_ensure_rule() {
    local chain="$1" hook="$2" dir="$3"
    if ! ${NFT} -a list chain inet kighmu "$chain" 2>/dev/null | grep -q "counter name ssh"; then
        if [[ "$dir" == "out" ]]; then
            ${NFT} add rule inet kighmu "$chain" meta skuid \$UID counter name ssh_\${UID}_out accept 2>/dev/null || true
        else
            ${NFT} add rule inet kighmu "$chain" meta skuid \$UID counter name ssh_\${UID}_in accept 2>/dev/null || true
        fi
    fi
}

sshNftablesAdd() {
    local username="$1" uid="$2"
    _ensure_counter "ssh_${uid}_out"
    _ensure_counter "ssh_${uid}_in"
    local cur_out cur_in
    cur_out=$(_read_nft_counter "ssh_${uid}_out")
    cur_in=$(_read_nft_counter "ssh_${uid}_in")
    echo "$cur_out" > "${DELTA_DIR}/${username}.out"
    echo "$cur_in"  > "${DELTA_DIR}/${username}.in"
}

sshNftablesRemove() {
    local username="$1" uid="$2"
    ${NFT} delete counter inet kighmu "ssh_${uid}_out" 2>/dev/null || true
    ${NFT} delete counter inet kighmu "ssh_${uid}_in" 2>/dev/null || true
    rm -f "${DELTA_DIR}/${username}.out" "${DELTA_DIR}/${username}.in"
}

while true; do
    ts=$(date +%s)
    while IFS='|' read -r username _rest; do
        [[ -z "$username" ]] && continue
        local uid
        uid=$(id -u "$username" 2>/dev/null) || continue
        local tag="ssh_${uid}"
        local cur_out cur_in
        cur_out=$(_read_nft_counter "${tag}_out")
        cur_in=$(_read_nft_counter "${tag}_in")
        local prev_out=0 prev_in=0
        [[ -f "${DELTA_DIR}/${username}.out" ]] && prev_out=$(< "${DELTA_DIR}/${username}.out")
        [[ -f "${DELTA_DIR}/${username}.in"  ]] && prev_in=$(< "${DELTA_DIR}/${username}.in")
        local delta_out=$(( cur_out - prev_out ))
        local delta_in=$(( cur_in - prev_in ))
        (( delta_out < 0 )) && delta_out=$cur_out
        (( delta_in < 0 )) && delta_in=$cur_in
        if (( delta_out > 0 || delta_in > 0 )); then
            local json="{\"stats\":[{\"username\":\"${username}\",\"upload_bytes\":${delta_in},\"download_bytes\":${delta_out}}]}"
            curl -s --max-time 5 -X POST "${PANEL_URL}/api/report/traffic" \
                -H "Content-Type: application/json" \
                -H "x-report-secret: ${SECRET}" \
                -d "$json" >/dev/null 2>&1 || true
            echo "$cur_out" > "${DELTA_DIR}/${username}.out"
            echo "$cur_in"  > "${DELTA_DIR}/${username}.in"
        fi
    done < <(cat "$USER_FILE" 2>/dev/null)
    sleep 5
done
BWEOF
    sed -i "s/__REPORT_SECRET__/${REPORT_SECRET:-$(grep '^REPORT_SECRET=' "$PANEL_DIR/.env" 2>/dev/null | cut -d= -f2 || echo "")}/g" /usr/local/bin/kighmu-bandwidth.sh
    chmod +x /usr/local/bin/kighmu-bandwidth.sh

    cat > /etc/systemd/system/kighmu-bandwidth.service << 'BWSVC'
[Unit]
Description=KIGHMU SSH Bandwidth Monitor
After=network.target
StartLimitIntervalSec=0
[Service]
Type=simple
ExecStart=/usr/local/bin/kighmu-bandwidth.sh
Restart=always
RestartSec=5
StandardOutput=append:/var/log/kighmu-bandwidth.log
StandardError=append:/var/log/kighmu-bandwidth.log
[Install]
WantedBy=multi-user.target
BWSVC
    systemctl daemon-reload
    systemctl enable --now kighmu-bandwidth.service 2>/dev/null || true
    log "Service Bandwidth SSH activé"
}

# ================================================
# INSTALLATION COMPLÈTE
# ================================================
full_install() {
    clear
    echo "${MAGENTA}${BOLD}╔═══════════════════════════════════════╗${RESET}"
    echo "${MAGENTA}║      INSTALLATION COMPLÈTE KIGHMU       ║${RESET}"
    echo "${MAGENTA}╚═══════════════════════════════════════╝${RESET}"
    echo

    install_system_deps
    install_nodejs
    install_mysql
    deploy_panel_files
    configure_env
    install_npm_panel
    create_admin_user
    configure_nginx
    setup_nftables
    setup_traffic_collection
    setup_bandwidth_service

    echo
    echo "${GREEN}${BOLD}✅ Installation terminée !${RESET}"
    echo "   Panel: http://$(hostname -I | awk '{print $1}'):8585/admin/"
    echo "   Fichiers: install.sh, ssh.sh, udp.sh, xray-v2ray.sh"
    pause
}

# ================================================
# MENU PRINCIPAL
# ================================================
main_menu() {
    while true; do
        clear
        echo "${CYAN}${BOLD}╔═══════════════════════════════════════╗${RESET}"
        echo "${CYAN}║       KIGHMU PANEL v4 - COMMERCIAL      ║${RESET}"
        echo "${CYAN}╚═══════════════════════════════════════╝${RESET}"
        echo
        echo "${WHITE}Infrastructure:${RESET}"
        echo "  ${GREEN}[1]${RESET} Installation complète (tout-en-un)"
        echo "  ${GREEN}[2]${RESET} Installer/Réparer le Panel uniquement"
        echo "  ${GREEN}[3]${RESET} Statut des services"
        echo
        echo "${WHITE}Tunnels disponibles:${RESET}"
        echo "  ${GREEN}[4]${RESET} Tunnels UDP (ZIVPN, Hysteria, BadVPN, UDP Custom)"
        echo "  ${GREEN}[5]${RESET} Xray & V2Ray (VMess, VLESS, Trojan, Shadowsocks)"
        echo "  ${GREEN}[6]${RESET} Tunnels SSH (Dropbear, SlowDNS, SSL, WS, SOCKS)"
        echo
        echo "  ${RED}[0]${RESET} Quitter"
        echo
        echo -n "Choix: "
        read -r CHOIX
        case $CHOIX in
            1) full_install ;;
            2) install_system_deps; install_nodejs; install_mysql; deploy_panel_files; configure_env; install_npm_panel; create_admin_user; configure_nginx; setup_nftables; pause ;;
            3) show_status ;;
            4) bash "$SCRIPT_DIR/udp.sh" ;;
            5) bash "$SCRIPT_DIR/xray-v2ray.sh" ;;
            6) bash "$SCRIPT_DIR/ssh.sh" ;;
            0) exit 0 ;;
            *) ;;
        esac
    done
}

show_status() {
    clear
    echo "${CYAN}━━━ Statut des services ━━━${RESET}"
    for svc in nginx mysql pm2 kighmu-panel nftables ssh dropbear xray v2ray zivpn hysteria badvpn udp-custom slowdns ssl_tls sshws; do
        local display="$svc"
        case $svc in
            kighmu-panel) display="Panel (PM2)" ;;
            pm2) display="PM2" ;;
        esac
        if systemctl is-active --quiet "$svc" 2>/dev/null || pm2 show "$svc" &>/dev/null 2>&1; then
            echo "  ${GREEN}✅${RESET} $display"
        else
            echo "  ${RED}❌${RESET} $display"
        fi
    done
    echo
    echo "${CYAN}Ports ouverts principaux:${RESET}"
    ss -tlnp 2>/dev/null | grep -E '8585|8587|3000|80|443|8880|8443|109|22|444|9090|5667|20000|36712|5401|5353|5300|7100|7200|7300|2095|700' | awk '{print "  "$4}' | sort -u
    pause
}

check_root
main_menu
