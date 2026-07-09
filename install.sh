#!/bin/bash
# Kighmu Panel - Auto-Installation Commercial 4-en-1
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PANEL_DIR="/opt/kighmu-panel"
KIGHMU_DIR="/root/Kighmu-v2"
DB_NAME="kighmu_panel"
DB_USER="kighmu_user"

# ── Couleurs 24-bit ──
BG='\e[48;2;43;15;66m'
CYAN='\e[38;2;30;144;255m'
TITLE_BG='\e[48;2;91;79;232m'
LAV='\e[38;2;155;143;232m'
WHITE='\e[97m'
BOLD='\e[1m'
DIM='\e[2m'
MAG='\e[38;2;255;0;255m'
GREEN='\e[38;2;0;255;0m'
YELLOW='\e[38;2;255;200;0m'
ORANGE='\e[38;2;255;165;0m'
RED='\e[91m'
RESET='\e[0m'
CLR='\e[2J\e[H'

center() { local t="$1" w=${2:-60} l; l=$(echo -e "$t" | sed 's/\x1b\[[0-9;]*m//g' | wc -c); l=$((l-1)); printf "%$(( (w-l)/2 ))s%b%$(( (w-l+1)/2 ))s" "" "$t" ""; }
log() { echo -e "${GREEN}[✓]${RESET} $*"; }
warn() { echo -e "${YELLOW}[!]${RESET} $*"; }
err() { echo -e "${RED}[✗]${RESET} $*"; }
pause() { echo; read -rp "  Press Enter..."; }

gen_pass() { openssl rand -base64 20 | tr -d '=/+' | head -c "$1"; }

step_header() {
    echo
    echo -e "${BG}${CYAN}╔═══$(printf '═%.0s' {1..57})═══╗${RESET}"
    echo -e "${BG}${CYAN}║${RESET}${TITLE_BG}$(center "$1" 61)${RESET}${BG}${CYAN}║${RESET}"
    echo -e "${BG}${CYAN}╚═══$(printf '═%.0s' {1..57})═══╝${RESET}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then err "Root required"; exit 1; fi
}

# ── Écran d'accueil ──
show_banner() {
    echo -e "${CLR}${BG}"
    echo -e "${BG}${CYAN}╔═══$(printf '═%.0s' {1..67})═══╗${RESET}"
    echo -e "${BG}${CYAN}║${RESET}${TITLE_BG}$(center '  KIGHMU PREMIUM VPN  ' 71)${RESET}${BG}${CYAN}║${RESET}"
    echo -e "${BG}${CYAN}║${RESET}${TITLE_BG}$(center 'Installation Commerciale 4-en-1' 71)${RESET}${BG}${CYAN}║${RESET}"
    echo -e "${BG}${CYAN}╚═══$(printf '═%.0s' {1..67})═══╝${RESET}"
    echo
    echo -e "${BG}  ${LAV}Infrastructure complète :${RESET}"
    echo -e "${BG}  ${WHITE}∘ Panel Web (Node.js + MySQL)${RESET}"
    echo -e "${BG}  ${WHITE}∘ Xray (VMess / VLESS / Trojan / Shadowsocks)${RESET}"
    echo -e "${BG}  ${WHITE}∘ V2Ray DNS${RESET}"
    echo -e "${BG}  ${WHITE}∘ SSH + Dropbear + SlowDNS + SSL + WS${RESET}"
    echo -e "${BG}  ${WHITE}∘ Hysteria v1 + ZIVPN + BadVPN + UDP Custom${RESET}"
    echo
}

# ── Page NS (Nameserver) ──
ask_nameservers() {
    clear
    echo -e "${CLR}${BG}"
    echo -e "${BG}${CYAN}╔═══$(printf '═%.0s' {1..67})═══╗${RESET}"
    echo -e "${BG}${CYAN}║${RESET}${TITLE_BG}$(center '🌐  CONFIGURATION NAMESERVER  🌐' 71)${RESET}${BG}${CYAN}║${RESET}"
    echo -e "${BG}${CYAN}╚═══$(printf '═%.0s' {1..67})═══╝${RESET}"
    echo
    echo -e "${BG}  ${LAV}Les nameservers sont utilisés par SlowDNS et V2Ray DNS.${RESET}"
    echo -e "${BG}  ${LAV}Ils pointent vers votre VPS pour les requêtes DNS.${RESET}"
    echo
    echo -e "${BG}  ${ORANGE}>>${RESET} ${LAV}NS4 (SlowDNS)${RESET}"
    echo -e "${BG}  ${DIM}  Ex: ns4.example.com${RESET}"
    echo -ne "${BG}${WHITE}  » ${RESET}"; read -r NS4
    NS4=${NS4:-ns4.kingom.ggff.net}
    echo
    echo -e "${BG}  ${ORANGE}>>${RESET} ${LAV}NV4 (V2Ray DNS)${RESET}"
    echo -e "${BG}  ${DIM}  Ex: nv4.example.com${RESET}"
    echo -ne "${BG}${WHITE}  » ${RESET}"; read -r NV4
    NV4=${NV4:-nv4.kingom.ggff.net}
    echo
    echo -e "${BG}  ${GREEN}Nameservers configurés${RESET}"
    sleep 1
}

# ── DÉPENDANCES (totalement silencieuses) ──
install_system_deps() {
    step_header '📦  Dépendances Système  📦'
    apt-get update -qq 2>/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        curl wget jq openssl nftables iproute2 \
        xz-utils unzip zip sudo ufw \
        apt-transport-https gnupg lsb-release \
        cron bash-completion ca-certificates lsof \
        build-essential cmake python3 python3-pip \
        git nginx mysql-server 2>/dev/null
    # Reinstall si les fichiers de base ont été supprimés (ex: désinstallation incomplète)
    [[ ! -f /etc/nginx/nginx.conf ]] && apt-get install --reinstall -y -qq nginx 2>/dev/null
    [[ ! -f /etc/mysql/my.cnf ]] && apt-get install --reinstall -y -qq mysql-server 2>/dev/null
    [[ ! -f /etc/haproxy/haproxy.cfg ]] && apt-get install --reinstall -y -qq haproxy 2>/dev/null
    log "Dépendances installées"
}

# ── NODE.JS 20 + PM2 ──
install_nodejs() {
    step_header '🟢  Node.js 20 + PM2  🟢'
    if command -v node &>/dev/null && [[ "$(node -v)" =~ ^v20 ]]; then
        log "Node.js $(node -v) déjà présent"
    else
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nodejs 2>/dev/null
        log "Node.js $(node -v) installé"
    fi
    npm install -g pm2 --quiet 2>/dev/null || true
    log "PM2 $(pm2 -v 2>/dev/null || echo '?')"
}

# ── MYSQL ──
install_mysql() {
    step_header '🗄️  MySQL + Base de données  🗄️'
    systemctl start mysql 2>/dev/null || true
    systemctl enable mysql 2>/dev/null || true

    DB_PASS=$(grep '^DB_PASSWORD=' "$PANEL_DIR/.env" 2>/dev/null | cut -d= -f2 || gen_pass 24)
    JWT_SECRET=$(grep '^JWT_SECRET=' "$PANEL_DIR/.env" 2>/dev/null | cut -d= -f2 || openssl rand -base64 64 | tr -d '=/+\n' | head -c 72)
    REPORT_SECRET=$(grep '^REPORT_SECRET=' "$PANEL_DIR/.env" 2>/dev/null | cut -d= -f2 || gen_pass 40)

    mysql -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null
    mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';" 2>/dev/null
    mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost'; FLUSH PRIVILEGES;" 2>/dev/null

    local GH="https://raw.githubusercontent.com/kinf744/Tyiop24/main"
    if [[ -f "$PANEL_DIR/schema.sql" ]]; then
        mysql "${DB_NAME}" < "$PANEL_DIR/schema.sql" 2>/dev/null && log "Schema importé" || warn "Schema déjà présent"
    else
        curl -fsSL "$GH/schema.sql" -o /tmp/schema.sql 2>/dev/null && mysql "${DB_NAME}" < /tmp/schema.sql 2>/dev/null && log "Schema importé (GitHub)" && rm -f /tmp/schema.sql || warn "Schema non trouvé"
    fi
    log "Base de données prête"
}

# ── DÉPLOIEMENT PANEL ──
deploy_panel_files() {
    step_header '📁  Déploiement Panel  📁'
    mkdir -p "$PANEL_DIR/frontend/admin" "$PANEL_DIR/frontend/reseller" "$KIGHMU_DIR"
    local GH="https://raw.githubusercontent.com/kinf744/Tyiop24/main"
    if [[ -f "$SCRIPT_DIR/panel.sh" ]]; then
        source "$SCRIPT_DIR/panel.sh" && extract_web_panel "$PANEL_DIR" && log "Panel extrait de panel.sh"
    elif [[ -f "$KIGHMU_DIR/panel.sh" ]]; then
        source "$KIGHMU_DIR/panel.sh" && extract_web_panel "$PANEL_DIR" && log "Panel extrait de $KIGHMU_DIR/panel.sh"
    else
        curl -fsSL "$GH/panel.sh" -o /tmp/panel.sh 2>/dev/null && source /tmp/panel.sh && extract_web_panel "$PANEL_DIR" && rm -f /tmp/panel.sh && log "Panel téléchargé et extrait depuis GitHub"
        if [[ ! -f "$PANEL_DIR/package.json" ]]; then
            warn "Échec téléchargement panel.sh — création panel minimal"
            cat > "$PANEL_DIR/package.json" << 'EOF'
{"name":"kighmu-panel","version":"4.0.0","private":true,"dependencies":{"express":"^4.18.2","mysql2":"^3.6.0","bcryptjs":"^2.4.3","jsonwebtoken":"^9.0.2","cors":"^2.8.5","morgan":"^1.10.0","axios":"^1.6.0","dotenv":"^16.4.5","uuid":"^9.0.1","helmet":"^7.1.0","express-rate-limit":"^7.1.5","node-cron":"^3.0.3","systeminformation":"^5.21.8"}}
EOF
            cat > "$PANEL_DIR/server.js" << 'EOF'
const express=require('express');const app=express();app.get('/',(r,s)=>s.send('Kighmu Panel'));app.listen(3000);
EOF
            echo '<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Kighmu Panel</title></head><body><h1>Kighmu Panel</h1></body></html>' > "$PANEL_DIR/frontend/index.html"
        fi
    fi
    log "Fichiers panel déployés"
}

