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
    local panel_url="https://raw.githubusercontent.com/kinf744/Tyiop24/main/kighmu.sh"
    mkdir -p /etc/kighmu
    curl -fsSL "$panel_url" -o /etc/kighmu/panel.sh 2>/dev/null || {
        [[ -f "$SCRIPT_DIR/kighmu.sh" ]] && cp "$SCRIPT_DIR/kighmu.sh" /etc/kighmu/panel.sh || { err "Panel non dispo"; return 1; }
    }
    chmod +x /etc/kighmu/panel.sh
    cat > /etc/profile.d/kighmu-panel.sh << 'PROF'
#!/bin/bash
if [[ $EUID -eq 0 && -f /etc/kighmu/panel.sh && -t 0 ]]; then
    /etc/kighmu/panel.sh
fi
PROF
    chmod +x /etc/profile.d/kighmu-panel.sh
    log "Panel déployé (/etc/kighmu/panel.sh)"
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
