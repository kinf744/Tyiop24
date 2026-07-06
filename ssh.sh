#!/bin/bash
# Kighmu - Tunnels SSH
# OpenSSH, Dropbear, SlowDNS, SSL/TLS, WS, SOCKS, wstunnel
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PANEL_DIR="/opt/kighmu-panel"

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
# OPENSSH
# ================================================
install_openssh() {
    echo "${CYAN}━━━ Configuration OpenSSH ━━━${RESET}"
    apt-get install -y -qq openssh-server 2>/dev/null || true
    systemctl enable ssh 2>/dev/null || true
    systemctl restart ssh 2>/dev/null || true
    # Tunneling
    sed -i 's/^#PermitTunnel.*/PermitTunnel yes/' /etc/ssh/sshd_config 2>/dev/null || echo "PermitTunnel yes" >> /etc/ssh/sshd_config
    sed -i 's/^#AllowTcpForwarding.*/AllowTcpForwarding yes/' /etc/ssh/sshd_config 2>/dev/null || echo "AllowTcpForwarding yes" >> /etc/ssh/sshd_config
    systemctl restart ssh 2>/dev/null || true
    log "OpenSSH actif (port 22)"
    pause
}

# ================================================
# DROPBEAR
# ================================================
install_dropbear() {
    echo "${CYAN}━━━ Installation Dropbear (port 109) ━━━${RESET}"
    command -v /usr/local/sbin/dropbear &>/dev/null && { warn "Dropbear déjà installé"; pause; return; }
    apt-get install -y -qq build-essential bzip2 zlib1g-dev wget tar dos2unix 2>/dev/null
    cd /usr/local/src
    wget -q "https://matt.ucc.asn.au/dropbear/releases/dropbear-2022.83.tar.bz2" -O dropbear-2022.83.tar.bz2 2>/dev/null || {
        err "Téléchargement échoué"; pause; return; }
    tar -xjf dropbear-2022.83.tar.bz2 2>/dev/null; cd dropbear-2022.83
    ./configure --prefix=/usr/local >/dev/null 2>&1; make -j"$(nproc)" >/dev/null 2>&1; make install >/dev/null 2>&1

    local DIR="/etc/dropbear"; mkdir -p "$DIR"
    for key in rsa ecdsa ed25519; do
        /usr/local/bin/dropbearkey -t "$key" -f "$DIR/dropbear_${key}_host_key" 2>/dev/null || true
    done
    chmod 600 "$DIR"/*_host_key 2>/dev/null || true

    echo "Bienvenue sur Kighmu - Connexion autorisée" > "$DIR/banner.txt"

    cat > /etc/systemd/system/dropbear-custom.service << 'UNIT'
[Unit]; Description=Dropbear Custom (port 109); After=network-online.target; Wants=network-online.target
[Service]; Type=simple; ExecStart=/usr/local/sbin/dropbear -F -E -p 109 -w -g -b /etc/dropbear/banner.txt -R; Restart=always; RestartSec=2; User=root; LimitNOFILE=1048576
[Install]; WantedBy=multi-user.target
UNIT
    systemctl daemon-reload && systemctl enable --now dropbear-custom.service 2>/dev/null || true
    deploy_nft_tunnel dropbear 'table inet dropbear { chain input { type filter hook input priority 0; policy accept; tcp dport 109 accept; }; }'
    log "Dropbear actif (port 109)"; pause
}

uninstall_dropbear() {
    read -rp "Confirmer ? (o/N): " C; [[ "$C" =~ ^[oO]$ ]] || return
    systemctl disable --now dropbear-custom.service 2>/dev/null || true
    rm -f /etc/systemd/system/dropbear-custom.service; rm -rf /etc/dropbear
    rm -f /usr/local/sbin/dropbear /usr/local/bin/dropbear*
    remove_nft_tunnel dropbear; systemctl daemon-reload; log "Dropbear supprimé"; pause
}

# ================================================
# SSL/TLS TUNNEL
# ================================================
install_ssl_tls() {
    echo "${CYAN}━━━ Installation SSL/TLS Tunnel (port 444 → 109) ━━━${RESET}"
    command -v ssl_tls &>/dev/null && { warn "ssl_tls déjà installé"; pause; return; }
    apt-get install -y -qq curl 2>/dev/null
    local url="https://github.com/kinf744/Kighmu/releases/download/v1.0.0/ssl_tls"
    local tmp; tmp=$(mktemp -d); cd "$tmp"
    curl -fsSL "$url" -o ssl_tls 2>/dev/null && chmod +x ssl_tls && file ssl_tls | grep -q ELF
    install -m 0755 ssl_tls /usr/local/bin/ssl_tls; rm -rf "$tmp"

    cat > /etc/systemd/system/ssl_tls.service << 'UNIT'
[Unit]; Description=Tunnel SSL/TLS (ssl_tls); After=network.target; Wants=network.target
[Service]; Type=simple; ExecStart=/usr/local/bin/ssl_tls -listen 444 -target-host 127.0.0.1 -target-port 109; Restart=always; RestartSec=2; LimitNOFILE=1048576; StandardOutput=journal; StandardError=journal
[Install]; WantedBy=multi-user.target
UNIT
    systemctl daemon-reload && systemctl enable --now ssl_tls.service 2>/dev/null || true
    deploy_nft_tunnel ssl_tls 'table inet ssl_tls { chain input { type filter hook input priority 0; policy accept; tcp dport 444 accept; }; chain output { type filter hook output priority 0; policy accept; tcp sport 444 accept; }; }'
    log "SSL/TLS actif (port 444 → 22/109)"; pause
}

uninstall_ssl_tls() {
    read -rp "Confirmer ? (o/N): " C; [[ "$C" =~ ^[oO]$ ]] || return
    systemctl disable --now ssl_tls.service 2>/dev/null || true; rm -f /etc/systemd/system/ssl_tls.service
    rm -f /usr/local/bin/ssl_tls; remove_nft_tunnel ssl_tls; systemctl daemon-reload; log "ssl_tls supprimé"; pause
}

# ================================================
# SSH WS (Slipstream)
# ================================================
install_sshws() {
    echo "${CYAN}━━━ Installation SSH WS (port 80 → 109) ━━━${RESET}"
    command -v sshws &>/dev/null && { warn "sshws déjà installé"; pause; return; }
    local url="https://github.com/kinf744/Kighmu/releases/download/v1.0.0"
    local tmp; tmp=$(mktemp -d); cd "$tmp"
    curl -LO "$url/sshws" 2>/dev/null && chmod +x sshws
    install -m 0755 sshws /usr/local/bin/sshws; rm -rf "$tmp"

    cat > /etc/systemd/system/sshws.service << 'UNIT'
[Unit]; Description=SSHWS Slipstream Tunnel; After=network.target
[Service]; Type=simple; ExecStart=/usr/local/bin/sshws -listen 80 -target-host 127.0.0.1 -target-port 109; Restart=always; RestartSec=2; User=root; LimitNOFILE=1048576
[Install]; WantedBy=multi-user.target
UNIT
    systemctl daemon-reload && systemctl enable --now sshws.service 2>/dev/null || true
    deploy_nft_tunnel sshws 'table inet sshws { chain input { type filter hook input priority 0; policy accept; tcp dport 80 accept; }; }'
    log "SSH WS actif (port 80 → 109)"; pause
}

uninstall_sshws() {
    read -rp "Confirmer ? (o/N): " C; [[ "$C" =~ ^[oO]$ ]] || return
    systemctl disable --now sshws.service 2>/dev/null || true; rm -f /etc/systemd/system/sshws.service
    rm -f /usr/local/bin/sshws; remove_nft_tunnel sshws; systemctl daemon-reload; log "sshws supprimé"; pause
}

# ================================================
# WSTUNNEL (proxy--ws)
# ================================================
install_wstunnel() {
    echo "${CYAN}━━━ Installation wstunnel (port 8880 → 22) ━━━${RESET}"
    command -v wstunnel &>/dev/null && { warn "wstunnel déjà installé"; pause; return; }
    apt-get install -y -qq wget 2>/dev/null
    rm -rf /tmp/wstunnel_inst; mkdir -p /tmp/wstunnel_inst; cd /tmp/wstunnel_inst
    local url="https://github.com/erebe/wstunnel/releases/download/v10.5.1/wstunnel_10.5.1_linux_amd64.tar.gz"
    wget -q "$url" -O wstunnel.tar.gz 2>/dev/null
    tar -xzf wstunnel.tar.gz >/dev/null 2>&1; chmod +x wstunnel; mv wstunnel /usr/local/bin/wstunnel; rm -rf /tmp/wstunnel_inst

    cat > /usr/local/bin/proxy--ws << 'PROXYEOF'
#!/usr/bin/env bash
DOMAIN="${DOMAIN:-0.0.0.0}"
exec /usr/local/bin/wstunnel server "ws://0.0.0.0:8880" --restrict-to "127.0.0.1:22"
PROXYEOF
    chmod +x /usr/local/bin/proxy--ws

    cat > /etc/systemd/system/proxy--ws.service << 'UNIT'
[Unit]; Description=Proxy WebSocket SSH (wstunnel); After=network.target
[Service]; Type=simple; User=root; ExecStart=/usr/local/bin/proxy--ws; Restart=always; RestartSec=5; StartLimitIntervalSec=0; KillMode=process; LimitNOFILE=1048576; StandardOutput=append:/var/log/proxy--ws.log; StandardError=append:/var/log/proxy--ws.err
[Install]; WantedBy=multi-user.target
UNIT
    systemctl daemon-reload && systemctl enable --now proxy--ws.service 2>/dev/null || true
    deploy_nft_tunnel proxy-ws 'table inet proxy-ws { chain input { type filter hook input priority 0; policy accept; tcp dport 8880 accept; }; }'
    log "wstunnel actif (port 8880 → 22)"; pause
}

uninstall_wstunnel() {
    read -rp "Confirmer ? (o/N): " C; [[ "$C" =~ ^[oO]$ ]] || return
    systemctl disable --now proxy--ws.service 2>/dev/null || true; rm -f /etc/systemd/system/proxy--ws.service
    rm -f /usr/local/bin/wstunnel /usr/local/bin/proxy--ws
    remove_nft_tunnel proxy-ws; systemctl daemon-reload; log "wstunnel supprimé"; pause
}

# ================================================
# SOCKS PYTHON WS (port 9090)
# ================================================
install_sockspy() {
    echo "${CYAN}━━━ Installation SOCKS Python WS (port 9090) ━━━${RESET}"
    command -v ws2_proxy.py &>/dev/null && { warn "sockspy déjà installé"; pause; return; }
    mkdir -p /etc/sockspy
    python3 -c "import socks" &>/dev/null || apt-get install -y -qq python3-socks 2>/dev/null || {
        python3 -m venv /root/socksenv 2>/dev/null; source /root/socksenv/bin/activate
        pip install pysocks >/dev/null 2>&1; deactivate
    }
    local url="https://raw.githubusercontent.com/kinf744/Kighmu/main/ws2_proxy.py"
    wget -q -O /usr/local/bin/ws2_proxy.py "$url" 2>/dev/null; chmod +x /usr/local/bin/ws2_proxy.py

    cat > /etc/systemd/system/socks_python_ws.service << 'UNIT'
[Unit]; Description=Proxy SOCKS/Python WS; After=network-online.target; Wants=network-online.target
[Service]; Type=simple; User=root; ExecStart=/usr/local/bin/ws2_proxy.py 9090; Restart=always; RestartSec=5; StandardOutput=journal; StandardError=journal; SyslogIdentifier=sockspy; LimitNOFILE=1048576; Nice=-5; CPUSchedulingPolicy=fifo; CPUSchedulingPriority=99
[Install]; WantedBy=multi-user.target
UNIT
    systemctl daemon-reload && systemctl enable --now socks_python_ws.service 2>/dev/null || true
    deploy_nft_tunnel sockspy 'table inet sockspy { chain input { type filter hook input priority 0; policy accept; tcp dport 9090 accept; }; }'
    log "SOCKS WS actif (port 9090)"; pause
}

uninstall_sockspy() {
    read -rp "Confirmer ? (o/N): " C; [[ "$C" =~ ^[oO]$ ]] || return
    systemctl disable --now socks_python_ws.service 2>/dev/null || true; rm -f /etc/systemd/system/socks_python_ws.service
    rm -f /usr/local/bin/ws2_proxy.py; rm -rf /etc/sockspy
    remove_nft_tunnel sockspy; systemctl daemon-reload; log "sockspy supprimé"; pause
}

# ================================================
# SOCKS PYTHON DIRECT (port user)
# ================================================
install_socks_python() {
    echo "${CYAN}━━━ Installation SOCKS Python Direct ━━━${RESET}"
    command -v KIGHMUPROXY.py &>/dev/null && { warn "SOCKS Python déjà installé"; pause; return; }
    mkdir -p /etc/socks_python
    read -rp "Port (1024-65535) [9050]: " PORT; PORT=${PORT:-9050}
    [[ "$PORT" -lt 1024 || "$PORT" -gt 65535 ]] && { err "Port invalide"; pause; return; }
    echo "$PORT" > /etc/socks_python/socks_port.conf
    python3 -c "import socks" &>/dev/null || apt-get install -y -qq python3-socks 2>/dev/null || {
        python3 -m venv /root/socksenv 2>/dev/null; source /root/socksenv/bin/activate
        pip install pysocks >/dev/null 2>&1; deactivate
    }
    local url="https://raw.githubusercontent.com/kinf744/Kighmu/main/KIGHMUPROXY.py"
    wget -q -O /usr/local/bin/KIGHMUPROXY.py "$url" 2>/dev/null; chmod +x /usr/local/bin/KIGHMUPROXY.py

    cat > /etc/systemd/system/socks_python.service << UNIT
[Unit]; Description=Proxy SOCKS Python; After=network.target network-online.target; Wants=network-online.target
[Service]; Type=simple; User=root; ExecStart=/usr/bin/python3 /usr/local/bin/KIGHMUPROXY.py $PORT; Restart=always; RestartSec=5; StandardOutput=journal; StandardError=journal; SyslogIdentifier=socks-python-proxy
[Install]; WantedBy=multi-user.target
UNIT
    systemctl daemon-reload && systemctl enable --now socks_python.service 2>/dev/null || true
    deploy_nft_tunnel socks-python "table inet socks-python { chain input { type filter hook input priority 0; policy accept; tcp dport ${PORT} accept; }; }"
    log "SOCKS Python actif (port $PORT)"; pause
}

uninstall_socks_python() {
    read -rp "Confirmer ? (o/N): " C; [[ "$C" =~ ^[oO]$ ]] || return
    systemctl disable --now socks_python.service 2>/dev/null || true; rm -f /etc/systemd/system/socks_python.service
    rm -f /usr/local/bin/KIGHMUPROXY.py; rm -rf /etc/socks_python
    remove_nft_tunnel socks-python; systemctl daemon-reload; log "SOCKS Python supprimé"; pause
}

# ================================================
# WS DROPBEAR + WS STUNNEL (Python websockets)
# ================================================
install_ws_services() {
    echo "${CYAN}━━━ Installation WS Dropbear (2095) + WS Stunnel (700) ━━━${RESET}"
    apt-get install -y -qq python3 python3-pip nginx certbot python3-certbot-nginx stunnel4 wget 2>/dev/null
    python3 -m pip install --upgrade pip websockets >/dev/null 2>&1 || true
    local base="https://raw.githubusercontent.com/kinf744/Kighmu/main"
    wget -q -O /usr/local/bin/ws-dropbear "$base/ws-dropbear" 2>/dev/null || true
    wget -q -O /usr/local/bin/ws-stunnel "$base/ws-stunnel" 2>/dev/null || true
    chmod +x /usr/local/bin/ws-dropbear /usr/local/bin/ws-stunnel 2>/dev/null || true

    cat > /etc/systemd/system/ws-dropbear.service << 'UNIT'
[Unit]; Description=Websocket-Dropbear; After=network.target
[Service]; Type=simple; User=root; ExecStart=/usr/bin/python3 -O /usr/local/bin/ws-dropbear 2095; Restart=always; RestartSec=3s; LimitNOFILE=1048576
[Install]; WantedBy=multi-user.target
UNIT
    cat > /etc/systemd/system/ws-stunnel.service << 'UNIT2'
[Unit]; Description=WS Stunnel HTTPS; After=network.target
[Service]; Type=simple; User=root; ExecStart=/usr/bin/python3 -O /usr/local/bin/ws-stunnel 700; Restart=always; RestartSec=3s; LimitNOFILE=1048576
[Install]; WantedBy=multi-user.target
UNIT2
    systemctl daemon-reload
    systemctl enable --now ws-dropbear ws-stunnel 2>/dev/null || true
    log "WS Dropbear (2095) + WS Stunnel (700) actifs"; pause
}

uninstall_ws_services() {
    read -rp "Confirmer ? (o/N): " C; [[ "$C" =~ ^[oO]$ ]] || return
    systemctl disable --now ws-dropbear ws-stunnel 2>/dev/null || true
    rm -f /etc/systemd/system/ws-dropbear.service /etc/systemd/system/ws-stunnel.service
    rm -f /usr/local/bin/ws-dropbear /usr/local/bin/ws-stunnel
    systemctl daemon-reload; log "WS services supprimés"; pause
}

# ================================================
# SLOWDNS
# ================================================
install_slowdns() {
    echo "${CYAN}━━━ Installation SlowDNS (53→5300→5353/5354) ━━━${RESET}"
    command -v dnstt-server &>/dev/null && { warn "SlowDNS déjà installé"; pause; return; }
    apt-get install -y -qq curl jq dnsdist wget 2>/dev/null

    local DIR="/etc/slowdns"; mkdir -p "$DIR/ns4" "$DIR/nv4" /var/log/slowdns
    local PUB_KEY; PUB_KEY=$(curl -s ipv4.icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')

    local DNSTT_PRIV="4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa"
    local DNSTT_PUB="2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c"
    printf '%s\n' "$DNSTT_PRIV" > "$DIR/server.key"; printf '%s\n' "$DNSTT_PUB" > "$DIR/server.pub"
    chmod 600 "$DIR/server.key"; chmod 644 "$DIR/server.pub"

    local tmp; tmp=$(mktemp)
    curl -fsSL "https://dnstt-server-client.s3.amazonaws.com/dnstt-server-linux-amd64" -o "$tmp" 2>/dev/null
    mv "$tmp" /usr/local/bin/dnstt-server; chmod +x /usr/local/bin/dnstt-server

    local NS4 NV4
    read -rp "NS4 (ex: ns4.votre-domaine.com): " NS4; NS4=${NS4:-ns4.kighmu.local}
    read -rp "NV4 (ex: vps-ns4.votre-domaine.com): " NV4; NV4=${NV4:-vps-ns4.kighmu.local}
    echo "NS4=$NS4" > "$DIR/ns.conf"; echo "NV4=$NV4" >> "$DIR/ns.conf"

    cat > /usr/local/bin/slowdns-ns4-start.sh << STARTEOF
#!/bin/bash
NS=\$(cat $DIR/ns.conf | grep NS4 | cut -d= -f2)
exec /usr/local/bin/dnstt-server -udp 0.0.0.0:5353 -privkey-file $DIR/server.key \$NS 127.0.0.1:109
STARTEOF
    chmod +x /usr/local/bin/slowdns-ns4-start.sh

    cat > /usr/local/bin/slowdns-nv4-start.sh << STARTEOF
#!/bin/bash
NV4=\$(cat $DIR/ns.conf | grep NV4 | cut -d= -f2)
exec /usr/local/bin/dnstt-server -udp 0.0.0.0:5354 -privkey-file $DIR/server.key \$NV4 127.0.0.1:5401
STARTEOF
    chmod +x /usr/local/bin/slowdns-nv4-start.sh

    for svc in slowdns-ns4 slowdns-nv4; do
        cat > "/etc/systemd/system/${svc}.service" << UNIT
[Unit]; Description=SlowDNS $svc; After=network-online.target; Wants=network-online.target
[Service]; Type=simple; ExecStartPre=/bin/sleep 5; ExecStart=/usr/local/bin/${svc}-start.sh; Restart=always; RestartSec=5; LimitNOFILE=1048576; StandardOutput=append:/var/log/slowdns/${svc}.log; StandardError=append:/var/log/slowdns/${svc}.log
[Install]; WantedBy=multi-user.target
UNIT
        systemctl daemon-reload && systemctl enable --now "${svc}.service" 2>/dev/null || true
    done

    cat > /etc/dnsdist/dnsdist.conf << 'DNSDEOF'
setSecurityPollSuffix("")
setACL({"0.0.0.0/0","::/0"})
addLocal("0.0.0.0:5300")
newServer({address="127.0.0.1:5353",pool="ns4"})
newServer({address="127.0.0.1:5354",pool="nv4"})
addAction(AllRule(), RCodeAction(5))
DNSDEOF
    mkdir -p /etc/systemd/system/dnsdist.service.d
    printf '[Service]\nRestart=always\n' > /etc/systemd/system/dnsdist.service.d/restart.conf
    systemctl daemon-reload; systemctl restart dnsdist 2>/dev/null || true

    deploy_nft_tunnel slowdns 'table inet slowdns { chain prerouting { type nat hook prerouting priority -100; udp dport 53 redirect to :5300; tcp dport 53 redirect to :5300; }; chain input { type filter hook input priority 0; policy accept; udp dport 53 accept; udp dport 5300 accept; udp dport 5353 accept; udp dport 5354 accept; tcp dport 109 accept; tcp dport 5401 accept; }; }'

    chattr -i /etc/resolv.conf 2>/dev/null || true
    printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf
    chattr +i /etc/resolv.conf 2>/dev/null || true

    log "SlowDNS actif (53→5300→5353/5354)"
    echo "   NS4: $NS4 → 127.0.0.1:109 (SSH)"
    echo "   NV4: $NV4 → 127.0.0.1:5401 (V2Ray)"
    pause
}

uninstall_slowdns() {
    read -rp "Confirmer ? (o/N): " C; [[ "$C" =~ ^[oO]$ ]] || return
    for svc in slowdns-ns4 slowdns-nv4 dnsdist; do
        systemctl disable --now "$svc" 2>/dev/null || true
    done
    rm -f /etc/systemd/system/slowdns-ns4.service /etc/systemd/system/slowdns-nv4.service
    rm -f /usr/local/bin/dnstt-server
    rm -f /usr/local/bin/slowdns-ns4-start.sh /usr/local/bin/slowdns-nv4-start.sh
    rm -rf /etc/slowdns /var/log/slowdns /etc/dnsdist
    rm -f /etc/systemd/system/dnsdist.service.d/restart.conf
    systemctl daemon-reload
    remove_nft_tunnel slowdns
    chattr -i /etc/resolv.conf 2>/dev/null || true
    log "SlowDNS supprimé"; pause
}

# ================================================
# MENU SSH
# ================================================
main_menu() {
    while true; do
        clear
        echo "${CYAN}${BOLD}╔═══════════════════════════════════════╗${RESET}"
        echo "${CYAN}║        TUNNELS SSH - KIGHMU            ║${RESET}"
        echo "${CYAN}╚═══════════════════════════════════════╝${RESET}"
        echo
        echo "${WHITE}1. OpenSSH${RESET}           ${GREEN}[1a]${RESET} Configurer"
        echo
        echo "${WHITE}2. Dropbear (109)${RESET}    ${GREEN}[2a]${RESET} Installer    ${GREEN}[2e]${RESET} Désinstaller"
        echo
        echo "${WHITE}3. SlowDNS (53)${RESET}      ${GREEN}[3a]${RESET} Installer    ${GREEN}[3e]${RESET} Désinstaller"
        echo
        echo "${WHITE}4. SSL/TLS (444)${RESET}     ${GREEN}[4a]${RESET} Installer    ${GREEN}[4e]${RESET} Désinstaller"
        echo
        echo "${WHITE}5. SSH WS (80)${RESET}       ${GREEN}[5a]${RESET} Installer    ${GREEN}[5e]${RESET} Désinstaller"
        echo
        echo "${WHITE}6. wstunnel (8880)${RESET}   ${GREEN}[6a]${RESET} Installer    ${GREEN}[6e]${RESET} Désinstaller"
        echo
        echo "${WHITE}7. SOCKS WS (9090)${RESET}   ${GREEN}[7a]${RESET} Installer    ${GREEN}[7e]${RESET} Désinstaller"
        echo
        echo "${WHITE}8. SOCKS Direct${RESET}      ${GREEN}[8a]${RESET} Installer    ${GREEN}[8e]${RESET} Désinstaller"
        echo
        echo "${WHITE}9. WS Dropbear + Stunnel${RESET}  ${GREEN}[9a]${RESET} Installer  ${GREEN}[9e]${RESET} Désinstaller"
        echo
        echo "  ${RED}[0]${RESET} Retour"
        echo
        echo -n "Choix: "
        read -r C
        case $C in
            1a) install_openssh ;;
            2a) install_dropbear ;; 2e) uninstall_dropbear ;;
            3a) install_slowdns ;; 3e) uninstall_slowdns ;;
            4a) install_ssl_tls ;; 4e) uninstall_ssl_tls ;;
            5a) install_sshws ;; 5e) uninstall_sshws ;;
            6a) install_wstunnel ;; 6e) uninstall_wstunnel ;;
            7a) install_sockspy ;; 7e) uninstall_sockspy ;;
            8a) install_socks_python ;; 8e) uninstall_socks_python ;;
            9a) install_ws_services ;; 9e) uninstall_ws_services ;;
            0) exit 0 ;;
            *) ;;
        esac
    done
}

check_root
main_menu
