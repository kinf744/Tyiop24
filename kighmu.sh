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

# ── Données ──
IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")
DOMAIN=$(cat /etc/kighmu/domain.txt 2>/dev/null || cat /etc/xray/domain 2>/dev/null || echo "$IP")
NS4=$(grep NS4 /etc/slowdns/ns.conf 2>/dev/null | cut -d= -f2 || echo "ns4.domain")
NV4=$(grep NV4 /etc/slowdns/ns.conf 2>/dev/null | cut -d= -f2 || echo "nv4.domain")
RAM=$(free -m | awk '/Mem:/ {print $3"MB/"$2"MB"}')
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
    printf "${BG}║${RESET}  ${LAV}RAM SERVER${RESET}     ${WHITE}%-34s${RESET}${BG}║${RESET}\n" "$RAM"
    printf "${BG}║${RESET}  ${LAV}DOMAIN${RESET}         ${ORANGE}%-34s${RESET}${BG}║${RESET}\n" "$DOMAIN"
    printf "${BG}║${RESET}  ${LAV}NS SLOWDNS${RESET}     ${MAG}%-34s${RESET}${BG}║${RESET}\n" "$NS4"
    printf "${BG}║${RESET}  ${LAV}NS V2RAY${RESET}       ${MAG}%-34s${RESET}${BG}║${RESET}\n" "$NV4"

    # ── Séparateur + Account Info ──
    printf "${BG}╠══════════════════════════════════════════════════════════════════════╣${RESET}\n"
    printf "${BG}║${RESET}  ${ORANGE}>>${RESET} $(center 'ACCOUNT INFORMATION' 48) ${ORANGE}<<${RESET}  ${BG}║${RESET}\n"
    printf "${BG}╠══════════════════════════════════════════════════════════════════════╣${RESET}\n"
    printf "${BG}║${RESET}  ══╡ $(rainbow) ╞══ ${BG}║${RESET}\n"
    printf "${BG}╠══════════════════════════════════════════════════════════════════════╣${RESET}\n"

    # ── Tableau comptes ──
    printf "${BG}║${RESET} ${LAV}SSH/OPENVPN${RESET}   ${MAG}%-2s${RESET}   ${LAV}VMESS${RESET}        ${MAG}%-2s${RESET}   ${LAV}VLESS${RESET}        ${MAG}%-2s${RESET} ${BG}║${RESET}\n" "$N_SSH" "$N_VMESS" "$N_VLESS"
    printf "${BG}║${RESET} ${LAV}TROJAN${RESET}        ${MAG}%-2s${RESET}   ${LAV}SHADOWSOCKS${RESET}  ${MAG}%-2s${RESET}   ${LAV}V2RAY${RESET}        ${MAG}%-2s${RESET} ${BG}║${RESET}\n" "$N_TROJAN" "$N_SHADOW" "$N_V2RAY"
    printf "${BG}║${RESET} ${LAV}HYSTERIA${RESET}      ${MAG}%-2s${RESET}   ${LAV}ZIVPN${RESET}        ${MAG}%-2s${RESET}   ${LAV}TOTAL${RESET}        ${MAG}%-2s${RESET} ${BG}║${RESET}\n" "$N_HY" "$N_ZIVPN" "$N_TOTAL"

    # ── Séparateur + Premium Menu ──
    printf "${BG}╠══════════════════════════════════════════════════════════════════════╣${RESET}\n"
    printf "${BG}║${RESET}  ══╡ $(rainbow) ╞══ ${BG}║${RESET}\n"
    printf "${BG}╠══════════════════════════════════════════════════════════════════════╣${RESET}\n"
    printf "${BG}║${RESET}  ${ORANGE}>>${RESET} $(center 'PREMIUM MENU' 48) ${ORANGE}<<${RESET}  ${BG}║${RESET}\n"
    printf "${BG}╠══════════════════════════════════════════════════════════════════════╣${RESET}\n"

    # ── Statuts services ──
    printf "${BG}║${RESET}  ${LAV}SSH${RESET}     %s  ${LAV}NGINX${RESET}   %s  ${LAV}HAPROXY${RESET}  %s  ${LAV}WS-epro${RESET} OFF   ${LAV}XRAY${RESET}    %s  ${LAV}DROPBEAR${RESET}  %s ${BG}║${RESET}\n" "$S_SSH" "$S_NGINX" "$S_HAPROXY" "$S_XRAY" "$S_DROP"
    printf "${BG}╠══════════════════════════════════════════════════════════════════════╣${RESET}\n"

    # ── Menu numéroté (3 colonnes) ──
    local items=(
        "[01] INSTALL UDP"    "[02] INSTALL XRAY"    "[03] INSTALL V2RAY"
        "[04] INSTALL SSH"    "[05] HYSTERIA"        "[06] ZIVPN"
        "[07] BADVPN"         "[08] DROPBEAR"        "[09] SLOWDNS"
        "[10] SSL/TLS"        "[11] SSH WS"          "[12] SOCKS WS"
        "[13] ADD UDP"        "[14] ADD XRAY"        "[15] ADD SSH"
        "[16] DEL UDP"        "[17] DEL XRAY"        "[18] DEL SSH"
        "[19] SERVICE FIX"    "[20] CHANGE DOMAIN"   "[21] BANDWIDTH"
        "[22] BACKUP"         "[23] RESTART"         "[24] REBOOT"
    )
    for ((i=0; i<24; i+=3)); do
        printf "${BG}║${RESET}  ${ORANGE}%-18s${RESET} ${ORANGE}%-18s${RESET} ${ORANGE}%-18s${RESET} ${BG}║${RESET}\n" \
            "${items[$i]}" "${items[$((i+1))]:-}" "${items[$((i+2))]:-}"
    done

    printf "${BG}╠══════════════════════════════════════════════════════════════════════╣${RESET}\n"

    # ── Options spéciales ──
    printf "${BG}║${RESET}  ${ORANGE}[25]${RESET} ${WHITE}LOCK ACCOUNT${RESET}       ${ORANGE}[26]${RESET} ${WHITE}UNLOCK ACCOUNT${RESET}       ${BG}║${RESET}\n"
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

# ── Boucle ──
while true; do
    draw_panel
    case $CHOIX in
        1) bash -c "$(curl -fsSL https://raw.githubusercontent.com/kinf744/Tyiop24/main/udp.sh 2>/dev/null || echo 'echo Erreur telechargement')" ;;
        2) bash -c "$(curl -fsSL https://raw.githubusercontent.com/kinf744/Tyiop24/main/xray-v2ray.sh 2>/dev/null)" ;;
        3) bash -c "$(curl -fsSL https://raw.githubusercontent.com/kinf744/Tyiop24/main/xray-v2ray.sh 2>/dev/null)" ;; # V2Ray
        4) bash -c "$(curl -fsSL https://raw.githubusercontent.com/kinf744/Tyiop24/main/ssh.sh 2>/dev/null)" ;;
        # Les autres options seront implémentées selon tes besoins
        0|q|exit) exit 0 ;;
        *) ;;
    esac
done
