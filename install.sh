#!/bin/bash
# Kighmu Panel - Auto-Installation Commercial 4-en-1
set -euo pipefail

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
    echo -e "${BG}${CYAN}║${RESET}${TITLE_BG}$(center '✨  KIGHMU PREMIUM VPN  ✨' 71)${RESET}${BG}${CYAN}║${RESET}"
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

    if [[ -f "$SCRIPT_DIR/schema.sql" ]]; then
        mysql "${DB_NAME}" < "$SCRIPT_DIR/schema.sql" 2>/dev/null && log "Schema importé" || warn "Schema déjà présent"
    fi
    log "Base de données prête"
}

# ── DÉPLOIEMENT PANEL ──
deploy_panel_files() {
    step_header '📁  Déploiement Panel  📁'
    mkdir -p "$PANEL_DIR/frontend/admin" "$PANEL_DIR/frontend/reseller" "$KIGHMU_DIR"
    for f in server.js admin.html reseller.html; do
        [[ -f "$SCRIPT_DIR/$f" ]] && cp "$SCRIPT_DIR/$f" "$PANEL_DIR/$f" || [[ -f "$KIGHMU_DIR/$f" ]] && cp "$KIGHMU_DIR/$f" "$PANEL_DIR/$f" || true
    done
    for f in admin.html reseller.html; do
        if [[ -f "$PANEL_DIR/$f" ]]; then
            local d="${f%.html}"; mkdir -p "$PANEL_DIR/frontend/$d"
            cp "$PANEL_DIR/$f" "$PANEL_DIR/frontend/$d/index.html"
        fi
    done
    if [[ ! -f "$PANEL_DIR/frontend/index.html" ]]; then
        cat > "$PANEL_DIR/frontend/index.html" << EOF
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Kighmu Panel</title>
<meta http-equiv="refresh" content="0;url=/admin/"></head><body><h1>Kighmu Panel</h1></body></html>
EOF
    fi
    log "Fichiers déployés"
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
    cd "$PANEL_DIR"
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
}

# ── ADMIN ──
create_admin_user() {
    step_header '👤  Administrateur  👤'
    local user="admin" pass
    pass=$(gen_pass 12)
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
    echo -e "  ${LAV}Admin : ${CYAN}admin${RESET}"
    echo -e "  ${LAV}Mot de passe : ${ORANGE}${pass}${RESET}"
    log "Admin '$user' configuré"
}

# ── NGINX ──
configure_nginx() {
    step_header '🌍  Nginx  🌍'
    local IP; IP=$(hostname -I | awk '{print $1}')
    echo -e "${BG}  ${LAV}Domaine/IP pour le panel [${CYAN}$IP${LAV}]${RESET}"
    echo -ne "${BG}${WHITE}  » ${RESET}"; read -r DOMAIN; DOMAIN=${DOMAIN:-$IP}
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
    nginx -t 2>/dev/null && systemctl start nginx && log "Nginx OK (port 8585)" || err "Nginx invalide"
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
        tcp dport { 8585, 8587 } accept
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
    mkdir -p /etc/slowdns
    echo "NS4=${NS4:-ns4.kingom.ggff.net}" > /etc/slowdns/ns.conf
    echo "NV4=${NV4:-nv4.kingom.ggff.net}" >> /etc/slowdns/ns.conf

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
send_stats() { local resp; resp=$(curl -s --max-time 10 -X POST "${PANEL_URL}/api/report/traffic" -H "Content-Type: application/json" -H "x-report-secret: ${SECRET}" -d "$1" 2>/dev/null); echo "[${TS}] → ${resp:-no response}"; }
_read_nft_counter() { ${NFT} list counter inet kighmu "$1" 2>/dev/null | grep -oP 'bytes \K\d+' || echo 0; }
collect_xray() { [ ! -x "$XRAY_BIN" ] && return; local raw; raw=$("$XRAY_BIN" api statsquery --server="$XRAY_API" 2>/dev/null) || return; [[ -z "$raw" ]] && return; local json='{"stats":[' first=1 has_data=0; while IFS='|' read -r name value; do local user="${name%%>>>*}"; local traffic="${name##*>>>}"; [[ "$user" =~ ^(default|)$ ]] && continue; [[ "$value" == "0" ]] && continue; [[ $first -eq 0 ]] && json+=','; if [[ "$traffic" == "uplink" ]]; then json+="{\"username\":\"${user}\",\"upload_bytes\":${value},\"download_bytes\":0}"; else json+="{\"username\":\"${user}\",\"upload_bytes\":0,\"download_bytes\":${value}}"; fi; first=0; has_data=1; done < <(echo "$raw" | jq -r '.stat[]? | select(.name | test("user>>>")) | "\(.name)|\(.value)"' 2>/dev/null); json+=']}'; [[ $has_data -eq 1 ]] && send_stats "$json"; }
collect_v2ray() { [ ! -x "$V2RAY_BIN" ] && return; local raw; raw=$("$V2RAY_BIN" api stats --server="$V2RAY_API" 2>/dev/null) || return; [[ -z "$raw" ]] && return; local json='{"stats":[' first=1 has_data=0; while IFS='|' read -r user up down; do [[ -z "$user" ]] && continue; [[ "$up" == "0" && "$down" == "0" ]] && continue; [[ $first -eq 0 ]] && json+=','; json+="{\"username\":\"${user}\",\"upload_bytes\":${up},\"download_bytes\":${down}}"; first=0; has_data=1; done < <(echo "$raw" | jq -r '.stat[]? | select(.name | test("user>>>")) | (.name / ">>>") as $p | "\($p[0])|\($p[2]//0)|\($p[3]//0)"' 2>/dev/null); json+=']}'; [[ $has_data -eq 1 ]] && send_stats "$json"; }
collect_ssh() { [ ! -f "$USER_FILE" ] && return; command -v nft &>/dev/null || return; nft list table inet kighmu &>/dev/null || return; local json='{"stats":[' first=1 has_data=0; while IFS='|' read -r username _rest; do [ -z "$username" ] && continue; local uid; uid=$(id -u "$username" 2>/dev/null) || continue; local tag="ssh_${uid}"; local cur_out cur_in; cur_out=$(_read_nft_counter "${tag}_out"); cur_in=$(_read_nft_counter "${tag}_in"); local prev_out=0 prev_in=0; [ -f "${DELTA_DIR}/${username}.out" ] && prev_out=$(< "${DELTA_DIR}/${username}.out"); [ -f "${DELTA_DIR}/${username}.in" ] && prev_in=$(< "${DELTA_DIR}/${username}.in"); local delta_out=$(( cur_out - prev_out )); local delta_in=$(( cur_in - prev_in )); (( delta_out < 0 )) && delta_out=$cur_out; (( delta_in < 0 )) && delta_in=$cur_in; if (( delta_out > 0 || delta_in > 0 )); then echo "$cur_out" > "${DELTA_DIR}/${username}.out"; echo "$cur_in" > "${DELTA_DIR}/${username}.in"; [[ $first -eq 0 ]] && json+=','; json+="{\"username\":\"${username}\",\"upload_bytes\":${delta_in},\"download_bytes\":${delta_out}}"; first=0; has_data=1; fi; done < <(cat "$USER_FILE" 2>/dev/null); json+=']}'; [[ $has_data -eq 1 ]] && send_stats "$json"; }
echo "[${TS}] KIGHMU collecte démarrée"; collect_xray; collect_v2ray; collect_ssh; echo "[${TS}] Terminé"
TCEOF
    sed -i "s/__REPORT_SECRET__/${REPORT_SECRET}/g" /etc/kighmu/traffic-collect.sh
    chmod +x /etc/kighmu/traffic-collect.sh
    crontab -l 2>/dev/null | grep -v "traffic-collect\|Auto-clean" | crontab - 2>/dev/null || true
    (crontab -l 2>/dev/null; echo "*/2 * * * * /etc/kighmu/traffic-collect.sh >> /var/log/kighmu-traffic.log 2>&1"; echo "*/10 * * * * ${KIGHMU_DIR}/Auto-clean.sh >> /var/log/auto-clean.log 2>&1") | crontab - 2>/dev/null || true
    log "Collecte trafic OK (cron 2min)"
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
    mkdir -p /etc/kighmu
    # Extraire le code du panneau depuis la fin de ce script (marqueurs PANEL_CODE)
    sed -n '/^# PANEL_CODE_START$/,/^# PANEL_CODE_END$/p' "$0" | tail -n +2 | head -n -1 > /etc/kighmu-v2/panel.sh || {
        err "Extraction du panneau échouée"; return 1;
    }
    chmod +x /etc/kighmu-v2/panel.sh
    cat > /etc/profile.d/kighmu-panel.sh << 'PROF'
#!/bin/bash
if [[ $EUID -eq 0 && -f /etc/kighmu-v2/panel.sh && -t 0 ]]; then
    /etc/kighmu-v2/panel.sh
fi
PROF
    chmod +x /etc/profile.d/kighmu-panel.sh
    log "Panel déployé (/etc/kighmu-v2/panel.sh)"
    log "Lancement auto au prochain SSH"
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
    install_mysql
    deploy_panel_files
    configure_env
    install_npm_panel
    create_admin_user
    configure_nginx
    setup_nftables
    setup_traffic_collection
    setup_bandwidth_service
    deploy_control_panel
    echo
    echo -e "${BG}${CYAN}╔═══$(printf '═%.0s' {1..57})═══╗${RESET}"
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
            2) install_system_deps; install_nodejs; install_mysql; deploy_panel_files; configure_env; install_npm_panel; create_admin_user; configure_nginx; setup_nftables; pause ;;
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
set -euo pipefail

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
    if ((b < 1099511627776)); then awk "BEGIN{printf \"%.1f GB\", $b/1073741824}"; return; fi
    awk "BEGIN{printf \"%.1f TB\", $b/1099511627776}"
}