# ── .ENV ──
configure_env() {
    step_header '🔐  Configuration .env  🔐'
    [[ -f "$PANEL_DIR/.env" ]] && { log ".env présent"; return; }
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

# ── NPM + PM2 ──
install_npm_panel() {
    step_header '📦  Modules Node.js  📦'
    pushd "$PANEL_DIR" >/dev/null || return 1
    if [[ ! -d node_modules ]]; then
        NODE_OPTIONS="--dns-result-order=ipv4first" npm install --production --quiet 2>/dev/null || npm install --production --quiet 2>/dev/null || warn "npm install warnings"
        log "Modules installés"
    fi
    pm2 delete kighmu-panel 2>/dev/null || true
    pm2 start server.js --name kighmu-panel --time --cwd "$PANEL_DIR" 2>/dev/null
    pm2 save --force >/dev/null 2>&1
    PM2_STARTUP=$(pm2 startup 2>/dev/null | grep "sudo" | head -1)
    eval "$PM2_STARTUP" >/dev/null 2>&1 || true
    log "Panel démarré"
    popd >/dev/null || true
}

# ── ADMIN ──
create_admin_user() {
    step_header '👤  Administrateur Panel  👤'
    local user pass
    if [[ -z "${SKIP_PAUSE:-}" ]]; then
        echo -e "${BG}  ${LAV}Création du compte administrateur pour le Panel Web${RESET}"
        echo
        echo -ne "${BG}${WHITE}  Nom d'utilisateur [${CYAN}admin${WHITE}] : ${RESET}"; read -r user
        user=${user:-admin}
        echo -ne "${BG}${WHITE}  Mot de passe (${YELLOW}vide = auto${WHITE}) : ${RESET}"; read -rs pass; echo
        pass=${pass:-$(gen_pass 12)}
    else
        user="admin"
        pass=$(gen_pass 12)
    fi
    node -e "
    const mysql = require('mysql2/promise');
    const bcrypt = require('bcryptjs');
    (async () => {
        const conn = await mysql.createConnection({ host:'127.0.0.1', user:'${DB_USER}', password:'${DB_PASS}', database:'${DB_NAME}' });
        const hash = await bcrypt.hash('$pass', 12);
        await conn.execute('INSERT INTO admins (username, password) VALUES (?,?) ON DUPLICATE KEY UPDATE password=VALUES(password)', ['$user', hash]);
        await conn.end();
    })();
    " 2>/dev/null || warn "Admin SQL — vérifie MySQL"
    echo
    echo -e "${BG}${CYAN}╔═══$(printf '═%.0s' {1..57})═══╗${RESET}"
    echo -e "${BG}${CYAN}║${RESET}${TITLE_BG}$(center '🔐  ACCÈS PANEL ADMIN  🔐' 61)${RESET}${BG}${CYAN}║${RESET}"
    echo -e "${BG}${CYAN}╠═══$(printf '═%.0s' {1..57})═══╣${RESET}"
    echo -e "${BG}${CYAN}║${RESET}  ${LAV}URL IP   :${RESET} ${CYAN}http://$(hostname -I | awk '{print $1}'):8585/admin/${RESET}  ${BG}${CYAN}║${RESET}"
    echo -e "${BG}${CYAN}║${RESET}  ${LAV}URL DOM  :${RESET} ${CYAN}https://$(cat /etc/kighmu/domain.txt 2>/dev/null)/admin/${RESET}  ${BG}${CYAN}║${RESET}"
    echo -e "${BG}${CYAN}║${RESET}  ${LAV}Utilisateur :${RESET} ${WHITE}${user}${RESET}                        ${BG}${CYAN}║${RESET}"
    echo -e "${BG}${CYAN}║${RESET}  ${LAV}Mot de passe :${RESET} ${ORANGE}${pass}${RESET}                       ${BG}${CYAN}║${RESET}"
    echo -e "${BG}${CYAN}╚═══$(printf '═%.0s' {1..57})═══╝${RESET}"
    echo
    log "Admin '$user' configuré"
}

# ── NGINX ──
configure_nginx() {
    step_header '🌍  Nginx  🌍'
    local IP; IP=$(hostname -I | awk '{print $1}')
    echo -e "${BG}  ${LAV}Domaine/IP pour le panel [${CYAN}$IP${LAV}]${RESET}"
    echo -ne "${BG}${WHITE}  » ${RESET}"; read -r DOMAIN; DOMAIN=${DOMAIN:-$IP}
    mkdir -p /etc/kighmu /etc/nginx/sites-available /etc/nginx/sites-enabled
    echo "$DOMAIN" > /etc/kighmu/domain.txt 2>/dev/null || true
    systemctl stop nginx 2>/dev/null || true
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
    cat > /etc/nginx/sites-available/kighmu << 'NGXEOF'
# Panel — HTTP (port 8585)
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

    location /ws-dropbear {
        proxy_pass http://127.0.0.1:2095;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_read_timeout 86400;
    }

    location /ws-stunnel {
        proxy_pass http://127.0.0.1:700;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_read_timeout 86400;
    }
}
NGXEOF
    ln -sf /etc/nginx/sites-available/kighmu /etc/nginx/sites-enabled/
    nginx -t 2>/dev/null && systemctl start nginx && log "Nginx OK (port 8585)" || err "Nginx invalide"
    if [[ "$DOMAIN" =~ \. ]] && ! [[ "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq certbot 2>/dev/null
        mkdir -p /etc/letsencrypt/renewal-hooks/pre /etc/letsencrypt/renewal-hooks/post
        cat > /etc/letsencrypt/renewal-hooks/pre/sshws-stop.sh << 'HOOK'
#!/bin/bash
systemctl stop sshws 2>/dev/null || true
sleep 1
HOOK
        cat > /etc/letsencrypt/renewal-hooks/post/sshws-start.sh << 'HOOK'
#!/bin/bash
systemctl start sshws 2>/dev/null || true
HOOK
        chmod +x /etc/letsencrypt/renewal-hooks/pre/sshws-stop.sh /etc/letsencrypt/renewal-hooks/post/sshws-start.sh
        systemctl stop sshws 2>/dev/null || true
        if certbot certonly --standalone --preferred-challenges http -d "$DOMAIN" --non-interactive --agree-tos -m "admin@$DOMAIN" 2>/dev/null; then
            log "Certificat SSL obtenu pour $DOMAIN"
            cat >> /etc/nginx/sites-available/kighmu << 'HTTPSEOF'

# HTTPS (port 8587 + 446)
server {
    listen 8587 ssl http2;
    listen 446 ssl http2;
    server_name SSL_DOMAIN;
    client_max_body_size 32m;

    ssl_certificate /etc/letsencrypt/live/SSL_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/SSL_DOMAIN/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

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

    location /ws-dropbear {
        proxy_pass http://127.0.0.1:2095;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_read_timeout 86400;
    }

    location /ws-stunnel {
        proxy_pass http://127.0.0.1:700;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_read_timeout 86400;
    }
}
HTTPSEOF
            sed -i "s/SSL_DOMAIN/$DOMAIN/g" /etc/nginx/sites-available/kighmu
            nginx -t 2>/dev/null && systemctl reload nginx || true
        else
            warn "Certbot a échoué pour $DOMAIN (vérifiez que le DNS pointe ici)"
        fi
        systemctl start sshws 2>/dev/null || true
    fi
}

# ── NFTABLES ──
setup_nftables() {
    step_header '🛡️  nftables  🛡️'
    systemctl enable --now nftables 2>/dev/null || true
    cat > /usr/local/bin/init-nftables.sh << 'INITEOF'
#!/bin/bash
mkdir -p /etc/nftables
if ! nft list tables 2>/dev/null | grep -q .; then
    echo "flush ruleset" > /etc/nftables.conf
    systemctl restart nftables 2>/dev/null || true
fi
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
    cat > /etc/nftables/kighmu-panel.nft << 'PNLEOF'
table inet kighmu-panel {
    chain input {
        type filter hook input priority 0; policy accept;
        tcp dport { 8585, 8587, 446 } accept
    }
}
PNLEOF
    nft -c -f /etc/nftables/kighmu-panel.nft 2>/dev/null && {
        systemctl enable --now nftables-tunnel@kighmu-panel.service 2>/dev/null || true
        log "nftables panel OK"
    } || warn "nftables panel erreur"
    log "nftables OK"
}

# ── TRAFFIC COLLECTION ──
setup_traffic_collection() {
    step_header '📊  Collecte Trafic  📊'
    mkdir -p /etc/kighmu /var/log/kighmu /var/lib/kighmu/ssh-counters

    # Enregistrer NS
    mkdir -p /etc/slowdns/nv4
    echo "${NS4:-ns4.kingom.ggff.net}" > /etc/slowdns/ns.conf
    echo "${NV4:-nv4.kingom.ggff.net}" > /etc/slowdns/nv4/ns.conf
    printf 'MODE=man\nNS4=%s\nNV4=%s\n' "${NS4:-ns4.kingom.ggff.net}" "${NV4:-nv4.kingom.ggff.net}" > /etc/slowdns/install.env

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
BW_DIR="/var/lib/kighmu/bandwidth"
USER_FILE="/etc/kighmu/users.list"
NFT="nft"
TS="$(date '+%Y-%m-%d %H:%M:%S')"
mkdir -p "$DELTA_DIR" "$BW_DIR/sent"
send_stats() { local resp; resp=$(curl -s --max-time 10 -X POST "${PANEL_URL}/api/report/traffic" -H "Content-Type: application/json" -H "x-report-secret: ${SECRET}" -d "$1" 2>/dev/null); echo "[${TS}] → ${resp:-no response}"; }
_read_nft_counter() { ${NFT} list counter inet kighmu "$1" 2>/dev/null | grep -oP 'bytes \K\d+' || echo 0; }
collect_xray() { [ ! -x "$XRAY_BIN" ] && return; local raw; raw=$("$XRAY_BIN" api statsquery --server="$XRAY_API" 2>/dev/null) || return; [[ -z "$raw" ]] && return; local json='{"stats":[' first=1 has_data=0; while IFS='|' read -r name value; do local user="${name%%>>>*}"; local traffic="${name##*>>>}"; [[ "$user" =~ ^(default|)$ ]] && continue; [[ "$value" == "0" ]] && continue; [[ $first -eq 0 ]] && json+=','; if [[ "$traffic" == "uplink" ]]; then json+="{\"username\":\"${user}\",\"upload_bytes\":${value},\"download_bytes\":0}"; else json+="{\"username\":\"${user}\",\"upload_bytes\":0,\"download_bytes\":${value}}"; fi; first=0; has_data=1; done < <(echo "$raw" | jq -r '.stat[]? | select(.name | test("user>>>")) | "\(.name)|\(.value)"' 2>/dev/null); json+=']}'; [[ $has_data -eq 1 ]] && send_stats "$json"; }
collect_v2ray() { [ ! -x "$V2RAY_BIN" ] && return; local raw; raw=$("$V2RAY_BIN" api stats --server="$V2RAY_API" 2>/dev/null) || return; [[ -z "$raw" ]] && return; local json='{"stats":[' first=1 has_data=0; while IFS='|' read -r user up down; do [[ -z "$user" ]] && continue; [[ "$up" == "0" && "$down" == "0" ]] && continue; [[ $first -eq 0 ]] && json+=','; json+="{\"username\":\"${user}\",\"upload_bytes\":${up},\"download_bytes\":${down}}"; first=0; has_data=1; done < <(echo "$raw" | jq -r '.stat[]? | select(.name | test("user>>>")) | (.name / ">>>") as $p | "\($p[0])|\($p[2]//0)|\($p[3]//0)"' 2>/dev/null); json+=']}'; [[ $has_data -eq 1 ]] && send_stats "$json"; }
collect_ssh() { [ ! -f "$USER_FILE" ] && return; command -v nft &>/dev/null || return; nft list table inet kighmu &>/dev/null || return; local json='{"stats":[' first=1 has_data=0; while IFS='|' read -r username _rest; do [ -z "$username" ] && continue; local uid; uid=$(id -u "$username" 2>/dev/null) || continue; local tag="ssh_${uid}"; local cur_out cur_in; cur_out=$(_read_nft_counter "${tag}_out"); cur_in=$(_read_nft_counter "${tag}_in"); local prev_out=0 prev_in=0; [ -f "${DELTA_DIR}/${username}.out" ] && prev_out=$(< "${DELTA_DIR}/${username}.out"); [ -f "${DELTA_DIR}/${username}.in" ] && prev_in=$(< "${DELTA_DIR}/${username}.in"); local delta_out=$(( cur_out - prev_out )); local delta_in=$(( cur_in - prev_in )); (( delta_out < 0 )) && delta_out=$cur_out; (( delta_in < 0 )) && delta_in=$cur_in; if (( delta_out > 0 || delta_in > 0 )); then echo "$cur_out" > "${DELTA_DIR}/${username}.out"; echo "$cur_in" > "${DELTA_DIR}/${username}.in"; [[ $first -eq 0 ]] && json+=','; json+="{\"username\":\"${username}\",\"upload_bytes\":${delta_in},\"download_bytes\":${delta_out}}"; first=0; has_data=1; fi; done < <(cat "$USER_FILE" 2>/dev/null); json+=']}'; [[ $has_data -eq 1 ]] && send_stats "$json"; }
collect_udp() {
  command -v nft &>/dev/null || return
  nft list table inet kighmu &>/dev/null || return
  local SENT_DIR="$BW_DIR/sent"
  local today
  today=$(date +%F)
  local json='{"stats":[' first=1 has_data=0
  for proto in zivpn hysteria; do
    local uf="" port=""
    if [[ "$proto" == "zivpn" ]]; then
      uf="/etc/zivpn/users.list"; port="5667"
    else
      uf="/etc/hysteria/users.txt"; port="20000"
    fi
    [[ ! -f "$uf" ]] && continue
    local cur_in cur_out
    cur_in=$(_read_nft_counter "udp_${proto}_in")
    cur_out=$(_read_nft_counter "udp_${proto}_out")
    [[ ! "$cur_in" =~ ^[0-9]+$ ]] && cur_in=0
    [[ ! "$cur_out" =~ ^[0-9]+$ ]] && cur_out=0
    local snap_in="$BW_DIR/udp_${proto}_global_in.snap"
    local snap_out="$BW_DIR/udp_${proto}_global_out.snap"
    local prev_in=0 prev_out=0
    [[ -f "$snap_in" ]] && prev_in=$(< "$snap_in")
    [[ -f "$snap_out" ]] && prev_out=$(< "$snap_out")
    [[ ! "$prev_in" =~ ^[0-9]+$ ]] && prev_in=0
    [[ ! "$prev_out" =~ ^[0-9]+$ ]] && prev_out=0
    local delta_in=$(( cur_in - prev_in ))
    local delta_out=$(( cur_out - prev_out ))
    (( delta_in < 0 )) && delta_in=$cur_in
    (( delta_out < 0 )) && delta_out=$cur_out
    (( delta_in == 0 && delta_out == 0 )) && continue
    echo "$cur_in" > "$snap_in"
    echo "$cur_out" > "$snap_out"
    local active_users=()
    while IFS='|' read -r username _pass expire; do
      [[ -z "$username" ]] && continue
      [[ "$expire" < "$today" ]] && continue
      active_users+=("$username")
    done < "$uf"
    local nb=${#active_users[@]}
    (( nb == 0 )) && continue
    local share_in=$(( delta_in / nb ))
    local share_out=$(( delta_out / nb ))
    for username in "${active_users[@]}"; do
      local usagefile="$BW_DIR/udp_${proto}_${username}.usage"
      local accum=0
      [[ -f "$usagefile" ]] && accum=$(< "$usagefile")
      [[ ! "$accum" =~ ^[0-9]+$ ]] && accum=0
      accum=$(( accum + share_in + share_out ))
      echo "$accum" > "$usagefile"
      local sentfile="$SENT_DIR/udp_${proto}_${username}.sent"
      local last_sent=0
      [[ -f "$sentfile" ]] && last_sent=$(< "$sentfile")
      [[ ! "$last_sent" =~ ^[0-9]+$ ]] && last_sent=0
      local user_delta=$(( accum - last_sent ))
      (( user_delta <= 0 )) && continue
      echo "$accum" > "$sentfile"
      [[ $first -eq 0 ]] && json+=","
      json+="{\"username\":\"${username}\",\"upload_bytes\":${share_in},\"download_bytes\":${share_out}}"
      first=0; has_data=1
    done
  done
  json+=']}'
  [[ $has_data -eq 1 ]] && send_stats "$json"
}
echo "[${TS}] KIGHMU collecte démarrée"; collect_xray; collect_v2ray; collect_ssh; collect_udp; echo "[${TS}] Terminé"
TCEOF
    sed -i "s/__REPORT_SECRET__/${REPORT_SECRET}/g" /etc/kighmu/traffic-collect.sh
    chmod +x /etc/kighmu/traffic-collect.sh
    crontab -l 2>/dev/null | grep -v "traffic-collect\|Auto-clean" | crontab - 2>/dev/null || true
    (crontab -l 2>/dev/null; echo "*/2 * * * * /etc/kighmu/traffic-collect.sh >> /var/log/kighmu-traffic.log 2>&1"; echo "*/10 * * * * ${KIGHMU_DIR}/Auto-clean.sh >> /var/log/auto-clean.log 2>&1") | crontab - 2>/dev/null || true
    log "Collecte trafic OK (cron 2min)"
}

# ── XRAY WATCHDOG PERMANENT ──
setup_xray_watchdog() {
    step_header '🛡️  Xray Watchdog Permanent  🛡️'
    mkdir -p /etc/kighmu

    cat > /etc/kighmu/xray-watchdog.sh << 'WDEOF'
#!/bin/bash
# Xray Watchdog — vérifie et répare Xray toutes les 60s
XRAY_BIN="/usr/local/bin/xray"
XRAY_CONFIG="/etc/xray/config.json"
WATCHDOG_LOG="/var/log/xray-watchdog.log"
MAX_RESTART=5
RESTART_WINDOW=300

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$WATCHDOG_LOG"; }

if systemctl is-active --quiet xray 2>/dev/null; then exit 0; fi

log "[WATCHDOG] Xray INACTIF — tentative de réparation..."
if [[ ! -x "$XRAY_BIN" ]]; then log "Binaire Xray manquant !"; exit 1; fi
if [[ -f "$XRAY_CONFIG" ]] && ! jq empty "$XRAY_CONFIG" 2>/dev/null; then
    log "Config JSON invalide ! Sauvegarde..."
    cp "$XRAY_CONFIG" "${XRAY_CONFIG}.corrupted.$(date +%s)"
fi
if [[ -f /etc/xray/xray.crt ]] && [[ -f /etc/xray/xray.key ]]; then
    if ! openssl x509 -checkend 0 -noout -in /etc/xray/xray.crt 2>/dev/null; then
        log "Certificat TLS expiré — regénération..."
        local domain; domain=$(cat /etc/xray/domain 2>/dev/null || hostname -I | awk '{print $1}')
        openssl req -x509 -newkey rsa:2048 -keyout /etc/xray/xray.key -out /etc/xray/xray.crt -nodes -days 3650 -subj "/CN=${domain}" 2>/dev/null
        cat /etc/xray/xray.crt /etc/xray/xray.key > /etc/xray/xray.pem
        chmod 600 /etc/xray/xray.key /etc/xray/xray.pem
    fi
fi
for port in 10001 10002 10003 10004 10005 10006 10007 10008 10009 10010 10011 10012 10013 10014 10015 10016 10017 10085; do
    local pid; pid=$(ss -tlnp | grep ":$port " | grep -v xray | grep -oP 'pid=\K[0-9]+' | head -1)
    if [[ -n "$pid" ]]; then log "Port $port bloqué par PID $pid — libération..."; kill "$pid" 2>/dev/null || true; sleep 1; fi
done
log "Démarrage de Xray..."
systemctl start xray 2>/dev/null
sleep 3
if systemctl is-active --quiet xray 2>/dev/null; then
    log "[WATCHDOG] Xray redémarré avec succès !"
else
    log "[WATCHDOG] ÉCHEC démarrage Xray"
    journalctl -u xray -n 20 --no-pager >> "$WATCHDOG_LOG" 2>/dev/null
fi
WDEOF
    chmod +x /etc/kighmu/xray-watchdog.sh

    # Cron toutes les minutes
    crontab -l 2>/dev/null | grep -v "xray-watchdog\|xray.*is-active" | crontab - 2>/dev/null || true
    (crontab -l 2>/dev/null; echo "* * * * * /etc/kighmu/xray-watchdog.sh") | crontab - 2>/dev/null

    # systemd timer
    cat > /etc/systemd/system/xray-watchdog.service << 'SVCEOF'
[Unit]
Description=Xray Watchdog Service
After=network.target
[Service]
Type=oneshot
ExecStart=/etc/kighmu/xray-watchdog.sh
User=root
SVCEOF
    cat > /etc/systemd/system/xray-watchdog.timer << 'TMREOF'
[Unit]
Description=Xray Watchdog Timer (toutes les 2 minutes)
[Timer]
OnBootSec=30
OnUnitActiveSec=120
Unit=xray-watchdog.service
[Install]
WantedBy=timers.target
TMREOF
    systemctl daemon-reload
    systemctl enable --now xray-watchdog.timer 2>/dev/null || true

    # rc.local
    if ! grep -q "xray-watchdog" /etc/rc.local 2>/dev/null; then
        [[ ! -f /etc/rc.local ]] && echo '#!/bin/bash\nexit 0' > /etc/rc.local && chmod +x /etc/rc.local
        sed -i '/^exit 0/i /etc/kighmu/xray-watchdog.sh' /etc/rc.local 2>/dev/null || true
    fi

    # logrotate
    cat > /etc/logrotate.d/xray-watchdog << 'LOGREOF'
/var/log/xray-watchdog.log {
    daily; rotate 7; compress; delaycompress; missingok; notifempty; copytruncate
}
LOGREOF

    log "Xray watchdog permanent installé (cron 60s + timer 120s + boot)"
}

# ── SERVICE BANDWIDTH SSH ──
setup_bandwidth_service() {
    step_header '📈  Service Bandwidth SSH  📈'
    mkdir -p /var/lib/kighmu
    cat > /usr/local/bin/kighmu-bandwidth.sh << 'BWEOF'
#!/bin/bash
PANEL_URL="http://127.0.0.1:3000"
SECRET="__REPORT_SECRET__"
DELTA_DIR="/var/lib/kighmu/ssh-counters"
USER_FILE="/etc/kighmu/users.list"
NFT="nft"
mkdir -p "$DELTA_DIR"
_read_nft_counter() { ${NFT} list counter inet kighmu "$1" 2>/dev/null | grep -oP 'bytes \K\d+' || echo 0; }
_ensure_counter() { local name="$1"; if ! ${NFT} list counter inet kighmu "$name" &>/dev/null; then ${NFT} add counter inet kighmu "$name" 2>/dev/null || true; fi; }
sshNftablesAdd() { local username="$1" uid="$2"; _ensure_counter "ssh_${uid}_out"; _ensure_counter "ssh_${uid}_in"; local cur_out cur_in; cur_out=$(_read_nft_counter "ssh_${uid}_out"); cur_in=$(_read_nft_counter "ssh_${uid}_in"); echo "$cur_out" > "${DELTA_DIR}/${username}.out"; echo "$cur_in" > "${DELTA_DIR}/${username}.in"; }
sshNftablesRemove() { local username="$1" uid="$2"; ${NFT} delete counter inet kighmu "ssh_${uid}_out" 2>/dev/null || true; ${NFT} delete counter inet kighmu "ssh_${uid}_in" 2>/dev/null || true; rm -f "${DELTA_DIR}/${username}.out" "${DELTA_DIR}/${username}.in"; }
while true; do
    ts=$(date +%s)
    while IFS='|' read -r username _rest; do
        [[ -z "$username" ]] && continue; local uid; uid=$(id -u "$username" 2>/dev/null) || continue
        local tag="ssh_${uid}"; local cur_out cur_in; cur_out=$(_read_nft_counter "${tag}_out"); cur_in=$(_read_nft_counter "${tag}_in")
        local prev_out=0 prev_in=0; [[ -f "${DELTA_DIR}/${username}.out" ]] && prev_out=$(< "${DELTA_DIR}/${username}.out"); [[ -f "${DELTA_DIR}/${username}.in" ]] && prev_in=$(< "${DELTA_DIR}/${username}.in")
        local delta_out=$(( cur_out - prev_out )); local delta_in=$(( cur_in - prev_in )); (( delta_out < 0 )) && delta_out=$cur_out; (( delta_in < 0 )) && delta_in=$cur_in
        if (( delta_out > 0 || delta_in > 0 )); then
            local json="{\"stats\":[{\"username\":\"${username}\",\"upload_bytes\":${delta_in},\"download_bytes\":${delta_out}}]}"
            curl -s --max-time 5 -X POST "${PANEL_URL}/api/report/traffic" -H "Content-Type: application/json" -H "x-report-secret: ${SECRET}" -d "$json" >/dev/null 2>&1 || true
            echo "$cur_out" > "${DELTA_DIR}/${username}.out"; echo "$cur_in" > "${DELTA_DIR}/${username}.in"
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
    log "Service Bandwidth SSH OK"
}

# ── PANEL DE CONTRÔLE SSH ──
deploy_control_panel() {
    step_header '🎛️  Panneau de Contrôle SSH  🎛️'
    mkdir -p /etc/kighmu /etc/kighmu-v2
    # Extraire le code du panneau depuis la fin de ce script (marqueurs PANEL_CODE)
    sed -n '/^# PANEL_CODE_START$/,/^# PANEL_CODE_END$/p' "$SCRIPT_DIR/install.sh" | tail -n +2 | head -n -1 > /etc/kighmu-v2/panel.sh || {
        err "Extraction du panneau échouée"; return 1;
    }
    chmod +x /etc/kighmu-v2/panel.sh
    ln -sf /etc/kighmu-v2/panel.sh /usr/local/bin/menu
    cat > /etc/profile.d/kighmu-panel.sh << 'PROF'
#!/bin/bash
if [[ $EUID -eq 0 && -f /etc/kighmu-v2/panel.sh && -t 0 ]]; then
    /etc/kighmu-v2/panel.sh
fi
PROF
    chmod +x /etc/profile.d/kighmu-panel.sh
    log "Panel déployé (/etc/kighmu-v2/panel.sh)"
    log "Tapez 'menu' pour l'ouvrir"
}

# ── NETTOYAGE ──
cleanup_scripts() {
    echo
    echo -e "${BG}${CYAN}╔═══$(printf '═%.0s' {1..57})═══╗${RESET}"
    echo -e "${BG}${CYAN}║${RESET}${TITLE_BG}$(center '🧹  NETTOYAGE VPS  🧹' 61)${RESET}${BG}${CYAN}║${RESET}"
    echo -e "${BG}${CYAN}╚═══$(printf '═%.0s' {1..57})═══╝${RESET}"
    echo
    echo -e "${BG}  ${YELLOW}Supprime les scripts d'installation du VPS client.${RESET}"
    echo -e "${BG}  ${YELLOW}Seuls les fichiers nécessaires au fonctionnement restent.${RESET}"
    echo
    read -rp "  Confirmer ? (o/N): " C
    [[ "$C" =~ ^[oO]$ ]] || { echo -e "  ${YELLOW}Annulé${RESET}"; return; }
    [[ -d "$SCRIPT_DIR" && "$SCRIPT_DIR" =~ Tyiop24 ]] && rm -rf "$SCRIPT_DIR" && echo -e "  ${GREEN}✓${RESET} $SCRIPT_DIR supprimé"
    [[ -d "$KIGHMU_DIR" ]] && rm -rf "$KIGHMU_DIR" && echo -e "  ${GREEN}✓${RESET} $KIGHMU_DIR supprimé"
    rm -f /root/.kighmu_info 2>/dev/null || true
    chmod 600 /opt/kighmu-panel/.env 2>/dev/null || true
    find /opt/kighmu-panel -name "*.env" -exec chmod 600 {} \; 2>/dev/null || true
    find /etc -name "*.key" -exec chmod 600 {} \; 2>/dev/null || true
    find /etc -name "*.pem" -exec chmod 600 {} \; 2>/dev/null || true
    echo
    log "Nettoyage terminé."
    echo -e "  ${LAV}Panel:${RESET} ${CYAN}http://$(hostname -I | awk '{print $1}'):8585/admin/${RESET}"
    echo
    read -rp "  Press Enter..."; exit 0
}

# ── INSTALLATION COMPLÈTE ──
full_install() {
    show_banner
    ask_nameservers
    install_system_deps
    install_nodejs
    deploy_panel_files
    configure_env
    install_mysql
    install_npm_panel
    create_admin_user
    configure_nginx
    setup_nftables
    setup_traffic_collection
    setup_bandwidth_service
    deploy_control_panel

    # ── Installation de tous les services ──
    export SKIP_PAUSE=1

    local GH="https://raw.githubusercontent.com/kinf744/Tyiop24/main"

    # Télécharger les scripts compagnons s'ils sont absents
    for _script in ssh.sh xray-v2ray.sh udp.sh; do
        if [[ ! -f "$SCRIPT_DIR/$_script" ]]; then
            log "Téléchargement de $_script depuis GitHub..."
            if ! curl -fsSL "$GH/$_script" -o "$SCRIPT_DIR/$_script"; then
                err "Échec du téléchargement de $_script — installation annulée"
                return 1
            fi
            chmod +x "$SCRIPT_DIR/$_script"
        fi
    done

    log "Installation des services SSH..."
    source "$SCRIPT_DIR/ssh.sh" || { err "ssh.sh introuvable"; return 1; }
    install_openssh
    install_dropbear
    install_ssl_tls
    install_sshws
    install_sockspy
    install_wstunnel
    install_socks_python
    install_ws_services
    install_slowdns

    log "Installation des services Xray & V2Ray..."
    source "$SCRIPT_DIR/xray-v2ray.sh" || { err "xray-v2ray.sh introuvable"; return 1; }
    install_xray
    install_v2ray
    setup_xray_watchdog

    log "Installation des services UDP..."
    source "$SCRIPT_DIR/udp.sh" || { err "udp.sh introuvable"; return 1; }
    install_zivpn
    install_hysteria
    install_badvpn
    install_udp_custom
    apply_network_optimizations

    unset SKIP_PAUSE

    # ── Vérification finale : s'assurer que tous les services sont présents ──
    log "Vérification finale des services..."
    for alias_svc in dropbear-custom:dropbear sshws:ws-dropbear; do
        local target="${alias_svc#*:}" alias="${alias_svc%:*}"
        if systemctl cat "$target.service" &>/dev/null 2>&1 && ! systemctl cat "$alias.service" &>/dev/null 2>&1; then
            ln -sf "/etc/systemd/system/$target.service" "/etc/systemd/system/$alias.service" 2>/dev/null
        fi
    done
    systemctl daemon-reload 2>/dev/null || true
    for svc in nginx haproxy xray v2ray dropbear-custom ssl_tls sshws hysteria zivpn udp-custom; do
        systemctl is-active --quiet "$svc" 2>/dev/null && continue
        systemctl restart "$svc" 2>/dev/null || true
    done

    echo
    echo -e "${BG}${CYAN}║${RESET}${TITLE_BG}$(center '✅  INSTALLATION TERMINÉE  ✅' 61)${RESET}${BG}${CYAN}║${RESET}"
    echo -e "${BG}${CYAN}╚═══$(printf '═%.0s' {1..57})═══╝${RESET}"
    echo
    echo -e "${BG}  ${LAV}Panel Web:${RESET} ${CYAN}http://$(hostname -I | awk '{print $1}'):8585/admin/${RESET}"
    echo
    read -rp "  Nettoyer les fichiers d'installation ? (o/N): " C
    [[ "$C" =~ ^[oO]$ ]] && cleanup_scripts || echo -e "  ${YELLOW}Scripts dans : $SCRIPT_DIR${RESET}"
    pause
}

# ── STATUT ──
show_status() {
    clear
    echo -e "${BG}${CYAN}╔═══$(printf '═%.0s' {1..47})═══╗${RESET}"
    echo -e "${BG}${CYAN}║${RESET}${TITLE_BG}$(center '📊  STATUT SERVICES  📊' 51)${RESET}${BG}${CYAN}║${RESET}"
    echo -e "${BG}${CYAN}╚═══$(printf '═%.0s' {1..47})═══╝${RESET}"
    echo
    for svc in nginx mysql pm2 kighmu-panel nftables ssh dropbear xray v2ray zivpn hysteria badvpn udp-custom slowdns ssl_tls sshws; do
        local d="$svc"
        case $svc in kighmu-panel) d="Panel (PM2)";; pm2) d="PM2";; esac
        if systemctl is-active --quiet "$svc" 2>/dev/null || pm2 show "$svc" &>/dev/null 2>&1; then
            echo -e "  ${GREEN}✅${RESET} ${WHITE}$d${RESET}"
        else
            echo -e "  ${RED}❌${RESET} ${WHITE}$d${RESET}"
        fi
    done
    echo
    echo -e "${BG}  ${LAV}Ports ouverts :${RESET}"
    ss -tlnp 2>/dev/null | grep -E '8585|8587|3000|80|443|8880|8443|109|22|444|9090|5667|20000|36712|5401|5353|5300|7100|7200|7300|2095|700' | awk '{print "  "$4}' | sort -u
    pause
}

# ── MENU PRINCIPAL ──
main_menu() {
    while true; do
        clear
        echo -e "${CLR}${BG}"
        echo -e "${BG}${CYAN}╔═══$(printf '═%.0s' {1..67})═══╗${RESET}"
        echo -e "${BG}${CYAN}║${RESET}${TITLE_BG}$(center '🛡️  KIGHMU PANEL v4  🛡️' 71)${RESET}${BG}${CYAN}║${RESET}"
        echo -e "${BG}${CYAN}╚═══$(printf '═%.0s' {1..67})═══╝${RESET}"
        echo
        echo -e "${BG}  ${LAV}Installation :${RESET}"
        echo -e "${BG}  ${ORANGE}[01]${RESET} ${WHITE}Installation complète${RESET}"
        echo -e "${BG}  ${ORANGE}[02]${RESET} ${WHITE}Panel uniquement${RESET}"
        echo -e "${BG}  ${ORANGE}[03]${RESET} ${WHITE}Statut des services${RESET}"
        echo
        echo -e "${BG}  ${LAV}Tunnels :${RESET}"
        echo -e "${BG}  ${ORANGE}[04]${RESET} ${WHITE}UDP (ZIVPN, Hysteria, BadVPN, UDP-Custom)${RESET}"
        echo -e "${BG}  ${ORANGE}[05]${RESET} ${WHITE}Xray & V2Ray (VMess, VLESS, Trojan, Shadowsocks)${RESET}"
        echo -e "${BG}  ${ORANGE}[06]${RESET} ${WHITE}SSH (Dropbear, SlowDNS, SSL, WS, SOCKS)${RESET}"
        echo
        echo -e "${BG}  ${LAV}Contrôle :${RESET}"
        echo -e "${BG}  ${ORANGE}[07]${RESET} ${WHITE}Panneau de contrôle SSH${RESET}"
        echo -e "${BG}  ${ORANGE}[08]${RESET} ${RED}🧹 Nettoyer les scripts d'installation${RESET}"
        echo -e "${BG}  ${ORANGE}[00]${RESET} ${WHITE}Quitter${RESET}"
        echo
        echo -ne "${BG}${LAV}  Choix »${RESET} ${WHITE}"; read -r CHOIX; echo -e "${RESET}"
        case $CHOIX in
            1) full_install ;;
            2) install_system_deps; install_nodejs; deploy_panel_files; configure_env; install_mysql; install_npm_panel; create_admin_user; configure_nginx; setup_nftables; pause ;;
            3) show_status ;;
            4) bash "$SCRIPT_DIR/udp.sh" ;;
            5) bash "$SCRIPT_DIR/xray-v2ray.sh" ;;
            6) bash "$SCRIPT_DIR/ssh.sh" ;;
            7) deploy_control_panel ;;
            8) cleanup_scripts ;;
            0|00) exit 0 ;;
            *) ;;
        esac
    done
}

check_root
main_menu

# PANEL_CODE_START
# Kighmu Control Panel - Design Terminal Haut de Gamme
set -uo pipefail

# ── Couleurs 24-bit ──
BG='\e[48;2;43;15;66m'
FG='\e[38;2;43;15;66m'
CYAN='\e[38;2;30;144;255m'
TITLE_BG='\e[48;2;91;79;232m'
LAV='\e[38;2;155;143;232m'
WHITE='\e[97m'
BOLD='\e[1m'
DIM='\e[2m'
MAG='\e[38;2;255;0;255m'
GREEN='\e[38;2;0;255;0m'
YELLOW='\e[38;2;255;200;0m'
ORANGE='\e[38;2;255;165;0m'
RED='\e[91m'
RESET='\e[0m'
CLR='\e[2J\e[H'

