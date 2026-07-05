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
# SOUS-MENU SSH VIP
# ================================================
menu_ssh_vip() {
    while true; do
        echo -e "${CLR}${BG}"
        echo -e "${BG}${CYAN}╔═══$(printf '═%.0s' {1..67})═══╗${RESET}"
        echo -e "${BG}${CYAN}║${RESET}${TITLE_BG}$(center '🔰  MENU SSH VIP  🔰' 71)${RESET}${BG}${CYAN}║${RESET}"
        echo -e "${BG}${CYAN}╚═══$(printf '═%.0s' {1..67})═══╝${RESET}"

        printf "${BG}╔══════════════════════════════════════════════════════════════════════╗${RESET}\n"
        printf "${BG}║${RESET}  ${ORANGE}[01]${RESET} ${WHITE}CREER COMPTE SSH${RESET}          ${ORANGE}[02]${RESET} ${WHITE}SUPPRIMER COMPTE${RESET}       ${BG}║${RESET}\n"
        printf "${BG}║${RESET}  ${ORANGE}[03]${RESET} ${WHITE}LISTE COMPTES${RESET}             ${ORANGE}[04]${RESET} ${WHITE}MONITOR CONNEXIONS${RESET}    ${BG}║${RESET}\n"
        printf "${BG}║${RESET}  ${ORANGE}[05]${RESET} ${WHITE}CHANGE PORT SSH${RESET}           ${ORANGE}[06]${RESET} ${WHITE}CHANGE BANNER${RESET}         ${BG}║${RESET}\n"
        printf "${BG}║${RESET}  ${ORANGE}[07]${RESET} ${WHITE}LOCK ACCOUNT${RESET}              ${ORANGE}[08]${RESET} ${WHITE}UNLOCK ACCOUNT${RESET}        ${BG}║${RESET}\n"
        printf "${BG}║${RESET}  ${ORANGE}[09]${RESET} ${WHITE}AJOUTER MULTI-LOGIN${RESET}       ${ORANGE}[10]${RESET} ${WHITE}LIMITER BANDWIDTH${RESET}     ${BG}║${RESET}\n"
        printf "${BG}║${RESET}  ${ORANGE}[11]${RESET} ${WHITE}BACKUP USERS${RESET}              ${ORANGE}[12]${RESET} ${WHITE}RESTORE USERS${RESET}        ${BG}║${RESET}\n"
        printf "${BG}╠══════════════════════════════════════════════════════════════════════╣${RESET}\n"
        printf "${BG}║${RESET}  ${RED}[0]${RESET} ${YELLOW}RETOUR AU MENU PRINCIPAL${RESET}                                      ${BG}║${RESET}\n"
        echo -e "${BG}${CYAN}╚═══$(printf '═%.0s' {1..67})═══╝${RESET}"
        echo
        echo -ne "${BG}${LAV}  SSH VIP »${RESET} ${WHITE}"
        read -r SUB
        echo -e "${RESET}"
        case $SUB in
            1) clear; echo -e "${CYAN}━━ Création compte SSH ━━${RESET}"; read -rp "Username: " u; read -rp "Password: " p; read -rp "Expire (jours): " e; useradd -e "$(date -d "+${e}days" +%Y-%m-%d)" -s /bin/bash "$u" 2>/dev/null && echo "$u:$p" | chpasswd && echo -e "${GREEN}✓ Compte $u créé${RESET}" || echo -e "${RED}✗ Échec${RESET}"; pause;;
            2) clear; echo -e "${CYAN}━━ Suppression compte SSH ━━${RESET}"; read -rp "Username: " u; userdel -r "$u" 2>/dev/null && echo -e "${GREEN}✓ Supprimé${RESET}" || echo -e "${RED}✗ Introuvable${RESET}"; pause;;
            3) clear; echo -e "${CYAN}━━ Liste comptes SSH actifs ━━${RESET}"; awk -F: '$7~/bash|sh/ && $3>=1000 {print "  " $1}' /etc/passwd; pause;;
            4) clear; echo -e "${CYAN}━━ Connexions actives ━━${RESET}"; who | awk '{print "  " $1 " depuis " $NF}'; echo; echo -e "${YELLOW}Appuyez sur Ctrl+C pour quitter${RESET}"; sleep 5;;
            5) clear; echo -e "${CYAN}━━ Changer port SSH ━━${RESET}"; read -rp "Nouveau port: " p; sed -i "s/^Port .*/Port $p/" /etc/ssh/sshd_config && systemctl restart ssh && echo -e "${GREEN}✓ Port changé en $p${RESET}"; pause;;
            6) clear; echo -e "${CYAN}━━ Changer banner SSH ━━${RESET}"; read -rp "Nouveau banner: " b; echo "$b" > /etc/ssh/banner.txt && echo -e "${GREEN}✓ OK${RESET}"; pause;;
            7|8) clear; echo -e "${YELLOW}Option à implémenter${RESET}"; pause;;
            9|10|11|12) clear; echo -e "${YELLOW}Option à implémenter${RESET}"; pause;;
            0|q) break ;;
            *) ;;
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
        2) bash -c "$(curl -fsSL https://raw.githubusercontent.com/kinf744/Tyiop24/main/xray-v2ray.sh 2>/dev/null)" ;;
        3) bash -c "$(curl -fsSL https://raw.githubusercontent.com/kinf744/Tyiop24/main/xray-v2ray.sh 2>/dev/null)" ;; # V2Ray
        4) bash -c "$(curl -fsSL https://raw.githubusercontent.com/kinf744/Tyiop24/main/ssh.sh 2>/dev/null)" ;;
        # Les autres options seront implémentées selon tes besoins
        0|q|exit) exit 0 ;;
        *) ;;
    esac
done