# ── Collecte bande passante ──
IFACE=$(ip route 2>/dev/null | awk '/default/{print $5; exit}' || echo "eth0")
BW_DIR="/etc/kighmu/bandwidth"
mkdir -p "$BW_DIR"

get_bytes() {
    awk -v iface="$IFACE" '$1 ~ iface":" {rx=$2; tx=$10; print rx+tx}' /proc/net/dev 2>/dev/null || echo 0
}

CUR_BYTES=$(get_bytes)
TODAY=$(date +%Y-%m-%d)

# Stocker le snapshot actuel
echo "$CUR_BYTES" > "$BW_DIR/$TODAY"

# Totaux accumulés
BW_DAY=$CUR_BYTES
prev=$CUR_BYTES
if [[ -f "$BW_DIR/$TODAY.prev" ]]; then
    prev=$(<"$BW_DIR/$TODAY.prev")
fi
BW_DAY=$((CUR_BYTES - prev))
(( BW_DAY < 0 )) && BW_DAY=$CUR_BYTES
echo "$CUR_BYTES" > "$BW_DIR/$TODAY.prev"

# Semaine (7 derniers jours)
BW_WEEK=0
for d in $(date -d "6 days ago" +%Y-%m-%d 2>/dev/null; seq 0 6 | xargs -I{} date -d "{} days ago" +%Y-%m-%d 2>/dev/null); do
    [[ -f "$BW_DIR/$d" ]] && BW_WEEK=$((BW_WEEK + $(<"$BW_DIR/$d")))
done

# Mois (30 derniers jours)
BW_MONTH=0
for d in $(seq 0 30 | xargs -I{} date -d "{} days ago" +%Y-%m-%d 2>/dev/null); do
    [[ -f "$BW_DIR/$d" ]] && BW_MONTH=$((BW_MONTH + $(<"$BW_DIR/$d")))
done

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
NS4=$(grep NS4 /etc/slowdns/ns.conf 2>/dev/null | cut -d= -f2 || echo "ns4.domain")
NV4=$(grep NV4 /etc/slowdns/ns.conf 2>/dev/null | cut -d= -f2 || echo "nv4.domain")
RAM=$(free -m | awk '/Mem:/ {print $3"MB/"$2"MB"}')
RAM_PCT=$(free -m | awk '/Mem:/ {printf "%d", $3/$2*100}')
CPU_CORES=$(nproc 2>/dev/null || echo "?")
CPU_USED=$(top -bn1 2>/dev/null | awk '/Cpu\(s\)/ {print $2}' | cut -d. -f1 || echo "?")
[[ -z "$CPU_USED" || "$CPU_USED" == "?" ]] && CPU_USED=$(ps -eo %cpu --no-headers 2>/dev/null | awk '{s+=$1}END{printf "%d", s/NR}' || echo "0")
KERNEL=$(uname -r 2>/dev/null || echo "?")

# Comptes
N_SSH=$(awk -F: '$7~/bash|sh/ && $3>=1000' /etc/passwd 2>/dev/null | wc -l)
N_VMESS=$(jq '.vmess | length' /etc/xray/users.json 2>/dev/null || echo 0)
N_VLESS=$(jq '.vless | length' /etc/xray/users.json 2>/dev/null || echo 0)
N_TROJAN=$(jq '.trojan | length' /etc/xray/users.json 2>/dev/null || echo 0)
N_SHADOW=$(jq '.shadow | length' /etc/xray/users.json 2>/dev/null || echo 0)
N_V2RAY=$(jq '.vless | length' /etc/v2ray/users.json 2>/dev/null || echo 0)
N_HY=$([[ -f /etc/hysteria/users.txt ]] && awk -F'|' -v d="$(date +%Y-%m-%d)" '$3>=d' /etc/hysteria/users.txt | wc -l || echo 0)
N_ZIVPN=$([[ -f /etc/zivpn/users.list ]] && awk -F'|' -v d="$(date +%Y-%m-%d)" '$3>=d' /etc/zivpn/users.list | wc -l || echo 0)
N_TOTAL=$((N_SSH + N_VMESS + N_VLESS + N_TROJAN + N_SHADOW + N_V2RAY + N_HY + N_ZIVPN))

# Statuts services
svc() { systemctl is-active --quiet "$1" 2>/dev/null && echo "${GREEN}ON${RESET}" || echo "${RED}OFF${RESET}"; }
S_SSH=$(svc ssh); S_DROP=$(svc dropbear-custom); S_NGINX=$(svc nginx)
S_HAPROXY=$(svc haproxy); S_XRAY=$(svc xray); S_V2RAY=$(svc v2ray)
S_HY=$(svc hysteria); S_ZIVPN=$(svc zivpn)

