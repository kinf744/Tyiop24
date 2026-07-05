# Kighmu Panel v4 - Commercial

Auto-installation sécurisée pour VPS : tunnels UDP, Xray/V2Ray, SSH.

## Fichiers

| Fichier | Rôle |
|---------|------|
| `install.sh` | Installation principale : dépendances, panel, nginx, nftables, cron |
| `udp.sh` | Tunnels UDP : ZIVPN, Hysteria v1/v2, BadVPN, UDP Custom |
| `xray-v2ray.sh` | Xray (VMess/VLESS/Trojan/Shadowsocks) + V2Ray (VLESS TCP) |
| `ssh.sh` | Tunnels SSH : Dropbear, SlowDNS, SSL/TLS, WS, SOCKS, wstunnel |

## Utilisation

```bash
git clone https://github.com/kinf744/Tyiop24.git
cd Tyiop24
chmod +x *.sh
./install.sh
```

## Sécurité
- NFTABLES validation via `nft -c -f`
- JWT + bcrypt pour le panel
- Secrets dans `.env` (chmod 600)
- Rate limiting sur les endpoints API
- Aucun secret hardcodé dans les scripts
- Tous les mots de passe utilisateur hashés