# ── Barre dégradée arc-en-ciel ──
rainbow() {
    local w=${1:-57}
    local cols=(
        '38;2;255;50;50'   '38;2;255;100;0'  '38;2;255;180;0'
        '38;2;200;255;0'   '38;2;50;255;50'  '38;2;0;200;200'
        '38;2;50;100;255'  '38;2;150;50;255' '38;2;255;50;200'
    )
    local i c; for ((i=0; i<w; i++)); do
        c=${cols[$((i % ${#cols[@]}))]}
        echo -ne "\e[${c}m━${RESET}"
    done
}

# ── Centre le texte dans une largeur donnée ──
center() {
    local t="$1" w=${2:-70} l
    l=$(echo -e "$t" | sed 's/\x1b\[[0-9;]*m//g' | wc -c)
    l=$((l-1))
    printf "%$(( (w-l)/2 ))s%b%$(( (w-l+1)/2 ))s" "" "$t" ""
}

# ── Couvre chaque ligne du fond violet ──
with_bg() { echo -ne "${BG}$1${RESET}"; }

# ── Convertisseur en GB/TB avec 1 décimale ──
fmt_bytes() {
    local b=$1
    if ((b < 1099511627776)); then awk "BEGIN{printf \"%.2f GB\", $b/1073741824}"; return; fi
    awk "BEGIN{printf \"%.2f TB\", $b/1099511627776}"
}

# ── Collecte bande passante via vnStat ──
IFACE=$(ip route 2>/dev/null | awk '/default/{print $5; exit}' || echo "eth0")
BW_DIR="/etc/kighmu/bandwidth"
mkdir -p "$BW_DIR"

# vnStat : total VPS traffic (rx + tx) par jour/semaine/mois
VNSTAT_DB=$(vnstat --json 2>/dev/null)
BW_DAY=0; BW_WEEK=0; BW_MONTH=0
if [[ -n "$VNSTAT_DB" ]]; then
    BW_DAY=$(echo "$VNSTAT_DB" | python3 -c "
import sys, json
d=json.load(sys.stdin)
t=d['interfaces'][0]['traffic']
last=t['day'][-1]
print(int(last['rx'])+int(last['tx']))" 2>/dev/null)
    BW_WEEK=$(echo "$VNSTAT_DB" | python3 -c "
import sys, json
d=json.load(sys.stdin)
days=d['interfaces'][0]['traffic']['day']
print(sum(int(dd['rx'])+int(dd['tx']) for dd in days[-7:]))" 2>/dev/null)
    BW_MONTH=$(echo "$VNSTAT_DB" | python3 -c "
import sys, json
d=json.load(sys.stdin)
last=d['interfaces'][0]['traffic']['month'][-1]
print(int(last['rx'])+int(last['tx']))" 2>/dev/null)
fi
: "${BW_DAY:=0}" "${BW_WEEK:=0}" "${BW_MONTH:=0}"

BW_DAY_H=$(fmt_bytes $BW_DAY)
BW_WEEK_H=$(fmt_bytes $BW_WEEK)
BW_MONTH_H=$(fmt_bytes $BW_MONTH)

# ── Quota coloré ──
quota_color() {
    local val=$1
    if ((val < 1073741824)); then echo "${GREEN}";          # < 1GB
    elif ((val < 5368709120)); then echo "${YELLOW}";       # 1-5GB
    else echo "${ORANGE}"; fi                                 # > 5GB
}

C_DAY=$(quota_color $BW_DAY)
C_WEEK=$(quota_color $BW_WEEK)
C_MONTH=$(quota_color $BW_MONTH)

# ── Données ──
IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")
DOMAIN=$(cat /etc/kighmu/domain.txt 2>/dev/null || cat /etc/xray/domain 2>/dev/null || echo "$IP")
NS4=$(cat /etc/slowdns/ns.conf 2>/dev/null | head -1 || grep NS4 /etc/slowdns/ns.conf 2>/dev/null | cut -d= -f2 || echo "ns4.domain")
NV4=$(cat /etc/slowdns/nv4/ns.conf 2>/dev/null || grep NV4 /etc/slowdns/ns.conf 2>/dev/null | cut -d= -f2 || echo "nv4.domain")
RAM=$(free -m | awk '/Mem:/ {print $3"MB/"$2"MB"}')
RAM_PCT=$(free -m | awk '/Mem:/ {printf "%d", $3/$2*100}')
CPU_CORES=$(nproc 2>/dev/null || echo "?")
CPU_USED=$(top -bn1 2>/dev/null | awk '/Cpu\(s\)/ {print $2}' | cut -d. -f1 || echo "?")
[[ -z "$CPU_USED" || "$CPU_USED" == "?" ]] && CPU_USED=$(ps -eo %cpu --no-headers 2>/dev/null | awk '{s+=$1}END{printf "%d", s/NR}' || echo "0")
KERNEL=$(uname -r 2>/dev/null || echo "?")
OS_NAME=$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || echo "$KERNEL")

# Statuts services
svc() {
    if systemctl cat "$1.service" &>/dev/null 2>&1; then
        systemctl is-active --quiet "$1" 2>/dev/null && echo -e "${GREEN}ON${RESET}" || echo -e "${RED}OFF${RESET}"
    else
        echo -e "${DIM}---${RESET}"
    fi
}
# ── Ligne services alignée (3 colonnes de 18 chars) ──
svc_line() {
    local line="" w=18
    while [[ $# -ge 2 ]]; do
        local name="$1" stat="$2"; shift 2
        local stat_plain=$(echo -e "$stat" | sed 's/\x1b\[[0-9;]*m//g')
        local cell="${LAV}${name}${RESET} ${CYAN}:${RESET} ${stat}"
        local vis=$(( ${#name} + 3 + ${#stat_plain} ))
        local needed=$((w - vis))
        [[ $needed -gt 0 ]] && cell+=$(printf '%*s' "$needed" '')
        line+="$cell"
    done
    echo -e "${BG}  ${line}"
}

# ── DRAW ──
HL() { printf "${BG}${CYAN}%s${RESET}\n" "$(printf '┄%.0s' {1..64})"; }

draw_panel() {
    echo -e "${CLR}${BG}"

    # ── Comptes (rafraîchis à chaque affichage) ──
    local N_SSH=$(awk -F: '$7~/bash|sh/ && $3>=1000' /etc/passwd 2>/dev/null | wc -l)
    local N_VMESS=$(jq '.vmess | length' /etc/xray/users.json 2>/dev/null || echo 0)
    local N_VLESS=$(jq '.vless | length' /etc/xray/users.json 2>/dev/null || echo 0)
    local N_TROJAN=$(jq '.trojan | length' /etc/xray/users.json 2>/dev/null || echo 0)
    local N_SHADOW=$(jq '.shadow | length' /etc/xray/users.json 2>/dev/null || echo 0)
    local N_V2RAY=$(jq '.vless | length' /etc/v2ray/users.json 2>/dev/null || echo 0)
    local N_HY=$([[ -f /etc/hysteria/users.txt ]] && awk -F'|' -v d="$(date +%Y-%m-%d)" '$3>=d' /etc/hysteria/users.txt | wc -l || echo 0)
    local N_ZIVPN=$([[ -f /etc/zivpn/users.list ]] && awk -F'|' -v d="$(date +%Y-%m-%d)" '$3>=d' /etc/zivpn/users.list | wc -l || echo 0)
    local S_SSH=$(svc ssh) S_DROP=$(svc dropbear-custom) S_NGINX=$(svc nginx)
    local S_HAPROXY=$(svc haproxy) S_XRAY=$(svc xray) S_V2RAY=$(svc v2ray)
    local S_HY=$(svc hysteria) S_ZIVPN=$(svc zivpn) S_SSHWS=$(svc sshws)

    # ── Bandeau titre ──
    HL
    echo -e "${BG}${CYAN}          ▓▓▓ ${WHITE}${BOLD}WELCOME TO KIGHMU VPN${RESET}${BG}${CYAN} ▓▓▓${RESET}"
    HL
    echo

    # ── Infos système ──
    local RAM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
    echo -e "${BG}  ${LAV} ${BOLD}»${RESET} ${LAV}SYSTEM VPS${RESET}  ${CYAN}:${RESET} ${WHITE}${OS_NAME}${RESET}"
    echo -e "${BG}  ${LAV} ${BOLD}»${RESET} ${LAV}RAM SERVER${RESET}  ${CYAN}:${RESET} ${WHITE}${RAM}${RESET} (${ORANGE}${RAM_PCT}%${RESET})"
    echo -e "${BG}  ${LAV} ${BOLD}»${RESET} ${LAV}CPU CORES${RESET}   ${CYAN}:${RESET} ${WHITE}${CPU_CORES}${RESET} (${YELLOW}${CPU_USED}% used${RESET})"
    echo -e "${BG}  ${LAV} ${BOLD}»${RESET} ${LAV}IP VPS${RESET}      ${CYAN}:${RESET} ${WHITE}${IP}${RESET}"
    echo -e "${BG}  ${LAV} ${BOLD}»${RESET} ${LAV}DOMAIN${RESET}      ${CYAN}:${RESET} ${ORANGE}${DOMAIN}${RESET}"
    echo -e "${BG}  ${LAV} ${BOLD}»${RESET} ${LAV}NS SLOWDNS${RESET}  ${CYAN}:${RESET} ${MAG}${NS4}${RESET}"
    echo -e "${BG}  ${LAV} ${BOLD}»${RESET} ${LAV}NS V2RAY${RESET}    ${CYAN}:${RESET} ${MAG}${NV4}${RESET}"

    echo
    HL
    echo -e "${BG}                ${ORANGE}>>>${RESET} ${LAV}${BOLD}DATA QUOTA${RESET} ${ORANGE}<<<${RESET}"
    HL
    local qd="${C_DAY}${BW_DAY_H}${RESET}" qw="${C_WEEK}${BW_WEEK_H}${RESET}" qm="${C_MONTH}${BW_MONTH_H}${RESET}"
    printf "${BG}   ${LAV}Day${RESET} ${CYAN}:${RESET} %b    ${LAV}Week${RESET} ${CYAN}:${RESET} %b    ${LAV}Month${RESET} ${CYAN}:${RESET} %b\n" "$qd" "$qw" "$qm"

    echo
    HL
    echo -e "${BG}           ${ORANGE}>>>${RESET} ${LAV}${BOLD}ACCOUNT INFORMATION${RESET} ${ORANGE}<<<${RESET}"
    HL
    printf "${BG}   ${LAV}%-9s${RESET} ${CYAN}:${RESET} ${WHITE}%s${RESET}  ${GREEN}ACCOUNT PREMIUM${RESET}\n" "SSH/UDP" "$N_SSH"
    printf "${BG}   ${LAV}%-9s${RESET} ${CYAN}:${RESET} ${WHITE}%s${RESET}  ${GREEN}ACCOUNT PREMIUM${RESET}\n" "VMESS" "$N_VMESS"
    printf "${BG}   ${LAV}%-9s${RESET} ${CYAN}:${RESET} ${WHITE}%s${RESET}  ${GREEN}ACCOUNT PREMIUM${RESET}\n" "VLESS" "$N_VLESS"
    printf "${BG}   ${LAV}%-9s${RESET} ${CYAN}:${RESET} ${WHITE}%s${RESET}  ${GREEN}ACCOUNT PREMIUM${RESET}\n" "TROJAN" "$N_TROJAN"
    printf "${BG}   ${LAV}%-9s${RESET} ${CYAN}:${RESET} ${WHITE}%s${RESET}  ${GREEN}ACCOUNT PREMIUM${RESET}\n" "V2RAY DNS" "$N_V2RAY"
    printf "${BG}   ${LAV}%-9s${RESET} ${CYAN}:${RESET} ${WHITE}%s${RESET}  ${GREEN}ACCOUNT PREMIUM${RESET}\n" "HYSTERIA" "$N_HY"
    printf "${BG}   ${LAV}%-9s${RESET} ${CYAN}:${RESET} ${WHITE}%s${RESET}  ${GREEN}ACCOUNT PREMIUM${RESET}\n" "ZIVPN" "$N_ZIVPN"

    echo
    HL
    echo -e "${BG}               ${ORANGE}>>>${RESET} ${LAV}${BOLD}PREMIUM MENU${RESET} ${ORANGE}<<<${RESET}"
    HL
    svc_line "SSH" "$S_SSH" "NGINX" "$S_NGINX" "HAPROXY" "$S_HAPROXY"
    svc_line "XRAY" "$S_XRAY" "V2RAY" "$S_V2RAY" "DROPBEAR" "$S_DROP"
    svc_line "HYSTERIA" "$S_HY" "ZIVPN" "$S_ZIVPN" "WS-epro" "$S_SSHWS"

    echo
    HL

    local items=(
        "[01] MENU SSH VIP"    "[09] AUTO REBOOT"     "[17] RESTART VPS"
        "[02] MENU VMESS"      "[10] MENU PORT"       "[18] SET DOMAIN"
        "[03] MENU VLESS"      "[11] PANEL WEB"       "[19] CERT SSL"
        "[04] MENU TROJAN"     "[12] DEL ALL EXP"     "[20] QUOTA USAGE"
        "[05] MENU SHADOW"     "[13] CLEAR LOG"       "[21] CLEAR CACHE"
        "[06] MENU ZIVPN"      "[14] STOP ALL SERV"   "[22] CEK BANDWIDTH"
        "[07] MENU HYSTERIA"   "[15] BCKP/RSTR"       "[23] DÉSINSTALLE"
        "[08] MENU V2RAY DNS"  "[16] REBOOT VPS"      "[24] MENU BOT VIP"
    )
    for ((i=0; i<24; i+=3)); do
        line=""
        for idx in $i $((i+1)) $((i+2)); do
            item="${items[$idx]:-}"
            if [[ -n "$item" ]]; then
                [[ -z "$line" ]] || line+=" "
                num="${item:0:4}"
                name="${item:5}"
                vlen=$(( ${#num} + 1 + ${#name} ))
                pad=$(( 20 - vlen ))
                [[ $pad -lt 0 ]] && pad=0
                line+="${WHITE}${num}${RESET} ${ORANGE}${name}${RESET}"
                [[ $pad -gt 0 ]] && line+="$(printf '%*s' "$pad" '')"
            fi
        done
        echo -e "${BG}  ${line}${RESET}"
    done

    HL
    echo -e "${BG}  ${ORANGE}[25]${RESET} ${WHITE}CHANGE BANNER SSH${RESET}   ${ORANGE}<<<${RESET}"
    echo -e "${BG}  ${ORANGE}[26]${RESET} ${WHITE}LOG CREATE USER ACCOUNT${RESET} ${ORANGE}<<<${RESET}"
    HL

    local CUR_USER=${USER:-root} VER="v4.0"
    echo -e "${BG}  ${LAV}Script Version${RESET}  ${CYAN}:${RESET} ${YELLOW}${VER}${RESET}"
    echo -e "${BG}  ${LAV}Script Status${RESET}   ${CYAN}:${RESET} ${GREEN}Active${RESET}"
    echo -e "${BG}  ${LAV}Username${RESET}        ${CYAN}:${RESET} ${WHITE}${CUR_USER}${RESET}"
    echo -e "${BG}  ${LAV}Expired script${RESET}  ${CYAN}:${RESET} ${YELLOW}PERMANENT${RESET}"
    HL

    echo -ne "${BG}${LAV} Select From Options [ 1-26 ] ${ORANGE}»»${RESET} ${WHITE}"
    read -r CHOIX
    echo -e "${RESET}"
}

# ================================================
# FONCTIONS AIDES POUR SOUS-MENUS
# ================================================
pause() { echo; read -rp "  Appuyez sur Entrée..."; }

sub_header() {
    echo -e "${CLR}${BG}"
    echo -e "${BG}${CYAN}╔═══$(printf '═%.0s' {1..67})═══╗${RESET}"
    echo -e "${BG}${CYAN}║${RESET}${TITLE_BG}$(center "$1" 71)${RESET}${BG}${CYAN}║${RESET}"
    echo -e "${BG}${CYAN}╚═══$(printf '═%.0s' {1..67})═══╝${RESET}"
}

sub_footer() {
    printf "${BG}╠══════════════════════════════════════════════════════════════════════╣${RESET}\n"
    printf "${BG}║${RESET}  ${RED}[0]${RESET} ${YELLOW}RETOUR AU MENU PRINCIPAL${RESET}                                      ${BG}║${RESET}\n"
    echo -e "${BG}${CYAN}╚═══$(printf '═%.0s' {1..67})═══╝${RESET}"
}

sub_row() { printf "${BG}║${RESET}  ${ORANGE}[%02d]${RESET} ${WHITE}%-24s${RESET} ${ORANGE}[%02d]${RESET} ${WHITE}%-24s${RESET} ${BG}║${RESET}\n" "$1" "$2" "$3" "$4"; }

prompt_sub() {
    echo; echo -ne "${BG}${LAV}  $1 »${RESET} ${WHITE}"
    read -r SUB
    echo -e "${RESET}"
}

# ── Tableau de suppression interactif ──
# Utilisation: mapfile -t selected < <(show_del_panel "TITRE" "user1|date1" "user2|date2" ...)
# Les noms choisis sont ecrits sur stdout (un par ligne).
show_del_panel() {
  local title="$1"; shift
  local -a users=("$@")
  local -a unames=()
  local i=0 expired=0 active=0 today
  today=$(date +%Y-%m-%d)
  clear
  echo -e "${BG}┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄${RESET}"
  echo -e "${BG}        >>> ${title} <<<${RESET}"
  echo -e "${BG}┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄${RESET}"
  echo ""
  printf "  ${WHITE}%-3s %-16s %-14s %s${RESET}\n" "NO" "USERNAME" "EXPIRED" "STATUS"
  echo -e "  ${DIM}──   ────────        ───────        ──────${RESET}"
  for entry in "${users[@]}"; do
    local uname="${entry%%|*}"
    local exp="${entry#*|}"
    unames+=("$uname")
    i=$((i+1))
    if [[ "$exp" < "$today" ]]; then
      printf "  ${CYAN}%02d${RESET}  ${WHITE}%-16s${RESET} ${MAG}%-14s${RESET} ${RED}%-6s${RESET}\n" "$i" "$uname" "$exp" "EXPIRED"
      expired=$((expired+1))
    else
      printf "  ${CYAN}%02d${RESET}  ${WHITE}%-16s${RESET} ${MAG}%-14s${RESET} ${GREEN}%-6s${RESET}\n" "$i" "$uname" "$exp" "ACTIVE"
      active=$((active+1))
    fi
  done
  echo -e "${BG}┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄${RESET}"
  printf "\n  ${LAV}Total :${RESET} ${WHITE}%d${RESET} utilisateurs  (${RED}%d expire${RESET} · ${GREEN}%d actif${RESET})\n\n" "$i" "$expired" "$active"
  echo -e "  ${YELLOW}Entrer le(s) numero(s) a supprimer${RESET}"
  echo -e "  ${DIM}(ex: 1 ou 1,3,5 ou 1-4)${RESET}\n"
  echo -e "  ${RED}[A]${RESET} Supprimer TOUT     ${GREEN}[0]${RESET} Annuler"
  echo -e "${BG}┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄${RESET}"
  echo -ne " ${CYAN}Select »»${RESET} "
  IFS= read -r input
  [[ -z "$input" ]] && return
  input="${input,,}"
  if [[ "$input" == "a" ]]; then
    for u in "${unames[@]}"; do echo "$u"; done
    return
  fi
  [[ "$input" == "0" ]] && return
  local -a selected=()
  IFS=',' read -ra parts <<< "$input"
  for part in "${parts[@]}"; do
    part="${part// /}"
    [[ -z "$part" ]] && continue
    if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      local start="${BASH_REMATCH[1]}" end="${BASH_REMATCH[2]}"
      for ((n=start; n<=end; n++)); do
        (( n >= 1 && n <= i )) && selected+=("${unames[n-1]}")
      done
    elif [[ "$part" =~ ^[0-9]+$ ]]; then
      (( part >= 1 && part <= i )) && selected+=("${unames[part-1]}")
    fi
  done
  printf "%s\n" "${selected[@]}"
}

# ================================================
# SOUS-MENU SSH VIP
# ================================================
menu_ssh_vip() {
    while true; do
 sub_header 'MENU SSH VIP'
        printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
        sub_row 1 "CREER COMPTE SSH"        2 "SUPPRIMER COMPTE"
        sub_row 3 "LISTE COMPTES"           4 "RENEW COMPTE"
        sub_row 5 "TRIAL 1 JOUR"            6 "CHECK EXPIRY"
        sub_row 7 "LOCK ACCOUNT"            8 "UNLOCK ACCOUNT"
        sub_row 9 "MONITOR CONNEXIONS"     10 "KILL CONNEXION"
        sub_row 11 "CHANGE PORT SSH"       12 "CHANGE BANNER"
        sub_footer
        prompt_sub "SSH VIP"
        case $SUB in
            1) clear; echo -e "${CYAN}━━ Création compte SSH ━━${RESET}"; read -rp "  Username: " u; read -rp "  Password: " p; read -rp "  Expire (jours): " e; if useradd -e "$(date -d "+${e}days" +%Y-%m-%d)" -s /bin/bash "$u" 2>/dev/null && echo "$u:$p" | chpasswd; then
                local D="${DOMAIN:-$IP}" E="$(date -d "+${e}days" +%Y-%m-%d)"
                local KEY=$(cat /etc/slowdns/server.pub 2>/dev/null || echo "non-dispo")
                local NS=$(cat /etc/slowdns/ns.conf 2>/dev/null || echo "ns4.kingom.ggff.net")
                clear
                echo -e "${BG}╔═══════════════════════════════════════════════════════════════════════╗${RESET}"
                 echo -e "${BG}║${RESET}  ${ORANGE}  NOUVEAU UTILISATEUR CRE  ${RESET}                             ${BG}║${RESET}"
                echo -e "${BG}╠═══════════════════════════════════════════════════════════════════════╣${RESET}"
                 echo -e "${BG}║${RESET}  ${LAV}PORTS DISPONIBLES :${RESET}                                       ${BG}║${RESET}"
                echo -e "${BG}║${RESET}  ${WHITE}∘ SSH: 22          ∘ System-DNS: 53${RESET}                         ${BG}║${RESET}"
                echo -e "${BG}║${RESET}  ${WHITE}∘ SSH WS: 80      ∘ DROPBEAR: 109   ∘ SSL: 444${RESET}              ${BG}║${RESET}"
                echo -e "${BG}║${RESET}  ${WHITE}∘ BadVPN: 7100, 7200, 7300${RESET}                                  ${BG}║${RESET}"
                echo -e "${BG}║${RESET}  ${WHITE}∘ SLOWDNS: 5300    ∘ UDP-Custom: 1-65535${RESET}                    ${BG}║${RESET}"
                echo -e "${BG}║${RESET}  ${WHITE}∘ WS-epro: 80  ∘ Proxy WS: 9090${RESET}                             ${BG}║${RESET}"
                echo -e "${BG}╠═══════════════════════════════════════════════════════════════════════╣${RESET}"
                 echo -e "${BG}║${RESET}  ${ORANGE}DOMAINE :${RESET} ${CYAN}${D}${RESET}                                            ${BG}║${RESET}"
                 echo -e "${BG}║${RESET}  ${ORANGE}IP HOST :${RESET} ${CYAN}${IP}${RESET}                                             ${BG}║${RESET}"
                 echo -e "${BG}║${RESET}  ${ORANGE}UTILISATEUR :${RESET} ${MAG}${u}${RESET}                                            ${BG}║${RESET}"
                 echo -e "${BG}║${RESET}  ${ORANGE}MOT DE PASSE :${RESET} ${MAG}${p}${RESET}                                            ${BG}║${RESET}"
                 echo -e "${BG}║${RESET}  ${ORANGE}LIMITE :${RESET} ${YELLOW}${e} jours${RESET}                                            ${BG}║${RESET}"
                echo -e "${BG}║${RESET}  ${ORANGE}📅 DATE D'EXPIRATION :${RESET} ${YELLOW}${E}${RESET}                                      ${BG}║${RESET}"
                echo -e "${BG}╠═══════════════════════════════════════════════════════════════════════╣${RESET}"
                 echo -e "${BG}║${RESET}  ${LAV}APPS : HTTP Injector, CUSTOM, SOCKSIP TUNNEL, SSC ZIVPN, etc.${RESET}  ${BG}║${RESET}"
                 echo -e "${BG}║${RESET}  ${WHITE}SSH WS :${RESET} ${CYAN}${D}:80@${u}:${p}${RESET}                             ${BG}║${RESET}"
                 echo -e "${BG}║${RESET}  ${WHITE}SSL/TLS :${RESET} ${CYAN}${D}:444@${u}:${p}${RESET}                             ${BG}║${RESET}"
                 echo -e "${BG}║${RESET}  ${WHITE}PROXY WS :${RESET} ${CYAN}${D}:9090@${u}:${p}${RESET}                             ${BG}║${RESET}"
                 echo -e "${BG}║${RESET}  ${WHITE}SSH UDP :${RESET} ${CYAN}${D}:1-65535@${u}:${p}${RESET}                              ${BG}║${RESET}"
                 echo -e "${BG}║${RESET}  ${LAV}PAYLOAD WS:${RESET}                                              ${BG}║${RESET}"
                echo -e "${BG}║${RESET}  ${DIM}GET / HTTP/1.1[crlf]Host: [host][crlf]Connection: Upgrade${RESET}     ${BG}║${RESET}"
                echo -e "${BG}║${RESET}  ${DIM}[crlf]User-Agent: [ua][crlf]Upgrade: websocket[crlf][crlf]${RESET}    ${BG}║${RESET}"
                echo -e "${BG}╠═══════════════════════════════════════════════════════════════════════╣${RESET}"
                 echo -e "${BG}║${RESET}  ${LAV}CONFIG FASTDNS (5300)${RESET}                                    ${BG}║${RESET}"
                 echo -e "${BG}║${RESET}  ${LAV}Pub KEY:${RESET} ${YELLOW}${KEY}${RESET}          ${BG}║${RESET}"
                echo -e "${BG}║${RESET}  ${LAV}NameServer:${RESET} ${CYAN}${NS}${RESET}                                         ${BG}║${RESET}"
                 echo -e "${BG}║${RESET}  ${GREEN}COMPTE CREE AVEC SUCCES${RESET}                                   ${BG}║${RESET}"
                echo -e "${BG}╚═══════════════════════════════════════════════════════════════════════╝${RESET}"
                echo "$(date '+%Y-%m-%d %H:%M:%S') | CREATION | $u | Exp: $E" >> /var/log/kighmu-user.log 2>/dev/null || true
            else echo -e "${RED}  ✗ Échec création (user existe déjà ?)${RESET}"; fi; pause;;
             2) local -a ssh_users=(); while IFS= read -r u; do local exp=$(chage -l "$u" 2>/dev/null | grep "Account expires" | awk -F: '{print $2}' | xargs); [[ "$exp" == "never" || -z "$exp" ]] && exp="2099-12-31"; ssh_users+=("$u|$exp"); done < <(awk -F: '$7~/bash|sh/ && $3>=1000{print $1}' /etc/passwd 2>/dev/null); if (( ${#ssh_users[@]} == 0 )); then clear; echo -e "  ${YELLOW}Aucun utilisateur SSH${RESET}"; pause; else mapfile -t selected < <(show_del_panel "LISTE DES UTILISATEURS" "${ssh_users[@]}"); if (( ${#selected[@]} > 0 )); then local cnt=0; for del_user in "${selected[@]}"; do userdel -r "$del_user" 2>/dev/null && cnt=$((cnt+1)); done; clear; echo -e "${GREEN}  ✓ $cnt compte(s) SSH supprime(s)${RESET}"; else clear; echo -e "  ${YELLOW}Aucune suppression${RESET}"; fi; pause; fi;;
             3) clear; echo -e "${CYAN}━━ Liste comptes SSH ━━${RESET}"; awk -F: '$7~/bash|sh/ && $3>=1000 {printf "  %-15s exp: ", $1; system("chage -l "$1" 2>/dev/null | grep \"Account expires\" | cut -d: -f2")}' /etc/passwd; pause;;
            4) clear; echo -e "${CYAN}━━ Renew compte ━━${RESET}"; read -rp "  Username: " u; read -rp "  Jours suppl.: " e; chage -E "$(date -d "+${e}days" +%Y-%m-%d)" "$u" 2>/dev/null && echo -e "${GREEN}  ✓ Prolongé${RESET}" || echo -e "${RED}  ✗ Échec${RESET}"; pause;;
            5) clear; echo -e "${CYAN}━━ Trial 1 jour ━━${RESET}"; read -rp "  Username: " u; read -rp "  Password: " p; useradd -e "$(date -d "+1day" +%Y-%m-%d)" -s /bin/bash "$u" 2>/dev/null && echo "$u:$p" | chpasswd && echo -e "${GREEN}  ✓ Trial $u créé (24h)${RESET}"; pause;;
            6) clear; echo -e "${CYAN}━━ Check expiry ━━${RESET}"; read -rp "  Username: " u; chage -l "$u" 2>/dev/null | grep -E 'Account expires|Last change' || echo -e "${RED}  ✗ Compte introuvable${RESET}"; pause;;
            7) clear; echo -e "${CYAN}━━ Lock ━━${RESET}"; read -rp "  Username: " u; passwd -l "$u" 2>/dev/null && echo -e "${GREEN}  ✓ Bloqué${RESET}" || echo -e "${RED}  ✗ Échec${RESET}"; pause;;
            8) clear; echo -e "${CYAN}━━ Unlock ━━${RESET}"; read -rp "  Username: " u; passwd -u "$u" 2>/dev/null && echo -e "${GREEN}  ✓ Débloqué${RESET}" || echo -e "${RED}  ✗ Échec${RESET}"; pause;;
            9) clear
                echo -e "${CLR}${BG}"
                echo -e "${BG}${CYAN}╔═══$(printf '═%.0s' {1..47})═══╗${RESET}"
                echo -e "${BG}${CYAN}║${RESET}${TITLE_BG}$(center '  MONITEUR CONNEXIONS  ' 51)${RESET}${BG}${CYAN}║${RESET}"
                echo -e "${BG}${CYAN}╚═══$(printf '═%.0s' {1..47})═══╝${RESET}"
                echo -e "${BG}  ${LAV}Utilisateur       Appareils   Statut${RESET}"
                echo -e "${BG}  ${DIM}────────────────────────────────────────${RESET}"
                local total=0
                while IFS= read -r u; do
                    local count=$(who | awk -v u="$u" '$1==u' | wc -l)
                    local status="${RED}Inactif${RESET}"
                    (( count > 0 )) && status="${GREEN}Actif${RESET}"
                    total=$((total + count))
                    printf "${BG}  ${WHITE}%-16s${RESET} ${MAG}%-3s${RESET}        %b${RESET}\n" "$u" "$count" "$status"
                done < <(awk -F: '$7~/bash|sh/ && $3>=1000{print $1}' /etc/passwd 2>/dev/null | sort -u)
                echo -e "${BG}  ${DIM}────────────────────────────────────────${RESET}"
                printf "${BG}  ${LAV}TOTAL${RESET}          ${ORANGE}%s connexion(s)${RESET}                    ${BG}║${RESET}\n" "$total"
                echo; echo -e "${YELLOW}  Ctrl+C pour quitter${RESET}"; sleep 8; pause;;
            10) clear; echo -e "${CYAN}━━ Kill connexion ━━${RESET}"; read -rp "  Username: " u; pkill -u "$u" 2>/dev/null && echo -e "${GREEN}  ✓ Connexions de $u fermées${RESET}" || echo -e "${RED}  ✗ Aucune active${RESET}"; pause;;
            11) clear; echo -e "${CYAN}━━ Port SSH ━━${RESET}"; read -rp "  Nouveau port: " p; sed -i "s/^Port .*/Port $p/" /etc/ssh/sshd_config && systemctl restart ssh && echo -e "${GREEN}  ✓ Port → $p${RESET}"; pause;;
            12) clear; echo -e "${CYAN}━━ Banner ━━${RESET}"; read -rp "  Nouveau banner: " b; echo "$b" > /etc/ssh/banner.txt && systemctl restart ssh && echo -e "${GREEN}  ✓ OK${RESET}"; pause;;
            0|q) break ;;
        esac
    done
}

# ── Affiche le trafic Xray via l'API stats ──

show_xray_traffic() {
    local key="$1" label="$2"
    local XRAY_BIN="/usr/local/bin/xray" XRAY_API="127.0.0.1:10085"
    clear; echo -e "${CYAN}━━ Trafic $label (via API Xray) ━━${RESET}"
    [[ ! -x "$XRAY_BIN" ]] && { echo -e "${RED}  Xray non installé${RESET}"; pause; return; }
    local raw; raw=$("$XRAY_BIN" api statsquery --server="$XRAY_API" 2>/dev/null) || { echo -e "${RED}  API Xray indisponible${RESET}"; pause; return; }
    local users=$(echo "$raw" | jq -r '[.stat[]? | select(.name | test("^user>>>")) | (.name / ">>>")[1]] | unique[]' 2>/dev/null)
    [[ -z "$users" ]] && { echo -e "  ${YELLOW}Aucune donnée de trafic${RESET}"; pause; return; }
    echo "  ${LAV}Utilisateur       ↓ Téléchargement  ↑ Envoi          Total${RESET}"
    echo "  ${DIM}──────────────────────────────────────────────────────────${RESET}"
    local total_dl=0 total_ul=0
    while IFS= read -r u; do
        [[ -z "$u" ]] && continue
        local dl=$(echo "$raw" | jq -r "[.stat[]? | select(.name == \"user>>>${u}>>>traffic>>>downlink\") | .value] | add // 0" 2>/dev/null)
        local ul=$(echo "$raw" | jq -r "[.stat[]? | select(.name == \"user>>>${u}>>>traffic>>>uplink\") | .value] | add // 0" 2>/dev/null)
        total_dl=$((total_dl + dl)); total_ul=$((total_ul + ul))
        printf "  ${WHITE}%-16s${RESET} ${MAG}%10s${RESET}   ${CYAN}%10s${RESET}  ${ORANGE}%10s${RESET}\n" "${u%@*}" "$(fmt_bytes $dl)" "$(fmt_bytes $ul)" "$(fmt_bytes $((dl+ul)))"
    done <<< "$users"
    echo "  ${DIM}──────────────────────────────────────────────────────────${RESET}"
    printf "  ${LAV}TOTAL${RESET}           ${MAG}%10s${RESET}   ${CYAN}%10s${RESET}  ${ORANGE}%10s${RESET}\n" "$(fmt_bytes $total_dl)" "$(fmt_bytes $total_ul)" "$(fmt_bytes $((total_dl+total_ul)))"
    pause
}

show_v2ray_traffic() {
    local V2RAY_BIN="/usr/local/bin/v2ray" V2RAY_API="127.0.0.1:10086"
    clear; echo -e "${CYAN}━━ Trafic V2RAY DNS (via API V2Ray) ━━${RESET}"
    [[ ! -x "$V2RAY_BIN" ]] && { echo -e "${RED}  V2Ray non installé${RESET}"; pause; return; }
    local raw; raw=$("$V2RAY_BIN" api stats --server="$V2RAY_API" 2>/dev/null) || { echo -e "${RED}  API V2Ray indisponible${RESET}"; pause; return; }
    local users=$(echo "$raw" | jq -r '[.stat[]? | select(.name | test("^user>>>")) | (.name / ">>>")[1]] | unique[]' 2>/dev/null)
    [[ -z "$users" ]] && { echo -e "  ${YELLOW}Aucune donnée de trafic${RESET}"; pause; return; }
    echo "  ${LAV}Utilisateur       ↓ Téléchargement  ↑ Envoi          Total${RESET}"
    echo "  ${DIM}──────────────────────────────────────────────────────────${RESET}"
    local total_dl=0 total_ul=0
    while IFS= read -r u; do
        [[ -z "$u" ]] && continue
        local dl=$(echo "$raw" | jq -r "[.stat[]? | select(.name == \"user>>>${u}>>>traffic>>>downlink\") | .value] | add // 0" 2>/dev/null)
        local ul=$(echo "$raw" | jq -r "[.stat[]? | select(.name == \"user>>>${u}>>>traffic>>>uplink\") | .value] | add // 0" 2>/dev/null)
        total_dl=$((total_dl + dl)); total_ul=$((total_ul + ul))
        printf "  ${WHITE}%-16s${RESET} ${MAG}%10s${RESET}   ${CYAN}%10s${RESET}  ${ORANGE}%10s${RESET}\n" "${u%@*}" "$(fmt_bytes $dl)" "$(fmt_bytes $ul)" "$(fmt_bytes $((dl+ul)))"
    done <<< "$users"
    echo "  ${DIM}──────────────────────────────────────────────────────────${RESET}"
    printf "  ${LAV}TOTAL${RESET}           ${MAG}%10s${RESET}   ${CYAN}%10s${RESET}  ${ORANGE}%10s${RESET}\n" "$(fmt_bytes $total_dl)" "$(fmt_bytes $total_ul)" "$(fmt_bytes $((total_dl+total_ul)))"
    pause
}

menu_vmess() {
    while true; do
 sub_header 'MENU VMESS'
        printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
        sub_row 1 "CREER COMPTE"            2 "SUPPRIMER COMPTE"
        sub_row 3 "LISTE COMPTES"           4 "RENEW COMPTE"
        sub_row 5 "TRIAL ACCOUNT"           6 "CHECK EXPIRY"
        sub_row 7 "SHOW CONFIG"             8 "DELETE EXPIRED"
        sub_footer
        prompt_sub "VMESS"
        case $SUB in
            1) clear; echo -e "${CYAN}━━ Création VMESS ━━${RESET}"; read -rp "  Username: " u; read -rp "  Expire (jours): " e; read -rp "  Quota (GB, 0=illimité): " q; local id=$(gen_uuid); local exp=$(date -d "+${e}days" +%Y-%m-%d); if jq ".vmess += [{\"id\":\"$id\",\"email\":\"$u@${DOMAIN:-$IP}\",\"level\":0,\"expire\":\"$exp\",\"quota\":${q:-0}}]" /etc/xray/users.json > /tmp/xu.json 2>/dev/null && mv /tmp/xu.json /etc/xray/users.json && sync_xray; then clear; show_vmess_config "$u" "$id" "$exp" "${q:-0}"; else echo -e "${RED}  ✗ Échec${RESET}"; fi; pause;;
             2) local -a xr_users=(); while IFS='|' read -r uname exp; do xr_users+=("$uname|$exp"); done < <(jq -r '.vmess[] | select(.email) | "\(.email | split("@")[0])|\(.expire)"' /etc/xray/users.json 2>/dev/null); if (( ${#xr_users[@]} == 0 )); then clear; echo -e "  ${YELLOW}Aucun utilisateur VMESS${RESET}"; pause; else mapfile -t selected < <(show_del_panel "LISTE DES UTILISATEURS" "${xr_users[@]}"); if (( ${#selected[@]} > 0 )); then local cnt=0; for del_user in "${selected[@]}"; do jq "del(.vmess[] | select(.email | startswith(\"${del_user}@\")))" /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && cnt=$((cnt+1)); done; sync_xray; clear; echo -e "${GREEN}  ✓ $cnt compte(s) VMESS supprime(s)${RESET}"; else clear; echo -e "  ${YELLOW}Aucune suppression${RESET}"; fi; pause; fi;;
             3) clear; echo -e "${CYAN}━━ Liste VMESS ━━${RESET}"; jq -r '.vmess[] | "  \(.email) expire: \(.expire) quota: \(.quota // 0)GB"' /etc/xray/users.json 2>/dev/null || echo "  Aucun"; pause;;
            4) clear; echo -e "${CYAN}━━ Renew ━━${RESET}"; read -rp "  Username: " u; read -rp "  Jours suppl.: " e; jq "(.vmess[] | select(.email | startswith(\"$u@\")) | .expire) = \"$(date -d "+${e}days" +%Y-%m-%d)\"" /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && sync_xray && echo -e "${GREEN}  ✓ Prolongé${RESET}"; pause;;
            5) clear; echo -e "${CYAN}━━ Trial 1j ━━${RESET}"; read -rp "  Username: " u; local id=$(gen_uuid); jq ".vmess += [{\"id\":\"$id\",\"email\":\"$u@${DOMAIN:-$IP}\",\"level\":0,\"expire\":\"$(date -d "+1day" +%Y-%m-%d)\",\"quota\":1}]" /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && sync_xray && echo -e "${GREEN}  ✅ Trial $u créé (24h, 1GB)${RESET}"; pause;;
            6) clear; echo -e "${CYAN}━━ Check expiry ━━${RESET}"; read -rp "  Username: " u; jq -r '.vmess[] | select(.email | startswith("'"$u"'@")) | "Expire: \(.expire) Quota: \(.quota // 0)GB"' /etc/xray/users.json 2>/dev/null || echo "  Introuvable"; pause;;
            7) clear; echo -e "${CYAN}━━ Config VMESS ━━${RESET}"; read -rp "  Username: " u; jq -r '.vmess[] | select(.email | startswith("'"$u"'@")) | "  Serveur: '"${DOMAIN:-$IP}"':8443\n  UUID: \(.id)\n  Expire: \(.expire)\n  Quota: \(.quota // 0)GB"' /etc/xray/users.json 2>/dev/null || echo "  Introuvable"; pause;;
            8) clear; echo -e "${CYAN}━━ Suppression expirés ━━${RESET}"; local t=$(date +%s); jq --arg t "$t" '.vmess |= map(select(.expire | strptime("%Y-%m-%d") | mktime > ($t|tonumber)))' /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && sync_xray && echo -e "${GREEN}  ✓ Nettoyé${RESET}"; pause;;
            9) show_xray_traffic "vmess" "VMESS" ;;
            0|q) break ;;
        esac
    done
}