# ── DRAW ──
draw_panel() {
    echo -e "${CLR}${BG}"

    # ── Bandeau titre ──
    echo -e "${BG}${CYAN}╔═══$(printf '═%.0s' {1..67})═══╗${RESET}"
    echo -e "${BG}${CYAN}║${RESET}${TITLE_BG}          $(center '🚀  WELCOME TO KIGHMU PREMIUM VPN  🚀' 51)          ${RESET}${BG}${CYAN}║${RESET}"
    echo -e "${BG}${CYAN}╚═══$(printf '═%.0s' {1..67})═══╝${RESET}"

    # ── Infos système ──
    printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
    printf "${BG}║${RESET}  ${LAV}SYSTEM VPS${RESET}     ${WHITE}%-34s${RESET}${BG}║${RESET}\n" "$IP  $KERNEL"
    printf "${BG}║${RESET}  ${LAV}RAM SERVER${RESET}     ${WHITE}%-16s${RESET} (${ORANGE}%s%%${RESET} utilisé)${BG}║${RESET}\n" "$RAM" "$RAM_PCT"
    printf "${BG}║${RESET}  ${LAV}CPU CORES${RESET}      ${WHITE}%-2s${RESET} (${YELLOW}%s%%${RESET} utilisé)${BG}║${RESET}\n" "$CPU_CORES" "$CPU_USED"
    printf "${BG}║${RESET}  ${LAV}DOMAIN${RESET}         ${ORANGE}%-34s${RESET}${BG}║${RESET}\n" "$DOMAIN"
    printf "${BG}║${RESET}  ${LAV}NS SLOWDNS${RESET}     ${MAG}%-34s${RESET}${BG}║${RESET}\n" "$NS4"
    printf "${BG}║${RESET}  ${LAV}NS V2RAY${RESET}       ${MAG}%-34s${RESET}${BG}║${RESET}\n" "$NV4"

    # ── Cadre QUOTA ──
    local qd="${C_DAY}${BW_DAY_H}${RESET}" qw="${C_WEEK}${BW_WEEK_H}${RESET}" qm="${C_MONTH}${BW_MONTH_H}${RESET}"
    printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
    printf "${BG}║${RESET}  ${ORANGE}>>${RESET} ${LAV}DATA QUOTA${RESET}  ${WHITE}Jour:${RESET} %b  ${WHITE}Semaine:${RESET} %b  ${WHITE}Mois:${RESET} %b  ${BG}║${RESET}\n" "$qd" "$qw" "$qm"

    # ── Séparateur + Account Info ──
    printf "${BG}╠══════════════════════════════════════════════════════════════════════╣${RESET}\n"
    printf "${BG}║${RESET}  ${ORANGE}>>${RESET} $(center 'ACCOUNT INFORMATION' 48) ${ORANGE}<<${RESET}  ${BG}║${RESET}\n"
    printf "${BG}╠══════════════════════════════════════════════════════════════════════╣${RESET}\n"
    printf "${BG}║${RESET}  ══╡ $(rainbow) ╞══ ${BG}║${RESET}\n"
    printf "${BG}╠══════════════════════════════════════════════════════════════════════╣${RESET}\n"

    # ── Tableau comptes ──
    printf "${BG}║${RESET} ${LAV}SSH/OPENVPN${RESET}   ${MAG}%-2s${RESET}   ${LAV}VMESS${RESET}        ${MAG}%-2s${RESET}   ${LAV}VLESS${RESET}        ${MAG}%-2s${RESET} ${BG}║${RESET}\n" "$N_SSH" "$N_VMESS" "$N_VLESS"
    printf "${BG}║${RESET} ${LAV}TROJAN${RESET}        ${MAG}%-2s${RESET}   ${LAV}SHADOWSOCKS${RESET}  ${MAG}%-2s${RESET}   ${LAV}V2RAY DNS${RESET}    ${MAG}%-2s${RESET} ${BG}║${RESET}\n" "$N_TROJAN" "$N_SHADOW" "$N_V2RAY"
    printf "${BG}║${RESET} ${LAV}HYSTERIA${RESET}      ${MAG}%-2s${RESET}   ${LAV}ZIVPN${RESET}        ${MAG}%-2s${RESET}   ${LAV}TOTAL${RESET}        ${MAG}%-2s${RESET} ${BG}║${RESET}\n" "$N_HY" "$N_ZIVPN" "$N_TOTAL"

    # ── Séparateur + Premium Menu ──
    printf "${BG}╠══════════════════════════════════════════════════════════════════════╣${RESET}\n"
    printf "${BG}║${RESET}  ══╡ $(rainbow) ╞══ ${BG}║${RESET}\n"
    printf "${BG}╠══════════════════════════════════════════════════════════════════════╣${RESET}\n"
    printf "${BG}║${RESET}  ${ORANGE}>>${RESET} $(center 'PREMIUM MENU' 48) ${ORANGE}<<${RESET}  ${BG}║${RESET}\n"
    printf "${BG}╠══════════════════════════════════════════════════════════════════════╣${RESET}\n"

    # ── Statuts services ──
    printf "${BG}║${RESET}  ${LAV}SSH${RESET} %s  ${LAV}NGINX${RESET} %s  ${LAV}HAPROXY${RESET} %s  ${LAV}XRAY${RESET} %s  ${LAV}V2RAY${RESET} %s ${BG}║${RESET}\n" "$S_SSH" "$S_NGINX" "$S_HAPROXY" "$S_XRAY" "$S_V2RAY"
    printf "${BG}║${RESET}  ${LAV}DROPBEAR${RESET} %s  ${LAV}HYSTERIA${RESET} %s  ${LAV}ZIVPN${RESET} %s  ${LAV}WS-epro${RESET} OFF                               ${BG}║${RESET}\n" "$S_DROP" "$S_HY" "$S_ZIVPN"
    printf "${BG}╠══════════════════════════════════════════════════════════════════════╣${RESET}\n"

    # ── Menu numéroté (3 colonnes) ──
    local items=(
        "[01] MENU SSH VIP"    "[02] MENU VMESS"      "[03] MENU VLESS"
        "[04] MENU TROJAN"     "[05] MENU SHADOW"     "[06] MENU ZIVPN"
        "[07] MENU HYSTERIA"   "[08] MENU V2RAY DNS"  "[09] AUTO REBOOT"
        "[10] MENU PORT"       "[11] PANEL WEB"       "[12] DELL ALL EXP"
        "[13] CLEAR LOG"       "[14] STOP ALL SERV"   "[15] BCKP/RSTR"
        "[16] REBOOT VPS"      "[17] RESTART VPS"     "[18] SET DOMAIN"
        "[19] CERT SSL"        "[20] QUOTA USAGE"     "[21] CLEAR CACHE"
        "[22] CEK BANDWIDTH"   "[23] UP SCRIPT"       "[24] MENU BOT VIP"
    )
    for ((i=0; i<24; i+=3)); do
        printf "${BG}║${RESET}  ${ORANGE}%-20s${RESET} ${ORANGE}%-20s${RESET} ${ORANGE}%-20s${RESET} ${BG}║${RESET}\n" \
            "${items[$i]}" "${items[$((i+1))]:-}" "${items[$((i+2))]:-}"
    done

    printf "${BG}╠══════════════════════════════════════════════════════════════════════╣${RESET}\n"

    # ── Options spéciales ──
    printf "${BG}║${RESET}  ${ORANGE}[25]${RESET} ${WHITE}CHANGE BANNER SSH${RESET}   ${ORANGE}[26]${RESET} ${WHITE}LOG CREATE USER${RESET}     ${BG}║${RESET}\n"
    printf "${BG}╠══════════════════════════════════════════════════════════════════════╣${RESET}\n"

    # ── Footer ──
    local CUR_USER=${USER:-root} VER="v4.0"
    printf "${BG}║${RESET}  ${LAV}VERSION${RESET}  ${YELLOW}%-4s${RESET}      ${LAV}USER${RESET}      ${YELLOW}%-10s${RESET}  ${LAV}EXPIRATION${RESET} ${YELLOW}%-9s${RESET} ${BG}║${RESET}\n" "$VER" "$CUR_USER" "PERMANENT"
    echo -e "${BG}${CYAN}╚═══$(printf '═%.0s' {1..67})═══╝${RESET}"

    # ── Saisie ──
    echo
    echo -ne "${BG}${LAV}  Select From Options [ 1-26 ] »${RESET} ${WHITE}"
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

# ================================================
# SOUS-MENU SSH VIP
# ================================================
menu_ssh_vip() {
    while true; do
        sub_header '🔰  MENU SSH VIP  🔰'
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
                local NS=$(grep NS4 /etc/slowdns/ns.conf 2>/dev/null | cut -d= -f2 || echo "ns4.kingom.ggff.net")
                clear
                echo -e "${BG}╔═══════════════════════════════════════════════════════════════════════╗${RESET}"
                echo -e "${BG}║${RESET}  ${ORANGE}✨  NOUVEAU UTILISATEUR CRE  ✨${RESET}                             ${BG}║${RESET}"
                echo -e "${BG}╠═══════════════════════════════════════════════════════════════════════╣${RESET}"
                echo -e "${BG}║${RESET}  ${LAV}🔐 PORTS DISPONIBLES :${RESET}                                       ${BG}║${RESET}"
                echo -e "${BG}║${RESET}  ${WHITE}∘ SSH: 22          ∘ System-DNS: 53${RESET}                         ${BG}║${RESET}"
                echo -e "${BG}║${RESET}  ${WHITE}∘ SSH WS: 80      ∘ DROPBEAR: 109   ∘ SSL: 444${RESET}              ${BG}║${RESET}"
                echo -e "${BG}║${RESET}  ${WHITE}∘ BadVPN: 7100, 7200, 7300${RESET}                                  ${BG}║${RESET}"
                echo -e "${BG}║${RESET}  ${WHITE}∘ SLOWDNS: 5300    ∘ UDP-Custom: 1-65535${RESET}                    ${BG}║${RESET}"
                echo -e "${BG}║${RESET}  ${WHITE}∘ WS-epro: 80  ∘ Proxy WS: 9090${RESET}                             ${BG}║${RESET}"
                echo -e "${BG}╠═══════════════════════════════════════════════════════════════════════╣${RESET}"
                echo -e "${BG}║${RESET}  ${ORANGE}🌍 DOMAINE :${RESET} ${CYAN}${D}${RESET}                                            ${BG}║${RESET}"
                echo -e "${BG}║${RESET}  ${ORANGE}📌 IP HOST :${RESET} ${CYAN}${IP}${RESET}                                             ${BG}║${RESET}"
                echo -e "${BG}║${RESET}  ${ORANGE}👤 UTILISATEUR :${RESET} ${MAG}${u}${RESET}                                            ${BG}║${RESET}"
                echo -e "${BG}║${RESET}  ${ORANGE}🔑 MOT DE PASSE :${RESET} ${MAG}${p}${RESET}                                            ${BG}║${RESET}"
                echo -e "${BG}║${RESET}  ${ORANGE}📦 LIMITE :${RESET} ${YELLOW}${e} jours${RESET}                                            ${BG}║${RESET}"
                echo -e "${BG}║${RESET}  ${ORANGE}📅 DATE D'EXPIRATION :${RESET} ${YELLOW}${E}${RESET}                                      ${BG}║${RESET}"
                echo -e "${BG}╠═══════════════════════════════════════════════════════════════════════╣${RESET}"
                echo -e "${BG}║${RESET}  ${LAV}📲 APPS : HTTP Injector, CUSTOM, SOCKSIP TUNNEL, SSC ZIVPN, etc.${RESET}  ${BG}║${RESET}"
                echo -e "${BG}║${RESET}  ${WHITE}➡️ SSH WS :${RESET} ${CYAN}${D}:80@${u}:${p}${RESET}                             ${BG}║${RESET}"
                echo -e "${BG}║${RESET}  ${WHITE}➡️ SSL/TLS :${RESET} ${CYAN}${D}:444@${u}:${p}${RESET}                             ${BG}║${RESET}"
                echo -e "${BG}║${RESET}  ${WHITE}➡️ PROXY WS :${RESET} ${CYAN}${D}:9090@${u}:${p}${RESET}                             ${BG}║${RESET}"
                echo -e "${BG}║${RESET}  ${WHITE}➡️ SSH UDP :${RESET} ${CYAN}${D}:1-65535@${u}:${p}${RESET}                              ${BG}║${RESET}"
                echo -e "${BG}║${RESET}  ${LAV}📜 PAYLOAD WS:${RESET}                                              ${BG}║${RESET}"
                echo -e "${BG}║${RESET}  ${DIM}GET / HTTP/1.1[crlf]Host: [host][crlf]Connection: Upgrade${RESET}     ${BG}║${RESET}"
                echo -e "${BG}║${RESET}  ${DIM}[crlf]User-Agent: [ua][crlf]Upgrade: websocket[crlf][crlf]${RESET}    ${BG}║${RESET}"
                echo -e "${BG}╠═══════════════════════════════════════════════════════════════════════╣${RESET}"
                echo -e "${BG}║${RESET}  ${LAV}🚀 CONFIG FASTDNS (5300)${RESET}                                    ${BG}║${RESET}"
                echo -e "${BG}║${RESET}  ${LAV}🔐 Pub KEY:${RESET} ${YELLOW}${KEY}${RESET}          ${BG}║${RESET}"
                echo -e "${BG}║${RESET}  ${LAV}NameServer:${RESET} ${CYAN}${NS}${RESET}                                         ${BG}║${RESET}"
                echo -e "${BG}║${RESET}  ${GREEN}✅  COMPTE CREE AVEC SUCCES${RESET}                                   ${BG}║${RESET}"
                echo -e "${BG}╚═══════════════════════════════════════════════════════════════════════╝${RESET}"
                echo "$(date '+%Y-%m-%d %H:%M:%S') | CREATION | $u | Exp: $E" >> /var/log/kighmu-user.log 2>/dev/null || true
            else echo -e "${RED}  ✗ Échec création (user existe déjà ?)${RESET}"; fi; pause;;
            2) clear; echo -e "${CYAN}━━ Suppression ━━${RESET}"; read -rp "  Username: " u; userdel -r "$u" 2>/dev/null && echo -e "${GREEN}  ✓ Supprimé${RESET}" || echo -e "${RED}  ✗ Introuvable${RESET}"; pause;;
            3) clear; echo -e "${CYAN}━━ Liste comptes SSH ━━${RESET}"; awk -F: '$7~/bash|sh/ && $3>=1000 {printf "  %-15s exp: ", $1; system("chage -l "$1" 2>/dev/null | grep \"Account expires\" | cut -d: -f2")}' /etc/passwd; pause;;
            4) clear; echo -e "${CYAN}━━ Renew compte ━━${RESET}"; read -rp "  Username: " u; read -rp "  Jours suppl.: " e; chage -E "$(date -d "+${e}days" +%Y-%m-%d)" "$u" 2>/dev/null && echo -e "${GREEN}  ✓ Prolongé${RESET}" || echo -e "${RED}  ✗ Échec${RESET}"; pause;;
            5) clear; echo -e "${CYAN}━━ Trial 1 jour ━━${RESET}"; read -rp "  Username: " u; read -rp "  Password: " p; useradd -e "$(date -d "+1day" +%Y-%m-%d)" -s /bin/bash "$u" 2>/dev/null && echo "$u:$p" | chpasswd && echo -e "${GREEN}  ✓ Trial $u créé (24h)${RESET}"; pause;;
            6) clear; echo -e "${CYAN}━━ Check expiry ━━${RESET}"; read -rp "  Username: " u; chage -l "$u" 2>/dev/null | grep -E 'Account expires|Last change' || echo -e "${RED}  ✗ Compte introuvable${RESET}"; pause;;
            7) clear; echo -e "${CYAN}━━ Lock ━━${RESET}"; read -rp "  Username: " u; passwd -l "$u" 2>/dev/null && echo -e "${GREEN}  ✓ Bloqué${RESET}" || echo -e "${RED}  ✗ Échec${RESET}"; pause;;
            8) clear; echo -e "${CYAN}━━ Unlock ━━${RESET}"; read -rp "  Username: " u; passwd -u "$u" 2>/dev/null && echo -e "${GREEN}  ✓ Débloqué${RESET}" || echo -e "${RED}  ✗ Échec${RESET}"; pause;;
            9) clear
                echo -e "${CLR}${BG}"
                echo -e "${BG}${CYAN}╔═══$(printf '═%.0s' {1..47})═══╗${RESET}"
                echo -e "${BG}${CYAN}║${RESET}${TITLE_BG}$(center '📊  MONITEUR CONNEXIONS  📊' 51)${RESET}${BG}${CYAN}║${RESET}"
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
        sub_header '📡  MENU VMESS  📡'
        printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
        sub_row 1 "CREER COMPTE"            2 "SUPPRIMER COMPTE"
        sub_row 3 "LISTE COMPTES"           4 "RENEW COMPTE"
        sub_row 5 "TRIAL ACCOUNT"           6 "CHECK EXPIRY"
        sub_row 7 "SHOW CONFIG"             8 "DELETE EXPIRED"
        sub_footer
        prompt_sub "VMESS"
        case $SUB in
            1) clear; echo -e "${CYAN}━━ Création VMESS ━━${RESET}"; read -rp "  Username: " u; read -rp "  Expire (jours): " e; jq ".vmess.\"$u\" = \"$(date -d "+${e}days" +%Y-%m-%d)\"" /etc/xray/users.json 2>/dev/null > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && echo -e "${GREEN}  ✓ VMESS $u créé${RESET}" || echo -e "${RED}  ✗ Échec${RESET}"; pause;;
            2) clear; echo -e "${CYAN}━━ Suppression ━━${RESET}"; read -rp "  Username: " u; jq "del(.vmess.\"$u\")" /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && echo -e "${GREEN}  ✓ Supprimé${RESET}"; pause;;
            3) clear; echo -e "${CYAN}━━ Liste VMESS ━━${RESET}"; jq -r '.vmess | to_entries[] | "  " + .key + " → " + .value' /etc/xray/users.json 2>/dev/null || echo "  Aucun"; pause;;
            4) clear; echo -e "${CYAN}━━ Renew ━━${RESET}"; read -rp "  Username: " u; read -rp "  Jours suppl.: " e; jq ".vmess.\"$u\" = \"$(date -d "+${e}days" +%Y-%m-%d)\"" /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && echo -e "${GREEN}  ✓ Prolongé${RESET}"; pause;;
            5) clear; echo -e "${CYAN}━━ Trial 1j ━━${RESET}"; read -rp "  Username: " u; jq ".vmess.\"$u\" = \"$(date -d "+1day" +%Y-%m-%d)\"" /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && echo -e "${GREEN}  ✓ Trial $u créé${RESET}"; pause;;
            6) clear; echo -e "${CYAN}━━ Check expiry ━━${RESET}"; read -rp "  Username: " u; jq -r ".vmess.\"$u\" // \"Introuvable\"" /etc/xray/users.json 2>/dev/null; pause;;
            7) clear; echo -e "${CYAN}━━ Config VMESS ━━${RESET}"; read -rp "  Username: " u; local d="${DOMAIN:-$IP}"; echo "  server: $d, port: 8443, uuid: $(jq -r ".vmess.\"$u\"" /etc/xray/users.json 2>/dev/null || echo '?')"; pause;;
            8) clear; echo -e "${CYAN}━━ Suppression expirés ━━${RESET}"; local t=$(date +%s); jq --arg t "$t" '.vmess |= with_entries(select(.value | strptime("%Y-%m-%d") | mktime > ($t|tonumber)))' /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && echo -e "${GREEN}  ✓ Nettoyé${RESET}"; pause;;
            9) show_xray_traffic "vmess" "VMESS" ;;
            0|q) break ;;
        esac
    done
}

