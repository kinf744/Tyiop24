# Kighmu Panel v4 - Commercial

Auto-installation sécurisée pour VPS : tunnels UDP, Xray/V2Ray, SSH.

## Fichiers

| Fichier | Rôle |
|---------|------|
| `install.sh` | Installation principale : dépendances, panel, nginx, nftables, cron |
| `udp.sh` | Tunnels UDP : ZIVPN, Hysteria v1, BadVPN, UDP Custom |
| `xray-v2ray.sh` | Xray (VMess/VLESS/Trojan/Shadowsocks) + V2Ray (VLESS TCP) |
| `ssh.sh` | Tunnels SSH : Dropbear, SlowDNS, SSL/TLS, WS, SOCKS, wstunnel |
| `xray-fix.sh` | Diagnostic, réparation et watchdog permanent pour Xray |

## Utilisation

```bash
git clone https://github.com/kinf744/Tyiop24.git
cd Tyiop24
chmod +x *.sh
./install.sh
```

## Dépannage Xray

Si Xray est en panne (OFF dans le panneau) :

```bash
cd Tyiop24
bash xray-fix.sh
```

Le script `xray-fix.sh` diagnostique automatiquement le problème, répare la configuration, le binaire ou les certificats, et installe un watchdog permanent multi-couche :
- **Couche 1** : systemd Restart=always (redémarrage instantané)
- **Couche 2** : Cron toutes les 60 secondes
- **Couche 3** : systemd timer toutes les 2 minutes
- **Couche 4** : rc.local au boot

## Sécurité
- NFTABLES validation via `nft -c -f`
- JWT + bcrypt pour le panel
- Secrets dans `.env` (chmod 600)
- Rate limiting sur les endpoints API
- Aucun secret hardcodé dans les scripts
- Tous les mots de passe utilisateur hashés