menu_vless() {
    while true; do
 sub_header 'MENU VLESS'
        printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
        sub_row 1 "CREER COMPTE"            2 "SUPPRIMER COMPTE"
        sub_row 3 "LISTE COMPTES"           4 "RENEW COMPTE"
        sub_row 5 "TRIAL ACCOUNT"           6 "CHECK EXPIRY"
        sub_row 7 "SHOW CONFIG"             8 "DELETE EXPIRED"
        sub_footer
        prompt_sub "VLESS"
        case $SUB in
            1) clear; echo -e "${CYAN}━━ Création VLESS ━━${RESET}"; read -rp "  Username: " u; read -rp "  Expire (jours): " e; read -rp "  Quota (GB, 0=illimité): " q; local id=$(gen_uuid); local exp=$(date -d "+${e}days" +%Y-%m-%d); if jq ".vless += [{\"id\":\"$id\",\"email\":\"$u@${DOMAIN:-$IP}\",\"level\":0,\"expire\":\"$exp\",\"quota\":${q:-0}}]" /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && sync_xray; then clear; show_vless_config "$u" "$id" "$exp" "${q:-0}"; else echo -e "${RED}  ✗ Échec${RESET}"; fi; pause;;
             2) local -a xr_users=(); while IFS='|' read -r uname exp; do xr_users+=("$uname|$exp"); done < <(jq -r '.vless[] | select(.email) | "\(.email | split("@")[0])|\(.expire)"' /etc/xray/users.json 2>/dev/null); if (( ${#xr_users[@]} == 0 )); then clear; echo -e "  ${YELLOW}Aucun utilisateur VLESS${RESET}"; pause; else mapfile -t selected < <(show_del_panel "LISTE DES UTILISATEURS" "${xr_users[@]}"); if (( ${#selected[@]} > 0 )); then local cnt=0; for del_user in "${selected[@]}"; do jq "del(.vless[] | select(.email | startswith(\"${del_user}@\")))" /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && cnt=$((cnt+1)); done; sync_xray; clear; echo -e "${GREEN}  ✓ $cnt compte(s) VLESS supprime(s)${RESET}"; else clear; echo -e "  ${YELLOW}Aucune suppression${RESET}"; fi; pause; fi;;
             3) clear; echo -e "${CYAN}━━ Liste VLESS ━━${RESET}"; jq -r '.vless[] | "  \(.email) expire: \(.expire) quota: \(.quota // 0)GB"' /etc/xray/users.json 2>/dev/null || echo "  Aucun"; pause;;

            4) clear; echo -e "${CYAN}━━ Renew ━━${RESET}"; read -rp "  Username: " u; read -rp "  Jours: " e; jq "(.vless[] | select(.email | startswith(\"$u@\")) | .expire) = \"$(date -d "+${e}days" +%Y-%m-%d)\"" /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && sync_xray && echo -e "${GREEN}  ✓ Prolongé${RESET}"; pause;;
            5) clear; echo -e "${CYAN}━━ Trial 1j ━━${RESET}"; read -rp "  Username: " u; local id=$(gen_uuid); jq ".vless += [{\"id\":\"$id\",\"email\":\"$u@${DOMAIN:-$IP}\",\"level\":0,\"expire\":\"$(date -d "+1day" +%Y-%m-%d)\",\"quota\":1}]" /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && sync_xray && echo -e "${GREEN}  ✅ Trial $u créé (24h, 1GB)${RESET}"; pause;;
            6) clear; echo -e "${CYAN}━━ Check ━━${RESET}"; read -rp "  Username: " u; jq -r '.vless[] | select(.email | startswith("'"$u"'@")) | "Expire: \(.expire) Quota: \(.quota // 0)GB"' /etc/xray/users.json 2>/dev/null || echo "  Introuvable"; pause;;
            7) clear; echo -e "${CYAN}━━ Config ━━${RESET}"; read -rp "  Username: " u; jq -r '.vless[] | select(.email | startswith("'"$u"'@")) | "  Serveur: '"${DOMAIN:-$IP}"':8443 flow: xtls-rprx-vision\n  UUID: \(.id)\n  Expire: \(.expire)\n  Quota: \(.quota // 0)GB"' /etc/xray/users.json 2>/dev/null || echo "  Introuvable"; pause;;
            8) clear; echo -e "${CYAN}━━ Suppression expirés ━━${RESET}"; local t=$(date +%s); jq --arg t "$t" '.vless |= map(select(.expire | strptime("%Y-%m-%d") | mktime > ($t|tonumber)))' /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && sync_xray && echo -e "${GREEN}  ✓ Nettoyé${RESET}"; pause;;
            9) show_xray_traffic "vless" "VLESS" ;;
            0|q) break ;;
        esac
    done
}

menu_trojan() {
    while true; do
 sub_header 'MENU TROJAN'
        printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
        sub_row 1 "CREER COMPTE"            2 "SUPPRIMER COMPTE"
        sub_row 3 "LISTE COMPTES"           4 "RENEW COMPTE"
        sub_row 5 "TRIAL ACCOUNT"           6 "CHECK EXPIRY"
        sub_row 7 "SHOW CONFIG"             8 "DELETE EXPIRED"
        sub_footer
        prompt_sub "TROJAN"
        case $SUB in
            1) clear; echo -e "${CYAN}━━ Création Trojan ━━${RESET}"; read -rp "  Username: " u; read -rp "  Password: " p; read -rp "  Expire (jours): " e; read -rp "  Quota (GB, 0=illimité): " q; local exp=$(date -d "+${e}days" +%Y-%m-%d); if jq ".trojan += [{\"password\":\"$p\",\"email\":\"$u@${DOMAIN:-$IP}\",\"level\":0,\"expire\":\"$exp\",\"quota\":${q:-0}}]" /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && sync_xray; then clear; show_trojan_config "$u" "$p" "$exp" "${q:-0}"; else echo -e "${RED}  ✗ Échec${RESET}"; fi; pause;;
             2) local -a xr_users=(); while IFS='|' read -r uname exp; do xr_users+=("$uname|$exp"); done < <(jq -r '.trojan[] | select(.email) | "\(.email | split("@")[0])|\(.expire)"' /etc/xray/users.json 2>/dev/null); if (( ${#xr_users[@]} == 0 )); then clear; echo -e "  ${YELLOW}Aucun utilisateur TROJAN${RESET}"; pause; else mapfile -t selected < <(show_del_panel "LISTE DES UTILISATEURS" "${xr_users[@]}"); if (( ${#selected[@]} > 0 )); then local cnt=0; for del_user in "${selected[@]}"; do jq "del(.trojan[] | select(.email | startswith(\"${del_user}@\")))" /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && cnt=$((cnt+1)); done; sync_xray; clear; echo -e "${GREEN}  ✓ $cnt compte(s) TROJAN supprime(s)${RESET}"; else clear; echo -e "  ${YELLOW}Aucune suppression${RESET}"; fi; pause; fi;;
             3) clear; echo -e "${CYAN}━━ Liste ━━${RESET}"; jq -r '.trojan[] | "  \(.email) expire: \(.expire) quota: \(.quota // 0)GB"' /etc/xray/users.json 2>/dev/null || echo "  Aucun"; pause;;
            4) clear; echo -e "${CYAN}━━ Renew ━━${RESET}"; read -rp "  Username: " u; read -rp "  Jours: " e; jq "(.trojan[] | select(.email | startswith(\"$u@\")) | .expire) = \"$(date -d "+${e}days" +%Y-%m-%d)\"" /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && sync_xray && echo -e "${GREEN}  ✓ Prolongé${RESET}"; pause;;
            5) clear; echo -e "${CYAN}━━ Trial 1j ━━${RESET}"; read -rp "  Username: " u; read -rp "  Password: " p; jq ".trojan += [{\"password\":\"$p\",\"email\":\"$u@${DOMAIN:-$IP}\",\"level\":0,\"expire\":\"$(date -d "+1day" +%Y-%m-%d)\",\"quota\":1}]" /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && sync_xray && echo -e "${GREEN}  ✅ Trial $u créé (24h, 1GB)${RESET}"; pause;;
            6) clear; echo -e "${CYAN}━━ Check ━━${RESET}"; read -rp "  Username: " u; jq -r '.trojan[] | select(.email | startswith("'"$u"'@")) | "Expire: \(.expire) Quota: \(.quota // 0)GB"' /etc/xray/users.json 2>/dev/null || echo "  Introuvable"; pause;;
            7) clear; echo -e "${CYAN}━━ Config ━━${RESET}"; read -rp "  Username: " u; jq -r '.trojan[] | select(.email | startswith("'"$u"'@")) | "  Serveur: '"${DOMAIN:-$IP}"':8443 security: tls\n  Password: \(.password)\n  Expire: \(.expire)\n  Quota: \(.quota // 0)GB"' /etc/xray/users.json 2>/dev/null || echo "  Introuvable"; pause;;
            8) clear; echo -e "${CYAN}━━ Suppression expirés ━━${RESET}"; local t=$(date +%s); jq --arg t "$t" '.trojan |= map(select(.expire | strptime("%Y-%m-%d") | mktime > ($t|tonumber)))' /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && sync_xray && echo -e "${GREEN}  ✓ Nettoyé${RESET}"; pause;;
            9) show_xray_traffic "trojan" "TROJAN" ;;
            0|q) break ;;
        esac
    done
}

menu_shadow() {
    while true; do
 sub_header 'MENU SHADOWSOCKS'
        printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
        sub_row 1 "CREER COMPTE"            2 "SUPPRIMER COMPTE"
        sub_row 3 "LISTE COMPTES"           4 "RENEW COMPTE"
        sub_row 5 "TRIAL ACCOUNT"           6 "CHECK EXPIRY"
        sub_row 7 "SHOW CONFIG"             8 "DELETE EXPIRED"
        sub_footer
        prompt_sub "SHADOWSOCKS"
        case $SUB in
            1) clear; echo -e "${CYAN}━━ Création SS ━━${RESET}"; read -rp "  Username: " u; read -rp "  Password: " p; read -rp "  Expire (jours): " e; read -rp "  Quota (GB, 0=illimité): " q; local exp=$(date -d "+${e}days" +%Y-%m-%d); if jq ".shadow += [{\"password\":\"$p\",\"method\":\"aes-256-gcm\",\"email\":\"$u@${DOMAIN:-$IP}\",\"level\":0,\"expire\":\"$exp\",\"quota\":${q:-0}}]" /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && sync_xray; then clear; show_shadow_config "$u" "$p" "$exp" "${q:-0}"; else echo -e "${RED}  ✗ Échec${RESET}"; fi; pause;;
             2) local -a xr_users=(); while IFS='|' read -r uname exp; do xr_users+=("$uname|$exp"); done < <(jq -r '.shadow[] | select(.email) | "\(.email | split("@")[0])|\(.expire)"' /etc/xray/users.json 2>/dev/null); if (( ${#xr_users[@]} == 0 )); then clear; echo -e "  ${YELLOW}Aucun utilisateur SHADOWSOCKS${RESET}"; pause; else mapfile -t selected < <(show_del_panel "LISTE DES UTILISATEURS" "${xr_users[@]}"); if (( ${#selected[@]} > 0 )); then local cnt=0; for del_user in "${selected[@]}"; do jq "del(.shadow[] | select(.email | startswith(\"${del_user}@\")))" /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && cnt=$((cnt+1)); done; sync_xray; clear; echo -e "${GREEN}  ✓ $cnt compte(s) SHADOWSOCKS supprime(s)${RESET}"; else clear; echo -e "  ${YELLOW}Aucune suppression${RESET}"; fi; pause; fi;;
             3) clear; echo -e "${CYAN}━━ Liste ━━${RESET}"; jq -r '.shadow[] | "  \(.email) expire: \(.expire) quota: \(.quota // 0)GB"' /etc/xray/users.json 2>/dev/null || echo "  Aucun"; pause;;
            4) clear; echo -e "${CYAN}━━ Renew ━━${RESET}"; read -rp "  Username: " u; read -rp "  Jours: " e; jq "(.shadow[] | select(.email | startswith(\"$u@\")) | .expire) = \"$(date -d "+${e}days" +%Y-%m-%d)\"" /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && sync_xray && echo -e "${GREEN}  ✓ Prolongé${RESET}"; pause;;
            5) clear; echo -e "${CYAN}━━ Trial ━━${RESET}"; read -rp "  Username: " u; read -rp "  Password: " p; jq ".shadow += [{\"password\":\"$p\",\"method\":\"aes-256-gcm\",\"email\":\"$u@${DOMAIN:-$IP}\",\"level\":0,\"expire\":\"$(date -d "+1day" +%Y-%m-%d)\",\"quota\":1}]" /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && sync_xray && echo -e "${GREEN}  ✅ Trial $u créé (24h, 1GB)${RESET}"; pause;;
            6) clear; echo -e "${CYAN}━━ Check ━━${RESET}"; read -rp "  Username: " u; jq -r '.shadow[] | select(.email | startswith("'"$u"'@")) | "Expire: \(.expire) Quota: \(.quota // 0)GB"' /etc/xray/users.json 2>/dev/null || echo "  Introuvable"; pause;;
            7) clear; echo -e "${CYAN}━━ Config ━━${RESET}"; read -rp "  Username: " u; jq -r '.shadow[] | select(.email | startswith("'"$u"'@")) | "  Serveur: '"${DOMAIN:-$IP}"':8443 method: aes-256-gcm\n  Password: \(.password)\n  Expire: \(.expire)\n  Quota: \(.quota // 0)GB"' /etc/xray/users.json 2>/dev/null || echo "  Introuvable"; pause;;
            8) clear; echo -e "${CYAN}━━ Suppression expirés ━━${RESET}"; local t=$(date +%s); jq --arg t "$t" '.shadow |= map(select(.expire | strptime("%Y-%m-%d") | mktime > ($t|tonumber)))' /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && sync_xray && echo -e "${GREEN}  ✓ Nettoyé${RESET}"; pause;;
            9) show_xray_traffic "shadow" "SHADOWSOCKS" ;;
            0|q) break ;;
        esac
    done
}

sync_zivpn() {
    local pwlist=$(awk -F'|' -v d="$(date +%Y-%m-%d)" '$3>=d {print $2}' /etc/zivpn/users.list 2>/dev/null | paste -sd, -)
    [[ -z "$pwlist" ]] && return 0
    jq --arg pw "$pwlist" '.auth.config = ($pw | split(","))' /etc/zivpn/config.json > /tmp/zivpn_tmp.json 2>/dev/null && mv /tmp/zivpn_tmp.json /etc/zivpn/config.json && systemctl restart zivpn 2>/dev/null || true
}
sync_hysteria() {
    local pwlist=$(awk -F'|' -v d="$(date +%Y-%m-%d)" '$3>=d {print $2}' /etc/hysteria/users.txt 2>/dev/null | paste -sd, -)
    [[ -z "$pwlist" ]] && return 0
    jq --arg pw "$pwlist" '.auth.config = ($pw | split(","))' /etc/hysteria/config.json > /tmp/hy_tmp.json 2>/dev/null && mv /tmp/hy_tmp.json /etc/hysteria/config.json && systemctl restart hysteria 2>/dev/null || true
}

gen_uuid() { cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || echo "$(date +%s)-$$-$(openssl rand -hex 4)"; }