menu_vless() {
    while true; do
        sub_header '📡  MENU VLESS  📡'
        printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
        sub_row 1 "CREER COMPTE"            2 "SUPPRIMER COMPTE"
        sub_row 3 "LISTE COMPTES"           4 "RENEW COMPTE"
        sub_row 5 "TRIAL ACCOUNT"           6 "CHECK EXPIRY"
        sub_row 7 "SHOW CONFIG"             8 "DELETE EXPIRED"
        sub_footer
        prompt_sub "VLESS"
        case $SUB in
            1) clear; echo -e "${CYAN}━━ Création VLESS ━━${RESET}"; read -rp "  Username: " u; read -rp "  Expire (jours): " e; jq ".vless.\"$u\" = \"$(date -d "+${e}days" +%Y-%m-%d)\"" /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && echo -e "${GREEN}  ✓ Créé${RESET}"; pause;;
            2) clear; echo -e "${CYAN}━━ Suppression ━━${RESET}"; read -rp "  Username: " u; jq "del(.vless.\"$u\")" /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && echo -e "${GREEN}  ✓ Supprimé${RESET}"; pause;;
            3) clear; echo -e "${CYAN}━━ Liste VLESS ━━${RESET}"; jq -r '.vless | to_entries[] | "  " + .key + " → " + .value' /etc/xray/users.json 2>/dev/null || echo "  Aucun"; pause;;
            4) clear; echo -e "${CYAN}━━ Renew ━━${RESET}"; read -rp "  Username: " u; read -rp "  Jours: " e; jq ".vless.\"$u\" = \"$(date -d "+${e}days" +%Y-%m-%d)\"" /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && echo -e "${GREEN}  ✓ Prolongé${RESET}"; pause;;
            5) clear; echo -e "${CYAN}━━ Trial 1j ━━${RESET}"; read -rp "  Username: " u; jq ".vless.\"$u\" = \"$(date -d "+1day" +%Y-%m-%d)\"" /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && echo -e "${GREEN}  ✓ Trial $u créé${RESET}"; pause;;
            6) clear; echo -e "${CYAN}━━ Check ━━${RESET}"; read -rp "  Username: " u; jq -r ".vless.\"$u\" // \"Introuvable\"" /etc/xray/users.json 2>/dev/null; pause;;
            7) clear; echo -e "${CYAN}━━ Config ━━${RESET}"; read -rp "  Username: " u; echo "  ${DOMAIN:-$IP}:8443, flow: xtls-rprx-vision"; pause;;
            8) clear; echo -e "${CYAN}━━ Suppression expirés ━━${RESET}"; local t=$(date +%s); jq --arg t "$t" '.vless |= with_entries(select(.value | strptime("%Y-%m-%d") | mktime > ($t|tonumber)))' /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && echo -e "${GREEN}  ✓ Nettoyé${RESET}"; pause;;
            9) show_xray_traffic "vless" "VLESS" ;;
            0|q) break ;;
        esac
    done
}

