#!/bin/bash
# Kighmu - Tunnels SSH
# OpenSSH, Dropbear, SlowDNS, SSL/TLS, WS, SOCKS, wstunnel
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
if ! declare -F log &>/dev/null; then
    log() { echo -e "${GREEN}[✓]${RESET} $*"; }
    warn() { echo -e "${YELLOW}[!]${RESET} $*"; }
    err() { echo -e "${RED}[✗]${RESET} $*"; }
fi
pause() { [[ -n "${SKIP_PAUSE:-}" ]] && return 0; echo; read -rp "Appuyez sur Entrée..."; }
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
    if command -v /usr/local/sbin/dropbear &>/dev/null; then
        if [[ ! -f /etc/systemd/system/dropbear-custom.service ]]; then
            warn "Dropbear binaire présent, service manquant — recréation..."
        else
            warn "Dropbear déjà installé"; pause; return
        fi
    else
        apt-get install -y -qq build-essential bzip2 zlib1g-dev wget tar dos2unix 2>/dev/null
        cd /usr/local/src
        wget -q "https://matt.ucc.asn.au/dropbear/releases/dropbear-2022.83.tar.bz2" -O dropbear-2022.83.tar.bz2 2>/dev/null || {
            err "Téléchargement échoué"; pause; return; }
        tar -xjf dropbear-2022.83.tar.bz2 2>/dev/null; cd dropbear-2022.83
        ./configure --prefix=/usr/local >/dev/null 2>&1; make -j"$(nproc)" >/dev/null 2>&1; make install >/dev/null 2>&1

        local DIR="/etc/dropbear"; mkdir -p "$DIR"
        for key in rsa ecdsa ed25519; do
            /usr/local/bin/dropbearkey -t "$key" -f "$DIR/dropbear_${key}_host_key" >/dev/null 2>&1 || true
        done
        chmod 600 "$DIR"/*_host_key 2>/dev/null || true
        echo "Bienvenue sur Kighmu - Connexion autorisée" > "$DIR/banner.txt"
    fi

    cat > /etc/systemd/system/dropbear-custom.service << 'UNIT'
[Unit]
Description=Dropbear Custom (port 109)
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
ExecStart=/usr/local/sbin/dropbear -F -E -p 109 -w -g -b /etc/dropbear/banner.txt -R
Restart=always
RestartSec=2
StartLimitIntervalSec=0
StartLimitBurst=0
User=root
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
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
    if command -v ssl_tls &>/dev/null; then
        if [[ ! -f /etc/systemd/system/ssl_tls.service ]]; then
            warn "ssl_tls binaire présent, service manquant — recréation..."
        else
            warn "ssl_tls déjà installé"; pause; return
        fi
    else
        apt-get install -y -qq curl 2>/dev/null
        local url="https://github.com/kinf744/Kighmu/releases/download/v1.0.0/ssl_tls"
        local tmp; tmp=$(mktemp -d)
        pushd "$tmp" >/dev/null || return 1
        curl -fsSL "$url" -o ssl_tls 2>/dev/null && chmod +x ssl_tls && file ssl_tls | grep -q ELF
        install -m 0755 ssl_tls /usr/local/bin/ssl_tls; popd >/dev/null 2>&1 || true; rm -rf "$tmp"
    fi

    cat > /etc/systemd/system/ssl_tls.service << 'UNIT'
[Unit]
Description=Tunnel SSL/TLS (ssl_tls)
After=network.target
Wants=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/ssl_tls -listen 444 -target-host 127.0.0.1 -target-port 109
Restart=always
RestartSec=2
StartLimitIntervalSec=0
StartLimitBurst=0
LimitNOFILE=1048576
StandardOutput=journal
StandardError=journal
[Install]
WantedBy=multi-user.target
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
    if command -v sshws &>/dev/null; then
        if [[ ! -f /etc/systemd/system/sshws.service ]]; then
            warn "sshws binaire présent, service manquant — recréation..."
        else
            warn "sshws déjà installé"; pause; return
        fi
    else
        local url="https://github.com/kinf744/Kighmu/releases/download/v1.0.0"
        local tmp; tmp=$(mktemp -d)
        pushd "$tmp" >/dev/null || return 1
        curl -LO "$url/sshws" 2>/dev/null && chmod +x sshws
        install -m 0755 sshws /usr/local/bin/sshws; popd >/dev/null 2>&1 || true; rm -rf "$tmp"
    fi

    cat > /etc/systemd/system/sshws.service << 'UNIT'
[Unit]
Description=SSHWS Slipstream Tunnel
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/sshws -listen 80 -target-host 127.0.0.1 -target-port 109
Restart=always
RestartSec=2
StartLimitIntervalSec=0
StartLimitBurst=0
User=root
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
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
    echo "${CYAN}━━━ Installation wstunnel (port 2082 → 22) ━━━${RESET}"
    command -v wstunnel &>/dev/null && { warn "wstunnel déjà installé"; pause; return; }
    apt-get install -y -qq wget 2>/dev/null
    local _cwd; _cwd=$(pwd)
    rm -rf /tmp/wstunnel_inst; mkdir -p /tmp/wstunnel_inst; cd /tmp/wstunnel_inst
    local url="https://github.com/erebe/wstunnel/releases/download/v10.5.1/wstunnel_10.5.1_linux_amd64.tar.gz"
    wget -q "$url" -O wstunnel.tar.gz 2>/dev/null
    tar -xzf wstunnel.tar.gz >/dev/null 2>&1; chmod +x wstunnel; mv wstunnel /usr/local/bin/wstunnel
    cd "$_cwd" 2>/dev/null || cd /; rm -rf /tmp/wstunnel_inst

    cat > /usr/local/bin/proxy--ws << 'PROXYEOF'
#!/usr/bin/env bash
DOMAIN="${DOMAIN:-0.0.0.0}"
exec /usr/local/bin/wstunnel server "ws://0.0.0.0:2082" --restrict-to "127.0.0.1:22"
PROXYEOF
    chmod +x /usr/local/bin/proxy--ws

    cat > /etc/systemd/system/proxy--ws.service << 'UNIT'
[Unit]
Description=Proxy WebSocket SSH (wstunnel)
After=network.target
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/proxy--ws
Restart=always
RestartSec=5
StartLimitIntervalSec=0
StartLimitBurst=0
KillMode=process
LimitNOFILE=1048576
StandardOutput=append:/var/log/proxy--ws.log
StandardError=append:/var/log/proxy--ws.err
[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload && systemctl enable --now proxy--ws.service 2>/dev/null || true
    deploy_nft_tunnel proxy-ws 'table inet proxy-ws { chain input { type filter hook input priority 0; policy accept; tcp dport 2082 accept; }; }'
    log "wstunnel actif (port 2082 → 22)"; pause
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
[Unit]
Description=Proxy SOCKS/Python WS
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/ws2_proxy.py 9090
Restart=always
RestartSec=5
StartLimitIntervalSec=0
StartLimitBurst=0
StandardOutput=journal
StandardError=journal
SyslogIdentifier=sockspy
LimitNOFILE=1048576
Nice=-5
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=99
[Install]
WantedBy=multi-user.target
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
    if [[ -n "${SKIP_PAUSE:-}" ]]; then PORT=9050; else read -rp "Port (1024-65535) [9050]: " PORT; PORT=${PORT:-9050}; fi
    [[ "$PORT" -lt 1024 || "$PORT" -gt 65535 ]] && { err "Port invalide"; pause; return; }
    echo "$PORT" > /etc/socks_python/socks_port.conf
    python3 -c "import socks" &>/dev/null || apt-get install -y -qq python3-socks 2>/dev/null || {
        python3 -m venv /root/socksenv 2>/dev/null; source /root/socksenv/bin/activate
        pip install pysocks >/dev/null 2>&1; deactivate
    }
    local url="https://raw.githubusercontent.com/kinf744/Kighmu/main/KIGHMUPROXY.py"
    wget -q -O /usr/local/bin/KIGHMUPROXY.py "$url" 2>/dev/null; chmod +x /usr/local/bin/KIGHMUPROXY.py

    cat > /etc/systemd/system/socks_python.service << UNIT
[Unit]
Description=Proxy SOCKS Python
After=network.target network-online.target
Wants=network-online.target
[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /usr/local/bin/KIGHMUPROXY.py $PORT
Restart=always
RestartSec=5
StartLimitIntervalSec=0
StartLimitBurst=0
StandardOutput=journal
StandardError=journal
SyslogIdentifier=socks-python-proxy
[Install]
WantedBy=multi-user.target
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
    rm -f /usr/local/bin/ws-dropbear /usr/local/bin/ws-stunnel
    cat > /usr/local/bin/ws-dropbear << 'PYEOF'
#!/usr/bin/env python3
import socket, threading, select, signal, sys, time, getopt

LISTENING_ADDR = '0.0.0.0'
LISTENING_PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 2095
PASS = ''
BUFLEN = 4096 * 4
TIMEOUT = 60
DEFAULT_HOST = '127.0.0.1:109'
RESPONSE = 'HTTP/1.1 101 <b><i><font color="green">WELCOME TO NETWORK TWEAKER</font></b>\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: foo\r\n\r\n'

class Server(threading.Thread):
    def __init__(self, host, port):
        threading.Thread.__init__(self)
        self.running = False
        self.host = host
        self.port = port
        self.threads = []
        self.threadsLock = threading.Lock()
        self.logLock = threading.Lock()

    def run(self):
        self.soc = socket.socket(socket.AF_INET)
        self.soc.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.soc.settimeout(2)
        self.soc.bind((self.host, self.port))
        self.soc.listen(0)
        self.running = True
        try:
            while self.running:
                try:
                    c, addr = self.soc.accept()
                    c.setblocking(1)
                except socket.timeout:
                    continue
                conn = ConnectionHandler(c, self, addr)
                conn.start()
                self.addConn(conn)
        finally:
            self.running = False
            self.soc.close()

    def printLog(self, log):
        self.logLock.acquire()
        print(log)
        self.logLock.release()

    def addConn(self, conn):
        try:
            self.threadsLock.acquire()
            if self.running:
                self.threads.append(conn)
        finally:
            self.threadsLock.release()

    def removeConn(self, conn):
        try:
            self.threadsLock.acquire()
            self.threads.remove(conn)
        finally:
            self.threadsLock.release()

    def close(self):
        try:
            self.running = False
            self.threadsLock.acquire()
            threads = list(self.threads)
            for c in threads:
                c.close()
        finally:
            self.threadsLock.release()

class ConnectionHandler(threading.Thread):
    def __init__(self, socClient, server, addr):
        threading.Thread.__init__(self)
        self.clientClosed = False
        self.targetClosed = True
        self.client = socClient
        self.client_buffer = b''
        self.server = server
        self.log = 'Connection: ' + str(addr)

    def close(self):
        try:
            if not self.clientClosed:
                self.client.shutdown(socket.SHUT_RDWR)
                self.client.close()
        except:
            pass
        finally:
            self.clientClosed = True
        try:
            if not self.targetClosed:
                self.target.shutdown(socket.SHUT_RDWR)
                self.target.close()
        except:
            pass
        finally:
            self.targetClosed = True

    def run(self):
        try:
            self.client_buffer = self.client.recv(BUFLEN)
            hostPort = self.findHeader(self.client_buffer, 'X-Real-Host')
            if hostPort == '':
                hostPort = DEFAULT_HOST
            split = self.findHeader(self.client_buffer, 'X-Split')
            if split != '':
                self.client.recv(BUFLEN)
            if hostPort != '':
                passwd = self.findHeader(self.client_buffer, 'X-Pass')
                if len(PASS) != 0 and passwd == PASS:
                    self.method_CONNECT(hostPort)
                elif len(PASS) != 0 and passwd != PASS:
                    self.client.send(b'HTTP/1.1 400 WrongPass!\r\n\r\n')
                elif hostPort.startswith('127.0.0.1') or hostPort.startswith('localhost'):
                    self.method_CONNECT(hostPort)
                else:
                    self.client.send(b'HTTP/1.1 403 Forbidden!\r\n\r\n')
            else:
                print('- No X-Real-Host!')
                self.client.send(b'HTTP/1.1 400 NoXRealHost!\r\n\r\n')
        except Exception as e:
            self.log += ' - error: ' + str(e)
            self.server.printLog(self.log)
        finally:
            self.close()
            self.server.removeConn(self)

    def findHeader(self, head, header):
        h = header.encode()
        aux = head.find(h + b': ')
        if aux == -1:
            return ''
        aux = head.find(b':', aux)
        head = head[aux+2:]
        aux = head.find(b'\r\n')
        if aux == -1:
            return ''
        return head[:aux].decode()

    def connect_target(self, host):
        i = host.find(':')
        if i != -1:
            port = int(host[i+1:])
            host = host[:i]
        else:
            port = int(sys.argv[1]) if len(sys.argv) > 1 else 2095
        (soc_family, soc_type, proto, _, address) = socket.getaddrinfo(host, port)[0]
        self.target = socket.socket(soc_family, soc_type, proto)
        self.targetClosed = False
        self.target.connect(address)

    def method_CONNECT(self, path):
        self.log += ' - CONNECT ' + path
        self.connect_target(path)
        self.client.sendall(RESPONSE.encode())
        self.client_buffer = b''
        self.server.printLog(self.log)
        self.doCONNECT()

    def doCONNECT(self):
        socs = [self.client, self.target]
        count = 0
        while True:
            count += 1
            try:
                (recv, _, err) = select.select(socs, [], socs, 3)
            except:
                break
            if err:
                break
            if recv:
                for in_ in recv:
                    try:
                        data = in_.recv(BUFLEN)
                        if data:
                            if in_ is self.target:
                                self.client.send(data)
                            else:
                                while data:
                                    byte = self.target.send(data)
                                    data = data[byte:]
                            count = 0
                        else:
                            return
                    except:
                        return

def main(host=LISTENING_ADDR, port=LISTENING_PORT):
    print("\n:-------PythonProxy-------:\n")
    print("Listening addr: " + LISTENING_ADDR)
    print("Listening port: " + str(LISTENING_PORT) + "\n")
    print(":-------------------------:\n")
    server = Server(LISTENING_ADDR, LISTENING_PORT)
    server.start()
    while True:
        try:
            time.sleep(2)
        except KeyboardInterrupt:
            print('Stopping...')
            server.close()
            break

if __name__ == '__main__':
    main()
PYEOF
    cat > /usr/local/bin/ws-stunnel << 'PYEOF2'
#!/usr/bin/env python3
import socket, threading, select, signal, sys, time, getopt

LISTENING_ADDR = '127.0.0.1'
LISTENING_PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 700
PASS = ''
BUFLEN = 4096 * 4
TIMEOUT = 60
DEFAULT_HOST = '127.0.0.1:69'
RESPONSE = 'HTTP/1.1 101 <b><i><font color="green">WELCOME TO NETWORK TWEAKER</font></b>\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: foo\r\n\r\n'

class Server(threading.Thread):
    def __init__(self, host, port):
        threading.Thread.__init__(self)
        self.running = False
        self.host = host
        self.port = port
        self.threads = []
        self.threadsLock = threading.Lock()
        self.logLock = threading.Lock()

    def run(self):
        self.soc = socket.socket(socket.AF_INET)
        self.soc.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.soc.settimeout(2)
        self.soc.bind((self.host, self.port))
        self.soc.listen(0)
        self.running = True
        try:
            while self.running:
                try:
                    c, addr = self.soc.accept()
                    c.setblocking(1)
                except socket.timeout:
                    continue
                conn = ConnectionHandler(c, self, addr)
                conn.start()
                self.addConn(conn)
        finally:
            self.running = False
            self.soc.close()

    def printLog(self, log):
        self.logLock.acquire()
        print(log)
        self.logLock.release()

    def addConn(self, conn):
        try:
            self.threadsLock.acquire()
            if self.running:
                self.threads.append(conn)
        finally:
            self.threadsLock.release()

    def removeConn(self, conn):
        try:
            self.threadsLock.acquire()
            self.threads.remove(conn)
        finally:
            self.threadsLock.release()

    def close(self):
        try:
            self.running = False
            self.threadsLock.acquire()
            threads = list(self.threads)
            for c in threads:
                c.close()
        finally:
            self.threadsLock.release()

class ConnectionHandler(threading.Thread):
    def __init__(self, socClient, server, addr):
        threading.Thread.__init__(self)
        self.clientClosed = False
        self.targetClosed = True
        self.client = socClient
        self.client_buffer = b''
        self.server = server
        self.log = 'Connection: ' + str(addr)

    def close(self):
        try:
            if not self.clientClosed:
                self.client.shutdown(socket.SHUT_RDWR)
                self.client.close()
        except:
            pass
        finally:
            self.clientClosed = True
        try:
            if not self.targetClosed:
                self.target.shutdown(socket.SHUT_RDWR)
                self.target.close()
        except:
            pass
        finally:
            self.targetClosed = True

    def run(self):
        try:
            self.client_buffer = self.client.recv(BUFLEN)
            hostPort = self.findHeader(self.client_buffer, 'X-Real-Host')
            if hostPort == '':
                hostPort = DEFAULT_HOST
            split = self.findHeader(self.client_buffer, 'X-Split')
            if split != '':
                self.client.recv(BUFLEN)
            if hostPort != '':
                passwd = self.findHeader(self.client_buffer, 'X-Pass')
                if len(PASS) != 0 and passwd == PASS:
                    self.method_CONNECT(hostPort)
                elif len(PASS) != 0 and passwd != PASS:
                    self.client.send(b'HTTP/1.1 400 WrongPass!\r\n\r\n')
                elif hostPort.startswith('127.0.0.1') or hostPort.startswith('localhost'):
                    self.method_CONNECT(hostPort)
                else:
                    self.client.send(b'HTTP/1.1 403 Forbidden!\r\n\r\n')
            else:
                print('- No X-Real-Host!')
                self.client.send(b'HTTP/1.1 400 NoXRealHost!\r\n\r\n')
        except Exception as e:
            self.log += ' - error: ' + str(e)
            self.server.printLog(self.log)
        finally:
            self.close()
            self.server.removeConn(self)

    def findHeader(self, head, header):
        h = header.encode()
        aux = head.find(h + b': ')
        if aux == -1:
            return ''
        aux = head.find(b':', aux)
        head = head[aux+2:]
        aux = head.find(b'\r\n')
        if aux == -1:
            return ''
        return head[:aux].decode()

    def connect_target(self, host):
        i = host.find(':')
        if i != -1:
            port = int(host[i+1:])
            host = host[:i]
        else:
            port = int(sys.argv[1]) if len(sys.argv) > 1 else 700
        (soc_family, soc_type, proto, _, address) = socket.getaddrinfo(host, port)[0]
        self.target = socket.socket(soc_family, soc_type, proto)
        self.targetClosed = False
        self.target.connect(address)

    def method_CONNECT(self, path):
        self.log += ' - CONNECT ' + path
        self.connect_target(path)
        self.client.sendall(RESPONSE.encode())
        self.client_buffer = b''
        self.server.printLog(self.log)
        self.doCONNECT()

    def doCONNECT(self):
        socs = [self.client, self.target]
        count = 0
        while True:
            count += 1
            try:
                (recv, _, err) = select.select(socs, [], socs, 3)
            except:
                break
            if err:
                break
            if recv:
                for in_ in recv:
                    try:
                        data = in_.recv(BUFLEN)
                        if data:
                            if in_ is self.target:
                                self.client.send(data)
                            else:
                                while data:
                                    byte = self.target.send(data)
                                    data = data[byte:]
                            count = 0
                        else:
                            return
                    except:
                        return

def main(host=LISTENING_ADDR, port=LISTENING_PORT):
    print("\n:-------PythonProxy-------:\n")
    print("Listening addr: " + LISTENING_ADDR)
    print("Listening port: " + str(LISTENING_PORT) + "\n")
    print(":-------------------------:\n")
    server = Server(LISTENING_ADDR, LISTENING_PORT)
    server.start()
    while True:
        try:
            time.sleep(2)
        except KeyboardInterrupt:
            print('Stopping...')
            server.close()
            break

if __name__ == '__main__':
    main()
PYEOF2
    chmod +x /usr/local/bin/ws-dropbear /usr/local/bin/ws-stunnel

    cat > /etc/systemd/system/ws-dropbear.service << 'UNIT'
[Unit]
Description=Websocket-Dropbear
After=network.target
[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 -O /usr/local/bin/ws-dropbear 2095
Restart=always
RestartSec=3s
StartLimitIntervalSec=0
StartLimitBurst=0
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
UNIT
    cat > /etc/systemd/system/ws-stunnel.service << 'UNIT2'
[Unit]
Description=WS Stunnel HTTPS
After=network.target
[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 -O /usr/local/bin/ws-stunnel 700
Restart=always
RestartSec=3s
StartLimitIntervalSec=0
StartLimitBurst=0
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
UNIT2
    systemctl daemon-reload
    systemctl enable --now ws-dropbear ws-stunnel 2>/dev/null || true

    if [[ -f /etc/nginx/sites-available/kighmu ]] && ! grep -q 'ws-dropbear' /etc/nginx/sites-available/kighmu 2>/dev/null; then
        sed -i '/listen 8585;/a\
\
    location /ws-dropbear {\
        proxy_pass http://127.0.0.1:2095;\
        proxy_http_version 1.1;\
        proxy_set_header Upgrade $http_upgrade;\
        proxy_set_header Connection "upgrade";\
        proxy_set_header Host $host;\
        proxy_set_header X-Real-IP $remote_addr;\
        proxy_read_timeout 86400;\
    }\
\
    location /ws-stunnel {\
        proxy_pass http://127.0.0.1:700;\
        proxy_http_version 1.1;\
        proxy_set_header Upgrade $http_upgrade;\
        proxy_set_header Connection "upgrade";\
        proxy_set_header Host $host;\
        proxy_set_header X-Real-IP $remote_addr;\
        proxy_read_timeout 86400;\
    }' /etc/nginx/sites-available/kighmu
        nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null || true
    fi
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
    echo "${CYAN}━━━ Installation SlowDNS (53→5353/5354 via slowdns-router) ━━━${RESET}"

    command -v dnstt-server &>/dev/null && { warn "SlowDNS déjà installé"; pause; return; }
    apt-get install -y -qq curl jq wget golang-go 2>/dev/null

    local DIR="/etc/slowdns"; mkdir -p "$DIR/ns4" "$DIR/nv4" /var/log/slowdns /root/Kighmu/slowdns-router
    local PUB_KEY; PUB_KEY=$(curl -s ipv4.icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')

    local DNSTT_PRIV="4ab3af05fc004cb69d50c89de2cd5d138be1c397a55788b8867088e801f7fcaa"
    local DNSTT_PUB="2cb39d63928451bd67f5954ffa5ac16c8d903562a10c4b21756de4f1a82d581c"
    printf '%s\n' "$DNSTT_PRIV" > "$DIR/server.key"; printf '%s\n' "$DNSTT_PUB" > "$DIR/server.pub"
    chmod 600 "$DIR/server.key"; chmod 644 "$DIR/server.pub"

    local tmp; tmp=$(mktemp)
    curl -fsSL "https://dnstt-server-client.s3.amazonaws.com/dnstt-server-linux-amd64" -o "$tmp" 2>/dev/null
    mv "$tmp" /usr/local/bin/dnstt-server; chmod +x /usr/local/bin/dnstt-server

    local NS4 NV4
    NS4=$(head -1 "$DIR/ns.conf" 2>/dev/null || echo "")
    NV4=$(head -1 "$DIR/nv4/ns.conf" 2>/dev/null || echo "")
    [[ -n "$NS4" && "$NS4" == *"."* ]] || NS4=""
    [[ -n "$NV4" && "$NV4" == *"."* ]] || NV4=""
    if [[ -z "$NS4" ]]; then
        read -rp "NS4 (ex: ns4.votre-domaine.com): " NS4; NS4=${NS4:-ns4.kighmu.local}
    fi
    if [[ -z "$NV4" ]]; then
        read -rp "NV4 (ex: vps-ns4.votre-domaine.com): " NV4; NV4=${NV4:-vps-ns4.kighmu.local}
    fi
    echo "$NS4" > "$DIR/ns.conf"
    echo "$NV4" > "$DIR/nv4/ns.conf"
    printf 'MODE=man\nNS4=%s\nNV4=%s\n' "$NS4" "$NV4" > "$DIR/install.env"

    cat > /usr/local/bin/slowdns-ns4-start.sh << STARTEOF
#!/bin/bash
NS=\$(cat $DIR/ns.conf)
exec /usr/local/bin/dnstt-server -udp 0.0.0.0:5353 -privkey-file $DIR/server.key \$NS 127.0.0.1:109
STARTEOF
    chmod +x /usr/local/bin/slowdns-ns4-start.sh

    cat > /usr/local/bin/slowdns-nv4-start.sh << STARTEOF
#!/bin/bash
NV4=\$(cat $DIR/nv4/ns.conf)
exec /usr/local/bin/dnstt-server -udp 0.0.0.0:5354 -privkey-file $DIR/server.key \$NV4 127.0.0.1:5401
STARTEOF
    chmod +x /usr/local/bin/slowdns-nv4-start.sh

    for svc in slowdns-ns4 slowdns-nv4; do
        cat > "/etc/systemd/system/${svc}.service" << UNIT
[Unit]
Description=SlowDNS $svc
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
ExecStartPre=/bin/sleep 5
ExecStart=/usr/local/bin/${svc}-start.sh
Restart=always
RestartSec=5
StartLimitIntervalSec=0
StartLimitBurst=0
LimitNOFILE=1048576
StandardOutput=append:/var/log/slowdns/${svc}.log
StandardError=append:/var/log/slowdns/${svc}.log
[Install]
WantedBy=multi-user.target
UNIT
        systemctl daemon-reload && systemctl enable --now "${svc}.service" 2>/dev/null || true
    done

    cat > /root/Kighmu/slowdns-router/main.go << 'GOEOF'
package main

import (
	"fmt"
	"log"
	"net"
	"os"
	"os/signal"
	"strings"
	"sync"
	"syscall"
	"time"
)

type route struct {
	domain string
	addr   *net.UDPAddr
}

type stats struct {
	mu      sync.Mutex
	total   int64
	routed  map[string]int64
	refused int64
	errors  int64
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" { return v }
	return fallback
}

func getEnvInt(key string, fallback int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := fmt.Sscanf(v, "%d", &fallback); n == 1 && err == nil { return fallback }
	}
	return fallback
}

func main() {
	listen := getEnv("LISTEN", "0.0.0.0:53")
	timeout := time.Duration(getEnvInt("TIMEOUT", 5)) * time.Second
	verbose := os.Getenv("VERBOSE") == "1"
	routesDef := getEnv("ROUTES", "")
	if routesDef == "" { log.Fatal("ROUTES required") }

	var routes []route
	for _, part := range strings.Split(routesDef, ",") {
		part = strings.TrimSpace(part)
		if part == "" { continue }
		eq := strings.IndexByte(part, '=')
		if eq < 1 { log.Fatalf("invalid route %%q", part) }
		domain := strings.ToLower(strings.TrimSuffix(part[:eq], "."))
		addr, err := net.ResolveUDPAddr("udp4", part[eq+1:])
		if err != nil { log.Fatalf("resolve: %%v", err) }
		routes = append(routes, route{domain: domain, addr: addr})
	}

	var st stats; st.routed = make(map[string]int64)
	laddr, _ := net.ResolveUDPAddr("udp4", listen)
	conn, err := net.ListenUDP("udp4", laddr)
	if err != nil { log.Fatalf("listen: %%v", err) }
	defer conn.Close()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM, syscall.SIGUSR1)
	go func() {
		for sig := range sigCh {
			if sig == syscall.SIGUSR1 { printStats(&st) } else { conn.Close(); return }
		}
	}()

	log.Printf("slowdns-router on %s", listen)
	for _, r := range routes { log.Printf("  %s -> %s", r.domain, r.addr) }

	buf := make([]byte, 4096)
	for {
		n, clientAddr, err := conn.ReadFromUDP(buf)
		if err != nil { break }
		st.mu.Lock(); st.total++; st.mu.Unlock()
		packet := make([]byte, n); copy(packet, buf[:n])
		go handle(conn, clientAddr, packet, routes, timeout, verbose, &st)
	}
	printStats(&st)
}

func handle(conn *net.UDPConn, clientAddr *net.UDPAddr, packet []byte, routes []route, timeout time.Duration, verbose bool, st *stats) {
	qname, err := extractQName(packet)
	if err != nil { return }
	qname = strings.ToLower(qname)
	if !strings.HasSuffix(qname, ".") { qname += "." }

	for _, r := range routes {
		if strings.HasSuffix(qname, r.domain+".") {
			resp, err := forward(packet, r.addr, timeout)
			if err != nil {
				st.mu.Lock(); st.errors++; st.mu.Unlock()
				sendRefused(conn, clientAddr, packet)
				return
			}
			st.mu.Lock(); st.routed[r.domain]++; st.mu.Unlock()
			conn.WriteToUDP(resp, clientAddr)
			return
		}
	}
	st.mu.Lock(); st.refused++; st.mu.Unlock()
	sendRefused(conn, clientAddr, packet)
}

func extractQName(packet []byte) (string, error) {
	if len(packet) < 12 { return "", fmt.Errorf("too short") }
	var labels []string; pos := 12
	for {
		if pos >= len(packet) { return "", fmt.Errorf("truncated") }
		length := int(packet[pos])
		if length == 0 { pos++; break }
		if length&0xC0 != 0 { return "", fmt.Errorf("compressed") }
		pos++
		if pos+length > len(packet) { return "", fmt.Errorf("overflow") }
		labels = append(labels, string(packet[pos:pos+length]))
		pos += length
	}
	return strings.Join(labels, "."), nil
}

func forward(packet []byte, backend *net.UDPAddr, timeout time.Duration) ([]byte, error) {
	bc, err := net.DialUDP("udp4", nil, backend)
	if err != nil { return nil, err }
	defer bc.Close()
	bc.SetDeadline(time.Now().Add(timeout))
	if _, err := bc.Write(packet); err != nil { return nil, err }
	resp := make([]byte, 4096)
	n, err := bc.Read(resp)
	if err != nil { return nil, err }
	out := make([]byte, n); copy(out, resp[:n])
	return out, nil
}

func sendRefused(conn *net.UDPConn, clientAddr *net.UDPAddr, req []byte) {
	if len(req) < 12 { return }
	resp := make([]byte, len(req)); copy(resp, req)
	resp[2] = (req[2] & 0x01) | 0x80
	resp[3] = 0x85; resp[6] = 0; resp[7] = 0
	resp[8] = 0; resp[9] = 0; resp[10] = 0; resp[11] = 0
	conn.WriteToUDP(resp, clientAddr)
}

func printStats(st *stats) {
	st.mu.Lock(); defer st.mu.Unlock()
	fmt.Fprintf(os.Stderr, "\n--- stats ---\ntotal: %d\n", st.total)
	for d, c := range st.routed { fmt.Fprintf(os.Stderr, "  %s: %d\n", d, c) }
	fmt.Fprintf(os.Stderr, "refused: %d\nerrors: %d\n------------\n", st.refused, st.errors)
}
GOEOF

    cd /root/Kighmu/slowdns-router && go build -o slowdns-router . 2>/dev/null
    cp slowdns-router /usr/local/bin/slowdns-router 2>/dev/null || true

    cat > /etc/systemd/system/slowdns-router.service << UNIT
[Unit]
Description=SlowDNS Go Router
After=network-online.target slowdns-ns4.service slowdns-nv4.service
Wants=network-online.target
StartLimitIntervalSec=0
[Service]
Type=simple
Environment=LISTEN=0.0.0.0:53
Environment=ROUTES=$NS4=127.0.0.1:5353,$NV4=127.0.0.1:5354
Environment=TIMEOUT=5
ExecStart=/usr/local/bin/slowdns-router
Restart=always
RestartSec=3
LimitNOFILE=1048576
KillMode=mixed
[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload && systemctl enable --now slowdns-router.service 2>/dev/null || true

    deploy_nft_tunnel slowdns 'table inet slowdns { chain prerouting { type nat hook prerouting priority -100; }; chain input { type filter hook input priority 0; policy accept; udp dport 53 accept; udp dport 5353 accept; udp dport 5354 accept; tcp dport 109 accept; tcp dport 5401 accept; }; }'

    chattr -i /etc/resolv.conf 2>/dev/null || true
    printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf
    chattr +i /etc/resolv.conf 2>/dev/null || true

    log "SlowDNS actif (53→5353/5354 via slowdns-router)"
    echo "   NS4: $NS4 → 127.0.0.1:109 (SSH)"
    echo "   NV4: $NV4 → 127.0.0.1:5401 (V2Ray)"
    pause
}

uninstall_slowdns() {
    read -rp "Confirmer ? (o/N): " C; [[ "$C" =~ ^[oO]$ ]] || return
    for svc in slowdns-ns4 slowdns-nv4 slowdns-router; do
        systemctl disable --now "$svc" 2>/dev/null || true
    done
    rm -f /etc/systemd/system/slowdns-ns4.service /etc/systemd/system/slowdns-nv4.service /etc/systemd/system/slowdns-router.service
    rm -f /usr/local/bin/dnstt-server /usr/local/bin/slowdns-router
    rm -f /usr/local/bin/slowdns-ns4-start.sh /usr/local/bin/slowdns-nv4-start.sh
    rm -rf /etc/slowdns /var/log/slowdns /root/Kighmu/slowdns-router
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
        echo "${WHITE}6. wstunnel (2082)${RESET}   ${GREEN}[6a]${RESET} Installer    ${GREEN}[6e]${RESET} Désinstaller"
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

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_root
    main_menu
fi