sync_xray() {
    local users=$(cat /etc/xray/users.json 2>/dev/null || echo '{"vmess":[],"vless":[],"trojan":[],"shadow":[]}')
    # Sanitize: uuid→id (bug panel), uuid→password (trojan)
    local sanitized=$(echo "$users" | jq '
        .vmess |= map(if has("uuid") then .id = .uuid | del(.uuid) else . end) |
        .vless |= map(if has("uuid") then .id = .uuid | del(.uuid) else . end) |
        .trojan |= map(if has("uuid") then .password = .uuid | del(.uuid) else . end)
    ' 2>/dev/null || echo "$users")
    local tmp=$(mktemp)
    cat /etc/xray/config.json | jq --argjson users "$sanitized" '
        if (.inbounds | any(.tag == "api")) then . else
            .inbounds += [{"tag":"api","port":10085,"listen":"127.0.0.1","protocol":"dokodemo-door","settings":{"address":"127.0.0.1"}}]
        end |
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
        (.inbounds[] | select(.tag == "Shadowsocks") .settings.clients) = $users.shadow
    ' > "$tmp" 2>/dev/null && jq empty "$tmp" >/dev/null 2>&1 && mv "$tmp" /etc/xray/config.json && systemctl restart xray 2>/dev/null || true
}

sync_v2ray() {
    local users=$(cat /etc/v2ray/users.json 2>/dev/null || echo '{"vless":[]}')
    local tmp=$(mktemp)
    cat /etc/v2ray/config.json | jq --argjson users "$(echo "$users" | jq '.vless')" '
        if (.inbounds | any(.tag == "api")) then . else
            .inbounds += [{"tag":"api","port":10086,"listen":"127.0.0.1","protocol":"dokodemo-door","settings":{"address":"127.0.0.1"}}]
        end |
        .inbounds[0].settings.clients = $users
    ' > "$tmp" 2>/dev/null && mv "$tmp" /etc/v2ray/config.json && systemctl restart v2ray 2>/dev/null || true
}

show_vmess_config() {
  local user=$1 uuid=$2 exp=$3 quota=$4 d=${DOMAIN:-$IP}
  local ql="$quota Go"
  [ "$quota" = "0" ] && ql="0 Go"
  local j1='{"v":"2","ps":"'"$user"'","add":"'"$d"'","port":"8443","id":"'"$uuid"'","aid":0,"net":"ws","type":"none","host":"'"$d"'","path":"/vmess","tls":"tls","sni":"'"$d"'"}'
  local j2='{"v":"2","ps":"'"$user"'","add":"'"$d"'","port":"8880","id":"'"$uuid"'","aid":0,"net":"ws","type":"none","host":"'"$d"'","path":"/vmess","tls":"none"}'
  local j3='{"v":"2","ps":"'"$user"'","add":"'"$d"'","port":"8443","id":"'"$uuid"'","aid":0,"net":"grpc","type":"none","host":"'"$d"'","path":"vmess-grpc","tls":"tls","sni":"'"$d"'"}'
  echo -e "${BG}==============================${RESET}"
  echo -e "${BG}  ${WHITE}VMESS${RESET}${BG} – ${WHITE}$user${RESET}"
  echo -e "${BG}==============================${RESET}"
  echo -e "${BG}  ${LAV}Domaine${RESET}    ${CYAN}:${RESET} ${ORANGE}$d${RESET}"
  echo -e "${BG}  ${LAV}UUID/Pwd${RESET}   ${CYAN}:${RESET} ${WHITE}$uuid${RESET}"
  echo -e "${BG}  ${LAV}Path(s)${RESET}    ${CYAN}:${RESET} ${WHITE}/vmess (WS), /vmess-grpc (gRPC)${RESET}"
  echo -e "${BG}  ${LAV}Utilisateur${RESET} ${CYAN}:${RESET} ${WHITE}$user${RESET}"
  echo -e "${BG}  ${LAV}Methode${RESET}    ${CYAN}:${RESET} ${WHITE}-${RESET}"
  echo -e "${BG}  ${LAV}Limite${RESET}     ${CYAN}:${RESET} ${WHITE}$ql${RESET}"
  echo -e "${BG}  ${LAV}Expire${RESET}     ${CYAN}:${RESET} ${WHITE}$exp${RESET}"
  echo -e "${BG}●━━━━━━━━━━━━━━━━━━━ Liens ━━━━━━━━━━━━━━━━━━━●${RESET}"
  echo -e "${BG}┃ ${GREEN}TLS WS${RESET}     ${CYAN}:${RESET} ${DIM}vmess://$(printf '%s' "$j1" | base64 -w0)${RESET}"
  echo -e "${BG}┃ ${GREEN}NTLS WS${RESET}    ${CYAN}:${RESET} ${DIM}vmess://$(printf '%s' "$j2" | base64 -w0)${RESET}"
  echo -e "${BG}┃ ${GREEN}TLS gRPC${RESET}   ${CYAN}:${RESET} ${DIM}vmess://$(printf '%s' "$j3" | base64 -w0)${RESET}"
  echo -e "${BG}●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●${RESET}"
}

show_vless_config() {
  local user=$1 uuid=$2 exp=$3 quota=$4 d=${DOMAIN:-$IP}
  local ql="$quota Go"
  [ "$quota" = "0" ] && ql="0 Go"
  local base="vless://$uuid@$d"
  local name="#$user"
  echo -e "${BG}==============================${RESET}"
  echo -e "${BG}  ${WHITE}VLESS${RESET}${BG} – ${WHITE}$user${RESET}"
  echo -e "${BG}==============================${RESET}"
  echo -e "${BG}  ${LAV}Domaine${RESET}    ${CYAN}:${RESET} ${ORANGE}$d${RESET}"
  echo -e "${BG}  ${LAV}UUID/Pwd${RESET}   ${CYAN}:${RESET} ${WHITE}$uuid${RESET}"
  echo -e "${BG}  ${LAV}Path(s)${RESET}    ${CYAN}:${RESET} ${WHITE}/vless (WS), /vless-xhttp (XHTTP), /vless-hupgrade (HUp), /vless-grpc (gRPC)${RESET}"
  echo -e "${BG}  ${LAV}Utilisateur${RESET} ${CYAN}:${RESET} ${WHITE}$user${RESET}"
  echo -e "${BG}  ${LAV}Methode${RESET}    ${CYAN}:${RESET} ${WHITE}-${RESET}"
  echo -e "${BG}  ${LAV}Limite${RESET}     ${CYAN}:${RESET} ${WHITE}$ql${RESET}"
  echo -e "${BG}  ${LAV}Expire${RESET}     ${CYAN}:${RESET} ${WHITE}$exp${RESET}"
  echo -e "${BG}●━━━━━━━━━━━━━━━━━━━ Liens ━━━━━━━━━━━━━━━━━━━●${RESET}"
  echo -e "${BG}┃ ${GREEN}TLS WS${RESET}     ${CYAN}:${RESET} ${DIM}${base}:8443?security=tls&type=ws&path=/vless&host=$d&sni=$d${name}${RESET}"
  echo -e "${BG}┃ ${GREEN}NTLS WS${RESET}    ${CYAN}:${RESET} ${DIM}${base}:8880?security=none&type=ws&path=/vless&host=$d${name}${RESET}"
  echo -e "${BG}┃ ${GREEN}TLS XHTTP${RESET}  ${CYAN}:${RESET} ${DIM}${base}:8443?security=tls&type=xhttp&path=/vless-xhttp&host=$d&sni=$d${name}${RESET}"
  echo -e "${BG}┃ ${GREEN}TLS HUpg${RESET}   ${CYAN}:${RESET} ${DIM}${base}:8443?security=tls&type=httpupgrade&path=/vless-hupgrade&host=$d&sni=$d${name}${RESET}"
  echo -e "${BG}┃ ${GREEN}TLS gRPC${RESET}   ${CYAN}:${RESET} ${DIM}${base}:8443?mode=grpc&security=tls&type=grpc&serviceName=vless-grpc&sni=$d${name}${RESET}"
  echo -e "${BG}┃ ${GREEN}NTLS TCP${RESET}   ${CYAN}:${RESET} ${DIM}${base}:8880?security=none&type=tcp${name}${RESET}"
  echo -e "${BG}┃ ${GREEN}TLS TCP${RESET}    ${CYAN}:${RESET} ${DIM}${base}:8443?security=tls&type=tcp&sni=$d${name}${RESET}"
  echo -e "${BG}●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●${RESET}"
}

show_trojan_config() {
  local user=$1 pass=$2 exp=$3 quota=$4 d=${DOMAIN:-$IP}
  local ql="$quota Go"
  [ "$quota" = "0" ] && ql="0 Go"
  local base="trojan://$pass@$d"
  local name="#$user"
  echo -e "${BG}==============================${RESET}"
  echo -e "${BG}  ${WHITE}TROJAN${RESET}${BG} – ${WHITE}$user${RESET}"
  echo -e "${BG}==============================${RESET}"
  echo -e "${BG}  ${LAV}Domaine${RESET}    ${CYAN}:${RESET} ${ORANGE}$d${RESET}"
  echo -e "${BG}  ${LAV}UUID/Pwd${RESET}   ${CYAN}:${RESET} ${WHITE}$pass${RESET}"
  echo -e "${BG}  ${LAV}Path(s)${RESET}    ${CYAN}:${RESET} ${WHITE}/trojan (WS), /trojan-xhttp (XHTTP), /trojan-grpc (gRPC)${RESET}"
  echo -e "${BG}  ${LAV}Utilisateur${RESET} ${CYAN}:${RESET} ${WHITE}$user${RESET}"
  echo -e "${BG}  ${LAV}Methode${RESET}    ${CYAN}:${RESET} ${WHITE}-${RESET}"
  echo -e "${BG}  ${LAV}Limite${RESET}     ${CYAN}:${RESET} ${WHITE}$ql${RESET}"
  echo -e "${BG}  ${LAV}Expire${RESET}     ${CYAN}:${RESET} ${WHITE}$exp${RESET}"
  echo -e "${BG}●━━━━━━━━━━━━━━━━━━━ Liens ━━━━━━━━━━━━━━━━━━━●${RESET}"
  echo -e "${BG}┃ ${GREEN}TLS WS${RESET}     ${CYAN}:${RESET} ${DIM}${base}:8443?security=tls&type=ws&path=/trojan&host=$d&sni=$d${name}${RESET}"
  echo -e "${BG}┃ ${GREEN}NTLS WS${RESET}    ${CYAN}:${RESET} ${DIM}${base}:8880?security=none&type=ws&path=/trojan&host=$d${name}${RESET}"
  echo -e "${BG}┃ ${GREEN}TLS XHTTP${RESET}  ${CYAN}:${RESET} ${DIM}${base}:8443?security=tls&type=xhttp&path=/trojan-xhttp&host=$d&sni=$d${name}${RESET}"
  echo -e "${BG}┃ ${GREEN}TLS gRPC${RESET}   ${CYAN}:${RESET} ${DIM}${base}:8443?security=tls&type=grpc&serviceName=trojan-grpc&sni=$d${name}${RESET}"
  echo -e "${BG}┃ ${GREEN}NTLS TCP${RESET}   ${CYAN}:${RESET} ${DIM}${base}:8880?security=none&type=tcp${name}${RESET}"
  echo -e "${BG}┃ ${GREEN}TLS TCP${RESET}    ${CYAN}:${RESET} ${DIM}${base}:8443?security=tls&type=tcp&sni=$d${name}${RESET}"
  echo -e "${BG}●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●${RESET}"
}

show_shadow_config() {
  local user=$1 pass=$2 exp=$3 quota=$4 d=${DOMAIN:-$IP} method="aes-256-gcm"
  local ql="$quota Go"
  [ "$quota" = "0" ] && ql="0 Go"
  local auth=$(printf '%s' "$method:$pass" | base64 -w0)
  local base="ss://$auth@$d"
  local name="#$user"
  echo -e "${BG}==============================${RESET}"
  echo -e "${BG}  ${WHITE}SHADOW${RESET}${BG} – ${WHITE}$user${RESET}"
  echo -e "${BG}==============================${RESET}"
  echo -e "${BG}  ${LAV}Domaine${RESET}    ${CYAN}:${RESET} ${ORANGE}$d${RESET}"
  echo -e "${BG}  ${LAV}UUID/Pwd${RESET}   ${CYAN}:${RESET} ${WHITE}$pass${RESET}"
  echo -e "${BG}  ${LAV}Path(s)${RESET}    ${CYAN}:${RESET} ${WHITE}/shadow (WS), /shadow-grpc (gRPC)${RESET}"
  echo -e "${BG}  ${LAV}Utilisateur${RESET} ${CYAN}:${RESET} ${WHITE}$user${RESET}"
  echo -e "${BG}  ${LAV}Methode${RESET}    ${CYAN}:${RESET} ${WHITE}$method${RESET}"
  echo -e "${BG}  ${LAV}Limite${RESET}     ${CYAN}:${RESET} ${WHITE}$ql${RESET}"
  echo -e "${BG}  ${LAV}Expire${RESET}     ${CYAN}:${RESET} ${WHITE}$exp${RESET}"
  echo -e "${BG}●━━━━━━━━━━━━━━━━━━━ Liens ━━━━━━━━━━━━━━━━━━━●${RESET}"
  echo -e "${BG}┃ ${GREEN}NTLS WS${RESET}    ${CYAN}:${RESET} ${DIM}${base}:8880?plugin=v2ray-plugin;path=/shadow;host=$d${name}${RESET}"
  echo -e "${BG}┃ ${GREEN}TLS WS${RESET}     ${CYAN}:${RESET} ${DIM}${base}:8443?plugin=v2ray-plugin;path=/shadow;host=$d;tls${name}${RESET}"
  echo -e "${BG}┃ ${GREEN}TLS gRPC${RESET}   ${CYAN}:${RESET} ${DIM}${base}:8443?plugin=v2ray-plugin;mode=grpc;serviceName=shadow-grpc;tls${name}${RESET}"
  echo -e "${BG}●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●${RESET}"
}

show_v2ray_config() {
  local user=$1 uuid=$2 exp=$3 quota=$4 days=$5
  local d=${DOMAIN:-$IP} pk=$(cat /etc/slowdns/server.pub 2>/dev/null || echo "n/a")
  local ns=${NV4:-nv4.kingom.ggff.net}
  local ql="Illimite"
  [ "$quota" != "0" ] && ql="$quota Go"
  local line="vless://$uuid@$d:5401?type=tcp&encryption=none&host=$d#$user-VLESS-TCP"
  echo -e "${BG}==========================================${RESET}"
  echo -e "${BG} ${CYAN}🧩${RESET}${BG} ${WHITE}VLESS TCP + FASTDNS${RESET}"
  echo -e "${BG}====================================================${RESET}"
  echo -e "${BG} ${CYAN}📄${RESET}${BG} ${LAV}Configuration pour${RESET} ${CYAN}:${RESET} ${WHITE}$user${RESET}"
  echo -e "${BG}-------------------------------------------------------------${RESET}"
  echo -e "${BG} ${CYAN}➤${RESET}${BG} ${LAV}DOMAINE${RESET} ${CYAN}:${RESET} ${ORANGE}$d${RESET}"
  echo -e "${BG} ${CYAN}➤${RESET}${BG} ${LAV}PORTS${RESET} ${CYAN}:${RESET}"
  echo -e "${BG}   ${LAV}FastDNS UDP${RESET} ${CYAN}:${RESET} ${WHITE}5354${RESET}"
  echo -e "${BG}   ${LAV}V2Ray TCP${RESET}  ${CYAN}:${RESET} ${WHITE}5401${RESET}"
  echo -e "${BG} ${CYAN}➤${RESET}${BG} ${LAV}UUID / Password${RESET} ${CYAN}:${RESET} ${WHITE}$uuid${RESET}"
  echo -e "${BG} ${CYAN}➤${RESET}${BG} ${LAV}Validite${RESET} ${CYAN}:${RESET} ${WHITE}$days jours${RESET} ${CYAN}(${RESET}${LAV}expire${RESET}${CYAN}:${RESET}${WHITE} $exp${RESET}${CYAN})${RESET}"
  echo -e "${BG} ${CYAN}➤${RESET}${BG} ${LAV}Quota${RESET}    ${CYAN}:${RESET} ${WHITE}$ql${RESET}"
  echo -e "${BG}━━━━━━━━━━━━━  ${WHITE}CONFIGS SLOWDNS PORT 5354${RESET}${BG} ━━━━━━━━━━━━━●${RESET}"
  echo -e "${BG}  ${LAV}CLe publique FastDNS${RESET} ${CYAN}:${RESET}"
  echo -e "${BG}  ${MAG}$pk${RESET}"
  echo -e "${BG}  ${LAV}NameServer${RESET} ${CYAN}:${RESET} ${MAG}$ns${RESET}"
  echo -e "${BG}●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●${RESET}"
  echo -e "${BG}┃ ${CYAN}Lien VLESS${RESET}  ${CYAN}:${RESET} ${DIM}$line${RESET}"
  echo -e "${BG}●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●${RESET}"
}

menu_zivpn() {
    while true; do
 sub_header 'MENU ZIVPN'
        printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
        sub_row 1 "CREER COMPTE"            2 "SUPPRIMER COMPTE"
        sub_row 3 "LISTE COMPTES"           4 "RENEW COMPTE"
        sub_row 5 "TRIAL ACCOUNT"           6 "CHECK EXPIRY"
        sub_row 7 "SHOW CONFIG"             8 "DELETE EXPIRED"
        sub_footer
        prompt_sub "ZIVPN"
        case $SUB in
            1) clear; echo -e "${CYAN}━━ Création ZIVPN ━━${RESET}"; read -rp "  Username: " u; read -rp "  Password: " p; read -rp "  Expire (jours): " e; local exp=$(date -d "+${e}days" +%Y-%m-%d); if echo "$u|$p|$exp" >> /etc/zivpn/users.list 2>/dev/null; then echo -e "${GREEN}  ✅ UTILISATEUR CREE${RESET}"; sync_zivpn; echo; echo -e "  🌐 Domaine : ${WHITE}${DOMAIN}${RESET}"; echo -e "  🔐 Password : ${WHITE}${p}${RESET}"; echo -e "  📅 Expire : ${WHITE}${exp}${RESET}"; else echo -e "${RED}  ✗ Échec${RESET}"; fi; pause;;
             2) local -a udp_users=(); while IFS='|' read -r uname _pw exp; do udp_users+=("$uname|$exp"); done < /etc/zivpn/users.list 2>/dev/null; if (( ${#udp_users[@]} == 0 )); then clear; echo -e "  ${YELLOW}Aucun utilisateur ZIVPN${RESET}"; pause; else mapfile -t selected < <(show_del_panel "LISTE DES UTILISATEURS" "${udp_users[@]}"); if (( ${#selected[@]} > 0 )); then local cnt=0; for del_user in "${selected[@]}"; do sed -i "/^${del_user}|/d" /etc/zivpn/users.list 2>/dev/null || true; cnt=$((cnt+1)); done; sync_zivpn; clear; echo -e "${GREEN}  ✓ $cnt compte(s) ZIVPN supprime(s)${RESET}"; else clear; echo -e "  ${YELLOW}Aucune suppression${RESET}"; fi; pause; fi;;
             3) clear; echo -e "${CYAN}━━ Liste ━━${RESET}"; [[ -f /etc/zivpn/users.list ]] && cat /etc/zivpn/users.list | awk -F'|' '{print "  " $1 " → " $3}' || echo "  Aucun"; pause;;
            4) clear; echo -e "${CYAN}━━ Renew ━━${RESET}"; read -rp "  Username: " u; read -rp "  Jours: " e; sed -i "/^$u|/s|[^|]*$|$(date -d "+${e}days" +%Y-%m-%d)|" /etc/zivpn/users.list 2>/dev/null && echo -e "${GREEN}  ✓ Prolongé${RESET}"; sync_zivpn; pause;;
            5) clear; echo -e "${CYAN}━━ Trial ━━${RESET}"; read -rp "  Username: " u; read -rp "  Password: " p; echo "$u|$p|$(date -d "+1day" +%Y-%m-%d)" >> /etc/zivpn/users.list && echo -e "${GREEN}  ✓ Trial $u créé${RESET}"; sync_zivpn; pause;;
            6) clear; echo -e "${CYAN}━━ Check ━━${RESET}"; read -rp "  Username: " u; awk -F'|' -v u="$u" '$1==u{print "  Expire: " $3}' /etc/zivpn/users.list 2>/dev/null || echo "  Introuvable"; pause;;
            7) clear; echo -e "${CYAN}━━ Config ━━${RESET}"; echo "  ${DOMAIN:-$IP}:5667 (UDP)"; pause;;
            8) clear; echo -e "${CYAN}━━ Suppression expirés ━━${RESET}"; local t=$(date +%s); [[ -f /etc/zivpn/users.list ]] && awk -F'|' -v t="$t" 'system("date -d "$3" +%s") >= t' /etc/zivpn/users.list > /tmp/zu.list 2>/dev/null && mv /tmp/zu.list /etc/zivpn/users.list; echo -e "${GREEN}  ✓ Nettoyé${RESET}"; sync_zivpn; pause;;
            0|q) break ;;
        esac
    done
}

menu_hysteria() {
    while true; do
 sub_header 'MENU HYSTERIA'
        printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
        sub_row 1 "CREER COMPTE"            2 "SUPPRIMER COMPTE"
        sub_row 3 "LISTE COMPTES"           4 "RENEW COMPTE"
        sub_row 5 "TRIAL ACCOUNT"           6 "CHECK EXPIRY"
        sub_row 7 "SHOW CONFIG"             8 "DELETE EXPIRED"
        sub_footer
        prompt_sub "HYSTERIA"
        case $SUB in
            1) clear; echo -e "${CYAN}━━ Création Hysteria ━━${RESET}"; read -rp "  Username: " u; read -rp "  Password: " p; read -rp "  Expire (jours): " e; local exp=$(date -d "+${e}days" +%Y-%m-%d); if echo "$u|$p|$exp" >> /etc/hysteria/users.txt 2>/dev/null; then echo -e "${GREEN}  ✅ UTILISATEUR CREE${RESET}"; sync_hysteria; echo; echo -e "  🌐 Domaine : ${WHITE}${DOMAIN}${RESET}"; echo -e "  🎭 Obfs : ${WHITE}hysteria${RESET}"; echo -e "  🔐 Password : ${WHITE}${p}${RESET}"; echo -e "  📅 Expire : ${WHITE}${exp}${RESET}"; echo -e "  🔌 Port : ${WHITE}20000-50000${RESET}"; else echo -e "${RED}  ✗ Échec${RESET}"; fi; pause;;
             2) local -a udp_users=(); while IFS='|' read -r uname _pw exp; do udp_users+=("$uname|$exp"); done < /etc/hysteria/users.txt 2>/dev/null; if (( ${#udp_users[@]} == 0 )); then clear; echo -e "  ${YELLOW}Aucun utilisateur HYSTERIA${RESET}"; pause; else mapfile -t selected < <(show_del_panel "LISTE DES UTILISATEURS" "${udp_users[@]}"); if (( ${#selected[@]} > 0 )); then local cnt=0; for del_user in "${selected[@]}"; do sed -i "/^${del_user}|/d" /etc/hysteria/users.txt 2>/dev/null || true; cnt=$((cnt+1)); done; sync_hysteria; clear; echo -e "${GREEN}  ✓ $cnt compte(s) HYSTERIA supprime(s)${RESET}"; else clear; echo -e "  ${YELLOW}Aucune suppression${RESET}"; fi; pause; fi;;
             3) clear; echo -e "${CYAN}━━ Liste ━━${RESET}"; [[ -f /etc/hysteria/users.txt ]] && cat /etc/hysteria/users.txt | awk -F'|' '{print "  " $1 " → " $3}' || echo "  Aucun"; pause;;
            4) clear; echo -e "${CYAN}━━ Renew ━━${RESET}"; read -rp "  Username: " u; read -rp "  Jours: " e; sed -i "/^$u|/s|[^|]*$|$(date -d "+${e}days" +%Y-%m-%d)|" /etc/hysteria/users.txt 2>/dev/null && echo -e "${GREEN}  ✓ Prolongé${RESET}"; sync_hysteria; pause;;
            5) clear; echo -e "${CYAN}━━ Trial ━━${RESET}"; read -rp "  Username: " u; read -rp "  Password: " p; echo "$u|$p|$(date -d "+1day" +%Y-%m-%d)" >> /etc/hysteria/users.txt && echo -e "${GREEN}  ✓ Trial $u créé${RESET}"; sync_hysteria; pause;;
            6) clear; echo -e "${CYAN}━━ Check ━━${RESET}"; read -rp "  Username: " u; awk -F'|' -v u="$u" '$1==u{print "  Expire: " $3}' /etc/hysteria/users.txt 2>/dev/null || echo "  Introuvable"; pause;;
            7) clear; echo -e "${CYAN}━━ Config ━━${RESET}"; echo "  ${DOMAIN:-$IP}:20000 (UDP)"; pause;;
            8) clear; echo -e "${CYAN}━━ Suppression expirés ━━${RESET}"; local t=$(date +%s); [[ -f /etc/hysteria/users.txt ]] && awk -F'|' -v t="$t" 'system("date -d "$3" +%s") >= t' /etc/hysteria/users.txt > /tmp/hy.list 2>/dev/null && mv /tmp/hy.list /etc/hysteria/users.txt; echo -e "${GREEN}  ✓ Nettoyé${RESET}"; sync_hysteria; pause;;
            0|q) break ;;
        esac
    done
}

menu_v2ray_dns() {
    while true; do
 sub_header 'MENU V2RAY DNS'
        printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
        sub_row 1 "CREER COMPTE"            2 "SUPPRIMER COMPTE"
        sub_row 3 "LISTE COMPTES"           4 "RENEW COMPTE"
        sub_row 5 "TRIAL ACCOUNT"           6 "CHECK EXPIRY"
        sub_row 7 "SHOW CONFIG"             8 "CHANGE NS"
        sub_footer
        prompt_sub "V2RAY DNS"
        case $SUB in
            1) clear; echo -e "${CYAN}━━ Création V2Ray DNS ━━${RESET}"; read -rp "  Username: " u; read -rp "  Expire (jours): " e; read -rp "  Quota (GB, 0=illimité): " q; local id=$(gen_uuid); local exp=$(date -d "+${e}days" +%Y-%m-%d); if jq ".vless += [{\"id\":\"$id\",\"email\":\"$u@${DOMAIN:-$IP}\",\"level\":0,\"expire\":\"$exp\",\"quota\":${q:-0}}]" /etc/v2ray/users.json 2>/dev/null > /tmp/v2u.json && mv /tmp/v2u.json /etc/v2ray/users.json && sync_v2ray; then clear; show_v2ray_config "$u" "$id" "$exp" "${q:-0}" "$e"; else echo -e "${RED}  ✗ Échec${RESET}"; fi; pause;;
             2) local -a v2_users=(); while IFS='|' read -r uname exp; do v2_users+=("$uname|$exp"); done < <(jq -r '.vless[] | select(.email) | "\(.email | split("@")[0])|\(.expire)"' /etc/v2ray/users.json 2>/dev/null); if (( ${#v2_users[@]} == 0 )); then clear; echo -e "  ${YELLOW}Aucun utilisateur V2RAY${RESET}"; pause; else mapfile -t selected < <(show_del_panel "LISTE DES UTILISATEURS" "${v2_users[@]}"); if (( ${#selected[@]} > 0 )); then local cnt=0; for del_user in "${selected[@]}"; do jq "del(.vless[] | select(.email | startswith(\"${del_user}@\")))" /etc/v2ray/users.json > /tmp/v2u.json && mv /tmp/v2u.json /etc/v2ray/users.json && cnt=$((cnt+1)); done; sync_v2ray; clear; echo -e "${GREEN}  ✓ $cnt compte(s) V2RAY supprime(s)${RESET}"; else clear; echo -e "  ${YELLOW}Aucune suppression${RESET}"; fi; pause; fi;;
             3) clear; echo -e "${CYAN}━━ Liste V2Ray DNS ━━${RESET}"; jq -r '.vless[] | "  \(.email) expire: \(.expire) quota: \(.quota // 0)GB"' /etc/v2ray/users.json 2>/dev/null || echo "  Aucun"; pause;;
            4) clear; echo -e "${CYAN}━━ Renew ━━${RESET}"; read -rp "  Username: " u; read -rp "  Jours: " e; jq "(.vless[] | select(.email | startswith(\"$u@\")) | .expire) = \"$(date -d "+${e}days" +%Y-%m-%d)\"" /etc/v2ray/users.json > /tmp/v2u.json && mv /tmp/v2u.json /etc/v2ray/users.json && sync_v2ray && echo -e "${GREEN}  ✓ Prolongé${RESET}"; pause;;
            5) clear; echo -e "${CYAN}━━ Trial 1j ━━${RESET}"; read -rp "  Username: " u; local id=$(gen_uuid); jq ".vless += [{\"id\":\"$id\",\"email\":\"$u@${DOMAIN:-$IP}\",\"level\":0,\"expire\":\"$(date -d "+1day" +%Y-%m-%d)\",\"quota\":1}]" /etc/v2ray/users.json > /tmp/v2u.json && mv /tmp/v2u.json /etc/v2ray/users.json && sync_v2ray && echo -e "${GREEN}  ✅ Trial $u créé (24h, 1GB)${RESET}"; pause;;
            6) clear; echo -e "${CYAN}━━ Check ━━${RESET}"; read -rp "  Username: " u; jq -r '.vless[] | select(.email | startswith("'"$u"'@")) | "Expire: \(.expire) Quota: \(.quota // 0)GB"' /etc/v2ray/users.json 2>/dev/null || echo "  Introuvable"; pause;;
            7) clear; echo -e "${CYAN}━━ Config ━━${RESET}"; read -rp "  Username: " u; jq -r '.vless[] | select(.email | startswith("'"$u"'@")) | "  Serveur: '"${DOMAIN:-$IP}"':8443 (V2Ray DNS)\n  UUID: \(.id)\n  Expire: \(.expire)\n  Quota: \(.quota // 0)GB"' /etc/v2ray/users.json 2>/dev/null || echo "  Introuvable"; pause;;
            8) clear; echo -e "${CYAN}━━ Changer NS V2Ray ━━${RESET}"
                echo -e "  ${LAV}Actuel:${RESET} ${MAG}$NV4${RESET}"
                read -rp "  Nouveau NV4: " n
                if [[ -n "$n" && "$n" != "0" ]]; then
                    mkdir -p /etc/slowdns/nv4
                    echo "$n" > /etc/slowdns/nv4/ns.conf
                    cat > /usr/local/bin/slowdns-nv4-start.sh << NV4EOF