menu_trojan() {
    while true; do
        sub_header '🔒  MENU TROJAN  🔒'
        printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
        sub_row 1 "CREER COMPTE"            2 "SUPPRIMER COMPTE"
        sub_row 3 "LISTE COMPTES"           4 "RENEW COMPTE"
        sub_row 5 "TRIAL ACCOUNT"           6 "CHECK EXPIRY"
        sub_row 7 "SHOW CONFIG"             8 "DELETE EXPIRED"
        sub_footer
        prompt_sub "TROJAN"
        case $SUB in
            1) clear; echo -e "${CYAN}━━ Création Trojan ━━${RESET}"; read -rp "  Password: " p; read -rp "  Expire (jours): " e; jq ".trojan += [{\"password\":\"$p\",\"exp\":\"$(date -d "+${e}days" +%Y-%m-%d)\"}]" /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && echo -e "${GREEN}  ✓ Créé${RESET}"; pause;;
            2) clear; echo -e "${CYAN}━━ Suppression ━━${RESET}"; read -rp "  Password: " p; jq "del(.trojan[] | select(.password==\"$p\"))" /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && echo -e "${GREEN}  ✓ Supprimé${RESET}"; pause;;
            3) clear; echo -e "${CYAN}━━ Liste ━━${RESET}"; jq -r '.trojan[] | "  " + .password + " → " + .exp' /etc/xray/users.json 2>/dev/null || echo "  Aucun"; pause;;
            4) clear; echo -e "${CYAN}━━ Renew ━━${RESET}"; read -rp "  Password: " p; read -rp "  Jours: " e; jq "(.[] | select(.password==\"$p\").exp) = \"$(date -d "+${e}days" +%Y-%m-%d)\"" /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && echo -e "${GREEN}  ✓ Prolongé${RESET}"; pause;;
            5) clear; echo -e "${CYAN}━━ Trial 1j ━━${RESET}"; read -rp "  Password: " p; jq ".trojan += [{\"password\":\"$p\",\"exp\":\"$(date -d "+1day" +%Y-%m-%d)\"}]" /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && echo -e "${GREEN}  ✓ Trial $p créé${RESET}"; pause;;
            6) clear; echo -e "${CYAN}━━ Check ━━${RESET}"; read -rp "  Password: " p; jq -r '.trojan[] | select(.password=="'"$p"'") | .exp' /etc/xray/users.json 2>/dev/null || echo "  Introuvable"; pause;;
            7) clear; echo -e "${CYAN}━━ Config ━━${RESET}"; echo "  ${DOMAIN:-$IP}:8443, security: tls"; pause;;
            8) clear; echo -e "${CYAN}━━ Suppression expirés ━━${RESET}"; local t=$(date +%s); jq --arg t "$t" '.trojan |= map(select(.exp | strptime("%Y-%m-%d") | mktime > ($t|tonumber)))' /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && echo -e "${GREEN}  ✓ Nettoyé${RESET}"; pause;;
            9) show_xray_traffic "trojan" "TROJAN" ;;
            0|q) break ;;
        esac
    done
}

