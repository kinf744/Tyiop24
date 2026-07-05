#!/bin/bash
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
                    local exp=$(chage -l "$u" 2>/dev/null | grep "Account expires" | cut -d: -f2)
                    local status="${GREEN}Actif${RESET}"
                    if echo "$exp" | grep -qi "never"; then
                        status="${GREEN}Actif${RESET}"
                    elif [[ -n "$exp" ]]; then
                        local exp_s=$(date -d "$exp" +%s 2>/dev/null || echo 0)
                        local now_s=$(date +%s)
                        (( exp_s < now_s )) && status="${RED}Expiré${RESET}"
                    fi
                    (( count == 0 )) && status="${RED}Inactif${RESET}"
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
    sub_header '🌍  PANEL WEB  🌍'
    printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
    sub_row 1 "STATUT PANEL"               2 "RESTART PANEL"
    sub_row 3 "CHANGE PORT PANEL"          4 "VIEW LOGS"
    sub_footer
    prompt_sub "PANEL WEB"
    case $SUB in
        1) clear; echo -e "${CYAN}━━ Statut Panel ━━${RESET}"; pm2 show kighmu-panel 2>/dev/null | grep -E 'status|uptime' || echo -e "${RED}  Panel non trouvé${RESET}"; pause;;
        2) clear; pm2 restart kighmu-panel 2>/dev/null && echo -e "${GREEN}  ✓ Panel redémarré${RESET}" || echo -e "${RED}  ✗ Échec${RESET}"; pause;;
        3) clear; echo -e "${CYAN}━━ Port Panel ━━${RESET}"; read -rp "  Nouveau port: " p; sed -i "s/:[0-9]*\//:$p\//" /etc/nginx/sites-enabled/kighmu 2>/dev/null && nginx -t && systemctl restart nginx && echo -e "${GREEN}  ✓ Port panel → $p${RESET}"; pause;;
        4) clear; tail -30 /var/log/kighmu*.log 2>/dev/null || echo "  Aucun log"; pause;;
        0|q) ;;
    esac
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
        curl -fsSL "https://raw.githubusercontent.com/kinf744/Tyiop24/main/kighmu.sh" -o /etc/kighmu/panel.sh.new && mv /etc/kighmu/panel.sh.new /etc/kighmu/panel.sh && chmod +x /etc/kighmu/panel.sh && echo -e "${GREEN}  ✓ Panneau mis à jour. Reconnectez-vous.${RESET}" && exit 0 || echo -e "${RED}  ✗ Échec mise à jour${RESET}"; pause
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