#!/bin/bash
NV4=\$(cat /etc/slowdns/nv4/ns.conf)
exec /usr/local/bin/dnstt-server -udp 0.0.0.0:5354 -privkey-file /etc/slowdns/server.key \$NV4 127.0.0.1:5401
NV4EOF
                    chmod +x /usr/local/bin/slowdns-nv4-start.sh
                    systemctl restart slowdns-nv4 2>/dev/null || true
                    echo -e "${GREEN}  ✓ NV4 mis à jour: ${MAG}$n${RESET} (service redémarré)${RESET}"
                fi; pause;;
            9) show_v2ray_traffic ;;
            0|q) break ;;
        esac
    done
}

menu_auto_reboot() {
 sub_header 'AUTO REBOOT'
    printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
    local cron=$(crontab -l 2>/dev/null | grep -i reboot || true)
    if [[ -n "$cron" ]]; then
        printf "${BG}║${RESET}  ${GREEN}Auto-reboot actif${RESET}                                        ${BG}║${RESET}\n"
        printf "${BG}║${RESET}  ${WHITE}$cron${RESET}                          ${BG}║${RESET}\n"
        sub_row 1 "DESACTIVER AUTO REBOOT"  2 "CHANGER HORAIRE"
    else
        printf "${BG}║${RESET}  ${RED}Auto-reboot inactif${RESET}                                      ${BG}║${RESET}\n"
        sub_row 1 "ACTIVER AUTO REBOOT"     2 "SET HORAIRE (2h-6h)"
    fi
    sub_footer
    prompt_sub "AUTO REBOOT"
    case $SUB in
        1) if [[ -n "$cron" ]]; then crontab -l 2>/dev/null | grep -v reboot | crontab - && echo -e "${GREEN}  ✓ Auto-reboot désactivé${RESET}"; else (crontab -l 2>/dev/null; echo "0 4 * * * /sbin/reboot") | crontab - && echo -e "${GREEN}  ✓ Auto-reboot activé (4h)${RESET}"; fi; pause;;
        2) read -rp "  Heure (0-23): " h; crontab -l 2>/dev/null | grep -v reboot | crontab -; (crontab -l 2>/dev/null; echo "0 $h * * * /sbin/reboot") | crontab - && echo -e "${GREEN}  ✓ Reboot programmé à ${h}h${RESET}"; pause;;
        0|q) ;;
    esac
}

menu_port() {
    while true; do
 sub_header 'MENU PORT'
        printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
        sub_row 1 "CHANGE PORT SSH"         2 "CHANGE PORT DROPBEAR"
        sub_row 3 "CHANGE PORT NGINX"       4 "CHANGE PORT XRAY"
        sub_row 5 "CHANGE PORT SLOWDNS"     6 "LISTE PORTS ACTIFS"
        sub_footer
        prompt_sub "PORT"
        case $SUB in
            1) clear; echo -e "${CYAN}━━ Port SSH ━━${RESET}"; read -rp "  Nouveau port: " p; sed -i "s/^Port .*/Port $p/" /etc/ssh/sshd_config && systemctl restart ssh && echo -e "${GREEN}  ✓ Port SSH → $p${RESET}"; pause;;
            2) clear; echo -e "${CYAN}━━ Port Dropbear ━━${RESET}"; read -rp "  Nouveau port: " p; sed -i "s/-p [0-9]*/-p $p/" /etc/default/dropbear 2>/dev/null && systemctl restart dropbear-custom && echo -e "${GREEN}  ✓ Dropbear → $p${RESET}"; pause;;
            3) clear; echo -e "${CYAN}━━ Port Nginx ━━${RESET}"; read -rp "  Nouveau port: " p; sed -i "s/listen [0-9]*/listen $p/" /etc/nginx/sites-enabled/* 2>/dev/null && nginx -t && systemctl restart nginx && echo -e "${GREEN}  ✓ Nginx → $p${RESET}"; pause;;
            4) clear; echo -e "${CYAN}━━ Port Xray ━━${RESET}"; echo "   Modifier /etc/xray/config.json manuellement"; pause;;
            5) clear; echo -e "${CYAN}━━ Port SlowDNS ━━${RESET}"; read -rp "  Nouveau port: " p; sed -i "s/^port: [0-9]*/port: $p/" /etc/slowdns/server.conf 2>/dev/null && systemctl restart slowdns && echo -e "${GREEN}  ✓ SlowDNS → $p${RESET}"; pause;;
            6) clear; echo -e "${CYAN}━━ Ports ouverts ━━${RESET}"; ss -tlnp 2>/dev/null | awk 'NR>1{print "  "$4}' | sort -u || echo "  Aucun"; pause;;
            0|q) break ;;
        esac
    done
}

menu_panel_web() {
    while true; do
 sub_header 'PANEL WEB'
        printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
        sub_row 1 "STATUT PANEL"             2 "DEMARRER PANEL"
        sub_row 3 "ARRETER PANEL"            4 "RESTART PANEL"
        sub_row 5 "CHANGE PORT PANEL"        6 "VIEW LOGS"
        sub_row 7 "LOGS TEMPS REEL"          8 "CHANGER DOMAINE"
        sub_row 9 "CERT SSL PANEL"          10 "BACKUP PANEL"
        sub_row 11 "RESTORE PANEL"          12 "RESET PASSWORD"
        sub_row 13 "STATUT MYSQL"           14 "MAINTENANCE"
        sub_footer
        prompt_sub "PANEL WEB"
        case $SUB in
            1) clear; echo -e "${CYAN}━━ Statut Panel ━━${RESET}"; pm2 show kighmu-panel 2>/dev/null | grep -E 'status|uptime|restarts|cpu|memory' || echo -e "${RED}  Panel non trouvé${RESET}"; pause;;
            2) clear; pm2 start kighmu-panel 2>/dev/null && echo -e "${GREEN}  ✓ Panel démarré${RESET}" || echo -e "${YELLOW}  Déjà en cours${RESET}"; pause;;
            3) clear; pm2 stop kighmu-panel 2>/dev/null && echo -e "${GREEN}  ✓ Panel arrêté${RESET}" || echo -e "${RED}  ✗ Déjà arrêté${RESET}"; pause;;
            4) clear; pm2 restart kighmu-panel 2>/dev/null && echo -e "${GREEN}  ✓ Panel redémarré${RESET}" || echo -e "${RED}  ✗ Échec${RESET}"; pause;;
            5) clear; echo -e "${CYAN}━━ Port Panel ━━${RESET}"; read -rp "  Nouveau port: " p; sed -i "s/listen [0-9]*;/listen $p;/" /etc/nginx/sites-enabled/kighmu 2>/dev/null && nginx -t && systemctl restart nginx && echo -e "${GREEN}  ✓ Port → $p${RESET}" || echo -e "${RED}  ✗ Échec${RESET}"; pause;;
            6) clear; tail -30 /var/log/kighmu*.log 2>/dev/null || echo "  Aucun log"; pause;;
            7) clear; echo -e "${YELLOW}  Ctrl+C pour quitter${RESET}"; tail -f /var/log/kighmu*.log 2>/dev/null || echo "  Aucun log";;
            8) clear; echo -e "${CYAN}━━ Domaine Panel ━━${RESET}"; read -rp "  Nouveau domaine: " d; echo "$d" > /etc/kighmu/domain.txt 2>/dev/null; echo -e "${GREEN}  ✓ Domaine: $d${RESET}"; pause;;
            9) clear; echo -e "${CYAN}━━ Cert SSL Panel ━━${RESET}"; read -rp "  Domaine à certifier: " d; DEBIAN_FRONTEND=noninteractive apt-get install -y -qq certbot python3-certbot-nginx 2>/dev/null; certbot --nginx -d "$d" --non-interactive --agree-tos -m admin@"$d" 2>/dev/null && echo -e "${GREEN}  ✓ SSL OK${RESET}" || echo -e "${RED}  ✗ Échec${RESET}"; pause;;
            10) clear; echo -e "${CYAN}━━ Backup ━━${RESET}"; local f="/root/kighmu-panel-backup-$(date +%Y%m%d-%H%M).tar.gz"; tar -czf "$f" /opt/kighmu-panel /etc/nginx/sites-available/kighmu /etc/kighmu/domain.txt 2>/dev/null && echo -e "${GREEN}  ✓ $f${RESET}" || echo -e "${RED}  ✗ Échec${RESET}"; pause;;
            11) clear; echo -e "${CYAN}━━ Restore ━━${RESET}"; ls -1 /root/kighmu-panel-backup-*.tar.gz 2>/dev/null || echo "  Aucun backup"; read -rp "  Fichier: " f; [[ -f "$f" ]] && tar -xzf "$f" -C / && pm2 restart kighmu-panel 2>/dev/null && echo -e "${GREEN}  ✓ Restauré${RESET}" || echo -e "${RED}  ✗ Fichier invalide${RESET}"; pause;;
            12) clear; echo -e "${CYAN}━━ Reset Password Admin ━━${RESET}"; local p=$(openssl rand -base64 20 | tr -d '=/+' | head -c 12); node -e "const mysql=require('mysql2/promise');const bcrypt=require('bcryptjs');(async()=>{const c=await mysql.createConnection({host:'127.0.0.1',user:'kighmu_user',password:'$(grep DB_PASSWORD /opt/kighmu-panel/.env 2>/dev/null | cut -d= -f2)',database:'kighmu_panel'});const h=await bcrypt.hash('$p',12);await c.execute('UPDATE admins SET password=? WHERE username=?',[h,'admin']);await c.end();})();" 2>/dev/null && echo -e "  ${LAV}Nouveau mot de passe: ${ORANGE}${p}${RESET}" || echo -e "${RED}  ✗ Échec${RESET}"; pause;;
            13) clear; echo -e "${CYAN}━━ MySQL ━━${RESET}"; mysqladmin ping 2>/dev/null && echo -e "  ${GREEN}✓ MySQL actif${RESET}" || echo -e "  ${RED}✗ MySQL inactif${RESET}"; mysql -e "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='kighmu_panel';" 2>/dev/null | grep -q kighmu_panel && echo -e "  ${GREEN}✓ Base kighmu_panel OK${RESET}" || echo -e "  ${RED}✗ Base absente${RESET}"; pause;;
            14) clear; echo -e "${CYAN}━━ Maintenance ━━${RESET}"; if [[ -f /opt/kighmu-panel/.maintenance ]]; then rm -f /opt/kighmu-panel/.maintenance && echo -e "${GREEN}  ✓ Mode maintenance OFF${RESET}"; else touch /opt/kighmu-panel/.maintenance && echo -e "${GREEN}  ✓ Mode maintenance ON (503)${RESET}"; fi; nginx -t && systemctl restart nginx 2>/dev/null; pause;;
            15) clear; echo -e "${CYAN}━━ Update Panel ━━${RESET}"
                local u="https://raw.githubusercontent.com/kinf744/Tyiop24/main"
                curl -fsSL "$u/server.js" -o /opt/kighmu-panel/server.js.new 2>/dev/null && mv /opt/kighmu-panel/server.js.new /opt/kighmu-panel/server.js && echo -e "${GREEN}  ✓ server.js mis à jour${RESET}" || echo -e "${RED}  ✗ Échec server.js${RESET}"
                for f in admin.html reseller.html; do
                    curl -fsSL "$u/$f" -o "/opt/kighmu-panel/frontend/${f%.html}/index.html.new" 2>/dev/null && mv "/opt/kighmu-panel/frontend/${f%.html}/index.html.new" "/opt/kighmu-panel/frontend/${f%.html}/index.html" && echo -e "${GREEN}  ✓ $f mis à jour${RESET}" || echo -e "${RED}  ✗ Échec $f${RESET}"
                done
                pm2 restart kighmu-panel 2>/dev/null && echo -e "${GREEN}  ✓ Panel redémarré${RESET}"; pause;;
            0|q) break ;;
        esac
    done
}

menu_dell_all_exp() {
    while true; do
 sub_header 'DELETE ALL EXPIRED'
        printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
        sub_row 1 "COMPTES SSH EXPIRES"        2 "COMPTES XRAY EXPIRES"
        sub_row 3 "TOUS COMPTES EXPIRES"       4 "LISTE COMPTES EXPIRES"
        sub_footer
        prompt_sub "DELL EXP"
        case $SUB in
            1) clear; echo -e "${CYAN}━━ SSH expirés ━━${RESET}"
                local today=$(date +%s) c=0
                for u in $(awk -F: '$7~/bash|sh/ && $3>=1000 {print $1}' /etc/passwd); do
                    local exp=$(chage -l "$u" 2>/dev/null | grep "Account expires" | awk -F: '{print $2}' | xargs)
                    [[ "$exp" != "never" && "$exp" != "" ]] && [[ $(date -d "$exp" +%s 2>/dev/null) -lt $today ]] && userdel -r "$u" 2>/dev/null && c=$((c+1))
                done; echo -e "${GREEN}  ✓ $c comptes SSH supprimés${RESET}"; pause;;
            2) clear; echo -e "${CYAN}━━ Xray/V2Ray expirés ━━${RESET}"
                local c=0
                for f in /etc/xray/users.json /etc/v2ray/users.json; do
                    [[ ! -f "$f" ]] && continue
                    local t=$(basename $(dirname "$f"))
                    for proto in vmess vless trojan shadow; do
                        jq -r ".$proto // {} | to_entries[] | select(.value < \"$(date +%Y-%m-%d)\") | .key" "$f" 2>/dev/null | while read -r u; do
                            jq "del(.$proto.\"$u\")" "$f" > /tmp/u.json && mv /tmp/u.json "$f" && c=$((c+1))
                        done
                    done
                done; echo -e "${GREEN}  ✓ Comptes Xray/V2Ray expirés supprimés${RESET}"; pause;;
            3) clear; echo -e "${RED}⚠ Supprimer TOUS les comptes expirés ?${RESET}"
                read -rp "  Confirmer (o/N): " c3; [[ "$c3" =~ ^[oO]$ ]] || break
                local today=$(date +%s) c=0
                for u in $(awk -F: '$7~/bash|sh/ && $3>=1000 {print $1}' /etc/passwd); do
                    local exp=$(chage -l "$u" 2>/dev/null | grep "Account expires" | awk -F: '{print $2}' | xargs)
                    [[ "$exp" != "never" && "$exp" != "" ]] && [[ $(date -d "$exp" +%s 2>/dev/null) -lt $today ]] && userdel -r "$u" 2>/dev/null && c=$((c+1))
                done
                for f in /etc/xray/users.json /etc/v2ray/users.json; do
                    [[ ! -f "$f" ]] && continue
                    for proto in vmess vless trojan shadow; do
                        jq -r ".$proto // {} | to_entries[] | select(.value < \"$(date +%Y-%m-%d)\") | .key" "$f" 2>/dev/null | while read -r u; do
                            jq "del(.$proto.\"$u\")" "$f" > /tmp/u.json && mv /tmp/u.json "$f"
                        done
                    done
                done; echo -e "${GREEN}  ✓ Tous les comptes expirés supprimés${RESET}"; pause;;
            4) clear; echo -e "${CYAN}━━ Liste comptes expirés ━━${RESET}"
                local today=$(date +%s) f=0
                echo -e "  ${LAV}SSH expirés:${RESET}"
                for u in $(awk -F: '$7~/bash|sh/ && $3>=1000 {print $1}' /etc/passwd); do
                    local exp=$(chage -l "$u" 2>/dev/null | grep "Account expires" | awk -F: '{print $2}' | xargs)
                    [[ "$exp" != "never" && "$exp" != "" ]] && [[ $(date -d "$exp" +%s 2>/dev/null) -lt $today ]] && echo -e "  ${RED}$u (expiré le $exp)${RESET}" && f=1
                done; [[ $f -eq 0 ]] && echo -e "  ${GREEN}Aucun${RESET}"
                for f2 in /etc/xray/users.json /etc/v2ray/users.json; do
                    [[ ! -f "$f2" ]] && continue
                    for proto in vmess vless trojan shadow; do
                        jq -r ".$proto // {} | to_entries[] | select(.value < \"$(date +%Y-%m-%d)\") | \"\(.key) (\(.value))\"" "$f2" 2>/dev/null | while read -r u; do echo -e "  ${RED}$proto: $u${RESET}"; done
                    done
                done; pause;;
            0|q) break ;;
        esac
    done
}

menu_clear_log() {
    while true; do
 sub_header 'CLEAR LOG'
        printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
        sub_row 1 "LOGS SYSTEME (syslog/auth)" 2 "LOGS NGINX"
        sub_row 3 "LOGS XRAY/V2RAY"            4 "LOGS PANEL + CRÉATION"
        sub_row 5 "JOURNALCTL VACUUM"          6 "TOUT NETTOYER"
        sub_footer
        prompt_sub "CLEAR LOG"
        case $SUB in
            1) clear; > /var/log/syslog 2>/dev/null; > /var/log/auth.log 2>/dev/null; > /var/log/kighmu*.log 2>/dev/null || true; echo -e "${GREEN}  ✓ Logs système nettoyés${RESET}"; pause;;
            2) clear; > /var/log/nginx/access.log 2>/dev/null; > /var/log/nginx/error.log 2>/dev/null || true; echo -e "${GREEN}  ✓ Logs Nginx nettoyés${RESET}"; pause;;
            3) clear; > /var/log/xray/access.log 2>/dev/null; > /var/log/xray/error.log 2>/dev/null; > /var/log/v2ray/access.log 2>/dev/null; > /var/log/v2ray/error.log 2>/dev/null || true; echo -e "${GREEN}  ✓ Logs Xray/V2Ray nettoyés${RESET}"; pause;;
            4) clear; > /var/log/kighmu-user.log 2>/dev/null; > /var/log/kighmu-xray-user.log 2>/dev/null || true; echo -e "${GREEN}  ✓ Logs panel nettoyés${RESET}"; pause;;
            5) clear; journalctl --rotate --vacuum-time=1s 2>/dev/null && echo -e "${GREEN}  ✓ Journalctl compressé${RESET}" || echo -e "${YELLOW}  Pas de journalctl${RESET}"; pause;;
            6) clear; > /var/log/syslog > /var/log/auth.log 2>/dev/null; > /var/log/kighmu*.log 2>/dev/null; > /var/log/nginx/access.log > /var/log/nginx/error.log 2>/dev/null; > /var/log/xray/access.log > /var/log/xray/error.log 2>/dev/null; > /var/log/v2ray/access.log > /var/log/v2ray/error.log 2>/dev/null; > /var/log/kighmu-user.log > /var/log/kighmu-xray-user.log 2>/dev/null; journalctl --rotate --vacuum-time=1s 2>/dev/null || true; echo -e "${GREEN}  ✓ Tous les logs nettoyés${RESET}"; pause;;
            0|q) break ;;
        esac
    done
}

menu_stop_all_serv() {
    while true; do
 sub_header 'STOP ALL SERVICES'
        printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
        sub_row 1 "ARRETER TOUS"               2 "ARRETER SSH/DROPBEAR"
        sub_row 3 "ARRETER XRAY"               4 "ARRETER V2RAY"
        sub_row 5 "ARRETER NGINX"              6 "ARRETER HYSTERIA/ZIVPN"
        sub_row 7 "ARRETER SLOWDNS"            8 "ARRETER PANEL WEB"
        sub_footer
        prompt_sub "STOP SERV"
        case $SUB in
            1) for s in nginx xray v2ray dropbear-custom hysteria zivpn slowdns ssh; do systemctl stop "$s" 2>/dev/null || true; done; pm2 stop kighmu-panel 2>/dev/null || true; echo -e "${GREEN}  ✓ Tous arrêtés${RESET}"; pause;;
            2) systemctl stop ssh dropbear-custom 2>/dev/null || true; echo -e "${GREEN}  ✓ SSH/Dropbear arrêtés${RESET}"; pause;;
            3) systemctl stop xray 2>/dev/null && echo -e "${GREEN}  ✓ Xray arrêté${RESET}" || echo -e "${YELLOW}  Déjà arrêté${RESET}"; pause;;
            4) systemctl stop v2ray 2>/dev/null && echo -e "${GREEN}  ✓ V2Ray arrêté${RESET}" || echo -e "${YELLOW}  Déjà arrêté${RESET}"; pause;;
            5) systemctl stop nginx 2>/dev/null && echo -e "${GREEN}  ✓ Nginx arrêté${RESET}" || echo -e "${YELLOW}  Déjà arrêté${RESET}"; pause;;
            6) systemctl stop hysteria zivpn 2>/dev/null || true; echo -e "${GREEN}  ✓ Hysteria/ZIVPN arrêtés${RESET}"; pause;;
            7) systemctl stop slowdns 2>/dev/null && echo -e "${GREEN}  ✓ SlowDNS arrêté${RESET}" || echo -e "${YELLOW}  Déjà arrêté${RESET}"; pause;;
            8) pm2 stop kighmu-panel 2>/dev/null && echo -e "${GREEN}  ✓ Panel Web arrêté${RESET}" || echo -e "${YELLOW}  Déjà arrêté${RESET}"; pause;;
            0|q) break ;;
        esac
    done
}

menu_bckp_rstr() {
    while true; do
 sub_header 'BACKUP / RESTORE'
        printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
        sub_row 1 "BACKUP COMPLETE"          2 "RESTORE BACKUP"
        sub_row 3 "BACKUP CONFIGS ONLY"     4 "LISTE BACKUPS"
        sub_footer
        prompt_sub "BCKP/RSTR"
        case $SUB in
            1) clear; local f="/root/kighmu-backup-$(date +%Y%m%d-%H%M).tar.gz"; tar -czf "$f" /etc/kighmu /etc/xray /etc/v2ray /etc/hysteria /etc/zivpn /etc/ssh /etc/nginx /opt/kighmu-panel 2>/dev/null && echo -e "${GREEN}  ✓ Backup: $f${RESET}" || echo -e "${RED}  ✗ Échec${RESET}"; pause;;
            2) clear; echo -e "${CYAN}━━ Backups disponibles ━━${RESET}"; ls -1 /root/kighmu-backup-*.tar.gz 2>/dev/null || echo "  Aucun"; read -rp "  Fichier à restaurer: " f; [[ -f "$f" ]] && tar -xzf "$f" -C / && echo -e "${GREEN}  ✓ Restauré${RESET}" || echo -e "${RED}  ✗ Fichier invalide${RESET}"; pause;;
            3) clear; local f="/root/kighmu-configs-$(date +%Y%m%d-%H%M).tar.gz"; tar -czf "$f" /etc/kighmu /etc/xray /etc/v2ray /etc/hysteria /etc/zivpn 2>/dev/null && echo -e "${GREEN}  ✓ Configs: $f${RESET}"; pause;;
            4) clear; echo -e "${CYAN}━━ Backups ━━${RESET}"; ls -lh /root/kighmu-backup-*.tar.gz /root/kighmu-configs-*.tar.gz 2>/dev/null | awk '{print "  " $NF " (" $5 ")"}' || echo "  Aucun backup"; pause;;
            0|q) break ;;
        esac
    done
}

menu_reboot() {
    while true; do
 sub_header 'REBOOT VPS'
        printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
        sub_row 1 "REBOOT MAINTENANT"          2 "REBOOT DANS X MINUTES"
        sub_row 3 "ANNULER REBOOT PROGRAMME"   0 ""
        sub_footer
        prompt_sub "REBOOT"
        case $SUB in
            1) echo -e "${YELLOW}  Redémarrage dans 5 secondes...${RESET}"; sleep 5; reboot;;
            2) read -rp "  Minutes avant reboot: " m
                [[ "$m" =~ ^[0-9]+$ ]] && { shutdown -r +$m "Reboot programmé dans $m minutes"; echo -e "${GREEN}  ✓ Reboot dans $m min${RESET}"; }; pause;;
            3) shutdown -c 2>/dev/null && echo -e "${GREEN}  ✓ Reboot annulé${RESET}" || echo -e "${YELLOW}  Aucun reboot programmé${RESET}"; pause;;
            0|q) break ;;
        esac
    done
}
menu_restart() {
    while true; do
 sub_header 'RESTART VPS'
        printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
        sub_row 1 "RESTART ALL SERVICES"     2 "RESTART SSH"
        sub_row 3 "RESTART DROPBEAR"         4 "RESTART NGINX"
        sub_row 5 "RESTART XRAY"             6 "RESTART V2RAY"
        sub_row 7 "RESTART HYSTERIA"         8 "RESTART ZIVPN"
        sub_row 9 "RESTART SLOWDNS"          0 ""
        sub_footer
        prompt_sub "RESTART VPS"
        case $SUB in
            1) clear; echo -e "${YELLOW}  Redémarrage de tous les services...${RESET}"
                for s in nginx xray v2ray dropbear-custom hysteria zivpn slowdns ssh; do systemctl restart "$s" 2>/dev/null || true; done
                echo -e "${GREEN}  ✓ Tous les services redémarrés${RESET}"; pause;;
            2) systemctl restart ssh 2>/dev/null && echo -e "${GREEN}  ✓ SSH restarted${RESET}" || echo -e "${RED}  ✗ Échec${RESET}"; pause;;
            3) systemctl restart dropbear-custom 2>/dev/null && echo -e "${GREEN}  ✓ Dropbear restarted${RESET}" || echo -e "${RED}  ✗ Échec${RESET}"; pause;;
            4) systemctl restart nginx 2>/dev/null && echo -e "${GREEN}  ✓ Nginx restarted${RESET}" || echo -e "${RED}  ✗ Échec${RESET}"; pause;;
            5) systemctl restart xray 2>/dev/null && echo -e "${GREEN}  ✓ Xray restarted${RESET}" || echo -e "${RED}  ✗ Échec${RESET}"; pause;;
            6) systemctl restart v2ray 2>/dev/null && echo -e "${GREEN}  ✓ V2Ray restarted${RESET}" || echo -e "${RED}  ✗ Échec${RESET}"; pause;;
            7) systemctl restart hysteria 2>/dev/null && echo -e "${GREEN}  ✓ Hysteria restarted${RESET}" || echo -e "${RED}  ✗ Échec${RESET}"; pause;;
            8) systemctl restart zivpn 2>/dev/null && echo -e "${GREEN}  ✓ ZIVPN restarted${RESET}" || echo -e "${RED}  ✗ Échec${RESET}"; pause;;
            9) systemctl restart slowdns 2>/dev/null && echo -e "${GREEN}  ✓ SlowDNS restarted${RESET}" || echo -e "${RED}  ✗ Échec${RESET}"; pause;;
            0|q) break ;;
        esac
    done
}