menu_shadow() {
    while true; do
        sub_header '🌑  MENU SHADOWSOCKS  🌑'
        printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
        sub_row 1 "CREER COMPTE"            2 "SUPPRIMER COMPTE"
        sub_row 3 "LISTE COMPTES"           4 "RENEW COMPTE"
        sub_row 5 "TRIAL ACCOUNT"           6 "CHECK EXPIRY"
        sub_row 7 "SHOW CONFIG"             8 "DELETE EXPIRED"
        sub_footer
        prompt_sub "SHADOWSOCKS"
        case $SUB in
            1) clear; echo -e "${CYAN}━━ Création SS ━━${RESET}"; read -rp "  Password: " p; read -rp "  Expire (jours): " e; jq ".shadow += [{\"password\":\"$p\",\"exp\":\"$(date -d "+${e}days" +%Y-%m-%d)\"}]" /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && echo -e "${GREEN}  ✓ Créé${RESET}"; pause;;
            2) clear; echo -e "${CYAN}━━ Suppression ━━${RESET}"; read -rp "  Password: " p; jq "del(.shadow[] | select(.password==\"$p\"))" /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && echo -e "${GREEN}  ✓ Supprimé${RESET}"; pause;;
            3) clear; echo -e "${CYAN}━━ Liste ━━${RESET}"; jq -r '.shadow[] | "  " + .password + " → " + .exp' /etc/xray/users.json 2>/dev/null || echo "  Aucun"; pause;;
            4) clear; echo -e "${CYAN}━━ Renew ━━${RESET}"; read -rp "  Password: " p; read -rp "  Jours: " e; jq "(.[] | select(.password==\"$p\").exp) = \"$(date -d "+${e}days" +%Y-%m-%d)\"" /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && echo -e "${GREEN}  ✓ Prolongé${RESET}"; pause;;
            5) clear; echo -e "${CYAN}━━ Trial ━━${RESET}"; read -rp "  Password: " p; jq ".shadow += [{\"password\":\"$p\",\"exp\":\"$(date -d "+1day" +%Y-%m-%d)\"}]" /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && echo -e "${GREEN}  ✓ Trial créé${RESET}"; pause;;
            6) clear; echo -e "${CYAN}━━ Check ━━${RESET}"; read -rp "  Password: " p; jq -r '.shadow[] | select(.password=="'"$p"'") | .exp' /etc/xray/users.json 2>/dev/null || echo "  Introuvable"; pause;;
            7) clear; echo -e "${CYAN}━━ Config ━━${RESET}"; echo "  ${DOMAIN:-$IP}:8443, method: aes-256-gcm"; pause;;
            8) clear; echo -e "${CYAN}━━ Suppression expirés ━━${RESET}"; local t=$(date +%s); jq --arg t "$t" '.shadow |= map(select(.exp | strptime("%Y-%m-%d") | mktime > ($t|tonumber)))' /etc/xray/users.json > /tmp/xu.json && mv /tmp/xu.json /etc/xray/users.json && echo -e "${GREEN}  ✓ Nettoyé${RESET}"; pause;;
            9) show_xray_traffic "shadow" "SHADOWSOCKS" ;;
            0|q) break ;;
        esac
    done
}

menu_zivpn() {
    while true; do
        sub_header '🌐  MENU ZIVPN  🌐'
        printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
        sub_row 1 "CREER COMPTE"            2 "SUPPRIMER COMPTE"
        sub_row 3 "LISTE COMPTES"           4 "RENEW COMPTE"
        sub_row 5 "TRIAL ACCOUNT"           6 "CHECK EXPIRY"
        sub_row 7 "SHOW CONFIG"             8 "DELETE EXPIRED"
        sub_footer
        prompt_sub "ZIVPN"
        case $SUB in
            1) clear; echo -e "${CYAN}━━ Création ZIVPN ━━${RESET}"; read -rp "  Username: " u; read -rp "  Password: " p; read -rp "  Expire (jours): " e; echo "$u|$p|$(date -d "+${e}days" +%Y-%m-%d)" >> /etc/zivpn/users.list && echo -e "${GREEN}  ✓ $u créé${RESET}" || echo -e "${RED}  ✗ Échec${RESET}"; pause;;
            2) clear; echo -e "${CYAN}━━ Suppression ━━${RESET}"; read -rp "  Username: " u; sed -i "/^$u|/d" /etc/zivpn/users.list 2>/dev/null || true; echo -e "${GREEN}  ✓ Supprimé${RESET}"; pause;;
            3) clear; echo -e "${CYAN}━━ Liste ━━${RESET}"; [[ -f /etc/zivpn/users.list ]] && cat /etc/zivpn/users.list | awk -F'|' '{print "  " $1 " → " $3}' || echo "  Aucun"; pause;;
            4) clear; echo -e "${CYAN}━━ Renew ━━${RESET}"; read -rp "  Username: " u; read -rp "  Jours: " e; sed -i "/^$u|/s|[^|]*$|$(date -d "+${e}days" +%Y-%m-%d)|" /etc/zivpn/users.list 2>/dev/null && echo -e "${GREEN}  ✓ Prolongé${RESET}"; pause;;
            5) clear; echo -e "${CYAN}━━ Trial ━━${RESET}"; read -rp "  Username: " u; read -rp "  Password: " p; echo "$u|$p|$(date -d "+1day" +%Y-%m-%d)" >> /etc/zivpn/users.list && echo -e "${GREEN}  ✓ Trial $u créé${RESET}"; pause;;
            6) clear; echo -e "${CYAN}━━ Check ━━${RESET}"; read -rp "  Username: " u; awk -F'|' -v u="$u" '$1==u{print "  Expire: " $3}' /etc/zivpn/users.list 2>/dev/null || echo "  Introuvable"; pause;;
            7) clear; echo -e "${CYAN}━━ Config ━━${RESET}"; echo "  ${DOMAIN:-$IP}:20000 (UDP)"; pause;;
            8) clear; echo -e "${CYAN}━━ Suppression expirés ━━${RESET}"; local t=$(date +%s); [[ -f /etc/zivpn/users.list ]] && awk -F'|' -v t="$t" 'system("date -d "$3" +%s") >= t' /etc/zivpn/users.list > /tmp/zu.list && mv /tmp/zu.list /etc/zivpn/users.list; echo -e "${GREEN}  ✓ Nettoyé${RESET}"; pause;;
            0|q) break ;;
        esac
    done
}

menu_hysteria() {
    while true; do
        sub_header '⚡  MENU HYSTERIA  ⚡'
        printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
        sub_row 1 "CREER COMPTE"            2 "SUPPRIMER COMPTE"
        sub_row 3 "LISTE COMPTES"           4 "RENEW COMPTE"
        sub_row 5 "TRIAL ACCOUNT"           6 "CHECK EXPIRY"
        sub_row 7 "SHOW CONFIG"             8 "DELETE EXPIRED"
        sub_footer
        prompt_sub "HYSTERIA"
        case $SUB in
            1) clear; echo -e "${CYAN}━━ Création Hysteria ━━${RESET}"; read -rp "  Username: " u; read -rp "  Password: " p; read -rp "  Expire (jours): " e; echo "$u|$p|$(date -d "+${e}days" +%Y-%m-%d)" >> /etc/hysteria/users.txt 2>/dev/null && echo -e "${GREEN}  ✓ $u créé${RESET}"; pause;;
            2) clear; echo -e "${CYAN}━━ Suppression ━━${RESET}"; read -rp "  Username: " u; sed -i "/^$u|/d" /etc/hysteria/users.txt 2>/dev/null || true; echo -e "${GREEN}  ✓ Supprimé${RESET}"; pause;;
            3) clear; echo -e "${CYAN}━━ Liste ━━${RESET}"; [[ -f /etc/hysteria/users.txt ]] && cat /etc/hysteria/users.txt | awk -F'|' '{print "  " $1 " → " $3}' || echo "  Aucun"; pause;;
            4) clear; echo -e "${CYAN}━━ Renew ━━${RESET}"; read -rp "  Username: " u; read -rp "  Jours: " e; sed -i "/^$u|/s|[^|]*$|$(date -d "+${e}days" +%Y-%m-%d)|" /etc/hysteria/users.txt 2>/dev/null && echo -e "${GREEN}  ✓ Prolongé${RESET}"; pause;;
            5) clear; echo -e "${CYAN}━━ Trial ━━${RESET}"; read -rp "  Username: " u; read -rp "  Password: " p; echo "$u|$p|$(date -d "+1day" +%Y-%m-%d)" >> /etc/hysteria/users.txt && echo -e "${GREEN}  ✓ Trial $u créé${RESET}"; pause;;
            6) clear; echo -e "${CYAN}━━ Check ━━${RESET}"; read -rp "  Username: " u; awk -F'|' -v u="$u" '$1==u{print "  Expire: " $3}' /etc/hysteria/users.txt 2>/dev/null || echo "  Introuvable"; pause;;
            7) clear; echo -e "${CYAN}━━ Config ━━${RESET}"; echo "  ${DOMAIN:-$IP}:5401 (UDP)"; pause;;
            8) clear; echo -e "${CYAN}━━ Suppression expirés ━━${RESET}"; local t=$(date +%s); [[ -f /etc/hysteria/users.txt ]] && awk -F'|' -v t="$t" 'system("date -d "$3" +%s") >= t' /etc/hysteria/users.txt > /tmp/hy.list && mv /tmp/hy.list /etc/hysteria/users.txt; echo -e "${GREEN}  ✓ Nettoyé${RESET}"; pause;;
            0|q) break ;;
        esac
    done
}

menu_v2ray_dns() {
    while true; do
        sub_header '🛰️  MENU V2RAY DNS  🛰️'
        printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
        sub_row 1 "CREER COMPTE"            2 "SUPPRIMER COMPTE"
        sub_row 3 "LISTE COMPTES"           4 "RENEW COMPTE"
        sub_row 5 "TRIAL ACCOUNT"           6 "CHECK EXPIRY"
        sub_row 7 "SHOW CONFIG"             8 "CHANGE NS"
        sub_footer
        prompt_sub "V2RAY DNS"
        case $SUB in
            1) clear; echo -e "${CYAN}━━ Création V2Ray ━━${RESET}"; read -rp "  Username: " u; read -rp "  Expire (jours): " e; jq ".vless.\"$u\" = \"$(date -d "+${e}days" +%Y-%m-%d)\"" /etc/v2ray/users.json 2>/dev/null > /tmp/v2u.json && mv /tmp/v2u.json /etc/v2ray/users.json && echo -e "${GREEN}  ✓ Créé${RESET}"; pause;;
            2) clear; echo -e "${CYAN}━━ Suppression ━━${RESET}"; read -rp "  Username: " u; jq "del(.vless.\"$u\")" /etc/v2ray/users.json > /tmp/v2u.json && mv /tmp/v2u.json /etc/v2ray/users.json && echo -e "${GREEN}  ✓ Supprimé${RESET}"; pause;;
            3) clear; echo -e "${CYAN}━━ Liste V2Ray ━━${RESET}"; jq -r '.vless | to_entries[] | "  " + .key + " → " + .value' /etc/v2ray/users.json 2>/dev/null || echo "  Aucun"; pause;;
            4) clear; echo -e "${CYAN}━━ Renew ━━${RESET}"; read -rp "  Username: " u; read -rp "  Jours: " e; jq ".vless.\"$u\" = \"$(date -d "+${e}days" +%Y-%m-%d)\"" /etc/v2ray/users.json > /tmp/v2u.json && mv /tmp/v2u.json /etc/v2ray/users.json && echo -e "${GREEN}  ✓ Prolongé${RESET}"; pause;;
            5) clear; echo -e "${CYAN}━━ Trial 1j ━━${RESET}"; read -rp "  Username: " u; jq ".vless.\"$u\" = \"$(date -d "+1day" +%Y-%m-%d)\"" /etc/v2ray/users.json > /tmp/v2u.json && mv /tmp/v2u.json /etc/v2ray/users.json && echo -e "${GREEN}  ✓ Trial $u créé${RESET}"; pause;;
            6) clear; echo -e "${CYAN}━━ Check ━━${RESET}"; read -rp "  Username: " u; jq -r ".vless.\"$u\" // \"Introuvable\"" /etc/v2ray/users.json 2>/dev/null; pause;;
            7) clear; echo -e "${CYAN}━━ Config ━━${RESET}"; read -rp "  Username: " u; echo "  ${DOMAIN:-$IP}:8443 (V2Ray DNS)"; pause;;
            8) clear; echo -e "${CYAN}━━ Changer NS ━━${RESET}"; read -rp "  Nouveau NS: " n; echo "NV4=$n" > /etc/slowdns/ns.conf && echo -e "${GREEN}  ✓ NS mis à jour${RESET}"; pause;;
            9) show_v2ray_traffic ;;
            0|q) break ;;
        esac
    done
}

menu_auto_reboot() {
    sub_header '🔄  AUTO REBOOT  🔄'
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
        sub_header '🔌  MENU PORT  🔌'
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
        sub_header '🌍  PANEL WEB  🌍'
        printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
        sub_row 1 "STATUT PANEL"             2 "DEMARRER PANEL"
        sub_row 3 "ARRETER PANEL"            4 "RESTART PANEL"
        sub_row 5 "CHANGE PORT PANEL"        6 "VIEW LOGS"
        sub_row 7 "LOGS TEMPS REEL"          8 "CHANGER DOMAINE"
        sub_row 9 "CERT SSL PANEL"          10 "BACKUP PANEL"
        sub_row 11 "RESTORE PANEL"          12 "RESET PASSWORD"
        sub_row 13 "STATUT MYSQL"           14 "MAINTENANCE"
        sub_row 15 "UPDATE PANEL"            0 "RETOUR"
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
    sub_header '🗑️  DELETE ALL EXPIRED  🗑️'
    printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
    printf "${BG}║${RESET}  ${RED}⚠ Supprimer tous les comptes expirés ?${RESET}            ${BG}║${RESET}\n"
    sub_footer
    prompt_sub "CONFIRMER (o/N)"
    if [[ "$SUB" =~ ^[oO]$ ]]; then
        clear
        local today=$(date +%s) count=0
        for u in $(awk -F: '$7~/bash|sh/ && $3>=1000 {print $1}' /etc/passwd); do
            local exp=$(chage -l "$u" 2>/dev/null | grep "Account expires" | awk -F: '{print $2}' | xargs)
            [[ "$exp" != "never" && "$exp" != "" ]] && [[ $(date -d "$exp" +%s 2>/dev/null) -lt $today ]] && userdel -r "$u" 2>/dev/null && count=$((count+1))
        done
        echo -e "${GREEN}  ✓ $count comptes expirés supprimés${RESET}"
        pause
    fi
}

menu_clear_log() {
    sub_header '🧹  CLEAR LOG  🧹'
    printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
    printf "${BG}║${RESET}  ${RED}⚠ Effacer tous les logs système ?${RESET}                   ${BG}║${RESET}\n"
    sub_footer
    prompt_sub "CONFIRMER (o/N)"
    if [[ "$SUB" =~ ^[oO]$ ]]; then
        > /var/log/syslog > /var/log/auth.log > /var/log/kighmu*.log 2>/dev/null || true
        journalctl --rotate --vacuum-time=1s 2>/dev/null || true
        echo -e "${GREEN}  ✓ Logs nettoyés${RESET}"
        pause
    fi
}

menu_stop_all_serv() {
    sub_header '⛔  STOP ALL SERVICES  ⛔'
    printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
    printf "${BG}║${RESET}  ${RED}⚠ Arrêter tous les services ?${RESET}                       ${BG}║${RESET}\n"
    sub_footer
    prompt_sub "CONFIRMER (o/N)"
    if [[ "$SUB" =~ ^[oO]$ ]]; then
        for s in nginx xray v2ray dropbear-custom hysteria zivpn slowdns ssh; do systemctl stop "$s" 2>/dev/null || true; done
        pm2 stop kighmu-panel 2>/dev/null || true
        echo -e "${GREEN}  ✓ Tous les services arrêtés${RESET}"
        pause
    fi
}