menu_set_domain() {
    while true; do
 sub_header 'SET DOMAIN'
        printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
        printf "${BG}║${RESET}  ${LAV}Domaine:${RESET}    ${ORANGE}%-40s${RESET} ${BG}║${RESET}\n" "$DOMAIN"
        printf "${BG}║${RESET}  ${LAV}NS SlowDNS:${RESET} ${MAG}%-40s${RESET} ${BG}║${RESET}\n" "$NS4"
        printf "${BG}║${RESET}  ${LAV}NS V2Ray:${RESET}   ${MAG}%-40s${RESET} ${BG}║${RESET}\n" "$NV4"
        printf "${BG}╠══════════════════════════════════════════════════════════════════════╣${RESET}\n"
        sub_row 1 "CHANGER DOMAINE PRINCIPAL" 2 "CHANGER NS SLOWDNS (NS4)"
        sub_row 3 "CHANGER NS V2RAY (NV4)"    0 ""
        sub_footer
        prompt_sub "SET DOMAIN"
        case $SUB in
            1) clear; read -rp "  Nouveau domaine: " d
                if [[ -n "$d" && "$d" != "0" ]]; then
                    echo "$d" > /etc/kighmu/domain.txt
                    echo "$d" > /etc/xray/domain 2>/dev/null || true
                    echo "$d" > /etc/v2ray/domain.txt 2>/dev/null || true
                    echo -e "${GREEN}  ✓ Domaine mis à jour: ${ORANGE}$d${RESET}"
                    echo -e "  ${YELLOW}⚠ Régénérez le cert SSL si besoin (menu 19)${RESET}"
                fi; pause;;
            2) clear; echo -e "${CYAN}━━ NS SlowDNS (pour SSH/Dropbear) ━━${RESET}"
                echo -e "  ${LAV}Actuel:${RESET} ${MAG}$NS4${RESET}"
                read -rp "  Nouveau NS4: " ns4
                if [[ -n "$ns4" && "$ns4" != "0" ]]; then
                    echo "$ns4" > /etc/slowdns/ns.conf
                    # Régénère le script de démarrage slowdns-ns4
                    cat > /usr/local/bin/slowdns-ns4-start.sh << NS4EOF
#!/bin/bash
NS=\$(cat /etc/slowdns/ns.conf)
exec /usr/local/bin/dnstt-server -udp 0.0.0.0:5353 -privkey-file /etc/slowdns/server.key \$NS 127.0.0.1:109
NS4EOF
                    chmod +x /usr/local/bin/slowdns-ns4-start.sh
                    systemctl restart slowdns-ns4 2>/dev/null || true
                    echo -e "${GREEN}  ✓ NS SlowDNS mis à jour: ${MAG}$ns4${RESET} (service redémarré)${RESET}"
                fi; pause;;
            3) clear; echo -e "${CYAN}━━ NS V2Ray DNS (NV4) ━━${RESET}"
                echo -e "  ${LAV}Actuel:${RESET} ${MAG}$NV4${RESET}"
                read -rp "  Nouveau NV4: " nv4
                if [[ -n "$nv4" && "$nv4" != "0" ]]; then
                    mkdir -p /etc/slowdns/nv4
                    echo "$nv4" > /etc/slowdns/nv4/ns.conf
                    # Régénère le script de démarrage slowdns-nv4
                    cat > /usr/local/bin/slowdns-nv4-start.sh << NV4EOF
#!/bin/bash
NV4=\$(cat /etc/slowdns/nv4/ns.conf)
exec /usr/local/bin/dnstt-server -udp 0.0.0.0:5354 -privkey-file /etc/slowdns/server.key \$NV4 127.0.0.1:5401
NV4EOF
                    chmod +x /usr/local/bin/slowdns-nv4-start.sh
                    systemctl restart slowdns-nv4 2>/dev/null || true
                    echo -e "${GREEN}  ✓ NS V2Ray mis à jour: ${MAG}$nv4${RESET} (service redémarré)${RESET}"
                fi; pause;;
            0|q) break ;;
        esac
    done
}

menu_cert_ssl() {
    while true; do
 sub_header 'CERT SSL'
        printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
        sub_row 1 "GENERER CERT LETSENCRYPT"  2 "LISTE CERTIFICATS"
        sub_row 3 "DETAILS CERTIFICAT"        4 "RENEW CERTIFICAT"
        sub_row 5 "AUTO-RENEW (CRON)"         6 "SUPPRIMER CERT"
        sub_footer
        prompt_sub "CERT SSL"
        case $SUB in
            1) clear; echo -e "${CYAN}━━ Génération Let's Encrypt ━━${RESET}"; read -rp "  Domaine: " d
                DEBIAN_FRONTEND=noninteractive apt-get install -y -qq certbot python3-certbot-nginx 2>/dev/null
                certbot --nginx -d "$d" --non-interactive --agree-tos -m admin@"$d" 2>/dev/null && echo -e "${GREEN}  ✓ Certificat généré pour $d${RESET}" || echo -e "${RED}  ✗ Échec (vérifiez que le domaine pointe vers ce VPS)${RESET}"; pause;;
            2) clear; certbot certificates 2>/dev/null | head -30 || echo -e "  ${YELLOW}Aucun certificat${RESET}"; pause;;
            3) clear; echo -e "${CYAN}━━ Détails ━━${RESET}"; read -rp "  Domaine: " d; certbot certificates -d "$d" 2>/dev/null || echo -e "  ${RED}Certificat introuvable pour $d${RESET}"; pause;;
            4) clear; echo -e "${CYAN}━━ Renew ━━${RESET}"; read -rp "  Domaine: " d; certbot renew --cert-name "$d" --non-interactive 2>/dev/null && echo -e "${GREEN}  ✓ Certificat renouvelé${RESET}" || echo -e "${RED}  ✗ Échec ou pas encore expiré${RESET}"; pause;;
            5) clear; echo -e "${CYAN}━━ Auto-Renew ━━${RESET}"
                if crontab -l 2>/dev/null | grep -q certbot; then
                    echo -e "  ${GREEN}Auto-renew déjà actif${RESET}"
                    read -rp "  Désactiver ? (o/N): " c; [[ "$c" =~ ^[oO]$ ]] && crontab -l 2>/dev/null | grep -v certbot | crontab - && echo -e "  ${GREEN}Auto-renew désactivé${RESET}"
                else
                    echo -e "  ${YELLOW}Auto-renew inactif${RESET}"
                    read -rp "  Activer (3h chaque lundi) ? (o/N): " c; [[ "$c" =~ ^[oO]$ ]] && (crontab -l 2>/dev/null; echo "0 3 * * 1 certbot renew --non-interactive --quiet && systemctl restart nginx") | crontab - && echo -e "  ${GREEN}Auto-renew activé (lundi 3h)${RESET}"
                fi; pause;;
            6) clear; echo -e "${CYAN}━━ Suppression ━━${RESET}"; read -rp "  Domaine: " d; certbot delete --cert-name "$d" --non-interactive 2>/dev/null && echo -e "${GREEN}  ✓ Certificat supprimé${RESET}" || echo -e "${RED}  ✗ Introuvable${RESET}"; pause;;
            0|q) break ;;
        esac
    done
}

menu_quota_usage() {
    local BW_DIR="/etc/kighmu/bandwidth"
    mkdir -p "$BW_DIR"
    local TODAY=$(date +%Y-%m-%d)
    local CUR_BYTES=0
    local iface=$(ip route 2>/dev/null | awk '/default/{print $5; exit}')
    [[ -n "$iface" ]] && {
        local rx=$(awk -v i="$iface" '$1 ~ i":"{print $2}' /proc/net/dev 2>/dev/null || echo 0)
        local tx=$(awk -v i="$iface" '$1 ~ i":"{print $10}' /proc/net/dev 2>/dev/null || echo 0)
        CUR_BYTES=$((rx + tx))
    }
    # Calcul quotas
    local BW_DAY=0 BW_WEEK=0 BW_MONTH=0
    local prev=$CUR_BYTES
    [[ -f "$BW_DIR/$TODAY.prev" ]] && prev=$(<"$BW_DIR/$TODAY.prev")
    BW_DAY=$((CUR_BYTES - prev)); ((BW_DAY < 0)) && BW_DAY=$CUR_BYTES
    for d in $(seq 0 6 | xargs -I{} date -d "{} days ago" +%Y-%m-%d 2>/dev/null); do
        [[ -f "$BW_DIR/$d" ]] && BW_WEEK=$((BW_WEEK + $(<"$BW_DIR/$d")))
    done
    for d in $(seq 0 30 | xargs -I{} date -d "{} days ago" +%Y-%m-%d 2>/dev/null); do
        [[ -f "$BW_DIR/$d" ]] && BW_MONTH=$((BW_MONTH + $(<"$BW_DIR/$d")))
    done
    local qd=$(fmt_bytes $BW_DAY) qw=$(fmt_bytes $BW_WEEK) qm=$(fmt_bytes $BW_MONTH)
    while true; do
 sub_header 'QUOTA USAGE'
        printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
        printf "${BG}║${RESET}  ${LAV}Jour:${RESET}     %-44s${BG}║${RESET}\n" "$qd"
        printf "${BG}║${RESET}  ${LAV}Semaine:${RESET}  %-44s${BG}║${RESET}\n" "$qw"
        printf "${BG}║${RESET}  ${LAV}Mois:${RESET}     %-44s${BG}║${RESET}\n" "$qm"
        printf "${BG}╠══════════════════════════════════════════════════════════════════════╣${RESET}\n"
        sub_row 1 "QUOTA PAR UTILISATEUR"     2 "RESET QUOTA"
        sub_row 3 "TOP CONSOMMATEURS"         0 ""
        sub_footer
        prompt_sub "QUOTA"
        case $SUB in
            1) clear; echo -e "${CYAN}━━ Quota par utilisateur ━━${RESET}"
                echo -e "  ${LAV}Utilisateur       Téléchargé    Envoyé        Total${RESET}"
                echo -e "  ${DIM}──────────────────────────────────────────────────────${RESET}"
                local total_u=0 total_d=0
                while IFS= read -r l; do
                    local u=$(echo "$l" | awk -F: '{print $1}')
                    local uid=$(id -u "$u" 2>/dev/null) || continue
                    local tag="ssh_${uid}"
                    local ul=$(nft list counter inet kighmu "${tag}_out" 2>/dev/null | grep -oP 'bytes \K\d+' || echo 0)
                    local dl=$(nft list counter inet kighmu "${tag}_in" 2>/dev/null | grep -oP 'bytes \K\d+' || echo 0)
                    total_u=$((total_u + ul)); total_d=$((total_d + dl))
                    printf "  ${WHITE}%-16s${RESET} ${MAG}%10s${RESET}  ${CYAN}%10s${RESET}  ${ORANGE}%10s${RESET}\n" "$u" "$(fmt_bytes $dl)" "$(fmt_bytes $ul)" "$(fmt_bytes $((dl+ul)))"
                done < <(awk -F: '$7~/bash|sh/ && $3>=1000{print $1}' /etc/passwd 2>/dev/null)
                echo -e "  ${DIM}──────────────────────────────────────────────────────${RESET}"
                printf "  ${LAV}TOTAL${RESET}           ${MAG}%10s${RESET}  ${CYAN}%10s${RESET}  ${ORANGE}%10s${RESET}\n" "$(fmt_bytes $total_d)" "$(fmt_bytes $total_u)" "$(fmt_bytes $((total_d+total_u)))"; pause;;
            2) clear; echo -e "${RED}⚠ Réinitialiser tous les quotas ?${RESET}"; read -rp "  Confirmer (o/N): " c
                [[ "$c" =~ ^[oO]$ ]] && {
                    for i in $(seq 0 30); do local d=$(date -d "$i days ago" +%Y-%m-%d 2>/dev/null); rm -f "$BW_DIR/$d" "$BW_DIR/$d.prev" 2>/dev/null; done
                    echo -e "${GREEN}  ✓ Quotas réinitialisés${RESET}"
                }; pause;;
            3) clear; echo -e "${CYAN}━━ Top consommateurs ━━${RESET}"
                local tmpf=$(mktemp)
                while IFS= read -r l; do
                    local u=$(echo "$l" | awk -F: '{print $1}')
                    local uid=$(id -u "$u" 2>/dev/null) || continue
                    local tag="ssh_${uid}"
                    local ul=$(nft list counter inet kighmu "${tag}_out" 2>/dev/null | grep -oP 'bytes \K\d+' || echo 0)
                    local dl=$(nft list counter inet kighmu "${tag}_in" 2>/dev/null | grep -oP 'bytes \K\d+' || echo 0)
                    echo "$((dl+ul))|$u|$dl|$ul" >> "$tmpf"
                done < <(awk -F: '$7~/bash|sh/ && $3>=1000{print $1}' /etc/passwd 2>/dev/null)
                    sort -rn "$tmpf" | head -10 | while IFS='|' read -r total u dl ul; do
                    printf "  ${WHITE}%-16s${RESET} ${ORANGE}%10s${RESET}  ${MAG}↓%s${RESET}  ${CYAN}↑%s${RESET}\n" "$u" "$(fmt_bytes $total)" "$(fmt_bytes $dl)" "$(fmt_bytes $ul)"
                done; rm -f "$tmpf"; pause;;
            0|q) break ;;
        esac
    done
}