menu_bckp_rstr() {
    while true; do
        sub_header '💾  BACKUP / RESTORE  💾'
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

menu_reboot() { sub_header '🔄  REBOOT VPS  🔄'; printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"; printf "${BG}║${RESET}  ${RED}⚠ Redémarrer le VPS maintenant ?${RESET}                         ${BG}║${RESET}\n"; sub_footer; prompt_sub "CONFIRMER (o/N)"; [[ "$SUB" =~ ^[oO]$ ]] && echo -e "${YELLOW}  Redémarrage...${RESET}" && reboot || echo "  Annulé"; }
menu_restart() { sub_header '🔄  RESTART SERVICES  🔄'; printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"; printf "${BG}║${RESET}  ${GREEN}Redémarrage de tous les services...${RESET}                        ${BG}║${RESET}\n"; sub_footer; prompt_sub "CONFIRMER (o/N)"; if [[ "$SUB" =~ ^[oO]$ ]]; then for s in nginx xray v2ray dropbear-custom hysteria zivpn slowdns ssh; do systemctl restart "$s" 2>/dev/null || true; done; pm2 restart kighmu-panel 2>/dev/null || true; echo -e "${GREEN}  ✓ Services redémarrés${RESET}"; fi; pause; }

menu_set_domain() {
    sub_header '🌐  SET DOMAIN  🌐'
    printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
    printf "${BG}║${RESET}  ${LAV}Domaine actuel:${RESET} ${ORANGE}%-36s${RESET} ${BG}║${RESET}\n" "$DOMAIN"
    printf "${BG}║${RESET}                                                                    ${BG}║${RESET}\n"
    printf "${BG}║${RESET}  Ceci modifie le domaine pour Xray, V2Ray, SlowDNS${RESET}           ${BG}║${RESET}\n"
    sub_footer
    prompt_sub "NOUVEAU DOMAINE (ou 0)"
    [[ "$SUB" != "0" && -n "$SUB" ]] && { echo "$SUB" > /etc/kighmu/domain.txt; echo "$SUB" > /etc/xray/domain 2>/dev/null || true; echo -e "${GREEN}  ✓ Domaine mis à jour: $SUB${RESET}"; pause; }
}

menu_cert_ssl() {
    sub_header '🔐  CERT SSL  🔐'
    printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
    printf "${BG}║${RESET}  [1] ${WHITE}Générer certificat Let's Encrypt${RESET}                   ${BG}║${RESET}\n"
    printf "${BG}║${RESET}  [2] ${WHITE}Voir statut certificat${RESET}                              ${BG}║${RESET}\n"
    sub_footer
    prompt_sub "CERT SSL"
    case $SUB in
        1) clear; read -rp "  Domaine: " d; apt-get install -y certbot python3-certbot-nginx 2>/dev/null && certbot --nginx -d "$d" --non-interactive --agree-tos -m admin@"$d" && echo -e "${GREEN}  ✓ Certificat généré${RESET}" || echo -e "${RED}  ✗ Échec${RESET}"; pause;;
        2) clear; certbot certificates 2>/dev/null || echo "  Aucun certificat"; pause;;
        0|q) ;;
    esac
}

menu_quota_usage() {
    sub_header '📊  QUOTA USAGE  📊'
    printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
    printf "${BG}║${RESET}  ${LAV}Jour:${RESET}     %b                                           ${BG}║${RESET}\n" "$qd"
    printf "${BG}║${RESET}  ${LAV}Semaine:${RESET}  %b                                           ${BG}║${RESET}\n" "$qw"
    printf "${BG}║${RESET}  ${LAV}Mois:${RESET}     %b                                           ${BG}║${RESET}\n" "$qm"
    sub_footer
    prompt_sub "QUOTA"
    pause
}

menu_clear_cache() {
    sub_header '🧹  CLEAR CACHE  🧹'
    printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
    printf "${BG}║${RESET}  ${RED}⚠ Nettoyer le cache système ?${RESET}                          ${BG}║${RESET}\n"
    sub_footer
    prompt_sub "CONFIRMER (o/N)"
    if [[ "$SUB" =~ ^[oO]$ ]]; then
        sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
        apt-get clean 2>/dev/null || true
        rm -rf /tmp/* 2>/dev/null || true
        echo -e "${GREEN}  ✓ Cache nettoyé${RESET}"
        pause
    fi
}

menu_cek_bandwidth() {
    sub_header '📈  CEK BANDWIDTH  📈'
    local iface=$(ip route 2>/dev/null | awk '/default/{print $5; exit}')
    local rx=$(awk -v i="$iface" '$1 ~ i":"{print $2}' /proc/net/dev 2>/dev/null || echo 0)
    local tx=$(awk -v i="$iface" '$1 ~ i":"{print $10}' /proc/net/dev 2>/dev/null || echo 0)
    printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
    printf "${BG}║${RESET}  ${LAV}Interface:${RESET} ${WHITE}%-48s${RESET} ${BG}║${RESET}\n" "$iface"
    printf "${BG}║${RESET}  ${LAV}Réception:${RESET}  ${MAG}$(fmt_bytes $rx)${RESET}                                           ${BG}║${RESET}\n"
    printf "${BG}║${RESET}  ${LAV}Émission:${RESET}    ${MAG}$(fmt_bytes $tx)${RESET}                                           ${BG}║${RESET}\n"
    printf "${BG}║${RESET}  ${LAV}Total:${RESET}       ${ORANGE}$(fmt_bytes $((rx+tx)))${RESET}                                           ${BG}║${RESET}\n"
    sub_footer
    prompt_sub "CEK BW"
    pause
}

menu_up_script() {
    sub_header '🔄  UPDATE SCRIPT  🔄'
    printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
    printf "${BG}║${RESET}  ${YELLOW}Mise à jour du panneau de contrôle...${RESET}                   ${BG}║${RESET}\n"
    printf "${BG}║${RESET}  Source: github.com/kinf744/Tyiop24${RESET}                             ${BG}║${RESET}\n"
    sub_footer
    prompt_sub "CONFIRMER (o/N)"
    if [[ "$SUB" =~ ^[oO]$ ]]; then
        curl -fsSL "https://raw.githubusercontent.com/kinf744/Tyiop24/main/kighmu.sh" -o /etc/kighmu-v2/panel.sh.new && mv /etc/kighmu-v2/panel.sh.new /etc/kighmu-v2/panel.sh && chmod +x /etc/kighmu-v2/panel.sh && echo -e "${GREEN}  ✓ Panneau mis à jour. Reconnectez-vous.${RESET}" && exit 0 || echo -e "${RED}  ✗ Échec mise à jour${RESET}"; pause
    fi
}

menu_bot_vip() {
    while true; do
        sub_header '🤖  MENU BOT VIP  🤖'
        printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
        sub_row 1 "STATUT BOT"              2 "START BOT"
        sub_row 3 "STOP BOT"                4 "SET TOKEN BOT"
        sub_footer
        prompt_sub "BOT VIP"
        case $SUB in
            1) clear; pm2 show kighmu-bot 2>/dev/null | grep -E 'status|uptime' || echo -e "${RED}  Bot inactif${RESET}"; pause;;
            2) clear; pm2 start kighmu-bot 2>/dev/null && echo -e "${GREEN}  ✓ Bot démarré${RESET}" || echo -e "${RED}  ✗ Échec${RESET}"; pause;;
            3) clear; pm2 stop kighmu-bot 2>/dev/null && echo -e "${GREEN}  ✓ Bot arrêté${RESET}"; pause;;
            4) clear; read -rp "  Token Telegram: " t; echo "BOT_TOKEN=$t" >> /opt/kighmu-panel/.env 2>/dev/null; echo -e "${GREEN}  ✓ Token enregistré${RESET}"; pause;;
            0|q) break ;;
        esac
    done
}

menu_change_banner() {
    sub_header '📝  CHANGE BANNER SSH  📝'
    printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
    printf "${BG}║${RESET}  ${LAV}Banner actuel:${RESET}${WHITE}%-51s${RESET} ${BG}║${RESET}\n" "$(head -1 /etc/ssh/banner.txt 2>/dev/null || echo "Aucun")"
    printf "${BG}║${RESET}                                                                    ${BG}║${RESET}\n"
    printf "${BG}║${RESET}  Entrez le nouveau texte du banner (une ligne)${RESET}                 ${BG}║${RESET}\n"
    sub_footer
    prompt_sub "NOUVEAU BANNER (ou 0)"
    [[ "$SUB" != "0" && -n "$SUB" ]] && { echo "$SUB" | tee /etc/ssh/banner.txt > /dev/null; systemctl restart ssh; echo -e "${GREEN}  ✓ Banner mis à jour${RESET}"; pause; }
}

menu_log_create_user() {
    sub_header '📋  LOG CREATE USER  📋'
    printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
    local logfile="/var/log/kighmu-user.log"
    if [[ -f "$logfile" ]]; then
        tail -15 "$logfile" | while IFS= read -r line; do printf "${BG}║${RESET}  ${WHITE}%-66s${RESET} ${BG}║${RESET}\n" "$line"; done
    else
        printf "${BG}║${RESET}  ${YELLOW}Aucun log de création disponible${RESET}                     ${BG}║${RESET}\n"
    fi
    sub_footer
    prompt_sub "LOG"
    pause
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
        23) menu_up_script ;;
        24) menu_bot_vip ;;
        25) menu_change_banner ;;
        26) menu_log_create_user ;;
        0|q|exit) exit 0 ;;
        *) ;;
    esac
done
# PANEL_CODE_END