menu_clear_cache() {
    while true; do
 sub_header 'CLEAR CACHE'
        printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
        sub_row 1 "CACHE SYSTEME (drop_caches)" 2 "CACHE APT"
        sub_row 3 "FICHIERS TEMPORAIRES"        4 "TOUT NETTOYER"
        sub_footer
        prompt_sub "CLEAR CACHE"
        case $SUB in
            1) sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null && echo -e "${GREEN}  ✓ Cache système vidé${RESET}" || echo -e "${RED}  ✗ Échec${RESET}"; pause;;
            2) apt-get clean 2>/dev/null && echo -e "${GREEN}  ✓ Cache APT nettoyé${RESET}" || echo -e "${YELLOW}  Déjà propre${RESET}"; pause;;
            3) rm -rf /tmp/* /var/tmp/* 2>/dev/null || true; echo -e "${GREEN}  ✓ Fichiers temporaires supprimés${RESET}"; pause;;
            4) sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null; apt-get clean 2>/dev/null; rm -rf /tmp/* /var/tmp/* 2>/dev/null || true; echo -e "${GREEN}  ✓ Tout nettoyé${RESET}"; pause;;
            0|q) break ;;
        esac
    done
}

menu_cek_bandwidth() {
    while true; do
 sub_header 'CEK BANDWIDTH'
        local iface=$(ip route 2>/dev/null | awk '/default/{print $5; exit}')
        local rx=$(awk -v i="$iface" '$1 ~ i":"{print $2}' /proc/net/dev 2>/dev/null || echo 0)
        local tx=$(awk -v i="$iface" '$1 ~ i":"{print $10}' /proc/net/dev 2>/dev/null || echo 0)
        printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
        printf "${BG}║${RESET}  ${LAV}Interface:${RESET} ${WHITE}%-48s${RESET} ${BG}║${RESET}\n" "$iface"
        printf "${BG}║${RESET}  ${LAV}Réception:${RESET}  ${MAG}$(fmt_bytes $rx)${RESET}                                           ${BG}║${RESET}\n"
        printf "${BG}║${RESET}  ${LAV}Émission:${RESET}    ${MAG}$(fmt_bytes $tx)${RESET}                                           ${BG}║${RESET}\n"
        printf "${BG}║${RESET}  ${LAV}Total:${RESET}       ${ORANGE}$(fmt_bytes $((rx+tx)))${RESET}                                           ${BG}║${RESET}\n"
        printf "${BG}╠══════════════════════════════════════════════════════════════════════╣${RESET}\n"
        sub_row 1 "RAFRAICHIR"                  2 "HISTORIQUE (JOURS)"
        sub_row 3 "TOP INTERFACES"              0 ""
        sub_footer
        prompt_sub "CEK BW"
        case $SUB in
            1) clear; continue ;;
            2) clear; echo -e "${CYAN}━━ Historique bande passante ━━${RESET}"
                local BW_DIR="/etc/kighmu/bandwidth"
                if [[ -d "$BW_DIR" ]]; then
                    for d in $(ls -1 "$BW_DIR" 2>/dev/null | grep -v '.prev$' | tail -14); do
                        local val=$(cat "$BW_DIR/$d" 2>/dev/null || echo 0)
                        echo -e "  ${WHITE}$d${RESET} → ${ORANGE}$(fmt_bytes $val)${RESET}"
                    done
                else
                    echo -e "  ${YELLOW}Aucun historique${RESET}"
                fi; pause;;
            3) clear; echo -e "${CYAN}━━ Traffic par interface ━━${RESET}"
                echo -e "  ${LAV}Interface       Réception      Émission       Total${RESET}"
                echo -e "  ${DIM}──────────────────────────────────────────────────────────${RESET}"
                for ifc in $(ls /sys/class/net 2>/dev/null); do
                    local r=$(cat /sys/class/net/$ifc/statistics/rx_bytes 2>/dev/null || echo 0)
                    local t=$(cat /sys/class/net/$ifc/statistics/tx_bytes 2>/dev/null || echo 0)
                    printf "  ${WHITE}%-15s${RESET} ${MAG}%10s${RESET}   ${CYAN}%10s${RESET}   ${ORANGE}%10s${RESET}\n" "$ifc" "$(fmt_bytes $r)" "$(fmt_bytes $t)" "$(fmt_bytes $((r+t)))"
                done; pause;;
            0|q) break ;;
        esac
    done
}

menu_desinstalle() {
	sub_header 'DESINSTALLATION'
    printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
    printf "${BG}║${RESET}  ${RED}╔════════════════════════════════════════════════════════════════╗${RESET}  ${BG}║${RESET}\n"
    printf "${BG}║${RESET}  ${RED}║${RESET}  ${WHITE}⚠  ATTENTION : Action irréversible  ⚠${RESET}                 ${RED}║${RESET}  ${BG}║${RESET}\n"
    printf "${BG}║${RESET}  ${RED}║${RESET}  Supprime TOUS les services, configs, utilisateurs,${RESET}     ${RED}║${RESET}  ${BG}║${RESET}\n"
    printf "${BG}║${RESET}  ${RED}║${RESET}  logs et paquets. VPS remis à l'état d'origine.${RESET}        ${RED}║${RESET}  ${BG}║${RESET}\n"
    printf "${BG}║${RESET}  ${RED}╚════════════════════════════════════════════════════════════════╝${RESET}  ${BG}║${RESET}\n"
    printf "${BG}╠══════════════════════════════════════════════════════════════════════╣${RESET}\n"
    sub_row 1 "DÉSINSTALLATION COMPLÈTE"      0 ""
    sub_footer
    prompt_sub "DÉSINSTALLER"
    case $SUB in
        1) clear
            echo -e "${BG}${RED}╔══════════════════════════════════════════════════════════════════════╗${RESET}"
            echo -e "${BG}${RED}║${RESET}  ${WHITE}⚠  DÉSINSTALLATION COMPLÈTE  ⚠${RESET}                           ${BG}${RED}║${RESET}"
            echo -e "${BG}${RED}║${RESET}  ${YELLOW}Pour confirmer, tapez le mot: ${WHITE}PURGE${RESET}                    ${BG}${RED}║${RESET}"
            echo -e "${BG}${RED}╚══════════════════════════════════════════════════════════════════════╝${RESET}"
            read -rp "  » " CONFIRM
            if [[ "$CONFIRM" == "PURGE" ]]; then
                # ── 1. Arrêt de tous les services ──
                echo -e "${YELLOW}  [1/12] Arrêt de tous les services...${RESET}"
                for s in $(systemctl list-units --type=service --all --no-legend 2>/dev/null | awk '{print $1}' | sed 's/\.service//' | grep -iE 'xray|v2ray|nginx|haproxy|hysteria|zivpn|dropbear|sshws|ws-|stunnel|socks|udp-custom|slowdns|dnsdist|bot2|mysql|kighmu|panel|badvpn|nftables-tunnel|proxy|pm2|kighmu-cleanup'); do
                    systemctl disable --now "$s" 2>/dev/null || true
                done
                # Force kill any remaining custom processes
                pkill -9 -f "xray|dnstt-server|hysteria|zivpn|wstunnel|ws-dropbear|ws-stunnel|slowdns|proxy--ws|KIGHMUPROXY|udp-custom|badvpn|bot2" 2>/dev/null || true
                sleep 1
                pm2 kill 2>/dev/null || true; pm2 cleardump 2>/dev/null || true; pm2 unstartup 2>/dev/null || true
                rm -f /root/.pm2/dump.pm2 2>/dev/null || true

                # ── 2. Suppression de tous les binaires ──
                echo -e "${YELLOW}  [2/12] Suppression des binaires...${RESET}"
                rm -f \
                    /usr/local/bin/xray \
                    /usr/local/bin/v2ray \
                    /usr/local/bin/dnstt-server \
                    /usr/local/bin/hysteria \
                    /usr/local/bin/zivpn \
                    /usr/local/bin/badvpn-udpgw \
                    /usr/local/bin/udp-custom \
                    /usr/local/bin/wstunnel \
                    /usr/local/bin/proxy--ws \
                    /usr/local/bin/ws2_proxy.py \
                    /usr/local/bin/KIGHMUPROXY.py \
                    /usr/local/bin/ws-dropbear \
                    /usr/local/bin/ws-stunnel \
                    /usr/local/bin/init-nftables.sh \
                    /usr/local/bin/kighmu-bandwidth.sh \
                    /usr/local/bin/slowdns-ns4-start.sh \
                    /usr/local/bin/slowdns-nv4-start.sh \
                    /usr/local/bin/slowdns-watchdog.sh \
                    /usr/local/bin/slowdns-update-ip.sh \
                    /usr/local/bin/geoip.dat \
                    /usr/local/bin/geosite.dat \
                    /usr/local/bin/kighmu-panel.sh \
                    /root/Kighmu/bot2 2>/dev/null || true

                # ── 3. Suppression fichiers systemd ──
                echo -e "${YELLOW}  [3/12] Suppression des services systemd...${RESET}"
                rm -f \
                    /etc/systemd/system/{xray,v2ray,nginx,haproxy,hysteria,zivpn,dropbear-custom,sshws,ssl_tls,proxy--ws,ws-dropbear,ws-stunnel,socks_python_ws,socks_python,udp-custom,badvpn@,slowdns-ns4,slowdns-nv4,dnsdist,bot2,kighmu-bandwidth,kighmu-panel,pm2-kighmu,kighmu-cleanup}.service \
                    /etc/systemd/system/nftables-tunnel@*.service \
                    /etc/systemd/system/mysql.service 2>/dev/null || true
                rm -rf /etc/systemd/system/dnsdist.service.d 2>/dev/null || true
                find /etc/systemd/system/ -name '*kighmu*' -o -name '*slowdns*' -o -name '*ws-*' -o -name '*socks*' -o -name '*badvpn*' -o -name '*udp-custom*' -o -name '*sshws*' -o -name '*cleanup*' 2>/dev/null | xargs rm -f 2>/dev/null || true
                # Supprimer les symlinks dans multi-user.target.wants
                find /etc/systemd/system/multi-user.target.wants/ -name '*kighmu*' -o -name '*xray*' -o -name '*v2ray*' -o -name '*slowdns*' -o -name '*badvpn*' -o -name '*sshws*' -o -name '*hysteria*' -o -name '*zivpn*' -o -name '*dropbear*' -o -name '*udp-custom*' -o -name '*nginx*' -o -name '*haproxy*' -o -name '*mysql*' -o -name '*cleanup*' 2>/dev/null | xargs rm -f 2>/dev/null || true

                # ── 4. Purge nftables + iptables ──
                echo -e "${YELLOW}  [4/12] Purge nftables + iptables...${RESET}"
                for t in $(nft list tables 2>/dev/null | grep -oP '(?<=table inet )\S+' | grep -iE 'kighmu|slowdns|xray|v2ray|zivpn|hysteria|badvpn|udp-custom|dropbear|panel|proxy'); do
                    nft delete table inet "$t" 2>/dev/null || true
                done
                nft flush ruleset 2>/dev/null || true
                rm -f /etc/nftables/*.nft 2>/dev/null || true
                rm -f /etc/nftables/*.nft 2>/dev/null || true
                # Reset iptables to default (allow all)
                iptables -P INPUT ACCEPT 2>/dev/null; iptables -P FORWARD ACCEPT 2>/dev/null; iptables -P OUTPUT ACCEPT 2>/dev/null
                iptables -t nat -F 2>/dev/null; iptables -t mangle -F 2>/dev/null; iptables -F 2>/dev/null; iptables -X 2>/dev/null
                ip6tables -P INPUT ACCEPT 2>/dev/null; ip6tables -P FORWARD ACCEPT 2>/dev/null; ip6tables -P OUTPUT ACCEPT 2>/dev/null
                ip6tables -t nat -F 2>/dev/null; ip6tables -t mangle -F 2>/dev/null; ip6tables -F 2>/dev/null; ip6tables -X 2>/dev/null
                ufw disable 2>/dev/null || true

                # ── 5. Suppression répertoires configurables + données ──
                echo -e "${YELLOW}  [5/12] Suppression des configurations...${RESET}"
                # Supprimer la base de données MySQL
                if command -v mysql &>/dev/null; then
                    mysql -e "DROP DATABASE IF EXISTS \`${DB_NAME:-kighmu}\`;" 2>/dev/null || true
                    mysql -e "DROP USER IF EXISTS '${DB_USER:-kighmu}'@'localhost';" 2>/dev/null || true
                    mysql -e "FLUSH PRIVILEGES;" 2>/dev/null || true
                fi
                # Ne PAS supprimer /etc/nginx /etc/mysql /etc/haproxy /etc/dropbear /etc/stunnel
                # (sinon apt n'en recrée pas les fichiers de base au prochain install)
                rm -rf \
                    /etc/kighmu /etc/kighmu-v2 /etc/xray /etc/v2ray \
                    /etc/hysteria /etc/zivpn /etc/slowdns /etc/dnsdist \
                    /etc/udp-custom \
                    /opt/kighmu-panel /root/Kighmu /root/.pm2 \
                    /root/.npm /root/.config /root/.cache \
                    /root/socksenv /var/lib/mysql \
                    /var/www/html /root/.acme.sh 2>/dev/null || true
                rm -f \
                    /etc/nginx/sites-available/kighmu \
                    /etc/nginx/sites-enabled/kighmu \
                    /etc/haproxy/haproxy.cfg \
                    /etc/stunnel/stunnel.conf \
                    /etc/dropbear/dropbear_dss_host_key \
                    /etc/dropbear/dropbear_rsa_host_key \
                    /etc/dropbear/dropbear_ecdsa_host_key \
                    /etc/dropbear/dropbear_ed25519_host_key 2>/dev/null || true
                # Supprimer les résidus acme.sh dans les profils shell
                sed -i '/acme\.sh/d' /root/.bashrc /root/.profile /root/.bash_profile 2>/dev/null || true
                rm -f \
                    /etc/profile.d/kighmu-panel.sh \
                    /etc/sysctl.d/99-v2ray.conf \
                    /etc/sysctl.d/99-slowdns.conf \
                    /etc/logrotate.d/slowdns \
                    /root/.kighmu_info 2>/dev/null || true

                # ── 6. Suppression logs ──
                echo -e "${YELLOW}  [6/12] Suppression des logs...${RESET}"
                rm -rf \
                    /var/log/xray /var/log/v2ray /var/log/slowdns \
                    /var/log/hysteria /var/log/zivpn /var/log/nginx \
                    /var/log/mysql /var/log/haproxy /var/log/stunnel4 \
                    /root/.pm2/logs 2>/dev/null || true

                # ── 7. Suppression certificats SSL ──
                echo -e "${YELLOW}  [7/12] Suppression des certificats SSL...${RESET}"
                rm -rf /etc/letsencrypt /etc/ssl/kighmu 2>/dev/null || true

                # ── 8. Suppression utilisateurs (système + SSH) ──
                echo -e "${YELLOW}  [8/12] Suppression des utilisateurs...${RESET}"
                for u in xray v2ray hysteria zivpn mysql; do
                    userdel -r "$u" 2>/dev/null || true
                done
                awk -F: '$7~/bash|sh/ && $3>=1000{print $1}' /etc/passwd 2>/dev/null | while read -r u; do
                    userdel -r "$u" 2>/dev/null || true
                done
                for g in xray v2ray hysteria zivpn kighmu; do
                    groupdel "$g" 2>/dev/null || true
                done

                # ── 9. Restauration SSH par défaut + resolv.conf + sysctl ──
                echo -e "${YELLOW}  [9/12] Restauration SSH, resolv.conf, sysctl...${RESET}"
                # Restaurer sshd_config (enlever Banner, Port custom)
                sed -i '/^Banner /d' /etc/ssh/sshd_config 2>/dev/null || true
                sed -i '/^Port /d' /etc/ssh/sshd_config 2>/dev/null || true
                rm -f /etc/ssh/banner.txt 2>/dev/null || true
                systemctl restart ssh 2>/dev/null || true
                # Restaurer resolv.conf
                crontab -r 2>/dev/null || true
                chattr -i /etc/resolv.conf 2>/dev/null || true
                echo "nameserver 1.1.1.1" > /etc/resolv.conf
                chattr +i /etc/resolv.conf 2>/dev/null || true
                # Nettoyer sysctl
                rm -f /etc/sysctl.d/99-*.conf 2>/dev/null || true
                sed -i '/^net\.core\.default_qdisc/d; /^net\.ipv4\.tcp_congestion_control/d; /^net\.ipv4\.tcp_notsent_lowat/d; /^net\.ipv4\.tcp_fastopen/d; /^fs\.file-max/d' /etc/sysctl.conf 2>/dev/null || true
                sysctl -p 2>/dev/null || true

                # ── 10. Suppression paquets ──
                echo -e "${YELLOW}  [10/12] Suppression des paquets...${RESET}"
                apt-get remove --purge -y \
                    xray-server v2ray haproxy hysteria zivpn \
                    nginx nginx-common nginx-core \
                    mysql-server mysql-client mysql-common \
                    nodejs npm stunnel4 dropbear dnsdist \
                    certbot python3-certbot-nginx \
                    nftables build-essential cmake \
                    golang-go 2>/dev/null || true
                apt-get autoremove --purge -y 2>/dev/null || true
                apt-get autoclean 2>/dev/null || true
                rm -f /etc/apt/sources.list.d/nodesource.list 2>/dev/null || true
                apt-get update 2>/dev/null || true

                # ── 11. Nettoyage temp + reliquats + autostart panel ──
                echo -e "${YELLOW}  [11/12] Nettoyage complet...${RESET}"
                rm -rf /tmp/{Tyiop24,Kighmu,wstunnel_inst,xray_inst,panel.sh} 2>/dev/null || true
                rm -f /root/install.sh /root/udp.sh /root/ssh.sh /root/xray-v2ray.sh /root/panel.sh 2>/dev/null || true
                find /root -maxdepth 1 -name '*.sh' -o -name '*.tar.gz' -o -name '*.zip' 2>/dev/null | xargs rm -f 2>/dev/null || true
                rm -rf /usr/local/lib/node_modules 2>/dev/null || true
                rm -f /usr/local/bin/{pm2,node,npm,npx} 2>/dev/null || true
                # Supprimer l'autostart du panel
                sed -i '/kighmu\|kighmu-panel\|Kighmu\|panel\.sh/d' /root/.bashrc /root/.profile 2>/dev/null || true
                rm -f /usr/local/bin/kighmu-panel.sh 2>/dev/null || true

                # ── 12. Rechargement systemd + cleanup post-reboot ──
                systemctl daemon-reload 2>/dev/null || true
                # Créer un script post-reboot pour enlever les derniers résidus
                cat > /tmp/cleanup-reboot.sh << 'CLEANUP'
#!/bin/bash
rm -rf /etc/kighmu /etc/kighmu-v2 /root/Kighmu /root/.kighmu_info 2>/dev/null
rm -f /etc/profile.d/kighmu-panel.sh 2>/dev/null
sed -i '/kighmu\|Kighmu\|acme\.sh/d' /root/.bashrc /root/.profile 2>/dev/null
systemctl daemon-reload 2>/dev/null
rm -f /tmp/cleanup-reboot.sh /etc/systemd/system/kighmu-cleanup.service 2>/dev/null
CLEANUP
                chmod +x /tmp/cleanup-reboot.sh
                cat > /etc/systemd/system/kighmu-cleanup.service << 'CLNSRV'
[Unit]
Description=Kighmu cleanup after reboot
After=network.target

[Service]
Type=oneshot
ExecStart=/tmp/cleanup-reboot.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
CLNSRV
                systemctl daemon-reload 2>/dev/null
                systemctl enable kighmu-cleanup.service 2>/dev/null || true

                echo
                echo -e "${GREEN}  ╔═══════════════════════════════════════════════════════╗${RESET}"
                echo -e "${GREEN}  ║${RESET}  ✓ Désinstallation COMPLÈTE terminée               ${GREEN}║${RESET}"
                echo -e "${GREEN}  ║${RESET}  ${WHITE}VPS nettoyé — état d'origine${RESET}              ${GREEN}║${RESET}"
                echo -e "${GREEN}  ║${RESET}  ${YELLOW}Recommandé : reboot${RESET}                      ${GREEN}║${RESET}"
                echo -e "${GREEN}  ║${RESET}  ${DIM}(un cleanup post-reboot supprimera les${RESET}      ${GREEN}║${RESET}"
                echo -e "${GREEN}  ║${RESET}  ${DIM} derniers résidus)${RESET}                          ${GREEN}║${RESET}"
                echo -e "${GREEN}  ╚═══════════════════════════════════════════════════════╝${RESET}"
            else
                echo -e "  ${YELLOW}Désinstallation annulée.${RESET}"
            fi; pause;;
        0|q) ;;
    esac
}

menu_bot_vip() {
    local SCRIPT_DIR="/root/Kighmu" BOT_BIN="$SCRIPT_DIR/bot2" BOTS_CLIENT="/etc/kighmu/bots.json" SERVICE_FILE="/etc/systemd/system/bot2.service"
    while true; do
 sub_header 'MENU BOT VIP'
        printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
        sub_row 1 "STATUT BOT"              2 "COMPILER BOT"
        sub_row 3 "INSTALLER (SYSTEMD)"     4 "DEMARRER BOT"
        sub_row 5 "ARRETER BOT"             6 "RESTART BOT"
        sub_row 7 "LOGS BOT"                8 "AJOUTER CLIENT"
        sub_row 9 "GERER USERS CLIENT"      10 "SET TOKEN"
        sub_row 11 "SET ADMIN ID"           12 "VOIR BOTS.JSON"
        sub_row 13 "DESINSTALLER BOT"       0 ""
        sub_footer
        prompt_sub "BOT VIP"
        case $SUB in
            1) clear; echo -e "${CYAN}━━ Statut Bot ━━${RESET}"
                if systemctl is-active --quiet bot2 2>/dev/null; then echo -e "  ${GREEN}✓ Bot actif (systemd)${RESET}"
                elif pm2 show kighmu-bot &>/dev/null 2>&1; then echo -e "  ${GREEN}✓ Bot actif (pm2)${RESET}"
                else echo -e "  ${RED}✗ Bot inactif${RESET}"; fi
                [[ -f "$BOT_BIN" ]] && echo -e "  ${GREEN}✓ Binaire présent${RESET}" || echo -e "  ${RED}✗ Binaire manquant${RESET}"; pause;;
            2) clear; echo -e "${CYAN}━━ Compilation Bot ━━${RESET}"
                command -v go &>/dev/null || { echo -e "${RED}  Go non installé. Installez golang-go${RESET}"; pause; break; }
                mkdir -p "$SCRIPT_DIR"
                cp /opt/kighmu-panel/frontend/bot/bot2.go "$SCRIPT_DIR/bot2.go" 2>/dev/null || curl -fsSL "https://raw.githubusercontent.com/kinf744/Tyiop24/main/bot2.go" -o "$SCRIPT_DIR/bot2.go" 2>/dev/null || { echo -e "${RED}  bot2.go introuvable${RESET}"; pause; break; }
                cd "$SCRIPT_DIR" && go mod init telegram-bot 2>/dev/null || true && go mod tidy && go build -o bot2 bot2.go 2>/dev/null && echo -e "${GREEN}  ✓ Bot compilé${RESET}" || echo -e "${RED}  ✗ Échec compilation${RESET}"; pause;;
            3) clear; echo -e "${CYAN}━━ Installation systemd ━━${RESET}"
                [[ ! -f "$BOT_BIN" ]] && { echo -e "${RED}  Compilez d'abord (option 2)${RESET}"; pause; break; }
                local tk=$(grep BOT_TOKEN /opt/kighmu-panel/.env 2>/dev/null | cut -d= -f2)
                local ai=$(grep ADMIN_ID /opt/kighmu-panel/.env 2>/dev/null | cut -d= -f2)
                [[ -z "$tk" ]] && read -rp "  Bot Token: " tk
                [[ -z "$ai" ]] && read -rp "  Admin ID: " ai
                cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Telegram VPS Control Bot
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=$SCRIPT_DIR
ExecStart=$BOT_BIN
Restart=always
RestartSec=5
Environment=BOT_TOKEN=$tk
Environment=ADMIN_ID=$ai
[Install]
WantedBy=multi-user.target
EOF
                systemctl daemon-reload && systemctl enable --now bot2 && echo -e "${GREEN}  ✓ Bot installé et démarré${RESET}" || echo -e "${RED}  ✗ Échec${RESET}"; pause;;
            4) clear; systemctl start bot2 2>/dev/null && echo -e "${GREEN}  ✓ Bot démarré${RESET}" || echo -e "${YELLOW}  Déjà actif ou non installé${RESET}"; pause;;
            5) clear; systemctl stop bot2 2>/dev/null && echo -e "${GREEN}  ✓ Bot arrêté${RESET}" || echo -e "${RED}  ✗ Déjà arrêté${RESET}"; pause;;
            6) clear; systemctl restart bot2 2>/dev/null && echo -e "${GREEN}  ✓ Bot redémarré${RESET}" || echo -e "${RED}  ✗ Échec${RESET}"; pause;;
            7) clear; echo -e "${YELLOW}  Ctrl+C pour quitter${RESET}"; journalctl -u bot2 -n 50 --no-pager 2>/dev/null || echo "  Aucun log"; pause;;
            8) clear; echo -e "${CYAN}━━ Ajouter un client bot ━━${RESET}"
                read -rp "  Nom du bot: " nom; read -rp "  Token: " token; read -rp "  ID: " id; read -rp "  Rôle (admin/client): " role
                [[ "$role" != "admin" && "$role" != "client" ]] && { echo -e "${RED}  Rôle invalide${RESET}"; pause; break; }
                read -rp "  Utilisateurs (virgules): " usrs; read -rp "  Expire (jours): " days
                local uj="[]"
                IFS=',' read -ra UA <<< "$usrs"; for u in "${UA[@]}"; do
                    [[ -n "$u" ]] && uj=$(echo "$uj" | jq --arg n "$u" --arg e "$(date -d "+$days days" +%Y-%m-%d)" '. += [{"nom":$n,"expire":$e}]')
                done
                jq --arg nom "$nom" --arg token "$token" --argjson id "$id" --arg role "$role" --argjson users "$uj" '.bots += [{"NomBot":$nom,"Token":$token,"ID":$id,"Role":$role,"Utilisateurs":$users}]' "$BOTS_CLIENT" > /tmp/bc.json && mv /tmp/bc.json "$BOTS_CLIENT" && chmod 600 "$BOTS_CLIENT" && echo -e "${GREEN}  ✓ Client $nom ajouté${RESET}" || echo -e "${RED}  ✗ Échec${RESET}"; pause;;
            9) clear; echo -e "${CYAN}━━ Gérer utilisateurs client ━━${RESET}"
                jq -r '.bots[] | "  \(.NomBot) (ID: \(.ID))"' "$BOTS_CLIENT" 2>/dev/null || { echo "  Aucun client"; pause; break; }
                read -rp "  Nom du client: " nc
                local ulist=$(jq -r --arg n "$nc" '.bots[] | select(.NomBot == $n) | .Utilisateurs[] | "  \(.nom) | expire: \(.expire)"' "$BOTS_CLIENT" 2>/dev/null)
                [[ -z "$ulist" ]] && { echo "  Aucun utilisateur"; pause; break; }
                echo "$ulist"; read -rp "  Supprimer utilisateur (nom): " ud
                jq --arg n "$nc" --arg u "$ud" '(.bots[] | select(.NomBot == $n) | .Utilisateurs) |= map(select(.nom != $u))' "$BOTS_CLIENT" > /tmp/bc.json && mv /tmp/bc.json "$BOTS_CLIENT" && echo -e "${GREEN}  ✓ $ud supprimé${RESET}" || echo -e "${RED}  ✗ Échec${RESET}"; pause;;
            10) clear; echo -e "${CYAN}━━ Token Bot ━━${RESET}"; read -rp "  Token Telegram: " t; grep -q BOT_TOKEN /opt/kighmu-panel/.env 2>/dev/null && sed -i "s/BOT_TOKEN=.*/BOT_TOKEN=$t/" /opt/kighmu-panel/.env || echo "BOT_TOKEN=$t" >> /opt/kighmu-panel/.env; echo -e "${GREEN}  ✓ Token enregistré${RESET}"; pause;;
            11) clear; echo -e "${CYAN}━━ Admin ID ━━${RESET}"; read -rp "  Admin Telegram ID: " a; grep -q ADMIN_ID /opt/kighmu-panel/.env 2>/dev/null && sed -i "s/ADMIN_ID=.*/ADMIN_ID=$a/" /opt/kighmu-panel/.env || echo "ADMIN_ID=$a" >> /opt/kighmu-panel/.env; echo -e "${GREEN}  ✓ Admin ID enregistré${RESET}"; pause;;
            12) clear; echo -e "${CYAN}━━ bots.json ━━${RESET}"; jq . "$BOTS_CLIENT" 2>/dev/null || echo "  Fichier absent ou vide"; pause;;
            13) clear; echo -e "${RED}⚠ Désinstaller le bot ?${RESET}"; read -rp "  Confirmer (o/N): " C
                [[ "$C" =~ ^[oO]$ ]] && { systemctl stop bot2 2>/dev/null; systemctl disable bot2 2>/dev/null; rm -f "$SERVICE_FILE" "$BOT_BIN"; rm -f /root/Kighmu/go.mod /root/Kighmu/go.sum /root/Kighmu/bot2.go 2>/dev/null; echo -e "${GREEN}  ✓ Bot désinstallé${RESET}"; } || echo -e "  Annulé"; pause;;
            0|q) break ;;
        esac
    done
}

menu_change_banner() {
    local BANNER_FILE="/etc/ssh/banner.txt"
    while true; do
 sub_header 'CHANGE BANNER SSH'
        printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
        printf "${BG}║${RESET}  ${LAV}Banner actuel:${RESET}                                          ${BG}║${RESET}\n"
        if [[ -f "$BANNER_FILE" ]]; then
            head -4 "$BANNER_FILE" | while IFS= read -r line; do
                printf "${BG}║${RESET}  ${WHITE}%-66s${RESET} ${BG}║${RESET}\n" "$line"
            done
            [[ $(wc -l < "$BANNER_FILE") -gt 4 ]] && printf "${BG}║${RESET}  ${DIM}... (+%d lignes)${RESET}                                          ${BG}║${RESET}\n" $(($(wc -l < "$BANNER_FILE")-4))
        else
            printf "${BG}║${RESET}  ${YELLOW}Aucun banner défini${RESET}                                         ${BG}║${RESET}\n"
        fi
        printf "${BG}╠══════════════════════════════════════════════════════════════════════╣${RESET}\n"
        sub_row 1 "BANNER TEXTE PERSONNALISE"  2 "BANNER MULTI-LIGNES"
        sub_row 3 "BANNER PAR DEFAUT"          4 "PREVIEW BANNER"
        sub_row 5 "DESACTIVER BANNER"          6 "BANNER COLORES (ASCII)"
        sub_footer
        prompt_sub "BANNER SSH"
        case $SUB in
            1) clear; echo -e "${CYAN}━━ Banner texte ━━${RESET}"; read -rp "  Texte du banner: " t
                [[ -n "$t" && "$t" != "0" ]] && { echo "$t" > "$BANNER_FILE"; chmod 644 "$BANNER_FILE"; systemctl restart ssh; echo -e "${GREEN}  ✓ Banner mis à jour${RESET}"; }; pause;;
            2) clear; echo -e "${CYAN}━━ Banner multi-lignes (Entrée = fin) ━━${RESET}"
                > "$BANNER_FILE"
                echo -e "  ${YELLOW}Entrez vos lignes (ligne vide pour terminer):${RESET}"
                while true; do read -rp "  " l; [[ -z "$l" ]] && break; echo "$l" >> "$BANNER_FILE"; done
                chmod 644 "$BANNER_FILE"; systemctl restart ssh; echo -e "${GREEN}  ✓ Banner multi-lignes enregistré${RESET}"; pause;;
            3) clear; echo -e "${CYAN}━━ Banner par défaut ━━${RESET}"
                cat > "$BANNER_FILE" << 'BANEOF'
█████████████████████████████████████████████████████████████████
█                                                               █
█           WELCOME TO KIGHMU PREMIUM VPN SERVER                █
█        ⚠ UNAUTHORIZED ACCESS IS STRICTLY PROHIBITED ⚠         █
█                                                               █
█████████████████████████████████████████████████████████████████
BANEOF
                chmod 644 "$BANNER_FILE"; systemctl restart ssh; echo -e "${GREEN}  ✓ Banner par défaut appliqué${RESET}"; pause;;
            4) clear; echo -e "${CYAN}━━ Preview banner ━━${RESET}"
                if [[ -f "$BANNER_FILE" ]]; then
                    echo -e "${WHITE}$(cat "$BANNER_FILE")${RESET}"
                else
                    echo -e "  ${YELLOW}Aucun banner défini${RESET}"
                fi; pause;;
            5) clear; echo -e "${CYAN}━━ Désactiver banner ━━${RESET}"
                rm -f "$BANNER_FILE"
                sed -i 's/^Banner .*/#Banner none/' /etc/ssh/sshd_config 2>/dev/null || true
                systemctl restart ssh; echo -e "${GREEN}  ✓ Banner désactivé${RESET}"; pause;;
            6) clear; echo -e "${CYAN}━━ Bannières colorées ASCII ━━${RESET}"
                echo -e "  ${ORANGE}[1]${RESET} ${WHITE}Classic Kighmu${RESET}"
                echo -e "  ${ORANGE}[2]${RESET} ${WHITE}Neon Style${RESET}"
                echo -e "  ${ORANGE}[3]${RESET} ${WHITE}Minimal${RESET}"
                read -rp "  Choix [1-3]: " bc
                case $bc in
                    1) cat > "$BANNER_FILE" << 'BAN1'
╔═══════════════════════════════════════════════════════════════╗
║           KIGHMU PREMIUM VPN - SERVER ONLINE              ║
║         CONNEXION NON AUTORISEE INTERDITE                 ║
╚═══════════════════════════════════════════════════════════════╝
BAN1
                    ;;
                    2) cat > "$BANNER_FILE" << 'BAN2'
███╗   ██╗███████╗ ██████╗ ███╗   ██╗
████╗  ██║██╔════╝██╔═══██╗████╗  ██║
██╔██╗ ██║█████╗  ██║   ██║██╔██╗ ██║
██║╚██╗██║██╔══╝  ██║   ██║██║╚██╗██║
██║ ╚████║███████╗╚██████╔╝██║ ╚████║
╚═╝  ╚═══╝╚══════╝ ╚═════╝ ╚═╝  ╚═══╝
BAN2
                    ;;
                    3) cat > "$BANNER_FILE" << 'BAN3'
KIGHMU VPN
Connexion surveillee - Acces reserve aux abonnes
BAN3
                    ;;
                esac
                chmod 644 "$BANNER_FILE"; systemctl restart ssh; echo -e "${GREEN}  ✓ Banner appliqué${RESET}"; pause;;
            0|q) break ;;
        esac
    done
}

menu_log_create_user() {
    local logfile="/var/log/kighmu-user.log" logfile_xray="/var/log/kighmu-xray-user.log"
    while true; do
 sub_header 'LOG CREATE USER'
        printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
        sub_row 1 "VOIR DERNIERS LOGS"         2 "VOIR TOUS LES LOGS"
        sub_row 3 "FILTRER PAR UTILISATEUR"     4 "LOGS XRAY/V2RAY"
        sub_row 5 "EFFACER LOGS"                6 "EXPORTER LOGS"
        sub_footer
        prompt_sub "LOG USER"
        case $SUB in
            1) clear; echo -e "${CYAN}━━ Derniers logs (20) ━━${RESET}"
                if [[ -f "$logfile" ]]; then
                    echo -e "  ${LAV}Date       Heure    Action          User${RESET}"
                    echo -e "  ${DIM}──────────────────────────────────────────────${RESET}"
                    tail -20 "$logfile" | while IFS= read -r line; do echo -e "  ${WHITE}$line${RESET}"; done
                else
                    echo -e "  ${YELLOW}Aucun log${RESET}"
                fi; pause;;
            2) clear; echo -e "${CYAN}━━ Tous les logs ━━${RESET}"
                if [[ -f "$logfile" ]]; then
                    wc -l < "$logfile" | xargs -I{} echo -e "  ${LAV}Total:${RESET} ${WHITE}{} lignes${RESET}"
                    echo -e "  ${DIM}──────────────────────────────────────────────${RESET}"
                    cat "$logfile" | while IFS= read -r line; do echo -e "  ${WHITE}$line${RESET}"; done | less -R
                else
                    echo -e "  ${YELLOW}Aucun log${RESET}"
                fi; pause;;
            3) clear; echo -e "${CYAN}━━ Filtrer par utilisateur ━━${RESET}"
                read -rp "  Nom d'utilisateur: " fu
                if [[ -n "$fu" && -f "$logfile" ]]; then
                    grep -i "$fu" "$logfile" | while IFS= read -r line; do echo -e "  ${WHITE}$line${RESET}"; done
                    echo; echo -e "  ${LAV}Total:${RESET} $(grep -ci "$fu" "$logfile" 2>/dev/null || echo 0) entrées"
                else
                    echo -e "  ${YELLOW}Aucun résultat pour '$fu'${RESET}"
                fi; pause;;
            4) clear; echo -e "${CYAN}━━ Logs Xray/V2Ray ━━${RESET}"
                if [[ -f "$logfile_xray" ]]; then
                    tail -20 "$logfile_xray" | while IFS= read -r line; do echo -e "  ${WHITE}$line${RESET}"; done
                else
                    echo -e "  ${YELLOW}Aucun log Xray/V2Ray${RESET}"
                fi; pause;;
            5) clear; echo -e "${RED}⚠ Effacer tous les logs ?${RESET}"; read -rp "  Confirmer (o/N): " c
                [[ "$c" =~ ^[oO]$ ]] && { > "$logfile" 2>/dev/null; > "$logfile_xray" 2>/dev/null; echo -e "${GREEN}  ✓ Logs effacés${RESET}"; }; pause;;
            6) clear; echo -e "${CYAN}━━ Export logs ━━${RESET}"
                local exp="/root/kighmu-logs-$(date +%Y%m%d-%H%M).tar.gz"
                tar -czf "$exp" "$logfile" "$logfile_xray" 2>/dev/null && echo -e "${GREEN}  ✓ Exporté: $exp${RESET}" || echo -e "${RED}  ✗ Aucun log à exporter${RESET}"; pause;;
            0|q) break ;;
        esac
    done
}

# ================================================
# BOUCLE PRINCIPALE
# ================================================
while true; do
    draw_panel
    case $CHOIX in
        1) menu_ssh_vip ;;
        2) menu_vmess ;;
        3) menu_vless ;;
        4) menu_trojan ;;
        5) menu_shadow ;;
        6) menu_zivpn ;;
        7) menu_hysteria ;;
        8) menu_v2ray_dns ;;
        9) menu_auto_reboot ;;
        10) menu_port ;;
        11) menu_panel_web ;;
        12) menu_dell_all_exp ;;
        13) menu_clear_log ;;
        14) menu_stop_all_serv ;;
        15) menu_bckp_rstr ;;
        16) menu_reboot ;;
        17) menu_restart ;;
        18) menu_set_domain ;;
        19) menu_cert_ssl ;;
        20) menu_quota_usage ;;
        21) menu_clear_cache ;;
        22) menu_cek_bandwidth ;;
        23) menu_desinstalle ;;
        24) menu_bot_vip ;;
        25) menu_change_banner ;;
        26) menu_log_create_user ;;
        0|q|exit) exit 0 ;;
        *) ;;
    esac
done
# PANEL_CODE_END
