#!/bin/bash
# panel.sh - Web Panel Assets pour Kighmu VPN
# Contient package.json, server.js, admin.html, reseller.html, schema.sql
# Extrait par install.sh pendant l'installation

extract_web_panel() {
    local DIR="$1"
    [[ -z "$DIR" ]] && DIR="/opt/kighmu-panel"
    mkdir -p "$DIR/frontend/admin" "$DIR/frontend/reseller"

    # ── package.json ──
    cat > "$DIR/package.json" << 'PKGEOF'
{
  "name": "kighmu-panel",
  "version": "4.0.0",
  "private": true,
  "dependencies": {
    "express": "^4.18.2",
    "mysql2": "^3.6.0",
    "bcryptjs": "^2.4.3",
    "jsonwebtoken": "^9.0.2",
    "cors": "^2.8.5",
    "morgan": "^1.10.0",
    "axios": "^1.6.0",
    "dotenv": "^16.4.5",
    "uuid": "^9.0.1",
    "helmet": "^7.1.0",
    "express-rate-limit": "^7.1.5",
    "node-cron": "^3.0.3",
    "systeminformation": "^5.21.8"
  }
}
PKGEOF

    # ── server.js ──
    cat > "$DIR/server.js" << 'SRVEOF'
// ============================================================
// KIGHMU PANEL v2 - Backend complet
// ============================================================
'use strict';

const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });

const express   = require('express');
const mysql     = require('mysql2/promise');
const bcrypt    = require('bcryptjs');
const jwt       = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const helmet    = require('helmet');
const cors      = require('cors');
const rateLimit = require('express-rate-limit');
const cron      = require('node-cron');
const si        = require('systeminformation');
const fs        = require('fs');
const { exec }  = require('child_process');
const crypto    = require('crypto');

const REQUIRED_ENV = ['DB_USER', 'DB_PASSWORD', 'DB_NAME', 'JWT_SECRET'];
const missing = REQUIRED_ENV.filter(k => !process.env[k]);
if (missing.length) {
  console.error(`[FATAL] Variables .env manquantes : ${missing.join(', ')}`);
  process.exit(1);
}

const REPORT_SECRET_FILE = path.join(__dirname, '.report_secret');
const ENV_FILE = path.join(__dirname, '.env');
let REPORT_SECRET = process.env.REPORT_SECRET;
if (!REPORT_SECRET) {
  try { REPORT_SECRET = fs.readFileSync(REPORT_SECRET_FILE, 'utf8').trim(); } catch {}
  if (!REPORT_SECRET) {
    REPORT_SECRET = crypto.randomBytes(32).toString('hex');
    fs.writeFileSync(REPORT_SECRET_FILE, REPORT_SECRET, { mode: 0o600 });
    try { fs.appendFileSync(ENV_FILE, `\nREPORT_SECRET=${REPORT_SECRET}\n`); } catch {}
    console.log('[SECRET] REPORT_SECRET genere et ajoute au .env');
  }
}

function genNonce() { return crypto.randomBytes(16).toString('base64url'); }

// ============================================================
// VALIDATION & SANITIZATION HELPERS
// ============================================================
const USERNAME_RE = /^[a-zA-Z0-9][a-zA-Z0-9_-]{2,31}$/;
function validateUsername(u) { return typeof u === 'string' && u.length <= 32 && USERNAME_RE.test(u); }
function validateLen(v, max) { return typeof v === 'string' && v.length <= max; }
function escapeShell(arg) { return `'${String(arg).replace(/'/g, "'\\''")}'`; }
function sanitizeLog(obj) {
  if (!obj || typeof obj !== 'object') return obj;
  const sensitive = ['password','pass','token','secret','hash','authorization'];
  const clone = Array.isArray(obj) ? [...obj] : { ...obj };
  for (const k of Object.keys(clone)) {
    if (sensitive.some(s => k.toLowerCase().includes(s))) clone[k] = '***';
    else if (typeof clone[k] === 'object' && clone[k] !== null) clone[k] = sanitizeLog(clone[k]);
  }
  return clone;
}

const app = express();

let db;
async function initDB() {
  try {
    const pool = mysql.createPool({
      host:               process.env.DB_HOST     || '127.0.0.1',
      port:           parseInt(process.env.DB_PORT || '3306'),
      database:           process.env.DB_NAME,
      user:               process.env.DB_USER,
      password:           process.env.DB_PASSWORD,
      waitForConnections: true,
      connectionLimit:    20,
      queueLimit:         0,
      enableKeepAlive:    true,
      keepAliveInitialDelay: 0,
      connectTimeout:     10000,
    });
    pool.on('error', async (err) => {
      console.error('[DB] Pool error:', err.message);
    });
    const conn = await pool.getConnection();
    await conn.ping();
    conn.release();
    db = pool;
    console.log(`[DB] Connexion MySQL OK → ${process.env.DB_NAME}@${process.env.DB_HOST || '127.0.0.1'}`);
    return true;
  } catch (e) {
    console.error(`[DB] ERREUR connexion MySQL : ${e.message}`);
    return false;
  }
}

async function dbHealthCheck() {
  if (!db) return false;
  try {
    const conn = await db.getConnection();
    await conn.ping();
    conn.release();
    return true;
  } catch {
    console.error('[DB] Health check FAILED - tentative reconnexion...');
    try { await initDB(); } catch (e) { console.error('[DB] Reconnexion echouee:', e.message); }
    return false;
  }
}

// ── NONCE generator middleware ───────────────────────────────
const nonceMiddleware = (req, res, next) => {
  req.nonce = genNonce();
  res.locals.nonce = req.nonce;
  next();
};
app.use(nonceMiddleware);

app.use(helmet({
  contentSecurityPolicy: {
    useDefaults: false,
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'", (req) => `'nonce-${req.nonce}'`, 'https://cdnjs.cloudflare.com', 'https://cdn.jsdelivr.net'],
      scriptSrcAttr: ["'unsafe-inline'"],
      styleSrc: ["'self'", "'unsafe-inline'", 'https://fonts.googleapis.com', 'https://cdnjs.cloudflare.com'],
      imgSrc: ["'self'", "data:"],
      connectSrc: ["'self'", 'https://fonts.googleapis.com'],
      fontSrc: ["'self'", 'https://fonts.gstatic.com', 'https://cdnjs.cloudflare.com'],
      objectSrc: ["'none'"],
      mediaSrc: ["'none'"],
      frameSrc: ["'none'"],
      formAction: ["'self'"],
      baseUri: ["'self'"],
    }
  },
  referrerPolicy: { policy: 'strict-origin-when-cross-origin' },
  hsts: false,
  noSniff: true,
  xssFilter: true,
}));

const CORS_ORIGIN = process.env.CORS_ORIGIN || null;
app.use(cors({
  origin: CORS_ORIGIN
    ? CORS_ORIGIN.split(',').map(s => s.trim())
    : function (origin, cb) {
        if (!origin || origin === 'null') return cb(null, false);
        cb(null, origin);
      },
}));

app.use(express.json({ limit: '10kb' }));
app.set('trust proxy', 1);

const globalLimiter = rateLimit({ windowMs: 15 * 60 * 1000, max: 500, standardHeaders: true, legacyHeaders: false });
app.use(globalLimiter);

const loginLimiter    = rateLimit({ windowMs: 15 * 60 * 1000, max: 20, standardHeaders: true, legacyHeaders: false, message: { error: 'Trop de tentatives de connexion. Réessayez plus tard.' } });
const writeLimiter    = rateLimit({ windowMs: 15 * 60 * 1000, max: 60, standardHeaders: true, legacyHeaders: false, message: { error: 'Trop de requetes. Reessayez plus tard.' } });
const authWriteLimiter = rateLimit({ windowMs: 15 * 60 * 1000, max: 30, standardHeaders: true, legacyHeaders: false, message: { error: 'Trop de requetes. Reessayez plus tard.' } });

app.get('/health', (req, res) => {
  res.json({ status: db ? 'ok' : 'db_error', uptime: Math.floor(process.uptime()) + 's', db: db ? 'connected' : 'disconnected', time: new Date().toISOString() });
});

app.use('/api', (req, res, next) => {
  if (!db) return res.status(503).json({ error: 'Base de données non connectée. Vérifiez MySQL.' });
  next();
});

const FIELD_MAX = { username: 32, password: 128, note: 500, tunnel_type: 32 };
function validateFields(body) {
  for (const [field, maxLen] of Object.entries(FIELD_MAX)) {
    if (body[field] !== undefined && body[field] !== null) {
      if (typeof body[field] !== 'string') continue;
      if (body[field].length > maxLen) {
        throw new Error(`Le champ "${field}" ne doit pas depasser ${maxLen} caracteres`);
      }
    }
  }
}
const inputValidation = (req, res, next) => {
  try {
    if (req.body && typeof req.body === 'object') validateFields(req.body);
    next();
  } catch (e) { res.status(400).json({ error: e.message }); }
};
app.use('/api', inputValidation);

const FRONTEND = path.join(__dirname, 'frontend');
if (!fs.existsSync(FRONTEND)) {
  console.error(`[STATIC] ERREUR : dossier frontend introuvable → ${FRONTEND}`);
}

// ============================================================
// BRUTE-FORCE
// ============================================================
const MAX_ATT   = parseInt(process.env.MAX_LOGIN_ATTEMPTS   || '5');
const BLOCK_MIN = parseInt(process.env.BLOCK_DURATION_MINUTES || '30');

async function checkBruteForce(ip) {
  try {
    const [rows] = await db.query('SELECT * FROM login_attempts WHERE ip_address = ?', [ip]);
    if (!rows.length) return null;
    const r = rows[0];
    if (r.blocked_until && new Date(r.blocked_until) > new Date()) {
      const mins = Math.ceil((new Date(r.blocked_until) - new Date()) / 60000);
      return `IP bloquée. Réessayez dans ${mins} min.`;
    }
    if (r.attempts >= MAX_ATT) {
      const until = new Date(Date.now() + BLOCK_MIN * 60000);
      await db.query('UPDATE login_attempts SET blocked_until=?, last_attempt=NOW() WHERE ip_address=?', [until, ip]);
      return `Trop de tentatives. IP bloquée ${BLOCK_MIN} minutes.`;
    }
    return null;
  } catch { return null; }
}
async function failAttempt(ip) {
  try {
    const [r] = await db.query('SELECT id FROM login_attempts WHERE ip_address=?', [ip]);
    if (r.length) await db.query('UPDATE login_attempts SET attempts=attempts+1, last_attempt=NOW() WHERE ip_address=?', [ip]);
    else await db.query('INSERT INTO login_attempts (ip_address) VALUES (?)', [ip]);
  } catch {}
}
async function clearAttempts(ip) {
  try { await db.query('DELETE FROM login_attempts WHERE ip_address=?', [ip]); } catch {}
}

// ============================================================
// JWT MIDDLEWARE
// ============================================================
function auth(roles = []) {
  return async (req, res, next) => {
    try {
      const header = req.headers.authorization || '';
      const token  = header.startsWith('Bearer ') ? header.slice(7) : null;
      if (!token) return res.status(401).json({ error: 'Token manquant' });
      const decoded = jwt.verify(token, process.env.JWT_SECRET);
      if (roles.length && !roles.includes(decoded.role))
        return res.status(403).json({ error: 'Accès refusé' });
      if (decoded.role === 'reseller') {
        const [[r]] = await db.query('SELECT is_active, expires_at FROM resellers WHERE id=?', [decoded.id]);
        if (!r || !r.is_active) return res.status(401).json({ error: 'Compte désactivé' });
        if (new Date(r.expires_at) < new Date()) {
          await cleanupReseller(decoded.id);
          await db.query('DELETE FROM resellers WHERE id=?', [decoded.id]);
          return res.status(401).json({ error: 'Compte expiré — accès révoqué' });
        }
      }
      req.user = decoded;
      next();
    } catch (e) {
      return res.status(401).json({ error: 'Token invalide ou expiré' });
    }
  };
}

// ============================================================
// LOGGER
// ============================================================
async function log(actorType, actorId, action, targetType, targetId, details, ip) {
  try {
    await db.query(
      'INSERT INTO activity_logs (actor_type,actor_id,action,target_type,target_id,details,ip_address) VALUES (?,?,?,?,?,?,?)',
      [actorType, actorId, action, targetType||null, targetId||null, details ? JSON.stringify(sanitizeLog(details)) : null, ip||null]
    );
  } catch {}
}

// ============================================================
// TUNNEL MANAGER
// ============================================================
const execAsync = (cmd) => new Promise((res, rej) =>
  exec(cmd, { timeout: 10000 }, (e, out, err) => e ? rej(new Error(err || e.message)) : res(out))
);
const readJson  = (p) => { try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch { return null; } };
const writeJson = (p, d) => { try { fs.writeFileSync(p, JSON.stringify(d, null, 2)); } catch(e) { console.error(`[TUNNEL] writeJson(${p}):`, e.message); } };

async function restartService(svc) {
  try { await execAsync(`systemctl restart ${svc}`); return true; }
  catch (e) { console.error(`[TUNNEL] restart ${svc}:`, e.message); return false; }
}

// ── Synchronise /etc/xray/users.json avec les créations/suppressions du panel ──
// Ce fichier est lu par menu_6.sh pour afficher et gérer les utilisateurs.
// Format attendu : { "vmess": [...], "vless": [...], "trojan": [...] }
// ⚠️ Xray attend "id" pour vmess/vless et "password" pour trojan — PAS "uuid"
function _xraySyncUsersJson(username, proto, uuid, action) {
  const usersPath = '/etc/xray/users.json';
  try {
    let data = readJson(usersPath) || { vmess: [], vless: [], trojan: [] };
    if (!data.vmess)  data.vmess  = [];
    if (!data.vless)  data.vless  = [];
    if (!data.trojan) data.trojan = [];

    if (action === 'add') {
      const idKey = proto === 'trojan' ? 'password' : 'id';
      const already = data[proto]?.some(u => u[idKey] === uuid || u.email === username || u.name === username);
      if (!already) {
        const tag = `${proto}_${username}_${uuid.slice(0, 8)}`;
        const entry = {
          email:    tag,
          name:     username,
          tag:      tag,
          limit_gb: 0,
          used_gb:  0,
          expire:   'N/A'
        };
        entry[idKey] = uuid;
        data[proto].push(entry);
        writeJson(usersPath, data);
        console.log(`[XRAY-SYNC] users.json : ajout ${proto}/${username} (${idKey})`);
      }
    } else if (action === 'remove') {
      const idKey = proto === 'trojan' ? 'password' : 'id';
      const before = (data[proto] || []).length;
      data[proto] = (data[proto] || []).filter(u => u[idKey] !== uuid && u.name !== username && u.email !== username);
      if (data[proto].length !== before) {
        writeJson(usersPath, data);
        console.log(`[XRAY-SYNC] users.json : suppression ${proto}/${username}`);
      }
    }
  } catch (e) {
    console.error(`[XRAY-SYNC] Erreur sync users.json (${action} ${username}):`, e.message);
  }
}

function xrayAdd(username, protocol, uuid) {
  const cfgPath = process.env.XRAY_CONFIG || '/etc/xray/config.json';
  const cfg = readJson(cfgPath);
  if (!cfg) return { ok: false, msg: `config xray introuvable : ${cfgPath}` };

  // Trouver TOUS les inbounds du protocole (vmess-ws-tls, vmess-grpc, vmess-ws-ntls, etc.)
  const proto = protocol.toLowerCase();
  const inbounds = cfg.inbounds?.filter(i => i.protocol === proto) || [];
  if (!inbounds.length) return { ok: false, msg: `inbound ${protocol} introuvable dans xray config` };

  let added = 0;
  for (const inb of inbounds) {
    if (!inb.settings) inb.settings = {};
    if (!inb.settings.clients) inb.settings.clients = [];

    // Ne pas dupliquer si déjà présent (par uuid ou email/password)
    const alreadyExists = proto === 'trojan'
      ? inb.settings.clients.some(c => c.password === uuid || c.email === username)
      : inb.settings.clients.some(c => c.id === uuid || c.email === username);

    if (alreadyExists) continue;

    // IMPORTANT : pour Trojan, password = uuid (cohérent avec menu_6.sh)
    const client = proto === 'trojan'
      ? { password: uuid, level: 0, email: username }
      : { id: uuid, level: 0, email: username, alterId: proto === 'vmess' ? 0 : undefined };

    // Supprimer les clés undefined pour un JSON propre
    Object.keys(client).forEach(k => client[k] === undefined && delete client[k]);

    inb.settings.clients.push(client);
    added++;
  }

  writeJson(cfgPath, cfg);
  console.log(`[XRAY] xrayAdd(${username}, ${proto}): ${added} inbound(s) mis à jour sur ${inbounds.length}`);

  // ── Synchroniser /etc/xray/users.json (lu par menu_6.sh) ────────────────
  _xraySyncUsersJson(username, proto, uuid, 'add');

  return { ok: true, inbounds_updated: added };
}

function xrayRemove(username, protocol, uuid) {
  const cfgPath = process.env.XRAY_CONFIG || '/etc/xray/config.json';
  const cfg = readJson(cfgPath);
  if (!cfg) return;

  // Supprimer le client dans TOUS les inbounds du protocole
  const proto = protocol.toLowerCase();
  const inbounds = cfg.inbounds?.filter(i => i.protocol === proto) || [];
  for (const inb of inbounds) {
    if (!inb?.settings?.clients) continue;
    if (proto === 'trojan') {
      // Trojan : password = uuid, email = username
      inb.settings.clients = inb.settings.clients.filter(
        c => c.password !== uuid && c.email !== username
      );
    } else {
      // VMess / VLESS : id = uuid, email = username
      inb.settings.clients = inb.settings.clients.filter(
        c => c.id !== uuid && c.email !== username
      );
    }
  }
  writeJson(cfgPath, cfg);
  console.log(`[XRAY] xrayRemove(${username}, ${proto}): supprimé dans ${inbounds.length} inbound(s)`);

  // ── Synchroniser /etc/xray/users.json (lu par menu_6.sh) ────────────────
  _xraySyncUsersJson(username, proto, uuid, 'remove');
}

// ============================================================
// SSH NFTABLES — comptage trafic par UID
// ============================================================
const SSH_DELTA_DIR = '/var/lib/kighmu/ssh-counters';
try { fs.mkdirSync(SSH_DELTA_DIR, { recursive: true }); } catch {}
const NFT = '/usr/sbin/nft';

async function ensureKighmuTable() {
  await execAsync('bash /usr/local/bin/init-nftables-kighmu.sh');
}

async function sshNftablesAdd(username) {
  try {
    await ensureKighmuTable();
    if (!validateUsername(username)) { console.error(`[SSH-RULES] skip: username invalide: ${username}`); return; }
    const safeUser = escapeShell(username);
    const uidRaw = await execAsync(`id -u ${safeUser} 2>/dev/null`);
    const uid = uidRaw.trim();
    if (!uid || !/^\d+$/.test(uid)) return;
    const tag = `ssh_${uid}`;
    const exists = await execAsync(`${NFT} list counter inet kighmu ${tag}_out 2>/dev/null`).catch(() => '');
    if (exists) return;
    await execAsync(`${NFT} add counter inet kighmu ${tag}_out`);
    await execAsync(`${NFT} add counter inet kighmu ${tag}_in`);
    await execAsync(`${NFT} add rule inet kighmu output skuid ${uid} ct state new ct mark set ${uid} comment \"${tag}\"`);
    await execAsync(`${NFT} add rule inet kighmu output skuid ${uid} counter name \"${tag}_out\" accept comment \"${tag}\"`);
    await execAsync(`${NFT} add rule inet kighmu input ct mark ${uid} counter name \"${tag}_in\" accept comment \"${tag}\"`);
    const curOut = await _readNftablesCounter(`${tag}_out`);
    const curIn  = await _readNftablesCounter(`${tag}_in`);
    fs.writeFileSync(`${SSH_DELTA_DIR}/${username}.out`, String(curOut));
    fs.writeFileSync(`${SSH_DELTA_DIR}/${username}.in`,  String(curIn));
    console.log(`[SSH-RULES] regles nftables creees pour ${username} (uid=${uid})`);
  } catch (e) {
    console.error(`[SSH-RULES] Erreur sshNftablesAdd(${username}):`, e.message);
  }
}

async function sshNftablesRemove(username) {
  try {
    if (!validateUsername(username)) { console.error(`[SSH-RULES] skip remove: username invalide: ${username}`); return; }
    const safeUser = escapeShell(username);
    const uidRaw = await execAsync(`id -u ${safeUser} 2>/dev/null`).catch(() => '');
    const uid = uidRaw.trim();
    if (uid && /^\d+$/.test(uid)) {
      const tag = `ssh_${uid}`;
      await execAsync(`${NFT} delete counter inet kighmu ${tag}_out 2>/dev/null || true`);
      await execAsync(`${NFT} delete counter inet kighmu ${tag}_in 2>/dev/null || true`);
      for (const chain of ['output', 'input']) {
        const handle = await execAsync(
          `${NFT} -a list chain inet kighmu ${chain} 2>/dev/null | grep 'comment "${tag}"' | grep -oP 'handle \\\\K\\\\d+' | tail -1`
        ).catch(() => '');
        if (handle && /^\d+$/.test(handle.trim())) {
          await execAsync(`${NFT} delete rule inet kighmu ${chain} handle ${handle.trim()}`);
        }
      }
    }
    try { fs.unlinkSync(`${SSH_DELTA_DIR}/${username}.out`); } catch {}
    try { fs.unlinkSync(`${SSH_DELTA_DIR}/${username}.in`);  } catch {}
    console.log(`[SSH-RULES] regles supprimees pour ${username}`);
  } catch (e) {
    console.error(`[SSH-RULES] Erreur sshNftablesRemove(${username}):`, e.message);
  }
}

async function _readNftablesCounter(name) {
  try {
    const out = await execAsync(`${NFT} list counter inet kighmu ${name} 2>/dev/null`);
    const m = out.match(/bytes\s+(\d+)/);
    return m ? parseInt(m[1]) : 0;
  } catch { return 0; }
}

// ── Synchroniser udp-custom/config.json avec /etc/kighmu/users.list ──
async function syncUdpCustom() {
  const udpCfgPath  = '/etc/udp-custom/config.json';
  const userFile    = '/etc/kighmu/users.list';
  if (!fs.existsSync(udpCfgPath) || !fs.existsSync(userFile)) return;
  const cfg = JSON.parse(fs.readFileSync(udpCfgPath, 'utf8'));
  const passwords = fs.readFileSync(userFile, 'utf8')
    .split('\n')
    .filter(l => l.trim())
    .map(l => l.split('|')[1])
    .filter(Boolean);
  cfg.auth = cfg.auth || {};
  cfg.auth.config = passwords;
  fs.writeFileSync(udpCfgPath, JSON.stringify(cfg, null, 2));
  await execAsync('systemctl restart udp-custom').catch(() => {});
  console.log(`[UDP-CUSTOM] ${passwords.length} mots de passe synchronisés`);
}

async function sshAdd(username, password, expiryDate) {
  const os  = require('os');
  const path = require('path');
  const tmp  = path.join(os.tmpdir(), `kighmu_ssh_${Date.now()}_${Math.random().toString(36).slice(2)}.sh`);

  try {
    const exp = new Date(expiryDate).toISOString().split('T')[0];
    const readF = p => { try { return fs.readFileSync(p, 'utf8').trim(); } catch { return ''; } };

    // Lire DOMAIN (priorité : domaine réel sur IP brute)
    const parseKV2 = (p, key) => {
      try {
        const txt = fs.readFileSync(p, 'utf8');
        const m = txt.match(new RegExp('^' + key + '=(.+)$', 'm'));
        return m && m[1].trim() ? m[1].trim() : '';
      } catch { return ''; }
    };
    const isIP = v => /^\d+\.\d+\.\d+\.\d+$/.test(v);
    const getDomain = () => {
      const sources = [
        readF('/etc/kighmu/domain.txt'),
        parseKV2(`${process.env.HOME || '/root'}/.kighmu_info`, 'DOMAIN'),
        parseKV2('/opt/kighmu-panel/.install_info', 'DOMAIN'),
        readF('/etc/xray/domain'),
        readF('/tmp/.xray_domain'),
      ];
      // Préférer un vrai domaine (non-IP) en premier
      return sources.find(v => v && !isIP(v))
          || sources.find(v => v) // sinon première valeur non vide
          || '';
    };

    const domain    = getDomain();
    const slowdnsNs = readF('/etc/slowdns/ns.conf') || readF('/etc/slowdns_v2ray/ns.conf') || '';
    let hostIp = '';
    try { const nets = await si.networkInterfaces(); const eth = nets.find(n => !n.internal && n.ip4); hostIp = eth ? eth.ip4 : ''; } catch {}
    const limite = Math.max(1, Math.round((new Date(exp) - new Date()) / 86400000));

    const bannerPath  = '/etc/ssh/sshd_banner';
    const kighmuDir   = '/etc/kighmu';
    const userFile    = `${kighmuDir}/users.list`;
    // zivpnUF/hyUF supprimés — SSH n'interagit plus avec ZIVPN/Hysteria

    // ── Script bash unique, identique à menu1.sh ────────────────
    // Le mot de passe est injecté via heredoc → aucun problème de
    // caractères spéciaux ($, !, ", `, \, espaces, etc.)
    const script = `#!/bin/bash
# Généré par Kighmu Panel — création utilisateur SSH
set -e

USERNAME="${username}"
EXPIRE_DATE="${exp}"
BANNER_PATH="${bannerPath}"
USER_HOME="/home/${username}"

# ── 1. Créer l'utilisateur système (identique à menu1.sh) ──
if id "$USERNAME" &>/dev/null; then
  echo "[SSH] Utilisateur $USERNAME existe déjà — mise à jour mot de passe"
else
  useradd -m -s /bin/bash "$USERNAME"
  echo "[SSH] Utilisateur $USERNAME créé"
fi

# ── 2. Définir le mot de passe via heredoc (sûr pour tous caractères) ──
chpasswd << 'CHPASSWD_EOF'
${username}:${password}
CHPASSWD_EOF

# ── 3. Date d'expiration ──
chage -E "$EXPIRE_DATE" "$USERNAME"

# ── 4. Répertoire home + .bashrc avec banner ──
if [ ! -d "$USER_HOME" ]; then
  mkdir -p "$USER_HOME"
  chown "$USERNAME":"$USERNAME" "$USER_HOME"
fi

cat > "$USER_HOME/.bashrc" << 'BASHRC_EOF'
# Affichage du banner Kighmu VPS Manager
if [ -f ${bannerPath} ]; then
    cat ${bannerPath}
fi
BASHRC_EOF

chown "$USERNAME":"$USERNAME" "$USER_HOME/.bashrc"
chmod 644 "$USER_HOME/.bashrc"

echo "[SSH] Utilisateur $USERNAME configuré avec succès"
`;

    fs.writeFileSync(tmp, script, { mode: 0o700 });
    await execAsync(`bash ${tmp}`);

    // ── users.list ───────────────────────────────────────────────
    try {
      if (!fs.existsSync(kighmuDir)) fs.mkdirSync(kighmuDir, { recursive: true });
      let lines = fs.existsSync(userFile)
        ? fs.readFileSync(userFile, 'utf8').split('\n').filter(l => l.trim() && !l.startsWith(`${username}|`))
        : [];
      lines.push(`${username}|${password}|${limite}|${exp}|${hostIp}|${domain}|${slowdnsNs}`);
      fs.writeFileSync(userFile, lines.join('\n') + '\n');
      fs.chmodSync(userFile, 0o600);
    } catch (e2) { console.error('[SSH] Erreur users.list:', e2.message); }

    // NOTE: ZIVPN et Hysteria sont des tunnels UDP indépendants.
    // Un user ssh-multi/ssh-ws/etc. ne doit PAS être ajouté dans ces configs.
    // Seuls les tunnel_type 'udp-zivpn' et 'udp-hysteria' utilisent ces services.
    await sshNftablesAdd(username);
    return { ok: true };

  } catch (e) {
    console.error(`[SSH] sshAdd ERREUR pour ${username}:`, e.message);
    return { ok: false, msg: e.message };
  } finally {
    try { fs.unlinkSync(tmp); } catch {}
  }
}

async function sshRemove(username) {
  try {
    await sshNftablesRemove(username);
    if (!validateUsername(username)) { console.error(`[SSH] skip remove: username invalide: ${username}`); return; }
    const safeUser = escapeShell(username);
    await execAsync(`userdel -r ${safeUser} 2>/dev/null || true`);
    // Nettoyage /etc/kighmu/users.list
    try {
      const userFile = '/etc/kighmu/users.list';
      if (fs.existsSync(userFile)) {
        const lines = fs.readFileSync(userFile, 'utf8').split('\n').filter(l => l.trim() && !l.startsWith(`${username}|`));
        fs.writeFileSync(userFile, lines.join('\n') + '\n');
      }
    } catch (e2) { console.error('[SSH] Erreur suppression /etc/kighmu/users.list:', e2.message); }
    // ── Synchroniser udp-custom après suppression ────────────────
    try { await syncUdpCustom(); } catch (e3) { console.error('[SSH] udp-custom sync:', e3.message); }
    // NOTE: Ne pas toucher ZIVPN/Hysteria — ce sont des tunnels UDP indépendants.
  } catch {}
}

async function sshLock(username) {
  try {
    if (!validateUsername(username)) return { ok: false, msg: 'username invalide' };
    const safeUser = escapeShell(username);
    await execAsync(`passwd -l ${safeUser} 2>/dev/null || true`);
    return { ok: true };
  } catch (e) { return { ok: false, msg: 'erreur lors du verrouillage' }; }
}

async function sshUnlock(username) {
  try {
    if (!validateUsername(username)) return { ok: false, msg: 'username invalide' };
    const safeUser = escapeShell(username);
    await execAsync(`passwd -u ${safeUser} 2>/dev/null || true`);
    return { ok: true };
  } catch (e) { return { ok: false, msg: 'erreur lors du deverrouillage' }; }
}

// ── Recrée les règles nftables SSH pour tous les clients actifs après reboot ──
async function syncAllSshRules() {
  try {
    const [rows] = await db.query(
      `SELECT username FROM clients WHERE tunnel_type LIKE 'ssh-%' AND is_active=1 AND expires_at >= NOW()`
    );
    let ok = 0;
    for (const r of rows) {
      try { await sshNftablesAdd(r.username); ok++; } catch {}
    }
    console.log(`[SSH-RULES] Sync apres reboot : ${ok}/${rows.length} regles nftables restaurees`);
  } catch (e) {
    console.error('[SSH-RULES] Sync error:', e.message);
  }
}

function zivpnAdd(username, password, expiresAt) {
  try {
    const userFile = '/etc/zivpn/users.list';
    const cfgFile  = '/etc/zivpn/config.json';
    if (!fs.existsSync('/etc/zivpn')) return { ok: false, msg: 'ZIVPN non installé (/etc/zivpn manquant)' };
    const expire = expiresAt ? new Date(expiresAt).toISOString().split('T')[0] : '2099-12-31';
    let lines = [];
    if (fs.existsSync(userFile)) {
      lines = fs.readFileSync(userFile, 'utf8').split('\n').filter(l => l.trim() && !l.startsWith(`${username}|`));
    }
    lines.push(`${username}|${password}|${expire}`);
    fs.writeFileSync(userFile, lines.join('\n') + '\n');
    fs.chmodSync(userFile, 0o600);
    _zivpnSyncConfig(userFile, cfgFile);
    return { ok: true };
  } catch (e) { return { ok: false, msg: e.message }; }
}

function zivpnRemove(username) {
  try {
    const userFile = '/etc/zivpn/users.list';
    const cfgFile  = '/etc/zivpn/config.json';
    if (!fs.existsSync(userFile)) return;
    const lines = fs.readFileSync(userFile, 'utf8').split('\n').filter(l => l.trim() && !l.startsWith(`${username}|`));
    fs.writeFileSync(userFile, lines.join('\n') + '\n');
    _zivpnSyncConfig(userFile, cfgFile);
  } catch {}
}

function _zivpnSyncConfig(userFile, cfgFile) {
  try {
    if (!fs.existsSync(cfgFile)) return;
    const today = new Date().toISOString().split('T')[0];
    const passwords = fs.readFileSync(userFile, 'utf8').split('\n')
      .filter(l => l.trim()).map(l => l.split('|'))
      .filter(p => p.length >= 3 && p[2] >= today).map(p => p[1])
      .filter((v, i, a) => a.indexOf(v) === i);
    const cfg = JSON.parse(fs.readFileSync(cfgFile, 'utf8'));
    if (!cfg.auth) cfg.auth = { mode: 'passwords', config: [] };
    cfg.auth.config = passwords.length > 0 ? passwords : ['zi'];
    fs.writeFileSync(cfgFile, JSON.stringify(cfg, null, 2));
  } catch (e) { console.error('[ZIVPN] sync config error:', e.message); }
}

function hysteriaAdd(username, password, expiresAt) {
  try {
    const userFile = '/etc/hysteria/users.txt';
    const cfgFile  = '/etc/hysteria/config.json';
    if (!fs.existsSync('/etc/hysteria')) return { ok: false, msg: 'Hysteria non installé (/etc/hysteria manquant)' };
    const expire = expiresAt ? new Date(expiresAt).toISOString().split('T')[0] : '2099-12-31';
    let lines = [];
    if (fs.existsSync(userFile)) {
      lines = fs.readFileSync(userFile, 'utf8').split('\n').filter(l => l.trim() && !l.startsWith(`${username}|`));
    }
    lines.push(`${username}|${password}|${expire}`);
    fs.writeFileSync(userFile, lines.join('\n') + '\n');
    fs.chmodSync(userFile, 0o600);
    _hysteriaSyncConfig(userFile, cfgFile);
    return { ok: true };
  } catch (e) { return { ok: false, msg: e.message }; }
}

function hysteriaRemove(username) {
  try {
    const userFile = '/etc/hysteria/users.txt';
    const cfgFile  = '/etc/hysteria/config.json';
    if (!fs.existsSync(userFile)) return;
    const lines = fs.readFileSync(userFile, 'utf8').split('\n').filter(l => l.trim() && !l.startsWith(`${username}|`));
    fs.writeFileSync(userFile, lines.join('\n') + '\n');
    _hysteriaSyncConfig(userFile, cfgFile);
  } catch {}
}

function _hysteriaSyncConfig(userFile, cfgFile) {
  try {
    if (!fs.existsSync(cfgFile)) return;
    const today = new Date().toISOString().split('T')[0];
    const passwords = fs.readFileSync(userFile, 'utf8').split('\n')
      .filter(l => l.trim()).map(l => l.split('|'))
      .filter(p => p.length >= 3 && p[2] >= today).map(p => p[1])
      .filter((v, i, a) => a.indexOf(v) === i);
    const cfg = JSON.parse(fs.readFileSync(cfgFile, 'utf8'));
    if (!cfg.auth) cfg.auth = { mode: 'passwords', config: [] };
    cfg.auth.config = passwords.length > 0 ? passwords : ['zi'];
    fs.writeFileSync(cfgFile, JSON.stringify(cfg, null, 2));
  } catch (e) { console.error('[HYSTERIA] sync config error:', e.message); }
}

function v2rayAdd(username, uuid) {
  const cfgPath = process.env.V2RAY_CONFIG || '/etc/v2ray/config.json';
  const cfg = readJson(cfgPath);
  if (!cfg) return { ok: false, msg: `config v2ray introuvable : ${cfgPath}` };
  const inb = cfg.inbounds?.find(i => i.protocol === 'vless' || i.protocol === 'vmess');
  if (!inb?.settings?.clients) return { ok: false, msg: 'inbound vless/vmess introuvable dans config v2ray' };
  if (inb.settings.clients.some(c => c.id === uuid || c.email === username)) return { ok: true };
  const client = { id: uuid, email: username };
  if (inb.protocol === 'vmess') client.alterId = 0;
  inb.settings.clients.push(client);
  writeJson(cfgPath, cfg);
  return { ok: true };
}

function v2rayRemove(username, uuid) {
  const cfgPath = process.env.V2RAY_CONFIG || '/etc/v2ray/config.json';
  const cfg = readJson(cfgPath);
  if (!cfg) return;
  const inb = cfg.inbounds?.find(i => i.protocol === 'vless' || i.protocol === 'vmess');
  if (!inb?.settings?.clients) return;
  inb.settings.clients = inb.settings.clients.filter(c => c.id !== uuid && c.email !== username);
  writeJson(cfgPath, cfg);
}

// ============================================================
// ZIVPN / HYSTERIA — BLOCK / RESTORE (quota)
// Au blocage quota : sauvegarde le password dans .blocked
// Au déblocage : restaure depuis .blocked ou depuis la DB
// ============================================================

function zivpnBlockSave(username) {
  try {
    const userFile    = '/etc/zivpn/users.list';
    const cfgFile     = '/etc/zivpn/config.json';
    const blockedDir  = '/etc/zivpn/blocked';
    if (!fs.existsSync(userFile)) return;
    if (!fs.existsSync(blockedDir)) fs.mkdirSync(blockedDir, { recursive: true });
    const lines = fs.readFileSync(userFile, 'utf8').split('\n').filter(l => l.trim());
    const userLine = lines.find(l => l.startsWith(`${username}|`));
    if (!userLine) return;
    fs.writeFileSync(`${blockedDir}/${username}.blocked`, userLine);
    fs.chmodSync(`${blockedDir}/${username}.blocked`, 0o600);
    const newLines = lines.filter(l => !l.startsWith(`${username}|`));
    fs.writeFileSync(userFile, newLines.join('\n') + '\n');
    _zivpnSyncConfig(userFile, cfgFile);
    console.log(`[ZIVPN-BLOCK] ${username} bloqué (password sauvegardé)`);
  } catch (e) { console.error(`[ZIVPN-BLOCK] Erreur blockSave(${username}):`, e.message); }
}

function zivpnBlockRestore(username, password, expires_at) {
  try {
    const userFile    = '/etc/zivpn/users.list';
    const cfgFile     = '/etc/zivpn/config.json';
    const blockedDir  = '/etc/zivpn/blocked';
    const blockedFile = `${blockedDir}/${username}.blocked`;
    let userLine = null;
    if (fs.existsSync(blockedFile)) {
      userLine = fs.readFileSync(blockedFile, 'utf8').trim();
      fs.unlinkSync(blockedFile);
    }
    if (!userLine) {
      const expire = expires_at ? new Date(expires_at).toISOString().split('T')[0] : '2099-12-31';
      userLine = `${username}|${password}|${expire}`;
    }
    let lines = [];
    if (fs.existsSync(userFile))
      lines = fs.readFileSync(userFile, 'utf8').split('\n').filter(l => l.trim() && !l.startsWith(`${username}|`));
    lines.push(userLine);
    fs.writeFileSync(userFile, lines.join('\n') + '\n');
    fs.chmodSync(userFile, 0o600);
    _zivpnSyncConfig(userFile, cfgFile);
    console.log(`[ZIVPN-BLOCK] ${username} débloqué`);
  } catch (e) { console.error(`[ZIVPN-BLOCK] Erreur blockRestore(${username}):`, e.message); }
}

function hysteriaBlockSave(username) {
  try {
    const userFile   = '/etc/hysteria/users.txt';
    const cfgFile    = '/etc/hysteria/config.json';
    const blockedDir = '/etc/hysteria/blocked';
    if (!fs.existsSync(userFile)) return;
    if (!fs.existsSync(blockedDir)) fs.mkdirSync(blockedDir, { recursive: true });
    const lines = fs.readFileSync(userFile, 'utf8').split('\n').filter(l => l.trim());
    const userLine = lines.find(l => l.startsWith(`${username}|`));
    if (!userLine) return;
    fs.writeFileSync(`${blockedDir}/${username}.blocked`, userLine);
    fs.chmodSync(`${blockedDir}/${username}.blocked`, 0o600);
    const newLines = lines.filter(l => !l.startsWith(`${username}|`));
    fs.writeFileSync(userFile, newLines.join('\n') + '\n');
    _hysteriaSyncConfig(userFile, cfgFile);
    console.log(`[HYSTERIA-BLOCK] ${username} bloqué (password sauvegardé)`);
  } catch (e) { console.error(`[HYSTERIA-BLOCK] Erreur blockSave(${username}):`, e.message); }
}

function hysteriaBlockRestore(username, password, expires_at) {
  try {
    const userFile    = '/etc/hysteria/users.txt';
    const cfgFile     = '/etc/hysteria/config.json';
    const blockedDir  = '/etc/hysteria/blocked';
    const blockedFile = `${blockedDir}/${username}.blocked`;
    let userLine = null;
    if (fs.existsSync(blockedFile)) {
      userLine = fs.readFileSync(blockedFile, 'utf8').trim();
      fs.unlinkSync(blockedFile);
    }
    if (!userLine) {
      const expire = expires_at ? new Date(expires_at).toISOString().split('T')[0] : '2099-12-31';
      userLine = `${username}|${password}|${expire}`;
    }
    let lines = [];
    if (fs.existsSync(userFile))
      lines = fs.readFileSync(userFile, 'utf8').split('\n').filter(l => l.trim() && !l.startsWith(`${username}|`));
    lines.push(userLine);
    fs.writeFileSync(userFile, lines.join('\n') + '\n');
    fs.chmodSync(userFile, 0o600);
    _hysteriaSyncConfig(userFile, cfgFile);
    console.log(`[HYSTERIA-BLOCK] ${username} débloqué`);
  } catch (e) { console.error(`[HYSTERIA-BLOCK] Erreur blockRestore(${username}):`, e.message); }
}

function cleanupUserBandwidthFiles(username) {
  const BW_DIR   = '/var/lib/kighmu/bandwidth';
  const SENT_DIR = BW_DIR + '/sent';
  const patterns = [
    `${BW_DIR}/${username}.usage`,
    `${SENT_DIR}/${username}.sent`,
    `${BW_DIR}/udp_zivpn_${username}.usage`,
    `${BW_DIR}/udp_hysteria_${username}.usage`,
    `${SENT_DIR}/udp_zivpn_${username}.sent`,
    `${SENT_DIR}/udp_hysteria_${username}.sent`,
    `/etc/zivpn/blocked/${username}.blocked`,
    `/etc/hysteria/blocked/${username}.blocked`,
  ];
  for (const f of patterns) {
    try { fs.unlinkSync(f); console.log(`[CLEANUP] Supprimé: ${f}`); } catch {}
  }
}


// ============================================================
// V2RAY RESYNC — Réinjection automatique après réinstallation
// ============================================================
async function resyncV2rayClients() {
  const cfgPath = process.env.V2RAY_CONFIG || '/etc/v2ray/config.json';
  if (!fs.existsSync(cfgPath)) {
    console.log('[V2RAY-RESYNC] config.json absent — resync ignoré');
    return { injected: 0, skipped: 0, total: 0 };
  }
  const cfg = readJson(cfgPath);
  if (!cfg) { console.error('[V2RAY-RESYNC] Impossible de lire config.json'); return { injected:0, skipped:0, total:0 }; }
  const inb = cfg.inbounds?.find(i => i.protocol === 'vless' || i.protocol === 'vmess');
  if (!inb?.settings) { console.error('[V2RAY-RESYNC] Aucun inbound vless/vmess'); return { injected:0, skipped:0, total:0 }; }
  if (!inb.settings.clients) inb.settings.clients = [];
  let injected = 0, skipped = 0;
  try {
    const [clients] = await db.query(`
      SELECT c.username, c.uuid, c.data_limit_gb,
             COALESCE(SUM(u.upload_bytes + u.download_bytes), 0) AS used_bytes
      FROM clients c
      LEFT JOIN usage_stats u ON u.client_id = c.id
      WHERE c.tunnel_type = 'v2ray-fastdns'
        AND c.is_active   = 1
        AND c.quota_blocked = 0
        AND c.expires_at  >= NOW()
      GROUP BY c.id
    `);
    const existing = new Set(inb.settings.clients.map(c => c.id));
    for (const c of clients) {
      if (c.data_limit_gb > 0) {
        const usedGb = c.used_bytes / (1024 * 1024 * 1024);
        if (usedGb >= parseFloat(c.data_limit_gb)) {
          console.log(`[V2RAY-RESYNC] ${c.username} ignoré — quota dépassé (${usedGb.toFixed(2)}/${c.data_limit_gb} Go)`);
          skipped++; continue;
        }
      }
      if (existing.has(c.uuid)) { skipped++; continue; }
      inb.settings.clients.push({ id: c.uuid, email: c.username });
      existing.add(c.uuid);
      injected++;
      console.log(`[V2RAY-RESYNC] Réinjecté : ${c.username}`);
    }
    if (injected > 0) {
      writeJson(cfgPath, cfg);
      await restartService('v2ray');
      console.log(`[V2RAY-RESYNC] ${injected} client(s) réinjecté(s) — V2Ray redémarré`);
    } else {
      console.log(`[V2RAY-RESYNC] Aucun client à réinjecter (${skipped} déjà présents/ignorés)`);
    }
  } catch (e) { console.error('[V2RAY-RESYNC] Erreur DB:', e.message); }
  return { injected, skipped, total: injected + skipped };
}

// Endpoint admin pour déclencher manuellement la resync
app.post('/api/admin/v2ray/resync', auth(['admin']), authWriteLimiter, async (req, res) => {
  try {
    const result = await resyncV2rayClients();
    res.json({ ok: true, ...result,
      message: result.injected > 0
        ? `${result.injected} client(s) réinjecté(s) dans V2Ray`
        : `Aucun client à réinjecter (${result.skipped} déjà présents ou ignorés)`
    });
  } catch (e) { res.status(500).json({ error: 'Erreur serveur' }); }
});

async function addTunnel(client) {
  const { username, password, uuid, tunnel_type, expires_at } = client;
  let result = { ok: false, msg: 'tunnel_type inconnu' };
  try {
    switch (tunnel_type) {
      case 'vless':         result = xrayAdd(username, 'vless', uuid);  if (result.ok) await restartService('xray');  break;
      case 'vmess':         result = xrayAdd(username, 'vmess', uuid);  if (result.ok) await restartService('xray');  break;
      case 'trojan':        result = xrayAdd(username, 'trojan', uuid); if (result.ok) await restartService('xray');  break;
      case 'ssh-multi':
      case 'ssh-ws':
      case 'ssh-slowdns':
      case 'ssh-ssl':
      case 'ssh-udp':       result = await sshAdd(username, password, expires_at); break;
      case 'udp-zivpn': {
        result = zivpnAdd(username, password, expires_at);
        if (result.ok) {
          await restartService('zivpn');
          const readF = p => { try { return fs.readFileSync(p,'utf8').trim(); } catch { return null; } };
          const zCfg  = (() => { try { return JSON.parse(readF('/etc/zivpn/config.json')||'{}'); } catch { return {}; } })();
          const zPort = (zCfg.listen||':5667').replace(':','');
          result.config_info = { domain: readF('/etc/zivpn/domain.txt') || readF('/etc/kighmu/domain.txt') || null, obfs: zCfg.obfs || 'zivpn', port: zPort || '5667' };
        }
        break;
      }
      case 'udp-hysteria': {
        result = hysteriaAdd(username, password, expires_at);
        if (result.ok) {
          await restartService('hysteria');
          const readF = p => { try { return fs.readFileSync(p,'utf8').trim(); } catch { return null; } };
          const hCfg  = (() => { try { return JSON.parse(readF('/etc/hysteria/config.json')||'{}'); } catch { return {}; } })();
          const hPort = (hCfg.listen||':20000').replace(':','');
          result.config_info = { domain: readF('/etc/hysteria/domain.txt') || readF('/etc/kighmu/domain.txt') || null, obfs: hCfg.obfs || 'hysteria', port: hPort || '20000', port_range: `${hPort || '20000'}-50000` };
        }
        break;
      }
      case 'v2ray-fastdns': {
        result = v2rayAdd(username, uuid);
        if (result.ok) {
          await restartService('v2ray');
          const readF = p => { try { return fs.readFileSync(p,'utf8').trim(); } catch { return null; } };
          result.config_info = {
            domain: readF('/etc/kighmu/domain.txt') || null,
            v2ray_domain: readF('/.v2ray_domain') || null,
            slowdns_key_v2ray: readF('/etc/slowdns/nv4/server.pub') || readF('/etc/slowdns_v2ray/server.pub') || readF('/etc/slowdns/server.pub') || null,
            slowdns_ns_v2ray: readF('/etc/slowdns/nv4/ns.conf') || readF('/etc/slowdns_v2ray/ns.conf') || null,
          };
        }
        break;
      }
    }
  } catch (e) { result = { ok: false, msg: e.message }; }
  return result;
}

async function removeTunnel(client) {
  const { username, uuid, tunnel_type } = client;
  try {
    switch (tunnel_type) {
      case 'vless':         xrayRemove(username, 'vless', uuid);  await restartService('xray');    break;
      case 'vmess':         xrayRemove(username, 'vmess', uuid);  await restartService('xray');    break;
      case 'trojan':        xrayRemove(username, 'trojan', uuid); await restartService('xray');    break;
      case 'ssh-multi':
      case 'ssh-ws':
      case 'ssh-slowdns':
      case 'ssh-ssl':
      case 'ssh-udp':       await sshRemove(username); break;
      case 'udp-zivpn':     zivpnRemove(username); await restartService('zivpn'); break;
      case 'udp-hysteria':  hysteriaRemove(username); await restartService('hysteria'); break;
      case 'v2ray-fastdns': v2rayRemove(username, uuid); await restartService('v2ray'); break;
    }
    cleanupUserBandwidthFiles(username);
  } catch (e) { console.error(`[TUNNEL] removeTunnel error:`, e.message); }
}

async function blockTunnel(client) {
  const { username, uuid, tunnel_type } = client;
  try {
    switch (tunnel_type) {
      case 'vless':
      case 'vmess':
      case 'trojan':
      case 'v2ray-fastdns':
        if (tunnel_type === 'v2ray-fastdns') v2rayRemove(username, uuid);
        else xrayRemove(username, tunnel_type, uuid);
        await restartService(tunnel_type === 'v2ray-fastdns' ? 'v2ray' : 'xray');
        break;
      case 'ssh-multi':
      case 'ssh-ws':
      case 'ssh-slowdns':
      case 'ssh-ssl':
      case 'ssh-udp':
        await sshLock(username);
        break;
      case 'udp-zivpn':
        zivpnBlockSave(username);
        await restartService('zivpn');
        break;
      case 'udp-hysteria':
        hysteriaBlockSave(username);
        await restartService('hysteria');
        break;
    }
    console.log(`[QUOTA] Tunnel bloqué : ${username} (${tunnel_type})`);
  } catch (e) { console.error(`[QUOTA] blockTunnel error:`, e.message); }
}

async function unblockTunnel(client) {
  const { username, password, uuid, tunnel_type, expires_at } = client;
  try {
    switch (tunnel_type) {
      case 'vless':
      case 'vmess':
      case 'trojan':
        xrayAdd(username, tunnel_type, uuid); await restartService('xray'); break;
      case 'v2ray-fastdns':
        v2rayAdd(username, uuid); await restartService('v2ray'); break;
      case 'ssh-multi':
      case 'ssh-ws':
      case 'ssh-slowdns':
      case 'ssh-ssl':
      case 'ssh-udp':
        await sshUnlock(username); break;
      case 'udp-zivpn':
        zivpnBlockRestore(username, password, expires_at);
        await restartService('zivpn');
        break;
      case 'udp-hysteria':
        hysteriaBlockRestore(username, password, expires_at);
        await restartService('hysteria');
        break;
    }
    console.log(`[QUOTA] Tunnel débloqué : ${username} (${tunnel_type})`);
  } catch (e) { console.error(`[QUOTA] unblockTunnel error:`, e.message); }
}

// ============================================================
// NETTOYAGE COMPLET REVENDEUR
// ============================================================
async function cleanupReseller(resellerId) {
  try {
    const [clients] = await db.query('SELECT * FROM clients WHERE reseller_id=?', [resellerId]);
    for (const c of clients) { await removeTunnel(c); }
    await db.query('DELETE FROM usage_stats WHERE reseller_id=?',   [resellerId]);
    await db.query('DELETE FROM usage_stats WHERE client_id IN (SELECT id FROM clients WHERE reseller_id=?)', [resellerId]);
    await db.query('DELETE FROM clients WHERE reseller_id=?',       [resellerId]);
    await db.query('DELETE FROM activity_logs WHERE actor_id=? AND actor_type="reseller"', [resellerId]);
    await db.query('UPDATE resellers SET used_users=0 WHERE id=?',  [resellerId]);
    console.log(`[CLEANUP] Revendeur #${resellerId} nettoyé — ${clients.length} client(s) supprimé(s)`);
    return clients.length;
  } catch (e) {
    console.error(`[CLEANUP] Erreur nettoyage revendeur #${resellerId}:`, e.message);
    return 0;
  }
}

// ============================================================
// AUTH ROUTES
// ============================================================
app.post('/api/auth/admin/login', loginLimiter, async (req, res) => {
  try {
    const { username, password } = req.body;
    const ip = req.ip || req.connection.remoteAddress || '0.0.0.0';
    if (!username || !password) return res.status(400).json({ error: 'Identifiant et mot de passe requis' });
    if (!validateUsername(username)) return res.status(400).json({ error: 'Format de username invalide' });
    const blocked = await checkBruteForce(ip);
    if (blocked) return res.status(429).json({ error: blocked });
    const [[admin]] = await db.query('SELECT * FROM admins WHERE username=?', [username]);
    if (!admin) {
      await bcrypt.compare(password, '$2b$12$' + 'x'.repeat(53));
      await failAttempt(ip);
      return res.status(401).json({ error: 'Identifiants invalides' });
    }
    if (!(await bcrypt.compare(password, admin.password))) {
      await failAttempt(ip);
      return res.status(401).json({ error: 'Identifiants invalides' });
    }
    await clearAttempts(ip);
    await db.query('UPDATE admins SET last_login=NOW() WHERE id=?', [admin.id]);
    const token = jwt.sign({ id: admin.id, username: admin.username, role: 'admin' }, process.env.JWT_SECRET, { expiresIn: process.env.JWT_EXPIRES_IN || '2h' });
    await log('admin', admin.id, 'LOGIN', null, null, null, ip);
    res.json({ token, role: 'admin', username: admin.username });
  } catch (e) { res.status(500).json({ error: 'Erreur serveur' }); }
});

app.post('/api/auth/reseller/login', loginLimiter, async (req, res) => {
  try {
    const { username, password } = req.body;
    const ip = req.ip || req.connection.remoteAddress || '0.0.0.0';
    if (!username || !password) return res.status(400).json({ error: 'Identifiant et mot de passe requis' });
    if (!validateUsername(username)) return res.status(400).json({ error: 'Format de username invalide' });
    const blocked = await checkBruteForce(ip);
    if (blocked) return res.status(429).json({ error: blocked });
    const [[r]] = await db.query('SELECT * FROM resellers WHERE username=?', [username]);
    if (!r) {
      await bcrypt.compare(password, '$2b$12$' + 'x'.repeat(53));
      await failAttempt(ip);
      return res.status(401).json({ error: 'Identifiants invalides' });
    }
    if (!(await bcrypt.compare(password, r.password))) {
      await failAttempt(ip);
      return res.status(401).json({ error: 'Identifiants invalides' });
    }
    if (!r.is_active) return res.status(403).json({ error: 'Compte désactivé' });
    if (new Date(r.expires_at) < new Date()) {
      await cleanupReseller(r.id);
      await db.query('DELETE FROM resellers WHERE id=?', [r.id]);
      return res.status(403).json({ error: 'Compte expiré — toutes vos données ont été nettoyées' });
    }
    await clearAttempts(ip);
    const token = jwt.sign({ id: r.id, username: r.username, role: 'reseller' }, process.env.JWT_SECRET, { expiresIn: process.env.JWT_EXPIRES_IN || '2h' });
    await log('reseller', r.id, 'LOGIN', null, null, null, ip);
    res.json({ token, role: 'reseller', username: r.username });
  } catch (e) { res.status(500).json({ error: 'Erreur serveur' }); }
});

// ============================================================
// REFRESH TOKEN
// ============================================================
app.post('/api/auth/refresh', async (req, res) => {
  try {
    const header = req.headers.authorization || '';
    const token  = header.startsWith('Bearer ') ? header.slice(7) : null;
    if (!token) return res.status(401).json({ error: 'Token manquant' });
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    const nowSec = Math.floor(Date.now() / 1000);
    const remaining = decoded.exp - nowSec;
    if (remaining < 0) return res.status(401).json({ error: 'Token expire' });
    const newToken = jwt.sign(
      { id: decoded.id, username: decoded.username, role: decoded.role },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_EXPIRES_IN || '2h' }
    );
    res.json({ token: newToken, role: decoded.role, username: decoded.username });
  } catch {
    res.status(401).json({ error: 'Token invalide' });
  }
});

// ============================================================
// ADMIN ROUTES
// ============================================================
const A = auth(['admin']);

app.get('/api/admin/resellers', A, async (req, res) => {
  try {
    const [rows] = await db.query(`
      SELECT r.*,
        (SELECT COUNT(*) FROM clients WHERE reseller_id=r.id) as total_clients,
        COALESCE((SELECT SUM(u.upload_bytes+u.download_bytes) FROM usage_stats u WHERE u.reseller_id=r.id),0) as total_bytes
      FROM resellers r ORDER BY r.created_at DESC`);
    const parsed = rows.map(r => {
      let at = null;
      if (r.allowed_tunnels && typeof r.allowed_tunnels === 'string') {
        try { at = JSON.parse(r.allowed_tunnels); } catch { at = null; }
      }
      if (!Array.isArray(at) || at.length === 0) at = null;
      return { ...r, allowed_tunnels: at };
    });
    res.json(parsed);
  } catch (e) { res.status(500).json({ error: 'Erreur serveur' }); }
});

app.post('/api/admin/resellers', A, authWriteLimiter, async (req, res) => {
  try {
    const { username, password, max_users, expires_at, data_limit_gb, allowed_tunnels } = req.body;
    if (!username || !password || !expires_at) return res.status(400).json({ error: 'Champs requis manquants' });
    if (!validateUsername(username)) return res.status(400).json({ error: 'Format de username invalide' });
    const [ex] = await db.query('SELECT id FROM resellers WHERE username=?', [username]);
    if (ex.length) return res.status(409).json({ error: 'Username déjà pris' });
    let tunnelList = null;
    if (allowed_tunnels && Array.isArray(allowed_tunnels) && allowed_tunnels.length > 0) {
      const VALID = ['vless','vmess','trojan','ssh-multi','udp-zivpn','udp-hysteria','v2ray-fastdns'];
      const filtered = allowed_tunnels.filter(t => VALID.includes(t));
      tunnelList = filtered.length ? JSON.stringify(filtered) : null;
    }
    const hash = await bcrypt.hash(password, parseInt(process.env.BCRYPT_ROUNDS) || 12);
    const [r] = await db.query(
      'INSERT INTO resellers (username,password,max_users,expires_at,data_limit_gb,allowed_tunnels,created_by) VALUES (?,?,?,?,?,?,?)',
      [username, hash, max_users||10, expires_at, data_limit_gb||0, tunnelList, req.user.id]);
    await log('admin', req.user.id, 'CREATE_RESELLER', 'reseller', r.insertId, { username, data_limit_gb }, req.ip);
    res.json({ id: r.insertId, message: 'Revendeur créé' });
  } catch (e) { res.status(500).json({ error: 'Erreur serveur' }); }
});

app.put('/api/admin/resellers/:id', A, authWriteLimiter, async (req, res) => {
  try {
    const { username, max_users, expires_at, is_active, password, data_limit_gb, allowed_tunnels } = req.body;
    const upd = {};
    if (username !== undefined && username.trim()) {
      const [[ex]] = await db.query('SELECT id FROM resellers WHERE username=? AND id!=?', [username.trim(), req.params.id]);
      if (ex) return res.status(409).json({ error: 'Ce username est déjà utilisé' });
      upd.username = username.trim();
    }
    if (max_users      !== undefined) upd.max_users      = max_users;
    if (expires_at     !== undefined) upd.expires_at     = expires_at;
    if (is_active      !== undefined) upd.is_active      = is_active;
    if (data_limit_gb  !== undefined) {
      upd.data_limit_gb = data_limit_gb;
      // Si la limite est augmentée ou supprimée (0=illimité), débloquer le revendeur et ses clients
      const [[rCur]] = await db.query('SELECT quota_blocked, data_limit_gb FROM resellers WHERE id=?', [req.params.id]);
      if (rCur && rCur.quota_blocked && (data_limit_gb === 0 || parseFloat(data_limit_gb) > parseFloat(rCur.data_limit_gb))) {
        upd.quota_blocked = 0;
        // Débloquer tous les clients quota_blocked du revendeur
        const [blockedClients] = await db.query('SELECT * FROM clients WHERE reseller_id=? AND quota_blocked=1', [req.params.id]);
        for (const c of blockedClients) {
          await unblockTunnel(c);
          await db.query('UPDATE clients SET quota_blocked=0, is_active=1 WHERE id=?', [c.id]);
        }
        console.log(`[QUOTA] Revendeur #${req.params.id} débloqué par admin (${blockedClients.length} client(s) restauré(s))`);
        await log('admin', req.user.id, 'QUOTA_UNBLOCK_RESELLER', 'reseller', req.params.id, { clients_unblocked: blockedClients.length, new_limit_gb: data_limit_gb }, req.ip);
      }
    }
    if (allowed_tunnels !== undefined) {
      if (Array.isArray(allowed_tunnels) && allowed_tunnels.length > 0) {
        const VALID = ['vless','vmess','trojan','ssh-multi','udp-zivpn','udp-hysteria','v2ray-fastdns'];
        const filtered = allowed_tunnels.filter(t => VALID.includes(t));
        upd.allowed_tunnels = filtered.length ? JSON.stringify(filtered) : null;
      } else { upd.allowed_tunnels = null; }
    }
    if (password) upd.password = await bcrypt.hash(password, parseInt(process.env.BCRYPT_ROUNDS) || 12);
    if (!Object.keys(upd).length) return res.status(400).json({ error: 'Aucun champ à modifier' });
    const sets = Object.keys(upd).map(k => `${k}=?`).join(',');
    await db.query(`UPDATE resellers SET ${sets} WHERE id=?`, [...Object.values(upd), req.params.id]);
    await log('admin', req.user.id, 'UPDATE_RESELLER', 'reseller', req.params.id, upd, req.ip);
    res.json({ message: 'Revendeur mis à jour' });
  } catch (e) { res.status(500).json({ error: 'Erreur serveur' }); }
});

app.delete('/api/admin/resellers/:id', A, authWriteLimiter, async (req, res) => {
  try {
    const [[r]] = await db.query('SELECT username FROM resellers WHERE id=?', [req.params.id]);
    if (!r) return res.status(404).json({ error: 'Revendeur introuvable' });
    const cleaned = await cleanupReseller(req.params.id);
    await db.query('DELETE FROM resellers WHERE id=?', [req.params.id]);
    await log('admin', req.user.id, 'DELETE_RESELLER', 'reseller', req.params.id, { username: r.username, clients_cleaned: cleaned }, req.ip);
    res.json({ message: `Revendeur supprimé + ${cleaned} client(s) nettoyé(s)` });
  } catch (e) { res.status(500).json({ error: 'Erreur serveur' }); }
});

app.post('/api/admin/resellers/:id/clean', A, authWriteLimiter, async (req, res) => {
  try {
    const cleaned = await cleanupReseller(req.params.id);
    await log('admin', req.user.id, 'CLEAN_RESELLER', 'reseller', req.params.id, { clients_cleaned: cleaned }, req.ip);
    res.json({ message: `${cleaned} client(s) nettoyé(s)` });
  } catch (e) { res.status(500).json({ error: 'Erreur serveur' }); }
});

app.get('/api/admin/clients', A, async (req, res) => {
  try {
    const [rows] = await db.query(`
      SELECT c.*, r.username as reseller_name,
        COALESCE(SUM(u.upload_bytes),0) as total_upload,
        COALESCE(SUM(u.download_bytes),0) as total_download
      FROM clients c
      LEFT JOIN resellers r ON c.reseller_id=r.id
      LEFT JOIN usage_stats u ON u.client_id=c.id
      GROUP BY c.id ORDER BY c.created_at DESC`);
    res.json(rows);
  } catch (e) { res.status(500).json({ error: 'Erreur serveur' }); }
});

app.post('/api/admin/clients', A, authWriteLimiter, async (req, res) => {
  try {
    const { username, password, tunnel_type, expires_at, note, reseller_id, data_limit_gb } = req.body;
    if (!username || !tunnel_type || !expires_at)
      return res.status(400).json({ error: 'username, tunnel_type et expires_at sont requis' });
    if (!validateUsername(username)) return res.status(400).json({ error: 'Format de username invalide (3-32 car., lettres/chiffres/tirets)' });
    const [ex] = await db.query('SELECT id FROM clients WHERE username=?', [username]);
    if (ex.length) return res.status(409).json({ error: 'Username déjà utilisé' });
    if (reseller_id) {
      const [[r]] = await db.query('SELECT max_users, used_users FROM resellers WHERE id=?', [reseller_id]);
      if (!r) return res.status(404).json({ error: 'Revendeur introuvable' });
      if (r.used_users >= r.max_users) return res.status(403).json({ error: `Limite revendeur atteinte (${r.max_users})` });
    }
    const uuid = uuidv4();
    const pass = password || crypto.randomBytes(12).toString('base64url').slice(0, 16);
    const tunnelResult = await addTunnel({ username, password: pass, uuid, tunnel_type, expires_at });
    const [ins] = await db.query(
      'INSERT INTO clients (username,password,uuid,reseller_id,tunnel_type,expires_at,note,data_limit_gb) VALUES (?,?,?,?,?,?,?,?)',
      [username, pass, uuid, reseller_id||null, tunnel_type, expires_at, note||null, data_limit_gb||0]);
    if (reseller_id) await db.query('UPDATE resellers SET used_users=used_users+1 WHERE id=?', [reseller_id]);
    await log('admin', req.user.id, 'CREATE_CLIENT', 'client', ins.insertId, { username, tunnel_type, data_limit_gb }, req.ip);
    const readF = p => { try { return fs.readFileSync(p,'utf8').trim(); } catch { return null; } };
    const vpsInfo = {
      domain:           getVpsDomain() || null,
      xray_domain:      readF('/etc/xray/domain') || readF('/tmp/.xray_domain') || null,
      v2ray_domain:     readF('/.v2ray_domain') || null,
      slowdns_key:      readF('/etc/slowdns/server.pub')        || null,
      slowdns_ns:       readF('/etc/slowdns/ns.conf')           || null,
      slowdns_key_v2ray:readF('/etc/slowdns/nv4/server.pub')   || readF('/etc/slowdns_v2ray/server.pub')|| readF('/etc/slowdns/server.pub')|| null,
      slowdns_ns_v2ray: readF('/etc/slowdns/nv4/ns.conf')      || readF('/etc/slowdns_v2ray/ns.conf')   || null,
    };
    let hostIp = null;
    try { const nets = await si.networkInterfaces(); const eth=nets.find(n=>!n.internal&&n.ip4); hostIp=eth?.ip4||null; } catch {}
    vpsInfo.host_ip = hostIp;
    res.json({ id: ins.insertId, username, password: pass, uuid, tunnel_type, expires_at, data_limit_gb: data_limit_gb||0, tunnelResult, vpsInfo });
  } catch (e) { res.status(500).json({ error: 'Erreur serveur' }); }
});

app.put('/api/admin/clients/:id', A, authWriteLimiter, async (req, res) => {
  try {
    const { username, password, uuid, expires_at, note, is_active, data_limit_gb } = req.body;
    const [[c]] = await db.query('SELECT * FROM clients WHERE id=?', [req.params.id]);
    if (!c) return res.status(404).json({ error: 'Client introuvable' });
    const upd = {};
    let tunnelChanged = false;
    if (username !== undefined && username.trim() && username.trim() !== c.username) {
      const [[ex]] = await db.query('SELECT id FROM clients WHERE username=? AND id!=?', [username.trim(), c.id]);
      if (ex) return res.status(409).json({ error: 'Ce username est déjà utilisé' });
      upd.username = username.trim();
      tunnelChanged = true;
    }
    if (password !== undefined && password.trim()) { upd.password = password.trim(); tunnelChanged = true; }
    if (uuid !== undefined && uuid.trim() && uuid.trim() !== c.uuid) { upd.uuid = uuid.trim(); tunnelChanged = true; }
    if (expires_at !== undefined) {
      upd.expires_at = expires_at;
      tunnelChanged = true;
      if (new Date(expires_at) > new Date() && !c.is_active) upd.is_active = 1;
    }
    if (note          !== undefined) upd.note          = note;
    if (is_active     !== undefined) { upd.is_active = is_active; tunnelChanged = true; }
    if (data_limit_gb !== undefined) upd.data_limit_gb = data_limit_gb;
    if (data_limit_gb !== undefined && c.quota_blocked) {
      upd.quota_blocked = 0;
      const toUnblock = { ...c, ...upd };
      await unblockTunnel(toUnblock);
    }
    if (!Object.keys(upd).length) return res.status(400).json({ error: 'Aucun champ à modifier' });
    if (tunnelChanged) {
      const updated = { ...c, ...upd };
      const active = updated.is_active && (!updated.expires_at || new Date(updated.expires_at) > new Date());
      if (active) {
        await removeTunnel(c);
        await addTunnel(updated);
      } else {
        await removeTunnel(c);
      }
    }
    const sets = Object.keys(upd).map(k => `${k}=?`).join(',');
    await db.query(`UPDATE clients SET ${sets} WHERE id=?`, [...Object.values(upd), req.params.id]);
    await log('admin', req.user.id, 'UPDATE_CLIENT', 'client', req.params.id, { fields: Object.keys(upd), tunnelChanged }, req.ip);
    res.json({ message: 'Client mis à jour', tunnelChanged });
  } catch (e) { res.status(500).json({ error: 'Erreur serveur' }); }
});

app.delete('/api/admin/clients/:id', A, authWriteLimiter, async (req, res) => {
  try {
    const [[c]] = await db.query('SELECT * FROM clients WHERE id=?', [req.params.id]);
    if (!c) return res.status(404).json({ error: 'Client introuvable' });
    await removeTunnel(c);
    if (c.reseller_id) await db.query('UPDATE resellers SET used_users=used_users-1 WHERE id=? AND used_users>0', [c.reseller_id]);
    await db.query('DELETE FROM usage_stats WHERE client_id=?', [req.params.id]);
    await db.query('DELETE FROM clients WHERE id=?', [req.params.id]);
    await log('admin', req.user.id, 'DELETE_CLIENT', 'client', req.params.id, null, req.ip);
    res.json({ message: 'Client supprimé' });
  } catch (e) { res.status(500).json({ error: 'Erreur serveur' }); }
});

app.get('/api/admin/stats', A, async (req, res) => {
  try {
    const dNow = new Date();
    const [[mt]] = await db.query('SELECT total_upload, total_download FROM monthly_totals WHERE year=? AND month=?', [dNow.getFullYear(), dNow.getMonth()+1]);
    const usage = { total_upload: (mt && mt.total_upload) || 0, total_download: (mt && mt.total_download) || 0 };
    const [[counts]] = await db.query(`SELECT
      (SELECT COUNT(*) FROM resellers)              as total_resellers,
      (SELECT COUNT(*) FROM clients)                as total_clients,
      (SELECT COUNT(*) FROM clients WHERE is_active=1) as active_clients`);
    const [resellerStats] = await db.query(`
      SELECT r.id, r.username, r.max_users, r.used_users, r.data_limit_gb, r.expires_at, r.is_active,
        COALESCE(SUM(u.upload_bytes+u.download_bytes),0) as total_bytes
      FROM resellers r LEFT JOIN usage_stats u ON u.reseller_id=r.id GROUP BY r.id`);
    const [cpu, mem, disk] = await Promise.all([si.currentLoad(), si.mem(), si.fsSize()]);

    // Stats mensuelles : consommation depuis le début du mois courant
    const monthStart = new Date(dNow.getFullYear(), dNow.getMonth(), 1).toISOString().slice(0,10);
    const [[mtd]] = await db.query('SELECT total_upload, total_download FROM monthly_totals WHERE year=? AND month=?', [dNow.getFullYear(), dNow.getMonth()+1]);
    const monthly = {
      month_upload:   (mtd && mtd.total_upload)   || 0,
      month_download: (mtd && mtd.total_download) || 0
    };
    // Stats par revendeur pour le mois courant
    const [monthlyResellers] = await db.query(`
      SELECT r.username,
        COALESCE(SUM(u.upload_bytes),0) as month_upload,
        COALESCE(SUM(u.download_bytes),0) as month_download
      FROM resellers r
      LEFT JOIN usage_stats u ON u.reseller_id=r.id AND u.recorded_at >= ?
      GROUP BY r.id ORDER BY (month_upload+month_download) DESC`, [monthStart]);

    res.json({
      global: { ...usage, ...counts },
      monthly: { ...monthly, month_start: monthStart, resellers: monthlyResellers },
      resellers: resellerStats,
      system: {
        cpu_usage:  cpu.currentLoad.toFixed(1),
        ram_total:  mem.total,
        ram_used:   mem.used,
        ram_free:   mem.free,
        disk: disk[0] ? { total: disk[0].size, used: disk[0].used, free: disk[0].available } : null
      }
    });
  } catch (e) { res.status(500).json({ error: 'Erreur serveur' }); }
});

// Reset mensuel manuel
app.post('/api/admin/stats/reset-monthly', A, authWriteLimiter, async (req, res) => {
  try {
    const d = new Date();
    await db.query(
      'INSERT INTO monthly_totals (year,month,total_upload,total_download) VALUES (?,?,0,0) ON DUPLICATE KEY UPDATE total_upload=0, total_download=0',
      [d.getFullYear(), d.getMonth()+1]
    );
    await log('admin', req.user.id, 'RESET_MONTHLY_STATS', 'system', null, {}, req.ip);
    res.json({ ok: true, message: 'Total mensuel réinitialisé (les stats individuelles sont conservées)' });
  } catch (e) { res.status(500).json({ error: 'Erreur serveur' }); }
});

app.get('/api/admin/logs', A, async (req, res) => {
  try {
    const [rows] = await db.query('SELECT * FROM activity_logs ORDER BY created_at DESC LIMIT 200');
    res.json(rows);
  } catch (e) { res.status(500).json({ error: 'Erreur serveur' }); }
});

// ============================================================
// RESELLER ROUTES
// ============================================================
const R = auth(['reseller']);

app.get('/api/reseller/me', R, async (req, res) => {
  try {
    const [[r]] = await db.query(`
      SELECT r.id, r.username, r.max_users, r.used_users, r.data_limit_gb, r.allowed_tunnels, r.expires_at, r.is_active,
        COALESCE(SUM(u.upload_bytes+u.download_bytes),0) as total_bytes
      FROM resellers r LEFT JOIN usage_stats u ON u.reseller_id=r.id
      WHERE r.id=? GROUP BY r.id`, [req.user.id]);
    if (r) {
      if (r.allowed_tunnels && typeof r.allowed_tunnels === 'string') {
        try { r.allowed_tunnels = JSON.parse(r.allowed_tunnels); } catch { r.allowed_tunnels = null; }
      }
      if (!Array.isArray(r.allowed_tunnels) || r.allowed_tunnels.length === 0) r.allowed_tunnels = null;
    }
    res.json(r);
  } catch (e) { res.status(500).json({ error: 'Erreur serveur' }); }
});

app.get('/api/reseller/clients', R, async (req, res) => {
  try {
    const [rows] = await db.query(`
      SELECT c.*,
        COALESCE(SUM(u.upload_bytes),0) as total_upload,
        COALESCE(SUM(u.download_bytes),0) as total_download
      FROM clients c LEFT JOIN usage_stats u ON u.client_id=c.id
      WHERE c.reseller_id=? GROUP BY c.id ORDER BY c.created_at DESC`, [req.user.id]);
    res.json(rows);
  } catch (e) { res.status(500).json({ error: 'Erreur serveur' }); }
});

app.post('/api/reseller/clients', R, authWriteLimiter, async (req, res) => {
  try {
    const { username, password, tunnel_type, expires_at, note, data_limit_gb } = req.body;
    if (!username || !tunnel_type || !expires_at) return res.status(400).json({ error: 'Champs requis manquants' });
    if (!validateUsername(username)) return res.status(400).json({ error: 'Format de username invalide' });
    const [[r]] = await db.query('SELECT * FROM resellers WHERE id=?', [req.user.id]);
    if (r.used_users >= r.max_users) return res.status(403).json({ error: `Limite atteinte (${r.max_users} max)` });
    // Bloquer la création si quota data dépassé
    if (r.quota_blocked) return res.status(403).json({ error: 'Quota de données dépassé — création de clients suspendue. Contactez l\'administrateur.' });
    if (r.allowed_tunnels) {
      let allowed;
      try { allowed = JSON.parse(r.allowed_tunnels); } catch { allowed = []; }
      if (!Array.isArray(allowed) || allowed.length === 0) allowed = null;
      if (allowed) {
        const SSH_VARIANTS = ['ssh-multi','ssh-ws','ssh-slowdns','ssh-ssl','ssh-udp'];
        const sshAllowed = allowed.includes('ssh-multi');
        const isSSH = SSH_VARIANTS.includes(tunnel_type);
        if (!(allowed.includes(tunnel_type) || (isSSH && sshAllowed))) {
          return res.status(403).json({ error: `Tunnel "${tunnel_type}" non autorisé pour votre compte` });
        }
      }
    }
    const [ex] = await db.query('SELECT id FROM clients WHERE username=?', [username]);
    if (ex.length) return res.status(409).json({ error: 'Username déjà utilisé' });
    const uuid = uuidv4();
    const pass = password || crypto.randomBytes(12).toString('base64url').slice(0, 16);
    const tunnelResult = await addTunnel({ username, password: pass, uuid, tunnel_type, expires_at });
    const [ins] = await db.query(
      'INSERT INTO clients (username,password,uuid,reseller_id,tunnel_type,expires_at,note,data_limit_gb) VALUES (?,?,?,?,?,?,?,?)',
      [username, pass, uuid, req.user.id, tunnel_type, expires_at, note||null, data_limit_gb||0]);
    await db.query('UPDATE resellers SET used_users=used_users+1 WHERE id=?', [req.user.id]);
    await log('reseller', req.user.id, 'CREATE_CLIENT', 'client', ins.insertId, { username, tunnel_type }, req.ip);
    // Même vpsInfo que la route admin — nécessaire pour afficher le domaine côté revendeur
    const readF = p => { try { return fs.readFileSync(p,'utf8').trim(); } catch { return null; } };
    const vpsInfo = {
      domain:           getVpsDomain() || null,
      xray_domain:      readF('/etc/xray/domain') || readF('/tmp/.xray_domain') || null,
      v2ray_domain:     readF('/.v2ray_domain') || null,
      slowdns_key:      readF('/etc/slowdns/server.pub')        || null,
      slowdns_ns:       readF('/etc/slowdns/ns.conf')           || null,
      slowdns_key_v2ray:readF('/etc/slowdns/nv4/server.pub')   || readF('/etc/slowdns_v2ray/server.pub')|| readF('/etc/slowdns/server.pub')|| null,
      slowdns_ns_v2ray: readF('/etc/slowdns/nv4/ns.conf')      || readF('/etc/slowdns_v2ray/ns.conf')   || null,
    };
    let hostIp = null;
    try { const nets = await si.networkInterfaces(); const eth=nets.find(n=>!n.internal&&n.ip4); hostIp=eth?.ip4||null; } catch {}
    vpsInfo.host_ip = hostIp;
    res.json({ id: ins.insertId, username, password: pass, uuid, tunnel_type, expires_at, data_limit_gb: data_limit_gb||0, tunnelResult, vpsInfo });
  } catch (e) { res.status(500).json({ error: 'Erreur serveur' }); }
});

app.put('/api/reseller/clients/:id', R, authWriteLimiter, async (req, res) => {
  try {
    const [[c]] = await db.query('SELECT * FROM clients WHERE id=? AND reseller_id=?', [req.params.id, req.user.id]);
    if (!c) return res.status(404).json({ error: 'Client introuvable' });
    const { expires_at, note, is_active, data_limit_gb } = req.body;
    const upd = {};
    let tunnelChanged = false;
    if (expires_at !== undefined) {
      upd.expires_at = expires_at;
      tunnelChanged = true;
      if (new Date(expires_at) > new Date() && !c.is_active) upd.is_active = 1;
    }
    if (note          !== undefined) upd.note          = note;
    if (is_active     !== undefined) { upd.is_active = is_active; tunnelChanged = true; }
    if (data_limit_gb !== undefined) upd.data_limit_gb = data_limit_gb;
    if (data_limit_gb !== undefined && c.quota_blocked) {
      upd.quota_blocked = 0;
      await unblockTunnel(c);
    }
    if (tunnelChanged) {
      const updated = { ...c, ...upd };
      const active = updated.is_active && (!updated.expires_at || new Date(updated.expires_at) > new Date());
      if (active) {
        await removeTunnel(c);
        await addTunnel(updated);
      } else {
        await removeTunnel(c);
      }
    }
    const sets = Object.keys(upd).map(k => `${k}=?`).join(',');
    if (sets) await db.query(`UPDATE clients SET ${sets} WHERE id=?`, [...Object.values(upd), req.params.id]);
    await log('reseller', req.user.id, 'UPDATE_CLIENT', 'client', req.params.id, upd, req.ip);
    res.json({ message: 'Client mis à jour' });
  } catch (e) { res.status(500).json({ error: 'Erreur serveur' }); }
});

app.delete('/api/reseller/clients/:id', R, authWriteLimiter, async (req, res) => {
  try {
    const [[c]] = await db.query('SELECT * FROM clients WHERE id=? AND reseller_id=?', [req.params.id, req.user.id]);
    if (!c) return res.status(404).json({ error: 'Client introuvable' });
    await removeTunnel(c);
    await db.query('DELETE FROM usage_stats WHERE client_id=?', [req.params.id]);
    await db.query('DELETE FROM clients WHERE id=?', [req.params.id]);
    await db.query('UPDATE resellers SET used_users=used_users-1 WHERE id=? AND used_users>0', [req.user.id]);
    await log('reseller', req.user.id, 'DELETE_CLIENT', 'client', req.params.id, null, req.ip);
    res.json({ message: 'Client supprimé' });
  } catch (e) { res.status(500).json({ error: 'Erreur serveur' }); }
});

// ============================================================
// HELPER : lecture domaine VPS (multi-sources dont ~/.kighmu_info)
// ============================================================
function getVpsDomain() {
  const readFile = (p) => { try { return require('fs').readFileSync(p,'utf8').trim(); } catch { return null; } };
  const parseKV  = (p, key) => {
    try {
      const txt = require('fs').readFileSync(p, 'utf8');
      const m = txt.match(new RegExp('^' + key + '=(.+)$', 'm'));
      return m && m[1].trim() ? m[1].trim() : null;
    } catch { return null; }
  };

  // 1. /etc/kighmu/domain.txt — mais seulement si c'est un vrai domaine (pas une IP pure)
  const domainTxt = readFile('/etc/kighmu/domain.txt');
  if (domainTxt && !/^\d+\.\d+\.\d+\.\d+$/.test(domainTxt)) return domainTxt;

  // 2. ~/.kighmu_info → DOMAIN= (écrit par menu1.sh et install-1.sh corrigé)
  const fromKighmuInfo = parseKV(`${process.env.HOME || '/root'}/.kighmu_info`, 'DOMAIN');
  if (fromKighmuInfo && !/^\d+\.\d+\.\d+\.\d+$/.test(fromKighmuInfo)) return fromKighmuInfo;

  // 3. .install_info (écrit par install-1.sh)
  const fromInstallInfo = parseKV('/opt/kighmu-panel/.install_info', 'DOMAIN');
  if (fromInstallInfo && !/^\d+\.\d+\.\d+\.\d+$/.test(fromInstallInfo)) return fromInstallInfo;

  // 4. /etc/xray/domain ou /tmp/.xray_domain
  const xrayDomain = readFile('/etc/xray/domain') || readFile('/tmp/.xray_domain');
  if (xrayDomain && !/^\d+\.\d+\.\d+\.\d+$/.test(xrayDomain)) return xrayDomain;

  // 5. Fallback IP (si aucun domaine trouvé, retourner ce qu'on a)
  return fromKighmuInfo || fromInstallInfo || domainTxt || xrayDomain || null;
}

// ============================================================
// VPS INFO ROUTES
// ============================================================
app.get('/api/admin/vps-info', A, authWriteLimiter, async (req, res) => {
  try {
    const readFile = (p) => { try { return fs.readFileSync(p,'utf8').trim(); } catch { return null; } };
    const domain = getVpsDomain();
    let hostIp = null;
    try { const nets = await si.networkInterfaces(); const eth = nets.find(n => !n.internal && n.ip4); hostIp = eth?.ip4 || null; } catch {}
    const slowdnsKey = readFile('/etc/slowdns/server.pub')       || null;
    const slowdnsNs  = readFile('/etc/slowdns/ns.conf')          || null;
    const slowdnsKeyV2 = readFile('/etc/slowdns/nv4/server.pub') || readFile('/etc/slowdns_v2ray/server.pub') || readFile('/etc/slowdns/server.pub') || null;
    const slowdnsNsV2  = readFile('/etc/slowdns/nv4/ns.conf')   || readFile('/etc/slowdns_v2ray/ns.conf')    || null;
    const xrayDomain = readFile('/etc/xray/domain') || readFile('/tmp/.xray_domain') || domain;
    const v2rayDomain = readFile('/.v2ray_domain') || domain;
    let hysteriaPort = '20000';
    try { const hCfg = JSON.parse(readFile('/etc/hysteria/config.json') || '{}'); hysteriaPort = (hCfg.listen || ':20000').replace(':','') || '20000'; } catch {}
    let zivpnPort = '5667';
    try { const zCfg = JSON.parse(readFile('/etc/zivpn/config.json') || '{}'); zivpnPort = (zCfg.listen || ':5667').replace(':','') || '5667'; } catch {}
    res.json({ domain, xray_domain: xrayDomain, v2ray_domain: v2rayDomain, host_ip: hostIp, slowdns_key: slowdnsKey, slowdns_ns: slowdnsNs, slowdns_key_v2ray: slowdnsKeyV2, slowdns_ns_v2ray: slowdnsNsV2, hysteria_port: hysteriaPort, hysteria_port_range: `${hysteriaPort}-50000`, zivpn_port: zivpnPort, ssh_ports: { ws: '80', ssl: '444', proxy_ws: '9090', udp: '1-65535', slowdns: '5300', dropbear: '2222', badvpn: '7200,7300' } });
  } catch (e) { res.status(500).json({ error: 'Erreur serveur' }); }
});

app.get('/api/reseller/vps-info', R, async (req, res) => {
  const readFile = (p) => { try { return fs.readFileSync(p,'utf8').trim(); } catch { return null; } };
  const domain = getVpsDomain();
  let hostIp = null;
  try { const nets = await si.networkInterfaces(); const eth = nets.find(n=>!n.internal&&n.ip4); hostIp=eth?.ip4||null; } catch {}
  const slowdnsKey = readFile('/etc/slowdns/server.pub')       || null;
  const slowdnsNs  = readFile('/etc/slowdns/ns.conf')          || null;
  const slowdnsKeyV2 = readFile('/etc/slowdns/nv4/server.pub') || readFile('/etc/slowdns_v2ray/server.pub') || readFile('/etc/slowdns/server.pub') || null;
  const slowdnsNsV2  = readFile('/etc/slowdns/nv4/ns.conf')   || readFile('/etc/slowdns_v2ray/ns.conf')    || null;
  let hysteriaPort='20000'; try { const h=JSON.parse(readFile('/etc/hysteria/config.json')||'{}'); hysteriaPort=(h.listen||':20000').replace(':','')||'20000'; } catch {}
  let zivpnPort='5667'; try { const z=JSON.parse(readFile('/etc/zivpn/config.json')||'{}'); zivpnPort=(z.listen||':5667').replace(':','')||'5667'; } catch {}
  res.json({ domain, host_ip: hostIp, slowdns_key: slowdnsKey, slowdns_ns: slowdnsNs, slowdns_key_v2ray: slowdnsKeyV2, slowdns_ns_v2ray: slowdnsNsV2, hysteria_port: hysteriaPort, hysteria_port_range: `${hysteriaPort}-50000`, zivpn_port: zivpnPort, xray_domain: readFile('/etc/xray/domain')||readFile('/tmp/.xray_domain')||domain, v2ray_domain: readFile('/.v2ray_domain')||domain, ssh_ports: { ws:'80', ssl:'444', proxy_ws:'9090', udp:'1-65535', slowdns:'5300' } });
});

// ============================================================
// ROUTE RAPPORT TRAFIC
// ============================================================
app.post('/api/report/traffic', writeLimiter, async (req, res) => {
  try {
    const secret = req.headers['x-report-secret'] || req.body.secret;
    if (secret !== (REPORT_SECRET))
      return res.status(403).json({ error: 'Secret invalide' });
    const { stats } = req.body;
    if (!Array.isArray(stats)) return res.status(400).json({ error: 'Format: { stats:[{username,upload_bytes,download_bytes}] }' });
    let updated = 0, totalUp = 0, totalDown = 0;
    for (const s of stats) {
      if (!s.username) continue;
      const up   = parseInt(s.upload_bytes)   || 0;
      const down = parseInt(s.download_bytes) || 0;
      if (up === 0 && down === 0) continue;
      totalUp += up; totalDown += down;
      const [[c]] = await db.query('SELECT id, reseller_id FROM clients WHERE username=?', [s.username]);
      if (!c) continue;
      const [[ex]] = await db.query('SELECT id FROM usage_stats WHERE client_id=? ORDER BY recorded_at DESC LIMIT 1', [c.id]).catch(() => [[null]]);
      if (ex) {
        await db.query('UPDATE usage_stats SET upload_bytes=upload_bytes+?, download_bytes=download_bytes+?, recorded_at=NOW() WHERE id=?', [up, down, ex.id]);
      } else {
        await db.query('INSERT INTO usage_stats (client_id, reseller_id, upload_bytes, download_bytes) VALUES (?,?,?,?)', [c.id, c.reseller_id || null, up, down]);
      }
      updated++;
    }
    if (totalUp > 0 || totalDown > 0) {
      const d = new Date();
      await db.query(
        'INSERT INTO monthly_totals (year,month,total_upload,total_download) VALUES (?,?,?,?) ON DUPLICATE KEY UPDATE total_upload=total_upload+VALUES(total_upload), total_download=total_download+VALUES(total_download)',
        [d.getFullYear(), d.getMonth()+1, totalUp, totalDown]
      );
    }
    res.json({ ok: true, updated });
  } catch (e) { res.status(500).json({ error: 'Erreur serveur' }); }
});

app.post('/api/report/traffic/set', writeLimiter, async (req, res) => {
  try {
    const secret = req.headers['x-report-secret'] || req.body.secret;
    if (secret !== (REPORT_SECRET))
      return res.status(403).json({ error: 'Secret invalide' });
    const { username, upload_bytes, download_bytes } = req.body;
    if (!username) return res.status(400).json({ error: 'username requis' });
    const up   = parseInt(upload_bytes)   || 0;
    const down = parseInt(download_bytes) || 0;
    const [[c]] = await db.query('SELECT id, reseller_id FROM clients WHERE username=?', [username]);
    if (!c) return res.status(404).json({ error: 'Client introuvable' });
    const [[ex]] = await db.query('SELECT id FROM usage_stats WHERE client_id=? LIMIT 1', [c.id]).catch(() => [[null]]);
    if (ex) {
      await db.query('UPDATE usage_stats SET upload_bytes=?, download_bytes=?, recorded_at=NOW() WHERE id=?', [up, down, ex.id]);
    } else {
      await db.query('INSERT INTO usage_stats (client_id, reseller_id, upload_bytes, download_bytes) VALUES (?,?,?,?)', [c.id, c.reseller_id || null, up, down]);
    }
    if (up > 0 || down > 0) {
      const d = new Date();
      await db.query(
        'INSERT INTO monthly_totals (year,month,total_upload,total_download) VALUES (?,?,?,?) ON DUPLICATE KEY UPDATE total_upload=total_upload+VALUES(total_upload), total_download=total_download+VALUES(total_download)',
        [d.getFullYear(), d.getMonth()+1, up, down]
      );
    }
    res.json({ ok: true });
  } catch (e) { res.status(500).json({ error: 'Erreur serveur' }); }
});

// ============================================================
// SPA ROUTING — avec injection nonce CSP
// ============================================================
const htmlCache = {};
function serveHTML(filePath, req, res) {
  try {
    if (!fs.existsSync(filePath)) return res.status(404).send('Fichier introuvable');
    if (!htmlCache[filePath]) htmlCache[filePath] = fs.readFileSync(filePath, 'utf8');
    let html = htmlCache[filePath];
    if (req.nonce) html = html.replace(/__NONCE__/g, req.nonce);
    res.type('html').send(html);
  } catch (e) {
    res.status(500).send('Erreur serveur');
  }
}
app.get('/admin*',    (req, res) => serveHTML(path.join(FRONTEND, 'admin/index.html'), req, res));
app.get('/reseller*', (req, res) => serveHTML(path.join(FRONTEND, 'reseller/index.html'), req, res));
app.get('*',          (req, res) => serveHTML(path.join(FRONTEND, 'index.html'), req, res));

app.use((err, req, res, next) => {
  console.error('[ERROR]', err.message);
  res.status(500).json({ error: 'Erreur interne du serveur' });
});

process.on('uncaughtException',  e => console.error('[UNCAUGHT]', e.message));
process.on('unhandledRejection', e => console.error('[UNHANDLED]', e));

// ============================================================
// CRON JOBS
// ============================================================
function startCron() {
  // ── Health check DB toutes les 30s (reconnexion auto si MySQL crash) ──
  setInterval(async () => {
    if (db) await dbHealthCheck();
  }, 30000);

  // ── Sync regles nftables SSH toutes les 10 min (recuperation apres reboot) ──
  setInterval(async () => {
    if (db) await syncAllSshRules();
  }, 600000);

  cron.schedule('*/5 * * * *', async () => { // toutes les 5 min pour blocage rapide
    const ok = db ? await dbHealthCheck() : false;
    if (!ok) return;
    try {
      const [expiredResellers] = await db.query('SELECT id, username FROM resellers WHERE expires_at < NOW()');
      for (const r of expiredResellers) {
        console.log(`[CRON] Revendeur expiré: ${r.username} (#${r.id}) — nettoyage...`);
        await cleanupReseller(r.id);
        await db.query('DELETE FROM resellers WHERE id=?', [r.id]);
        await db.query("INSERT INTO activity_logs (actor_type,actor_id,action,target_type,target_id,details) VALUES ('admin',0,'AUTO_EXPIRE_RESELLER','reseller',?,?)", [r.id, JSON.stringify({username:r.username,reason:'Expiration automatique'})]);
      }
      if (expiredResellers.length) console.log(`[CRON] ${expiredResellers.length} revendeur(s) expiré(s) supprimés`);

      const [expClients] = await db.query('SELECT * FROM clients WHERE expires_at < NOW() AND is_active=1');
      for (const c of expClients) {
        await removeTunnel(c);
        await db.query('UPDATE clients SET is_active=0 WHERE id=?', [c.id]);
      }
      if (expClients.length) console.log(`[CRON] ${expClients.length} client(s) expiré(s) désactivés`);

      const [clientsWithQuota] = await db.query(`
        SELECT c.id, c.username, c.tunnel_type, c.uuid, c.password, c.expires_at,
               c.data_limit_gb, c.quota_blocked, c.is_active,
               COALESCE(SUM(u.upload_bytes+u.download_bytes),0) as total_bytes
        FROM clients c LEFT JOIN usage_stats u ON u.client_id=c.id
        WHERE c.data_limit_gb>0 AND c.is_active=1 GROUP BY c.id`);
      for (const c of clientsWithQuota) {
        const usedGb  = c.total_bytes / (1024*1024*1024);
        const limitGb = parseFloat(c.data_limit_gb);
        if (usedGb >= limitGb && !c.quota_blocked) {
          await blockTunnel(c);
          await db.query('UPDATE clients SET quota_blocked=1, is_active=0 WHERE id=?', [c.id]);
          console.log(`[CRON] Quota dépassé → bloqué: ${c.username} (${usedGb.toFixed(2)}GB/${limitGb}GB)`);
        }
      }

      // ── Quota revendeur ─────────────────────────────────────────────────
      // Requête : revendeurs dont le quota est dépassé ET pas encore bloqués
      const [resellersWithQuota] = await db.query(`
        SELECT r.id, r.username, r.data_limit_gb,
               COALESCE(SUM(u.upload_bytes+u.download_bytes),0) as total_bytes
        FROM resellers r LEFT JOIN usage_stats u ON u.reseller_id=r.id
        WHERE r.data_limit_gb>0 AND r.is_active=1 AND r.quota_blocked=0 GROUP BY r.id
        HAVING total_bytes >= (r.data_limit_gb * 1073741824)`);
      for (const r of resellersWithQuota) {
        const usedGb  = r.total_bytes / (1024*1024*1024);
        const limitGb = parseFloat(r.data_limit_gb);
        console.log(`[CRON] Quota revendeur dépassé: ${r.username} (${usedGb.toFixed(2)}GB/${limitGb}GB) — blocage immédiat...`);

        // 1. Bloquer TOUS les clients actifs du revendeur (retire de Xray/SSH/etc.)
        const [rClients] = await db.query('SELECT * FROM clients WHERE reseller_id=? AND is_active=1', [r.id]);
        for (const c of rClients) {
          await blockTunnel(c);
          await db.query('UPDATE clients SET quota_blocked=1, is_active=0 WHERE id=?', [c.id]);
        }

        // 2. Marquer le revendeur lui-même comme quota_blocked (bloque la création de nouveaux clients)
        await db.query('UPDATE resellers SET quota_blocked=1 WHERE id=?', [r.id]);

        await log('admin', 0, 'QUOTA_BLOCK_RESELLER', 'reseller', r.id, {
          username: r.username,
          used_gb: usedGb.toFixed(3),
          limit_gb: limitGb,
          clients_blocked: rClients.length
        }, null);
        console.log(`[CRON] Revendeur ${r.username} bloqué — ${rClients.length} client(s) coupé(s)`);
      }
    } catch (e) { console.error('[CRON] erreur:', e.message); }
  });

  cron.schedule('0 0 * * *', async () => {
    if (!db) return;
    try { await db.query("DELETE FROM login_attempts WHERE last_attempt < DATE_SUB(NOW(), INTERVAL 1 DAY)"); } catch {}
  });

  // Nouveau mois : un nouveau total mensuel commence à 0 (les anciens restent archivés)
  cron.schedule('5 0 1 * *', async () => {
    if (!db) return;
    try {
      const d = new Date();
      await db.query(
        'INSERT INTO monthly_totals (year,month,total_upload,total_download) VALUES (?,?,0,0) ON DUPLICATE KEY UPDATE total_upload=0, total_download=0',
        [d.getFullYear(), d.getMonth()+1]
      );
      console.log('[CRON] Nouveau mois — total mensuel réinitialisé');
    } catch(e) { console.error('[CRON] Erreur reset mensuel:', e.message); }
  });

  console.log('[CRON] Jobs démarrés (vérif quota + expiration toutes les heures)');
}

// ============================================================
// DÉMARRAGE
// ============================================================
async function start() {
  const PORT = parseInt(process.env.PORT || '3000');
  let connected = false;
  for (let i = 1; i <= 3; i++) {
    console.log(`[DB] Tentative de connexion ${i}/3...`);
    connected = await initDB();
    if (connected) break;
    if (i < 3) await new Promise(r => setTimeout(r, 3000));
  }
  if (!connected) {
    console.error('[FATAL] Impossible de se connecter à MySQL après 3 tentatives.');
    console.error('[FATAL] Le serveur démarre quand même — les routes /api renverront 503');
  }
  await ensureKighmuTable().catch(e => console.warn('[SSH-RULES] nftables non disponible:', e.message));
  app.listen(PORT, '127.0.0.1', () => {
    console.log('');
    console.log('╔══════════════════════════════════════╗');
    console.log(`║   KIGHMU PANEL v2 — port ${PORT}       ║`);
    console.log('╚══════════════════════════════════════╝');
    console.log(`  → http://0.0.0.0:${PORT}/admin`);
    console.log(`  → http://0.0.0.0:${PORT}/reseller`);
    console.log(`  DB: ${connected ? 'connectée ✓' : 'ERREUR ✗'}`);
    console.log('');
  });
  if (connected) {
    await syncAllSshRules();
    await resyncV2rayClients().catch(e => console.error('[V2RAY-RESYNC] Erreur démarrage:', e.message));
    startCron();
  }
}

start().catch(e => {
  console.error('[FATAL] Erreur démarrage:', e.message);
  process.exit(1);
});
SRVEOF

    # ── admin.html ──
    cat > "$DIR/admin.html" << 'ADMEOF'
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>Kighmu — Admin</title>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500;700&display=swap" rel="stylesheet">
<style>
:root{--bg:#030712;--surface:#0d1117;--card:#111827;--card2:#1a2235;--border:rgba(0,200,255,.12);--borderB:rgba(0,200,255,.35);--cyan:#00c8ff;--cyanD:rgba(0,200,255,.15);--purple:#7c3aed;--purpleD:rgba(124,58,237,.15);--green:#10b981;--greenD:rgba(16,185,129,.15);--red:#ef4444;--redD:rgba(239,68,68,.15);--yellow:#f59e0b;--yellowD:rgba(245,158,11,.15);--text:#e2e8f0;--dim:#94a3b8;--muted:#475569;--mono:'JetBrains Mono',monospace;--ui:'Inter',sans-serif;--r:6px;--tr:.22s cubic-bezier(.4,0,.2,1)}
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
body{background:var(--bg);color:var(--text);font-family:var(--ui);font-size:15px;line-height:1.5;min-height:100vh;overflow-x:hidden}
.grid{position:fixed;inset:0;z-index:0;pointer-events:none;background-image:linear-gradient(rgba(0,200,255,.02) 1px,transparent 1px),linear-gradient(90deg,rgba(0,200,255,.02) 1px,transparent 1px);background-size:50px 50px}
/* LAYOUT */
.layout{display:flex;min-height:100vh;position:relative;z-index:1}
.sidebar{width:235px;min-height:100vh;background:var(--surface);border-right:1px solid var(--border);display:flex;flex-direction:column;position:fixed;top:0;left:0;z-index:100;transition:transform var(--tr)}
.s-logo{padding:1.25rem 1.5rem;border-bottom:1px solid var(--border)}
.s-logo .lt{font-family:var(--mono);font-size:1.15rem;letter-spacing:.25em;background:linear-gradient(135deg,var(--cyan),var(--purple));-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text;text-transform:uppercase}
.s-logo .ls{font-size:.62rem;color:var(--muted);letter-spacing:.3em;text-transform:uppercase;margin-top:2px}
.s-nav{flex:1;padding:.75rem 0;overflow-y:auto}
.s-sec{padding:.5rem 1rem .2rem;font-size:.62rem;letter-spacing:.3em;text-transform:uppercase;color:var(--muted)}
.nav{display:flex;align-items:center;gap:.65rem;padding:.6rem 1.2rem;cursor:pointer;color:var(--dim);font-size:.88rem;font-weight:500;transition:all var(--tr);border-left:2px solid transparent;text-decoration:none}
.nav:hover{color:var(--text);background:var(--cyanD)}
.nav.active{color:var(--cyan);background:var(--cyanD);border-left-color:var(--cyan)}
.nav .ic{width:18px;font-size:.95rem}
.s-foot{padding:.9rem 1.2rem;border-top:1px solid var(--border)}
.s-user{font-family:var(--mono);color:var(--cyan);font-size:.88rem;margin-bottom:.25rem}
.main{margin-left:235px;flex:1;display:flex;flex-direction:column;min-height:100vh}
.topbar{height:58px;background:var(--surface);border-bottom:1px solid var(--border);display:flex;align-items:center;justify-content:space-between;padding:0 1.25rem;position:sticky;top:0;z-index:50}
.tb-title{font-family:var(--mono);font-size:.82rem;color:var(--dim);letter-spacing:.08em}
.tb-title span{color:var(--cyan)}
.tb-acts{display:flex;align-items:center;gap:.65rem}
/* PAGES */
.page{padding:1.25rem;display:none}
.page.active{display:block}
.ptitle{font-size:1.4rem;font-weight:700;margin-bottom:.2rem;letter-spacing:.04em}
.psub{color:var(--dim);font-size:.82rem;margin-bottom:1.25rem}
/* STATS */
.sgrid{display:grid;grid-template-columns:repeat(auto-fit,minmax(185px,1fr));gap:.875rem;margin-bottom:1.25rem}
.scard{background:var(--card);border:1px solid var(--border);border-radius:var(--r);padding:1.1rem;position:relative;overflow:hidden;transition:border-color var(--tr)}
.scard::before{content:'';position:absolute;top:0;left:0;right:0;height:2px;background:linear-gradient(90deg,var(--cyan),var(--purple));opacity:0;transition:opacity var(--tr)}
.scard:hover{border-color:var(--borderB)}.scard:hover::before{opacity:1}
.scard-lbl{font-size:.67rem;letter-spacing:.2em;text-transform:uppercase;color:var(--muted);margin-bottom:.4rem}
.scard-val{font-family:var(--mono);font-size:1.65rem}
.scard-ico{position:absolute;top:1rem;right:1rem;font-size:1.3rem;opacity:.28}
.scard.c .scard-val{color:var(--cyan)}.scard.g .scard-val{color:var(--green)}.scard.p .scard-val{color:#a78bfa}.scard.y .scard-val{color:var(--yellow)}
/* CARD */
.card{background:var(--card);border:1px solid var(--border);border-radius:var(--r);margin-bottom:1.25rem}
.ch{display:flex;align-items:center;justify-content:space-between;padding:.875rem 1.1rem;border-bottom:1px solid var(--border)}
.ct{font-size:.78rem;font-weight:600;letter-spacing:.1em;text-transform:uppercase;color:var(--dim)}
.cb{padding:1.1rem}
/* TABLE */
.tw{overflow-x:auto}
table{width:100%;border-collapse:collapse;font-size:.835rem}
thead th{text-align:left;padding:.55rem .9rem;font-size:.67rem;letter-spacing:.15em;text-transform:uppercase;color:var(--muted);border-bottom:1px solid var(--border);background:var(--surface);font-weight:600}
tbody tr{border-bottom:1px solid rgba(255,255,255,.03);transition:background var(--tr)}
tbody tr:hover{background:rgba(0,200,255,.03)}
tbody td{padding:.65rem .9rem;color:var(--dim);font-family:var(--mono);font-size:.8rem}
td.nm{color:var(--text);font-family:var(--ui);font-weight:600}
/* BADGE */
.b{display:inline-block;padding:.12rem .55rem;border-radius:100px;font-size:.67rem;font-weight:700;letter-spacing:.05em;text-transform:uppercase;font-family:var(--mono)}
.bg{background:var(--greenD);color:var(--green);border:1px solid rgba(16,185,129,.3)}
.br{background:var(--redD);color:var(--red);border:1px solid rgba(239,68,68,.3)}
.bc{background:var(--cyanD);color:var(--cyan);border:1px solid rgba(0,200,255,.3)}
.by{background:var(--yellowD);color:var(--yellow);border:1px solid rgba(245,158,11,.3)}
.bp{background:var(--purpleD);color:#a78bfa;border:1px solid rgba(124,58,237,.3)}
/* BTN */
.btn{display:inline-flex;align-items:center;gap:.45rem;padding:.48rem 1rem;border-radius:var(--r);font-family:var(--ui);font-size:.82rem;font-weight:600;cursor:pointer;border:1px solid transparent;transition:all var(--tr);white-space:nowrap}
.btn:disabled{opacity:.5;cursor:not-allowed}
.btn-c{background:var(--cyanD);border-color:rgba(0,200,255,.4);color:var(--cyan)}.btn-c:hover:not(:disabled){background:var(--cyan);color:var(--bg)}
.btn-r{background:var(--redD);border-color:rgba(239,68,68,.4);color:var(--red)}.btn-r:hover:not(:disabled){background:var(--red);color:#fff}
.btn-g{background:var(--greenD);border-color:rgba(16,185,129,.4);color:var(--green)}.btn-g:hover:not(:disabled){background:var(--green);color:#fff}
.btn-p{background:var(--purpleD);border-color:rgba(124,58,237,.4);color:#a78bfa}.btn-p:hover:not(:disabled){background:var(--purple);color:#fff}
.btn-gh{background:transparent;border-color:var(--border);color:var(--dim)}.btn-gh:hover:not(:disabled){border-color:var(--borderB);color:var(--text)}
.btn-sm{padding:.28rem .65rem;font-size:.75rem}
.btn-ic{padding:.35rem}
/* FORM */
.fgrid{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:.875rem}
.fg{display:flex;flex-direction:column;gap:.3rem}
.fl{font-size:.68rem;letter-spacing:.15em;text-transform:uppercase;color:var(--muted);font-weight:600}
.fc{background:var(--bg);border:1px solid var(--border);border-radius:var(--r);padding:.55rem .8rem;color:var(--text);font-family:var(--mono);font-size:.82rem;outline:none;transition:border-color var(--tr);width:100%}
.fc:focus{border-color:var(--cyan);box-shadow:0 0 0 2px rgba(0,200,255,.1)}
.fc::placeholder{color:var(--muted)}
select.fc option{background:var(--card)}
/* MODAL */
.mo{position:fixed;inset:0;z-index:1000;background:rgba(3,7,18,.82);backdrop-filter:blur(4px);display:none;align-items:center;justify-content:center;padding:1rem}
.mo.open{display:flex}
.modal{background:var(--card);border:1px solid var(--borderB);border-radius:var(--r);width:100%;max-width:500px;box-shadow:0 0 60px rgba(0,200,255,.1);animation:mIn .22s ease}
@keyframes mIn{from{opacity:0;transform:translateY(-18px) scale(.97)}to{opacity:1;transform:none}}
.mh{display:flex;align-items:center;justify-content:space-between;padding:1.1rem 1.25rem;border-bottom:1px solid var(--border)}
.mt{font-size:.95rem;font-weight:700;letter-spacing:.04em}
.mb{padding:1.1rem 1.25rem}
.mf{display:flex;justify-content:flex-end;gap:.65rem;padding:.875rem 1.25rem;border-top:1px solid var(--border)}
/* PROGRESS */
.prg{height:5px;background:var(--bg);border-radius:3px;overflow:hidden}
.prg-b{height:100%;border-radius:3px;background:linear-gradient(90deg,var(--cyan),var(--purple));transition:width .5s}
.prg-b.warn{background:linear-gradient(90deg,var(--yellow),#f97316)}
.prg-b.crit{background:linear-gradient(90deg,#f97316,var(--red));animation:pulse-q .8s ease-in-out infinite alternate}
@keyframes pulse-q{from{opacity:1}to{opacity:.5}}
/* MONITOR */
.mgrid{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:1rem}
.mi{display:flex;flex-direction:column;gap:.4rem}
.ml{display:flex;justify-content:space-between;font-size:.78rem}
.mk{color:var(--dim);text-transform:uppercase;letter-spacing:.1em;font-size:.68rem}
.mv{color:var(--cyan);font-family:var(--mono)}
/* TOAST */
.tc{position:fixed;bottom:1.25rem;right:1.25rem;z-index:9999;display:flex;flex-direction:column;gap:.4rem}
.toast{background:var(--card);border:1px solid var(--border);border-radius:var(--r);padding:.65rem .9rem;font-size:.8rem;min-width:230px;display:flex;align-items:center;gap:.45rem;animation:tIn .25s;box-shadow:0 4px 20px rgba(0,0,0,.4)}
@keyframes tIn{from{opacity:0;transform:translateX(16px)}to{opacity:1}}
.toast.s{border-left:3px solid var(--green)}.toast.e{border-left:3px solid var(--red)}.toast.i{border-left:3px solid var(--cyan)}
/* TUNNEL SELECTOR */
.tgrid{display:grid;grid-template-columns:repeat(auto-fill,minmax(145px,1fr));gap:.65rem;margin-bottom:.875rem}
.tc2{background:var(--surface);border:2px solid var(--border);border-radius:var(--r);padding:.9rem .65rem;cursor:pointer;text-align:center;transition:all var(--tr);user-select:none}
.tc2:hover{border-color:var(--borderB);background:rgba(0,200,255,.04)}
.tc2.sel{border-color:var(--cyan);background:var(--cyanD);box-shadow:0 0 14px rgba(0,200,255,.13)}
.tc2.ssh.sel{border-color:var(--green);background:var(--greenD)}
.tc2.udp.sel{border-color:var(--red);background:var(--redD)}
.tc2.v2.sel{border-color:#a78bfa;background:var(--purpleD)}
.tci{font-size:1.5rem;margin-bottom:.3rem;color:var(--muted)}
.tc2.sel .tci{color:var(--cyan)}.tc2.ssh.sel .tci{color:var(--green)}.tc2.udp.sel .tci{color:var(--red)}.tc2.v2.sel .tci{color:#a78bfa}
.tlb{font-size:.76rem;font-weight:700;letter-spacing:.05em;color:var(--dim)}
.tsb{font-size:.64rem;color:var(--muted);margin-top:2px}
/* RESULT */
.rescard{background:var(--surface);border:1px solid var(--borderB);border-radius:var(--r);margin-top:1.25rem;overflow:hidden;animation:mIn .25s;max-width:780px}
.rh{background:linear-gradient(90deg,rgba(0,200,255,.1),rgba(124,58,237,.1));padding:.65rem 1.1rem;display:flex;align-items:center;justify-content:space-between;border-bottom:1px solid var(--border)}
.rt{color:var(--cyan);font-weight:700;font-size:.88rem}
.rbody{padding:1.1rem}
.rrow{display:flex;align-items:center;gap:.9rem;padding:.5rem 0;border-bottom:1px solid rgba(255,255,255,.04)}
.rrow:last-child{border:none}
.rk{font-size:.67rem;letter-spacing:.2em;text-transform:uppercase;color:var(--muted);min-width:90px}
.rv{font-family:var(--mono);font-size:.82rem;color:var(--text);word-break:break-all;flex:1}
.rv.hi{color:var(--cyan)}.rv.pw{color:var(--yellow)}.rv.uu{color:var(--dim);font-size:.76rem}
.cpbtn{padding:.18rem .5rem;font-size:.68rem;background:var(--card2);border:1px solid var(--border);border-radius:4px;color:var(--muted);cursor:pointer;transition:all var(--tr);white-space:nowrap}
.cpbtn:hover{border-color:var(--cyan);color:var(--cyan)}
/* ── Blocs résultat création tunnel ───────────────────── */
.tr-block{padding:1.1rem;font-family:var(--mono);font-size:.82rem;line-height:1.7}
.tr-block.udp   {border-left:3px solid var(--red)}
.tr-block.xray  {border-left:3px solid var(--blue)}
.tr-block.ssh   {border-left:3px solid var(--green)}
.tr-block.v2ray {border-left:3px solid var(--purple,#9f7aea)}
.tr-title{font-size:.9rem;font-weight:700;color:var(--text);margin-bottom:.6rem;letter-spacing:.02em}
.tr-sep{border-top:1px solid rgba(255,255,255,.07);margin:.6rem 0}
.tr-row{display:flex;align-items:flex-start;gap:.7rem;padding:.25rem 0;flex-wrap:wrap}
.tr-k{color:var(--muted);min-width:130px;flex-shrink:0;font-size:.75rem}
.tr-v{color:var(--text);word-break:break-all;flex:1}
.tr-v.hi{color:var(--cyan)}.tr-v.pw{color:var(--yellow)}.tr-v.uu{color:var(--dim);font-size:.76rem}
.tr-section-title{color:var(--muted);font-size:.72rem;margin:.35rem 0;letter-spacing:.05em;word-break:break-all}
.tr-pubkey{background:var(--bg3,rgba(0,0,0,.25));border-radius:5px;padding:.4rem .6rem;word-break:break-all;color:var(--green);font-size:.73rem;margin:.25rem 0}
.tr-links-header{color:var(--muted);font-size:.72rem;margin:.35rem 0}
.tr-link-row{display:flex;align-items:flex-start;gap:.5rem;padding:.2rem 0;flex-wrap:wrap}
.tr-lk{color:var(--cyan);min-width:110px;font-size:.74rem;flex-shrink:0}
.tr-lv{color:var(--dim);word-break:break-all;flex:1;font-size:.72rem}
.tr-payload{background:var(--bg3,rgba(0,0,0,.25));border-radius:5px;padding:.4rem .6rem;color:var(--yellow);font-size:.72rem;margin:.25rem 0;word-break:break-all}
.tr-status{padding:.4rem .7rem;border-radius:5px;font-size:.78rem;font-weight:600;margin-top:.6rem}
.tr-status.ok{background:rgba(72,187,120,.12);color:var(--green)}
.tr-status.warn{background:rgba(237,137,54,.12);color:var(--yellow)}
/* INFOBANNER */
.ibanner{background:linear-gradient(90deg,rgba(0,200,255,.05),rgba(124,58,237,.05));border:1px solid var(--border);border-radius:var(--r);padding:.75rem 1.1rem;display:flex;gap:2.25rem;margin-bottom:1.1rem;flex-wrap:wrap}
.ibi{display:flex;flex-direction:column}
.ibk{font-size:.62rem;letter-spacing:.2em;text-transform:uppercase;color:var(--muted)}
.ibv{font-family:var(--mono);font-size:1rem;color:var(--cyan)}
/* SEARCH */
.sbox{position:relative;display:inline-flex;align-items:center}
.sbox input{background:var(--surface);border:1px solid var(--border);border-radius:var(--r);padding:.42rem .7rem .42rem 1.85rem;color:var(--text);font-size:.78rem;outline:none;transition:border-color var(--tr)}
.sbox input:focus{border-color:var(--cyan)}
.sbox::before{content:'⌕';position:absolute;left:.55rem;color:var(--muted);font-size:.95rem;pointer-events:none}
/* MISC */
.ssep{display:flex;align-items:center;gap:.875rem;margin:1.25rem 0 .875rem;color:var(--muted);font-size:.68rem;letter-spacing:.2em;text-transform:uppercase;font-weight:700}
.ssep::after{content:'';flex:1;height:1px;background:var(--border)}
.dot{display:inline-block;width:8px;height:8px;border-radius:50%;margin-right:5px}
.dg{background:var(--green);box-shadow:0 0 5px var(--green)}.dr{background:var(--red);box-shadow:0 0 5px var(--red)}
.actg{display:flex;gap:.3rem;flex-wrap:nowrap}
.spin{display:inline-block;width:13px;height:13px;border:2px solid var(--border);border-top-color:var(--cyan);border-radius:50%;animation:spin .65s linear infinite}
@keyframes spin{to{transform:rotate(360deg)}}
.flex{display:flex}.aic{align-items:center}.jb{justify-content:space-between}.g1{gap:.5rem}.g2{gap:.875rem}.mt1{margin-top:.5rem}.mono{font-family:var(--mono)}.muted{color:var(--muted)}.sm{font-size:.78rem}
/* LOGIN */
.lpage{min-height:100vh;display:flex;align-items:center;justify-content:center;padding:1rem;position:relative}
.lglow{position:fixed;width:500px;height:500px;border-radius:50%;background:radial-gradient(circle,rgba(0,150,255,.07),transparent 70%);top:50%;left:50%;transform:translate(-50%,-50%);pointer-events:none}
.lbox{background:var(--card);border:1px solid var(--borderB);border-radius:8px;padding:2.25rem;width:100%;max-width:390px;position:relative;z-index:1;box-shadow:0 0 60px rgba(0,200,255,.08)}
.llogo{font-family:var(--mono);font-size:1.4rem;letter-spacing:.3em;text-align:center;background:linear-gradient(135deg,var(--cyan),var(--purple));-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text;margin-bottom:.4rem}
.lsub{text-align:center;color:var(--muted);font-size:.7rem;letter-spacing:.3em;text-transform:uppercase;margin-bottom:1.75rem}
.lsep{width:100%;height:1px;background:linear-gradient(90deg,transparent,var(--borderB),transparent);margin-bottom:1.75rem}
.lerr{background:var(--redD);border:1px solid rgba(239,68,68,.3);border-radius:var(--r);padding:.55rem .9rem;color:var(--red);font-size:.78rem;margin-bottom:.875rem;display:none}
.lbtn{width:100%;justify-content:center;padding:.7rem;font-size:.85rem;letter-spacing:.15em;text-transform:uppercase;background:linear-gradient(135deg,rgba(0,200,255,.18),rgba(124,58,237,.18));border:1px solid var(--borderB);color:var(--cyan);margin-top:1.25rem}
.lbtn:hover{background:linear-gradient(135deg,rgba(0,200,255,.35),rgba(124,58,237,.35));box-shadow:0 0 25px rgba(0,200,255,.2)}
/* RESPONSIVE */
.mbtn{display:none;background:none;border:none;color:var(--dim);font-size:1.1rem;cursor:pointer;padding:.2rem}
@media(max-width:768px){.sidebar{transform:translateX(-100%)}.sidebar.open{transform:none}.main{margin-left:0}.mbtn{display:block}.sgrid{grid-template-columns:1fr 1fr}.fgrid{grid-template-columns:1fr}.tgrid{grid-template-columns:repeat(3,1fr)}}
.hidden{display:none!important}

/* ── Sélecteur de tunnels ─────────────────────────── */
.tunnel-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(140px,1fr));gap:.4rem .5rem;margin-top:.3rem}
.tck{display:flex;align-items:center;gap:.45rem;padding:.38rem .6rem;border-radius:5px;border:1px solid rgba(255,255,255,.08);background:rgba(255,255,255,.03);cursor:pointer;transition:all .2s;user-select:none;font-size:.76rem}
.tck:hover{border-color:rgba(0,180,255,.4);background:rgba(0,180,255,.07)}
.tck input[type=checkbox]{accent-color:var(--ac);width:14px;height:14px;cursor:pointer;flex-shrink:0}
.tck.checked{border-color:rgba(0,180,255,.55);background:rgba(0,180,255,.12);color:var(--ac)}
.tck .tck-icon{font-size:.9rem}
.tck-all{font-size:.75rem;color:var(--dim);cursor:pointer;text-decoration:underline;margin-top:.25rem;display:inline-block}
.tck-group-label{font-size:.7rem;text-transform:uppercase;letter-spacing:.08em;color:var(--muted);grid-column:1/-1;margin-top:.3rem;padding-bottom:.1rem;border-bottom:1px solid rgba(255,255,255,.06)}
</style>
</head>
<body>
<div class="grid"></div>

<!-- LOGIN -->
<div id="LS">
  <div class="lpage">
    <div class="lglow"></div>
    <div class="lbox">
      <div class="llogo">KIGHMU</div>
      <div class="lsub">Accès Administrateur</div>
      <div class="lsep"></div>
      <div style="text-align:center;margin-bottom:1.25rem"><span class="b bc">ADMINISTRATOR</span></div>
      <div class="lerr" id="lerr"></div>
      <div class="fg"><label class="fl">Identifiant</label><input class="fc" id="lu" placeholder="admin" autocomplete="username"></div>
      <div id="pass-row" class="fg mt1"><label class="fl">Mot de passe</label><div class="flex g1"><input class="fc" type="password" id="lp" placeholder="••••••••" autocomplete="current-password" style="flex:1"><button class="btn btn-gh btn-sm" onclick="togglePw('lp',this)" type="button" tabindex="-1" style="font-size:1rem;line-height:1">👁</button></div></div>
      <button class="btn lbtn" id="lbtn" onclick="doLogin()"><span id="lbl">SE CONNECTER</span></button>
    </div>
  </div>
</div>

<!-- PANEL -->
<div id="PS" class="hidden">
  <div class="layout">
    <aside class="sidebar" id="sidebar">
      <div class="s-logo"><div class="lt">KIGHMU</div><div class="ls">Admin Panel</div></div>
      <nav class="s-nav">
        <div class="s-sec">Vue générale</div>
        <a class="nav active" data-p="dash" onclick="nav('dash')"><span class="ic">◈</span> Dashboard</a>
        <div class="s-sec">Tunnels</div>
        <a class="nav" data-p="create" onclick="nav('create')" style="border-left:2px solid rgba(0,200,255,.3)"><span class="ic" style="color:var(--cyan)">＋</span><span style="color:var(--cyan)">Créer un Tunnel</span></a>
        <a class="nav" data-p="clients" onclick="nav('clients');loadClients()"><span class="ic">◎</span> Tous les Clients</a>
        <div class="s-sec">Revendeurs</div>
        <a class="nav" data-p="resellers" onclick="nav('resellers');loadResellers()"><span class="ic">◉</span> Gérer Revendeurs</a>
        <div class="s-sec">Système</div>
        <a class="nav" data-p="system" onclick="nav('system');loadSystem()"><span class="ic">◇</span> Monitoring</a>
        <a class="nav" data-p="logs" onclick="nav('logs');loadLogs()"><span class="ic">≡</span> Logs</a>
      </nav>
      <div class="s-foot">
        <div style="display:flex;align-items:center;gap:.4rem;margin-bottom:.3rem"><span class="dot dg"></span><span class="s-user" id="su">admin</span></div>
        <div class="muted sm mono" id="ltime"></div>
        <div style="margin-top:.65rem"><button class="btn btn-r btn-sm" onclick="logout()" style="width:100%;justify-content:center">⊗ Déconnexion</button></div>
      </div>
    </aside>

    <main class="main">
      <div class="topbar">
        <div class="flex aic g1"><button class="mbtn" id="mbtn">☰</button><div class="tb-title" id="ptitle"><span>⬡</span> Dashboard</div></div>
        <div class="tb-acts">
          <span class="b bc" id="tu">ADMIN</span>
          <button class="btn btn-c btn-sm" onclick="nav('create')" style="letter-spacing:.04em">＋ Créer Tunnel</button>
          <button class="btn btn-gh btn-sm" onclick="refresh()">⟳</button>
        </div>
      </div>

      <!-- PAGE DASHBOARD -->
      <div class="page active" id="page-dash">
        <div class="ptitle">Dashboard</div>
        <div class="psub">Vue globale du système Kighmu</div>
        <div class="sgrid">
          <div class="scard c"><div class="scard-lbl">Revendeurs</div><div class="scard-val" id="s0">—</div><div class="scard-ico">◉</div></div>
          <div class="scard"><div class="scard-lbl">Total Clients</div><div class="scard-val" id="s1">—</div><div class="scard-ico">◎</div></div>
          <div class="scard g"><div class="scard-lbl">Clients Actifs</div><div class="scard-val" id="s2">—</div><div class="scard-ico">✓</div></div>
          <div class="scard p"><div class="scard-lbl">Upload Total</div><div class="scard-val" id="s3">—</div><div class="scard-ico">↑</div></div>
          <div class="scard y"><div class="scard-lbl">Download Total</div><div class="scard-val" id="s4">—</div><div class="scard-ico">↓</div></div>
        </div>
        <!-- Widget consommation mensuelle -->
        <div class="card" style="margin-top:.75rem">
          <div class="ch">
            <div class="ct">📅 Consommation du Mois <span class="muted" id="monthLabel" style="font-size:.75rem;font-weight:400"></span></div>
            <div class="flex g1">
              <button class="btn btn-gh btn-sm" onclick="loadDash()" title="Rafraîchir">⟳</button>
              <button class="btn btn-sm" style="background:rgba(239,68,68,.15);color:#ef4444;border:1px solid rgba(239,68,68,.3)" onclick="confirmMonthReset()" title="Réinitialiser les stats du mois">🗑 Reset</button>
            </div>
          </div>
          <div class="cb">
            <div style="display:flex;align-items:center;gap:2rem;flex-wrap:wrap;margin-bottom:.75rem">
              <div style="text-align:center">
                <div style="font-size:.72rem;color:var(--muted);margin-bottom:.2rem">↑ Upload mois</div>
                <div style="font-size:1.4rem;font-weight:700;color:var(--cyan)" id="mUp">—</div>
              </div>
              <div style="text-align:center">
                <div style="font-size:.72rem;color:var(--muted);margin-bottom:.2rem">↓ Download mois</div>
                <div style="font-size:1.4rem;font-weight:700;color:var(--yellow)" id="mDl">—</div>
              </div>
              <div style="text-align:center">
                <div style="font-size:.72rem;color:var(--muted);margin-bottom:.2rem">⇅ Total mois</div>
                <div style="font-size:1.6rem;font-weight:800;color:#a78bfa" id="mTotal">—</div>
              </div>
            </div>
            <div style="font-size:.72rem;color:var(--muted);margin-bottom:.4rem">Par revendeur ce mois :</div>
            <div id="mResellers" style="display:flex;flex-wrap:wrap;gap:.4rem"></div>
          </div>
        </div>
        <div class="card">
          <div class="ch"><div class="ct">◇ Système</div><button class="btn btn-gh btn-sm" onclick="loadDash()">⟳</button></div>
          <div class="cb"><div class="mgrid">
            <div class="mi"><div class="ml"><span class="mk">CPU</span><span class="mv" id="mc">—</span></div><div class="prg"><div class="prg-b" id="mcb" style="width:0%"></div></div></div>
            <div class="mi"><div class="ml"><span class="mk">RAM</span><span class="mv" id="mr">—</span></div><div class="prg"><div class="prg-b" id="mrb" style="width:0%"></div></div></div>
            <div class="mi"><div class="ml"><span class="mk">Disque</span><span class="mv" id="md">—</span></div><div class="prg"><div class="prg-b" id="mdb" style="width:0%"></div></div></div>
          </div></div>
        </div>
        <div class="card">
          <div class="ch"><div class="ct">◉ Revendeurs</div><div class="flex g1"><button class="btn btn-c btn-sm" onclick="openM('mar');document.getElementById('rn_tunnels_wrap').innerHTML=buildTunnelGrid('rn',[])">+ Ajouter</button><button class="btn btn-gh btn-sm" onclick="nav('resellers');loadResellers()">Voir tout</button></div></div>
          <div class="cb" style="padding:0"><div class="tw"><table><thead><tr><th>Revendeur</th><th>Clients</th><th>Quota</th><th>Data</th><th>Tunnels</th><th>Expire</th><th>Statut</th></tr></thead><tbody id="dr"><tr><td colspan="6" style="text-align:center;padding:2rem;color:var(--muted)">Chargement...</td></tr></tbody></table></div></div>
        </div>
        <div class="card">
          <div class="ch"><div class="ct">◎ Derniers Clients</div><button class="btn btn-c btn-sm" onclick="nav('create')" style="background:linear-gradient(135deg,rgba(0,200,255,.15),rgba(124,58,237,.15))">＋ Créer Tunnel</button></div>
          <div class="cb" style="padding:0"><div class="tw"><table><thead><tr><th>Username</th><th>Tunnel</th><th>Revendeur</th><th>Expire</th><th>Statut</th></tr></thead><tbody id="dc"><tr><td colspan="5" style="text-align:center;padding:2rem;color:var(--muted)">Chargement...</td></tr></tbody></table></div></div>
        </div>
      </div>

      <!-- PAGE CRÉER TUNNEL -->
      <div class="page" id="page-create">
        <div class="ptitle">Créer un Tunnel</div>
        <div class="psub">Ajouter un utilisateur Xray (VLESS/VMESS/Trojan) · SSH · UDP · V2Ray FastDNS</div>
        <div class="card" style="max-width:800px">
          <div class="ch"><div class="ct">⬡ Nouveau Client Tunnel</div><span class="b bc">ADMIN</span></div>
          <div class="cb">
            <div class="ssep">1 — Type de tunnel</div>
            <div class="tgrid">
              <div class="tc2" data-t="vless" onclick="selT(this,'vless')"><div class="tci">⬡</div><div class="tlb">VLESS</div><div class="tsb">Xray</div></div>
              <div class="tc2" data-t="vmess" onclick="selT(this,'vmess')"><div class="tci">⬡</div><div class="tlb">VMESS</div><div class="tsb">Xray</div></div>
              <div class="tc2" data-t="trojan" onclick="selT(this,'trojan')"><div class="tci">⬡</div><div class="tlb">TROJAN</div><div class="tsb">Xray</div></div>
              <div class="tc2 ssh" data-t="ssh-multi" onclick="selT(this,'ssh-multi')"><div class="tci">⌘</div><div class="tlb">SSH MULTIPLE</div><div class="tsb">WS · SSL · SlowDNS · UDP</div></div>
              <div class="tc2 udp" data-t="udp-zivpn" onclick="selT(this,'udp-zivpn')"><div class="tci">⬢</div><div class="tlb">UDP ZIVPN</div><div class="tsb">Custom UDP</div></div>
              <div class="tc2 udp" data-t="udp-hysteria" onclick="selT(this,'udp-hysteria')"><div class="tci">⬢</div><div class="tlb">HYSTERIA</div><div class="tsb">UDP Custom</div></div>
              <div class="tc2 v2" data-t="v2ray-fastdns" onclick="selT(this,'v2ray-fastdns')"><div class="tci">◈</div><div class="tlb">V2Ray FastDNS</div><div class="tsb">FastDNS</div></div>
            </div>
            <div id="tsel" style="margin-bottom:.875rem;display:none"><span class="muted sm">Sélectionné : </span><span id="tsv" class="b bc" style="font-size:.8rem"></span></div>
            <div id="uuid-info" style="display:none;margin:.25rem 0 .75rem;padding:.5rem .75rem;background:rgba(99,179,237,.08);border-radius:6px;border-left:3px solid var(--blue,#63b3ed);font-size:.78rem;color:var(--muted)">
              ℹ️ <strong>UUID généré automatiquement</strong> — Aucun mot de passe requis pour ce type de tunnel. L'UUID sera affiché après la création.
            </div>
            <div class="ssep">2 — Informations</div>
            <div class="fgrid">
              <div class="fg"><label class="fl">Username *</label><input class="fc" id="cu" placeholder="ex: user_jean"></div>
              <div id="pass-row" class="fg"><label class="fl">Mot de passe <span class="muted">(auto si vide)</span> <span id="pass-hint" style="font-size:.7rem;color:var(--blue,#63b3ed);font-weight:400"></span></label><div class="flex g1"><input class="fc" id="cp" placeholder="(auto-généré)" style="flex:1"><button class="btn btn-gh btn-sm" onclick="genP()" title="Générer">⟳</button></div></div>
              <div class="fg"><label class="fl">Expiration *</label><input class="fc" type="datetime-local" id="ce"></div>
              <div class="fg"><label class="fl">Revendeur <span class="muted">(optionnel)</span></label><select class="fc" id="cr"><option value="">— Aucun (admin) —</option></select></div>
              <div class="fg"><label class="fl">Quota Data (Go) <span class="muted">(0=illimité)</span></label><input class="fc" type="number" id="cdl" min="0" step="0.5" value="0" placeholder="0 = illimité"></div>
              <div class="fg" style="grid-column:1/-1"><label class="fl">Note <span class="muted">(optionnel)</span></label><input class="fc" id="cn" placeholder="Ex: client VIP, abonnement mensuel..."></div>
            </div>
            <div class="flex g2 mt1" style="margin-top:1.25rem;flex-wrap:wrap">
              <button class="btn btn-c" id="csub" onclick="createT()" style="padding:.6rem 1.4rem"><span id="csubl">⬡ Créer le Tunnel</span></button>
              <button class="btn btn-gh" onclick="resetT()">✕ Réinitialiser</button>
            </div>
          </div>
        </div>
        <div class="rescard hidden" id="cres">
          <div class="rh"><div class="rt">✓ Tunnel créé avec succès</div><button class="cpbtn" onclick="document.getElementById('cres').classList.add('hidden')">✕</button></div>
          <div class="rbody" id="cresbody"></div>
        </div>
        <div class="card" style="max-width:800px;margin-top:1.25rem">
          <div class="ch"><div class="ct">◎ Créés cette session</div></div>
          <div class="cb" style="padding:0"><div class="tw"><table><thead><tr><th>Username</th><th>Password</th><th>UUID</th><th>Tunnel</th><th>Expire</th></tr></thead><tbody id="sess"><tr><td colspan="5" style="text-align:center;padding:1.25rem;color:var(--muted)">Aucun tunnel créé cette session</td></tr></tbody></table></div></div>
        </div>
      </div>

      <!-- PAGE CLIENTS -->
      <div class="page" id="page-clients">
        <div class="ptitle">Tous les Clients</div>
        <div class="psub">Vue complète admin de tous les utilisateurs tunnel</div>
        <div class="ibanner">
          <div class="ibi"><div class="ibk">Total</div><div class="ibv" id="cl0">—</div></div>
          <div class="ibi"><div class="ibk">Actifs</div><div class="ibv" id="cl1" style="color:var(--green)">—</div></div>
          <div class="ibi"><div class="ibk">Expirés</div><div class="ibv" id="cl2" style="color:var(--red)">—</div></div>
          <div class="ibi"><div class="ibk">Xray</div><div class="ibv" id="cl3">—</div></div>
          <div class="ibi"><div class="ibk">SSH</div><div class="ibv" id="cl4">—</div></div>
          <div class="ibi"><div class="ibk">UDP</div><div class="ibv" id="cl5">—</div></div>
        </div>
        <div class="card">
          <div class="ch">
            <div class="flex aic g1" style="flex-wrap:wrap;gap:.4rem">
              <div class="sbox"><input type="text" id="csrch" placeholder="Username, tunnel, revendeur..." oninput="filterC()"></div>
              <select class="fc" id="ctf" style="width:auto;font-size:.76rem;padding:.38rem .6rem" onchange="filterC()">
                <option value="">Tous tunnels</option>
                <option value="vless">VLESS</option><option value="vmess">VMESS</option><option value="trojan">Trojan</option>
                <option value="ssh-multi">SSH MULTIPLE</option>
                <option value="udp-zivpn">UDP ZIVPN</option><option value="udp-hysteria">UDP Hysteria</option>
                <option value="v2ray-fastdns">V2Ray FastDNS</option>
              </select>
              <select class="fc" id="csf" style="width:auto;font-size:.76rem;padding:.38rem .6rem" onchange="filterC()">
                <option value="">Tous statuts</option><option value="a">Actifs</option><option value="e">Expirés</option>
              </select>
            </div>
            <button class="btn btn-c btn-sm" onclick="nav('create')">＋ Créer</button>
          </div>
          <div class="cb" style="padding:0"><div class="tw"><table>
            <thead><tr><th>#</th><th>Username</th><th>Password</th><th>UUID</th><th>Tunnel</th><th>Revendeur</th><th>↑</th><th>↓</th><th>Quota</th><th>Expire</th><th>Statut</th><th>Actions</th></tr></thead>
            <tbody id="ctbl"><tr><td colspan="11" style="text-align:center;padding:3rem;color:var(--muted)">Chargement...</td></tr></tbody>
          </table></div></div>
        </div>
      </div>

      <!-- PAGE REVENDEURS -->
      <div class="page" id="page-resellers">
        <div class="ptitle">Gestion Revendeurs</div>
        <div class="psub">Créer, modifier, supprimer les comptes revendeurs</div>
        <div class="card">
          <div class="ch"><div class="sbox"><input type="text" id="rsrch" placeholder="Rechercher..." oninput="filterR()"></div><button class="btn btn-c" onclick="openM('mar');document.getElementById('rn_tunnels_wrap').innerHTML=buildTunnelGrid('rn',[])">+ Nouveau Revendeur</button></div>
          <div class="cb" style="padding:0"><div class="tw"><table>
            <thead><tr><th>#</th><th>Username</th><th>Clients</th><th>Quota Data</th><th>Expire</th><th>Statut</th><th>Actions</th></tr></thead>
            <tbody id="rtbl"><tr><td colspan="8" style="text-align:center;padding:3rem;color:var(--muted)">Chargement...</td></tr></tbody>
          </table></div></div>
        </div>
      </div>

      <!-- PAGE MONITORING -->
      <div class="page" id="page-system">
        <div class="ptitle">Monitoring Système</div>
        <div class="psub">Ressources VPS en temps réel</div>
        <div class="sgrid">
          <div class="scard c"><div class="scard-lbl">CPU</div><div class="scard-val" id="sc">—</div></div>
          <div class="scard"><div class="scard-lbl">RAM Libre</div><div class="scard-val" id="srf">—</div></div>
          <div class="scard g"><div class="scard-lbl">RAM Total</div><div class="scard-val" id="srt">—</div></div>
          <div class="scard p"><div class="scard-lbl">Disque Libre</div><div class="scard-val" id="sdf">—</div></div>
        </div>
        <div class="card">
          <div class="ch"><div class="ct">Ressources détaillées</div><button class="btn btn-gh btn-sm" onclick="loadSystem()">⟳</button></div>
          <div class="cb"><div class="mgrid">
            <div class="mi"><div class="ml"><span class="mk">CPU</span><span class="mv" id="scv">—</span></div><div class="prg" style="height:12px"><div class="prg-b" id="scb" style="width:0%"></div></div></div>
            <div class="mi"><div class="ml"><span class="mk">RAM</span><span class="mv" id="srv">—</span></div><div class="prg" style="height:12px"><div class="prg-b" id="srb" style="width:0%"></div></div></div>
            <div class="mi"><div class="ml"><span class="mk">Disque</span><span class="mv" id="sdv">—</span></div><div class="prg" style="height:12px"><div class="prg-b" id="sdb" style="width:0%"></div></div></div>
          </div></div>
        </div>
      </div>

      <!-- PAGE LOGS -->
      <div class="page" id="page-logs">
        <div class="ptitle">Logs d'Activité</div>
        <div class="psub">200 dernières actions enregistrées</div>
        <div class="card">
          <div class="ch"><div class="ct">Journal Système</div><button class="btn btn-gh btn-sm" onclick="loadLogs()">⟳</button></div>
          <div class="cb" style="padding:0"><div class="tw"><table>
            <thead><tr><th>Date</th><th>Acteur</th><th>Rôle</th><th>Action</th><th>Cible</th><th>IP</th></tr></thead>
            <tbody id="ltbl"></tbody>
          </table></div></div>
        </div>
      </div>
    </main>
  </div>
</div>

<!-- MODAL: ADD RESELLER -->
<div class="mo" id="mar">
  <div class="modal">
    <div class="mh"><div class="mt">+ Nouveau Revendeur</div><button class="btn btn-gh btn-ic" onclick="closeM('mar')">✕</button></div>
    <div class="mb"><div class="fgrid">
      <div class="fg"><label class="fl">Username *</label><input class="fc" id="rnu" placeholder="revendeur1"></div>
      <div class="fg"><label class="fl">Mot de passe *</label><div class="flex g1"><input class="fc" id="rnp" type="password" placeholder="••••••••" style="flex:1"><button class="btn btn-gh btn-sm" onclick="togglePw('rnp',this)" type="button" tabindex="-1" style="font-size:1rem;line-height:1">👁</button></div></div>
      <div class="fg"><label class="fl">Max Users *</label><input class="fc" id="rnm" type="number" value="10" min="1"></div>
      <div class="fg"><label class="fl">Quota Data (Go) <span class="muted">(0=illimité)</span></label><input class="fc" id="rndl" type="number" value="0" min="0" step="0.5" placeholder="0 = illimité"></div>
      <div class="fg"><label class="fl">Expire le *</label><input class="fc" id="rnx" type="datetime-local"></div>
      <div class="fg" style="grid-column:1/-1"><label class="fl">Tunnels autorisés</label>
        <div id="rn_tunnels_wrap"></div>
      </div>
    </div></div>
    <div class="mf"><button class="btn btn-gh" onclick="closeM('mar')">Annuler</button><button class="btn btn-c" onclick="addR()">Créer</button></div>
  </div>
</div>

<!-- MODAL: EDIT RESELLER -->
<div class="mo" id="mer">
  <div class="modal">
    <div class="mh"><div class="mt">✎ Modifier Revendeur</div><button class="btn btn-gh btn-ic" onclick="closeM('mer')">✕</button></div>
    <div class="mb">
      <input type="hidden" id="reid">
      <div class="fgrid">
        <div class="fg"><label class="fl">Identifiant (username)</label><input class="fc" id="reun" placeholder="(inchangé si vide)"></div>
        <div class="fg"><label class="fl">Nouveau mot de passe</label><div class="flex g1"><input class="fc" id="rep" type="password" placeholder="(inchangé si vide)" style="flex:1"><button class="btn btn-gh btn-sm" onclick="togglePw('rep',this)" type="button" tabindex="-1" style="font-size:1rem;line-height:1">👁</button></div></div>
        <div class="fg"><label class="fl">Max Users</label><input class="fc" id="rem" type="number" min="1"></div>
        <div class="fg"><label class="fl">Quota Data (Go) <span class="muted">(0=illimité)</span></label><input class="fc" id="redl" type="number" min="0" step="0.5"></div>
        <div class="fg"><label class="fl">Expire le <span class="muted">(jj/hh/mm)</span></label><input class="fc" id="rex" type="datetime-local"></div>
        <div class="fg"><label class="fl">Statut</label><select class="fc" id="rea"><option value="1">Actif</option><option value="0">Désactivé</option></select></div>
        <div class="fg" style="grid-column:1/-1"><label class="fl">Tunnels autorisés</label>
          <div id="re_tunnels_wrap"></div>
        </div>
      </div>
    </div>
    <div class="mf"><button class="btn btn-gh" onclick="closeM('mer')">Annuler</button><button class="btn btn-c" onclick="editR()">Enregistrer</button></div>
  </div>
</div>

<!-- MODAL: EDIT CLIENT -->
<div class="mo" id="mec">
  <div class="modal" style="max-width:620px">
    <div class="mh"><div class="mt">✎ Modifier Client / Tunnel</div><button class="btn btn-gh btn-ic" onclick="closeM('mec')">✕</button></div>
    <div class="mb">
      <input type="hidden" id="ecid">
      <div style="background:rgba(0,180,255,.07);border:1px solid rgba(0,180,255,.2);border-radius:6px;padding:.55rem .9rem;margin-bottom:.8rem;font-size:.74rem;color:var(--dim)">
        ⚡ Modifier username / mot de passe / UUID recréera automatiquement le tunnel VPN.
      </div>
      <div class="fgrid">
        <div class="fg"><label class="fl">Username</label><input class="fc" id="ecu" placeholder="(inchangé si vide)"></div>
        <div class="fg"><label class="fl">Mot de passe</label><div class="flex g1"><input class="fc" id="ecpw" type="password" placeholder="(inchangé si vide)" style="flex:1"><button class="btn btn-gh btn-sm" onclick="togglePw('ecpw',this)" type="button" tabindex="-1" style="font-size:1rem;line-height:1">👁</button></div></div>
        <div class="fg" style="grid-column:1/-1"><label class="fl">UUID <small class="muted">(Xray/V2Ray — vide = inchangé)</small></label>
          <div style="display:flex;gap:.4rem">
            <input class="fc" id="ecuuid" placeholder="(inchangé si vide)" style="font-family:var(--mono);font-size:.74rem;flex:1">
            <button class="btn btn-gh" onclick="document.getElementById('ecuuid').value=genUUIDv4()" title="Générer nouveau UUID" style="white-space:nowrap;padding:0 .7rem">⟳ UUID</button>
          </div>
        </div>
        <div class="fg"><label class="fl">Tunnel (type)</label><input class="fc" id="ect" disabled style="opacity:.5"></div>
        <div class="fg"><label class="fl">Expire le <small class="muted">(jours / heures / min)</small></label><input class="fc" type="datetime-local" id="ecx"></div>
        <div class="fg"><label class="fl">Quota Data (Go) <span class="muted">(0=illimité)</span></label><input class="fc" type="number" id="ecdl" min="0" step="0.5" placeholder="0 = illimité"></div>
        <div class="fg"><label class="fl">Statut</label><select class="fc" id="eca"><option value="1">Actif</option><option value="0">Désactivé</option></select></div>
        <div class="fg" style="grid-column:1/-1"><label class="fl">Note</label><input class="fc" id="ecn"></div>
      </div>
    </div>
    <div class="mf"><button class="btn btn-gh" onclick="closeM('mec')">Annuler</button><button class="btn btn-c" onclick="saveC()">Enregistrer</button></div>
  </div>
</div>

<div class="tc" id="toastC"></div>

<script nonce="__NONCE__">
function esc(s){const d=document.createElement('div');d.appendChild(document.createTextNode(s??''));return d.innerHTML;}
function q(s){return'"'+esc(s)+'"'}

// ── Définitions des tunnels disponibles ─────────────────────
const TUNNEL_DEFS = [
  { g:'Xray',   v:'vless',         l:'VLESS',        i:'⚡' },
  { g:'Xray',   v:'vmess',         l:'VMESS',        i:'⚡' },
  { g:'Xray',   v:'trojan',        l:'Trojan',       i:'🛡' },
  { g:'SSH',    v:'ssh-multi',     l:'SSH Multiple', i:'🖥' },
  { g:'UDP',    v:'udp-zivpn',     l:'ZIVPN',        i:'🌀' },
  { g:'UDP',    v:'udp-hysteria',  l:'Hysteria',     i:'💨' },
  { g:'V2Ray',  v:'v2ray-fastdns', l:'FastDNS',      i:'🚀' },
];

// Construire le HTML de la grille de checkboxes tunnels
function buildTunnelGrid(prefix, selectedArr) {
  const sel = Array.isArray(selectedArr) ? selectedArr : [];
  const groups = [...new Set(TUNNEL_DEFS.map(t => t.g))];
  let html = `<div style="font-size:.74rem;color:var(--dim);margin-bottom:.35rem">
    Tunnels autorisés — <span class="tck-all" onclick="toggleAllTunnels('${prefix}',true)">Tout sélectionner</span> · 
    <span class="tck-all" onclick="toggleAllTunnels('${prefix}',false)">Tout déselectionner</span>
    <span class="muted" style="font-size:.7rem"> (aucun = tous autorisés)</span>
  </div><div class="tunnel-grid">`;
  for (const g of groups) {
    html += `<div class="tck-group-label">${g}</div>`;
    for (const t of TUNNEL_DEFS.filter(x => x.g === g)) {
      const chk = sel.includes(t.v) ? 'checked' : '';
      const cls = sel.includes(t.v) ? ' checked' : '';
      html += `<label class="tck${cls}" id="tck_${prefix}_${t.v}">
        <input type="checkbox" name="${prefix}_tunnels" value="${t.v}" ${chk}
          onchange="this.closest('label').classList.toggle('checked',this.checked)">
        <span class="tck-icon">${t.i}</span><span>${t.l}</span>
      </label>`;
    }
  }
  html += '</div>';
  return html;
}

// Lire les tunnels cochés d'un groupe
function getCheckedTunnels(prefix) {
  const boxes = document.querySelectorAll(`input[name="${prefix}_tunnels"]:checked`);
  return [...boxes].map(b => b.value);
}

// Tout cocher / décocher
function toggleAllTunnels(prefix, state) {
  document.querySelectorAll(`input[name="${prefix}_tunnels"]`).forEach(b => {
    b.checked = state;
    b.closest('label').classList.toggle('checked', state);
  });
}

// ============================================================
// UTILITIES
// ============================================================
const API = {
  t: localStorage.getItem('kt'),
  h() { return { 'Content-Type':'application/json', Authorization:`Bearer ${this.t}` }; },
  async req(m, u, d) {
    const o = { method:m, headers:this.h() };
    if(d) o.body = JSON.stringify(d);
    const r = await fetch(u, o);
    const j = await r.json().catch(()=>({}));
    if(!r.ok) throw new Error(j.error || `HTTP ${r.status}`);
    return j;
  },
  get: u => API.req('GET',u),
  post: (u,d) => API.req('POST',u,d),
  put: (u,d) => API.req('PUT',u,d),
  del: u => API.req('DELETE',u),
};

const fmtB = (b,d=2) => { if(!b||b==0) return '0 B'; const k=1024,s=['B','KB','MB','GB','TB'],i=Math.floor(Math.log(b)/Math.log(k)); return (b/Math.pow(k,i)).toFixed(d)+' '+s[i]; };
const fmtD = d => d ? new Date(d).toLocaleDateString('fr-FR') : '-';
const fmtDT = d => d ? new Date(d).toLocaleDateString('fr-FR')+' '+new Date(d).toLocaleTimeString('fr-FR',{hour:'2-digit',minute:'2-digit'}) : '-';
const isExp = d => new Date(d) < new Date();
const dLeft = d => Math.ceil((new Date(d)-new Date())/(1000*60*60*24));
const toDay = () => new Date().toISOString().split('T')[0];
const dInp = d => {
  if (!d) return '';
  const dt = new Date(d);
  const p = n => String(n).padStart(2,'0');
  return dt.getFullYear()+'-'+p(dt.getMonth()+1)+'-'+p(dt.getDate())+'T'+p(dt.getHours())+':'+p(dt.getMinutes());
};
const fmtDLeft = d => {
  if (!d) return '';
  const ms = new Date(d) - new Date();
  if (ms <= 0) return '<span class="b br">EXPIRÉ</span>';
  const j  = Math.floor(ms/86400000);
  const h  = Math.floor((ms%86400000)/3600000);
  const m  = Math.floor((ms%3600000)/60000);
  if (j > 0)  return j+'j '+h+'h '+m+'m';
  if (h > 0)  return h+'h '+m+'m';
  return m+'m';
};

const TC = {vless:'bc',vmess:'bp',trojan:'by','ssh-multi':'bg','ssh-ws':'bg','ssh-slowdns':'bg','ssh-ssl':'bg','ssh-udp':'bg','udp-zivpn':'br','udp-hysteria':'br','v2ray-fastdns':'bp'};
const tbadge = t => `<span class="b ${TC[t]||'bc'}">${t}</span>`;

const Toast = {
  show(msg, type='i', dur=3500) {
    const ic = {s:'✓',e:'✗',i:'ℹ'};
    const t = document.createElement('div');
    t.className = `toast ${type}`;
    t.innerHTML = `<span>${ic[type]}</span>${esc(msg)}`;
    document.getElementById('toastC').appendChild(t);
    setTimeout(()=>t.remove(), dur);
  },
  s:m=>Toast.show(m,'s'), e:m=>Toast.show(m,'e'), i:m=>Toast.show(m,'i')
};

const openM  = id => document.getElementById(id)?.classList.add('open');
const closeM = id => document.getElementById(id)?.classList.remove('open');

let curPage = 'dash';
function nav(id) {
  curPage = id;
  document.querySelectorAll('.page').forEach(p=>p.classList.remove('active'));
  document.querySelectorAll('.nav').forEach(n=>n.classList.remove('active'));
  document.getElementById('page-'+id)?.classList.add('active');
  document.querySelector(`[data-p="${id}"]`)?.classList.add('active');
  const titles = {dash:'Dashboard',create:'Créer un Tunnel',clients:'Tous les Clients',resellers:'Revendeurs',system:'Monitoring',logs:'Logs'};
  document.getElementById('ptitle').innerHTML = `<span>⬡</span> ${titles[id]||id}`;
  document.getElementById('sidebar')?.classList.remove('open');
}

function refresh() {
  if(curPage==='dash') loadDash();
  else if(curPage==='clients') loadClients();
  else if(curPage==='resellers') loadResellers();
  else if(curPage==='system') loadSystem();
  else if(curPage==='logs') loadLogs();
}

function logout() { localStorage.clear(); location.href='/'; }

// ============================================================
// AUTH
// ============================================================
async function doLogin() {
  const u = document.getElementById('lu').value.trim();
  const p = document.getElementById('lp').value;
  const err = document.getElementById('lerr');
  err.style.display='none';
  if(!u||!p){err.textContent='Remplissez tous les champs.';err.style.display='block';return;}
  const btn = document.getElementById('lbtn');
  btn.innerHTML='<span class="spin"></span>';
  try {
    const d = await API.post('/api/auth/admin/login',{username:u,password:p});
    localStorage.setItem('kt',d.token);
    localStorage.setItem('kr',d.role);
    localStorage.setItem('ku',d.username);
    API.t = d.token;
    initPanel(d.username);
  } catch(e){err.textContent=e.message;err.style.display='block';}
  finally{btn.innerHTML='<span>SE CONNECTER</span>';}
}
document.addEventListener('keypress',e=>{if(e.key==='Enter'&&!document.getElementById('LS').classList.contains('hidden'))doLogin();});

function initPanel(uname) {
  document.getElementById('LS').classList.add('hidden');
  document.getElementById('PS').classList.remove('hidden');
  document.getElementById('su').textContent = uname||'admin';
  document.getElementById('tu').textContent = (uname||'ADMIN').toUpperCase();
  document.getElementById('ce').setAttribute('min',toDay());
  document.getElementById('rnx').setAttribute('min',toDay());
  setInterval(()=>{ const t=new Date(); document.getElementById('ltime').textContent=t.toLocaleTimeString('fr-FR'); },1000);
  loadDash(); loadROptions();
}

document.getElementById('mbtn')?.addEventListener('click',()=>document.getElementById('sidebar').classList.toggle('open'));
document.addEventListener('click',e=>{const s=document.getElementById('sidebar'); if(s&&!s.contains(e.target)&&e.target.id!=='mbtn') s.classList.remove('open');});

// Vérification du token au chargement — évite le blocage sur token expiré
(async function checkAuth() {
  const token = localStorage.getItem('kt');
  const role  = localStorage.getItem('kr');
  const uname = localStorage.getItem('ku');
  if (!token || role !== 'admin') return; // pas de token → afficher login
  API.t = token;
  try {
    // Vérifier que le token est encore valide côté serveur
    const r = await fetch('/api/admin/stats', {
      headers: { 'Authorization': 'Bearer ' + token }
    });
    if (r.status === 401 || r.status === 403) {
      // Token invalide ou expiré → vider et afficher login
      localStorage.clear();
      return;
    }
    // Token valide → afficher le panel
    initPanel(uname);
  } catch(e) {
    // Erreur réseau → vider et afficher login
    localStorage.clear();
  }
})();

// ============================================================
// DASHBOARD
// ============================================================
async function loadDash() {
  try {
    const d = await API.get('/api/admin/stats');
    const g=d.global, sys=d.system, m=d.monthly||{};
    document.getElementById('s0').textContent=g.total_resellers;
    document.getElementById('s1').textContent=g.total_clients;
    document.getElementById('s2').textContent=g.active_clients;
    document.getElementById('s3').textContent=fmtB(g.total_upload);
    document.getElementById('s4').textContent=fmtB(g.total_download);
    const cpu=parseFloat(sys.cpu_usage), rPct=Math.round(sys.ram_used/sys.ram_total*100);
    const dPct=sys.disk?Math.round(sys.disk.used/sys.disk.total*100):0;
    document.getElementById('mc').textContent=cpu.toFixed(1)+'%'; document.getElementById('mcb').style.width=cpu+'%';
    document.getElementById('mr').textContent=fmtB(sys.ram_free)+' libre'; document.getElementById('mrb').style.width=rPct+'%';
    if(sys.disk){document.getElementById('md').textContent=fmtB(sys.disk.free)+' libre'; document.getElementById('mdb').style.width=dPct+'%';}

    if(m.month_start){
      const d0=new Date(m.month_start);
      document.getElementById('monthLabel').textContent=
        `(${d0.toLocaleDateString('fr-FR',{month:'long',year:'numeric'})})`;
    }
    document.getElementById('mUp').textContent    = fmtB(Number(m.month_upload)||0);
    document.getElementById('mDl').textContent    = fmtB(Number(m.month_download)||0);
    document.getElementById('mTotal').textContent = fmtB((Number(m.month_upload)||0)+(Number(m.month_download)||0));
    const rList = m.resellers||[];
    document.getElementById('mResellers').innerHTML = rList.length
      ? rList.map(r=>{
          const tot=(Number(r.month_upload)||0)+(Number(r.month_download)||0);
          return `<div style="background:rgba(124,58,237,.12);border:1px solid rgba(124,58,237,.25);border-radius:.4rem;padding:.3rem .6rem;font-size:.72rem">
            <span style="color:var(--cyan);font-weight:600">${esc(r.username)}</span>
            <span style="color:var(--muted);margin-left:.3rem">${fmtB(tot)}</span>
          </div>`;
        }).join('')
      : '<span style="color:var(--muted);font-size:.75rem">Aucune donnée ce mois</span>';

    document.getElementById('dr').innerHTML = d.resellers.length ? d.resellers.map(r=>{
      const ex=isExp(r.expires_at),dy=dLeft(r.expires_at),pct=r.max_users>0?Math.min(100,(r.used_users/r.max_users)*100).toFixed(0):0;
      return `<tr><td class="nm">${esc(r.username)}</td><td>${r.used_users}</td><td><div style="display:flex;align-items:center;gap:.4rem"><div class="prg" style="width:65px"><div class="prg-b" style="width:${pct}%"></div></div><span class="muted sm">${pct}%</span></div></td><td>${fmtB(parseInt(r.upload||0)+parseInt(r.download||0))}</td><td>${esc(fmtDT(r.expires_at))} <span class="muted sm">${fmtDLeft(r.expires_at)}</span></td><td>${ex?'<span class="b br">EXPIRÉ</span>':r.is_active?'<span class="b bg">ACTIF</span>':'<span class="b br">OFF</span>'}</td></tr>`;
    }).join('') : '<tr><td colspan="6" style="text-align:center;padding:1.5rem;color:var(--muted)">Aucun revendeur</td></tr>';
    const cl = await API.get('/api/admin/clients');
    document.getElementById('dc').innerHTML = cl.slice(0,6).map(c=>`<tr><td class="nm">${esc(c.username)}</td><td>${tbadge(esc(c.tunnel_type))}</td><td>${c.reseller_name ? esc(c.reseller_name) : '<span class="muted">admin</span>'}</td><td>${esc(fmtDT(c.expires_at))} <span class="muted sm">${fmtDLeft(c.expires_at)}</span>${isExp(c.expires_at)?'<span class="b br" style="margin-left:.3rem">EXP</span>':''}</td><td>${c.is_active&&!isExp(c.expires_at)?'<span class="b bg">ACTIF</span>':'<span class="b br">INACTIF</span>'}</td></tr>`).join('')||'<tr><td colspan="5" style="text-align:center;padding:1.5rem;color:var(--muted)">Aucun client</td></tr>';
  } catch(e){Toast.e('Dashboard: '+e.message);}
}

async function confirmMonthReset() {
  if(!confirm('⚠️ Réinitialiser les statistiques du mois précédent ?\n\nCette action supprime les données de consommation archivées.\nLes stats du mois courant sont conservées.')) return;
  try {
    await API.post('/api/admin/stats/reset-monthly', {});
    Toast.s('Statistiques réinitialisées');
    loadDash();
  } catch(e){ Toast.e(e.message); }
}

// ============================================================
// CRÉER TUNNEL
// ============================================================
let selTunnel='';
const sessC=[];

function selT(el, t) {
  document.querySelectorAll('.tc2').forEach(c=>c.classList.remove('sel'));
  el.classList.add('sel'); selTunnel=t;
  document.getElementById('tsv').textContent=t.toUpperCase();
  document.getElementById('tsel').style.display='block';

  // Adapter l'interface selon le type de tunnel
  const uuidInfo = document.getElementById('uuid-info');
  const passRow  = document.getElementById('pass-row');
  const passHint = document.getElementById('pass-hint');

  // Tunnels qui utilisent UUID (pas de password manuels)
  const xrayTypes  = ['vmess','vless','trojan'];
  // Tunnels qui utilisent password
  const passTypes  = ['ssh-multi','ssh-ws','ssh-ssl','ssh-slowdns','ssh-udp','udp-zivpn','udp-hysteria'];
  // V2Ray : UUID auto + password non utilisé
  const v2rayTypes = ['v2ray-fastdns'];

  if (xrayTypes.includes(t)) {
    if(uuidInfo) uuidInfo.style.display='block';
    if(passRow)  passRow.style.display='none';
    if(passHint) passHint.textContent='UUID généré automatiquement — pas de mot de passe requis';
  } else if (v2rayTypes.includes(t)) {
    if(uuidInfo) uuidInfo.style.display='block';
    if(passRow)  passRow.style.display='none';
    if(passHint) passHint.textContent='UUID généré automatiquement (VLESS TCP port 5401)';
  } else {
    // SSH et UDP : password requis
    if(uuidInfo) uuidInfo.style.display='none';
    if(passRow)  passRow.style.display='flex';
    if(passHint) passHint.textContent = passTypes.includes(t)
      ? (t.startsWith('udp') ? 'Password pour UDP (format users.list)' : 'Mot de passe SSH Linux (tous les modes inclus)')
      : '';
  }
}

function genP() {
  const c='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@#!';
  let p=''; for(let i=0;i<12;i++) p+=c[Math.floor(Math.random()*c.length)];
  document.getElementById('cp').value=p;
}

function togglePw(id, btn) {
  const inp = document.getElementById(id);
  if (inp.type === 'password') { inp.type = 'text';  btn.textContent = '🙈'; }
  else                         { inp.type = 'password'; btn.textContent = '👁'; }
}

// ─── Génère le lien vmess base64 ───────────────────────────────
function b64(obj){ return btoa(unescape(encodeURIComponent(JSON.stringify(obj)))); }

function buildVmessLink(name, domain, port, uuid, net, path_, tls){
  return 'vmess://'+b64({v:'2',ps:name,add:domain,port:String(port),id:uuid,aid:0,net,type:'none',host:domain,path:path_,tls,sni:tls==='tls'?domain:''});
}

// ─── Rendu du message selon le type de tunnel ──────────────────
function renderTunnelResult(res) {
  const V = res.vpsInfo || {};
  const TR = res.tunnelResult || {};
  const CI = TR.config_info || {};

  const domain      = CI.domain      || V.domain        || '—';
  const xrayDomain  = V.xray_domain  || domain;
  const v2Domain    = V.v2ray_domain || domain;
  const hostIp      = V.host_ip      || '—';
  const slowKey     = V.slowdns_key  || CI.slowdns_key  || '—';
  const slowNs      = V.slowdns_ns   || CI.slowdns_ns   || '—';
  const u           = res.username;
  const pw          = res.password;
  const uuid        = res.uuid;
  const exp         = (res.expires_at||'').split('T')[0];
  const expH        = res.expires_at
    ? new Date(res.expires_at).toLocaleDateString('fr-FR')+' '
      +new Date(res.expires_at).toLocaleTimeString('fr-FR',{hour:'2-digit',minute:'2-digit'})
    : '—';
  const t           = res.tunnel_type;
  const ok          = TR.ok !== false;
  const dlGb        = res.data_limit_gb || 0;
  const quotaLine   = dlGb > 0
    ? `<div class="tr-row"><span class="tr-k">📊 Quota Data</span><span class="tr-v" style="color:var(--cyan)">${dlGb} Go</span></div>`
    : `<div class="tr-row"><span class="tr-k">📊 Quota Data</span><span class="tr-v muted">Illimité ∞</span></div>`;

  const statusLine  = ok
    ? `<div class="tr-status ok">✅ Injecté dans la configuration système</div>`
    : `<div class="tr-status warn">⚠️ Vérifiez les logs — service peut-être arrêté</div>`;

  // ────────────────────────────────────────────────────────────
  // UDP ZIVPN
  // ────────────────────────────────────────────────────────────
  if (t === 'udp-zivpn') {
    const port = CI.port || '5667';
    const obfs = CI.obfs || 'zivpn';
    return `<div class="tr-block udp">
      <div class="tr-title">✅ 𝗨𝗧𝗜𝗟𝗜𝗦𝗔𝗧𝗘𝗨𝗥 𝗖𝗥𝗘𝗘</div>
      <div class="tr-sep"></div>
      <div class="tr-row"><span class="tr-k">🌐 Domaine</span><span class="tr-v">${esc(domain)}</span><button class="cpbtn" onclick="cp('${esc(domain)}')">📋</button></div>
      <div class="tr-row"><span class="tr-k">🎭 Obfs</span><span class="tr-v">${esc(obfs)}</span></div>
      <div class="tr-row"><span class="tr-k">👤 Username</span><span class="tr-v hi">${esc(u)}</span><button class="cpbtn" onclick="cp('${esc(u)}')">📋</button></div>
      <div class="tr-row"><span class="tr-k">🔐 Password</span><span class="tr-v pw">${esc(pw)}</span><button class="cpbtn" onclick="cp('${esc(pw)}')">📋</button></div>
      <div class="tr-row"><span class="tr-k">📅 Expire</span><span class="tr-v">${esc(expH)}</span></div>
      ${quotaLine}
      <div class="tr-row"><span class="tr-k">🔌 Port</span><span class="tr-v">${esc(port)}</span></div>
      <div class="tr-sep"></div>
      ${statusLine}
    </div>`;
  }

  // ────────────────────────────────────────────────────────────
  // UDP HYSTERIA
  // ────────────────────────────────────────────────────────────
  if (t === 'udp-hysteria') {
    const portRange = CI.port_range || `${CI.port||'20000'}-50000`;
    const obfs      = CI.obfs || 'hysteria';
    return `<div class="tr-block udp">
      <div class="tr-title">✅ 𝗨𝗧𝗜𝗟𝗜𝗦𝗔𝗧𝗘𝗨𝗥 𝗖𝗥𝗘𝗘</div>
      <div class="tr-sep"></div>
      <div class="tr-row"><span class="tr-k">🌐 Domaine</span><span class="tr-v">${esc(domain)}</span><button class="cpbtn" onclick="cp('${esc(domain)}')">📋</button></div>
      <div class="tr-row"><span class="tr-k">🎭 Obfs</span><span class="tr-v">${esc(obfs)}</span></div>
      <div class="tr-row"><span class="tr-k">👤 Username</span><span class="tr-v hi">${esc(u)}</span><button class="cpbtn" onclick="cp('${esc(u)}')">📋</button></div>
      <div class="tr-row"><span class="tr-k">🔐 Password</span><span class="tr-v pw">${esc(pw)}</span><button class="cpbtn" onclick="cp('${esc(pw)}')">📋</button></div>
      <div class="tr-row"><span class="tr-k">📅 Expire</span><span class="tr-v">${esc(expH)}</span></div>
      ${quotaLine}
      <div class="tr-row"><span class="tr-k">🔌 Port</span><span class="tr-v">${esc(portRange)}</span></div>
      <div class="tr-sep"></div>
      ${statusLine}
    </div>`;
  }

  // ────────────────────────────────────────────────────────────
  // XRAY — VMESS / VLESS / TROJAN
  // ────────────────────────────────────────────────────────────
  if (['vmess','vless','trojan'].includes(t)) {
    const proto     = t.toUpperCase();
    const portTls   = 443;
    const portNtls  = 8880;
    const pathMap   = { vmess:'/vmess', vless:'/vless', trojan:'/trojan' };
    const grpcMap   = { vmess:'vmess-grpc', vless:'vless-grpc', trojan:'trojan-grpc' };
    const wsPath    = pathMap[t] || `/${t}`;
    const grpcName  = grpcMap[t] || `${t}-grpc`;
    const xhttpPath = t === 'trojan' ? '/trojan-xhttp' : (t === 'vless' ? '/vless-xhttp' : '');
    const hupPath   = t === 'vless' ? '/vless-hupgrade' : '';

    let linkTls='', linkNtls='', linkGrpc='';
    let linkTcpTls='', linkTcpNtls='', linkXhttp='', linkHup='';

    if (t === 'vmess') {
      linkTls  = buildVmessLink(u, xrayDomain, portTls,  uuid, 'ws',   wsPath, 'tls');
      linkNtls = buildVmessLink(u, xrayDomain, portNtls, uuid, 'ws',   wsPath, 'none');
      linkGrpc = buildVmessLink(u, xrayDomain, portTls,  uuid, 'grpc', grpcName, 'tls');
    } else if (t === 'trojan') {
      const pw = uuid;
      linkTls  = `${t}://${pw}@${xrayDomain}:${portTls}?security=tls&type=ws&path=${wsPath}&host=${xrayDomain}&sni=${xrayDomain}#${u}`;
      linkNtls = `${t}://${pw}@${xrayDomain}:${portNtls}?security=none&type=ws&path=${wsPath}&host=${xrayDomain}#${u}`;
      linkGrpc = `${t}://${pw}@${xrayDomain}:${portTls}?mode=grpc&security=tls&serviceName=${grpcName}#${u}`;
      linkTcpTls = `${t}://${pw}@${xrayDomain}:${portTls}?security=tls&type=tcp&headerType=none&sni=${xrayDomain}#${u}-TCP-TLS`;
      linkTcpNtls = `${t}://${pw}@${xrayDomain}:${portNtls}?security=none&type=tcp&headerType=none#${u}-TCP`;
      linkXhttp = `${t}://${pw}@${xrayDomain}:${portTls}?security=tls&type=xhttp&path=${xhttpPath}&host=${xrayDomain}&sni=${xrayDomain}#${u}-XHTTP`;
    } else {
      // vless
      linkTls  = `${t}://${uuid}@${xrayDomain}:${portTls}?security=tls&type=ws&path=${wsPath}&host=${xrayDomain}&sni=${xrayDomain}#${u}`;
      linkNtls = `${t}://${uuid}@${xrayDomain}:${portNtls}?security=none&type=ws&path=${wsPath}&host=${xrayDomain}#${u}`;
      linkGrpc = `${t}://${uuid}@${xrayDomain}:${portTls}?mode=grpc&security=tls&serviceName=${grpcName}#${u}`;
      linkTcpTls = `${t}://${uuid}@${xrayDomain}:${portTls}?security=tls&type=tcp&headerType=none&sni=${xrayDomain}#${u}-TCP-TLS`;
      linkTcpNtls = `${t}://${uuid}@${xrayDomain}:${portNtls}?security=none&type=tcp&headerType=none#${u}-TCP`;
      linkXhttp = `${t}://${uuid}@${xrayDomain}:${portTls}?security=tls&encryption=none&type=xhttp&path=${xhttpPath}&host=${xrayDomain}&sni=${xrayDomain}#${u}-XHTTP`;
      linkHup = `${t}://${uuid}@${xrayDomain}:${portTls}?security=tls&encryption=none&type=httpupgrade&path=${hupPath}&host=${xrayDomain}&sni=${xrayDomain}#${u}-HUP`;
    }

    const copyLink = (lbl, link) =>
      `<div class="tr-link-row"><span class="tr-lk">${lbl}</span><span class="tr-lv">${esc(link)}</span><button class="cpbtn" onclick="cp(\`${esc(link)}\`)">📋</button></div>`;

    let extraLinks = '';
    let pathInfoRows = '';
    if (t === 'trojan') {
      pathInfoRows = `
      <div class="tr-row"><span class="tr-k">🚀 XHTTP</span><span class="tr-v">TLS [${esc(xhttpPath)}]</span></div>`;
      extraLinks = `
      <div class="tr-subheader">TCP</div>
      ${copyLink('┃ TLS TCP', linkTcpTls)}
      ${copyLink('┃ Non-TLS TCP', linkTcpNtls)}
      <div class="tr-subheader">XHTTP</div>
      ${copyLink('┃ XHTTP TLS', linkXhttp)}`;
    } else if (t === 'vless') {
      pathInfoRows = `
      <div class="tr-row"><span class="tr-k">🚀 XHTTP</span><span class="tr-v">TLS [${esc(xhttpPath)}]</span></div>
      <div class="tr-row"><span class="tr-k">⬆ HUP</span><span class="tr-v">TLS [${esc(hupPath)}]</span></div>`;
      extraLinks = `
      <div class="tr-subheader">TCP</div>
      ${copyLink('┃ TLS TCP', linkTcpTls)}
      ${copyLink('┃ Non-TLS TCP', linkTcpNtls)}
      <div class="tr-subheader">XHTTP</div>
      ${copyLink('┃ XHTTP TLS', linkXhttp)}
      <div class="tr-subheader">HTTPUpgrade</div>
      ${copyLink('┃ HUP TLS', linkHup)}`;
    }

    return `<div class="tr-block xray">
      <div class="tr-title">🧩 ${proto} — ${esc(u)}</div>
      <div class="tr-sep"></div>
      <div class="tr-row"><span class="tr-k">📄 Utilisateur</span><span class="tr-v hi">${esc(u)}</span><button class="cpbtn" onclick="cp('${esc(u)}')">📋</button></div>
      <div class="tr-row"><span class="tr-k">🌐 Domaine</span><span class="tr-v">${esc(xrayDomain||domain)}</span></div>
      <div class="tr-row"><span class="tr-k">🔌 Ports</span><span class="tr-v">TLS [${portTls}] | Non-TLS [${portNtls}] | gRPC [${portTls}]</span></div>
      <div class="tr-row"><span class="tr-k">🔑 UUID</span><span class="tr-v uu">${esc(uuid)}</span><button class="cpbtn" onclick="cp('${esc(uuid)}')">📋</button></div>
      <div class="tr-row"><span class="tr-k">📁 Paths WS</span><span class="tr-v">TLS [${esc(wsPath)}] | Non-TLS [${esc(wsPath)}]</span></div>
      <div class="tr-row"><span class="tr-k">📡 gRPC</span><span class="tr-v">${esc(grpcName)}</span></div>
      ${pathInfoRows}
      <div class="tr-row"><span class="tr-k">📅 Expire</span><span class="tr-v">${esc(expH)}</span></div>
      ${quotaLine}
      <div class="tr-sep"></div>
      <div class="tr-links-header">●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●</div>
      <div class="tr-subheader">WebSocket</div>
      ${copyLink('┃ TLS WS', linkTls)}
      ${copyLink('┃ Non-TLS WS', linkNtls)}
      <div class="tr-subheader">gRPC</div>
      ${copyLink('┃ gRPC TLS', linkGrpc)}
      ${extraLinks}
      <div class="tr-links-header">●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●</div>
      ${statusLine}
    </div>`;
  }

  // ────────────────────────────────────────────────────────────
  // SSH MULTIPLE
  // ────────────────────────────────────────────────────────────
  if (t === 'ssh-multi' || t.startsWith('ssh')) {
    const hasSlowDns = slowKey && slowKey !== '—';
    return `<div class="tr-block ssh">
      <div class="tr-title">✨ 𝙉𝙊𝙐𝙑𝙀𝘼𝙐 𝙐𝙏𝙄𝙇𝙄𝙎𝘼𝙏𝙀𝙐𝙍 𝘾𝙍𝙀𝙀</div>
      <div class="tr-sep"></div>
      <div class="tr-row"><span class="tr-k">🌍 Domaine</span><span class="tr-v">${esc(domain)}</span><button class="cpbtn" onclick="cp('${esc(domain)}')">📋</button></div>
      <div class="tr-row"><span class="tr-k">📌 IP Host</span><span class="tr-v">${esc(hostIp)}</span><button class="cpbtn" onclick="cp('${esc(hostIp)}')">📋</button></div>
      <div class="tr-row"><span class="tr-k">👤 Utilisateur</span><span class="tr-v hi">${esc(u)}</span><button class="cpbtn" onclick="cp('${esc(u)}')">📋</button></div>
      <div class="tr-row"><span class="tr-k">🔑 Mot de passe</span><span class="tr-v pw">${esc(pw)}</span><button class="cpbtn" onclick="cp('${esc(pw)}')">📋</button></div>
      <div class="tr-row"><span class="tr-k">📅 Expire</span><span class="tr-v">${esc(expH)}</span></div>
      ${quotaLine}
      <div class="tr-sep"></div>
      <div class="tr-section-title">📲 APPS : HTTP Injector, CUSTOM, SOCKSIP, SSC ZIVPN…</div>
      <div class="tr-link-row"><span class="tr-lk">➡️ SSH WS</span><span class="tr-lv">${esc(domain)}:80@${esc(u)}:${esc(pw)}</span><button class="cpbtn" onclick="cp('${esc(domain)}:80@${esc(u)}:${esc(pw)}')">📋</button></div>
      <div class="tr-link-row"><span class="tr-lk">➡️ SSL/TLS</span><span class="tr-lv">${esc(domain)}:444@${esc(u)}:${esc(pw)}</span><button class="cpbtn" onclick="cp('${esc(domain)}:444@${esc(u)}:${esc(pw)}')">📋</button></div>
      <div class="tr-link-row"><span class="tr-lk">➡️ PROXY WS</span><span class="tr-lv">${esc(domain)}:9090@${esc(u)}:${esc(pw)}</span><button class="cpbtn" onclick="cp('${esc(domain)}:9090@${esc(u)}:${esc(pw)}')">📋</button></div>
      <div class="tr-link-row"><span class="tr-lk">➡️ SSH UDP</span><span class="tr-lv">${esc(domain)}:1-65535@${esc(u)}:${esc(pw)}</span><button class="cpbtn" onclick="cp('${esc(domain)}:1-65535@${esc(u)}:${esc(pw)}')">📋</button></div>
      <div class="tr-sep"></div>
      <div class="tr-section-title">📜 PAYLOAD WS</div>
      <div class="tr-payload">GET / HTTP/1.1[crlf]Host: [host][crlf]Connection: Upgrade[crlf]User-Agent: [ua][crlf]Upgrade: websocket[crlf][crlf]</div>
      <button class="cpbtn" onclick="cp('GET / HTTP/1.1[crlf]Host: [host][crlf]Connection: Upgrade[crlf]User-Agent: [ua][crlf]Upgrade: websocket[crlf][crlf]')">📋 Copier payload</button>
      ${hasSlowDns ? `<div class="tr-sep"></div>
      <div class="tr-section-title">🚀 CONFIG FASTDNS (port 5300)</div>
      <div class="tr-row"><span class="tr-k">🔐 Pub KEY</span></div>
      <div class="tr-pubkey">${esc(slowKey)}</div>
      <button class="cpbtn" onclick="cp('${esc(slowKey)}')">📋 Copier clé</button>
      <div class="tr-row" style="margin-top:.5rem"><span class="tr-k">🌐 NameServer</span><span class="tr-v">${esc(slowNs)}</span><button class="cpbtn" onclick="cp('${esc(slowNs)}')">📋</button></div>` : ''}
      <div class="tr-sep"></div>
      <div class="tr-status ok">✅ 𝘾𝙊𝙈𝙋𝙏𝙀 𝘾𝙍𝙀𝙀 𝘼𝙑𝙀𝘾 𝙎𝙐𝘾𝘾𝙀𝙎</div>
    </div>`;
  }

  // ────────────────────────────────────────────────────────────
  // V2RAY FASTDNS
  // ────────────────────────────────────────────────────────────
  if (t === 'v2ray-fastdns') {
    const vDomain  = v2Domain || domain;
    const vlessLink = `vless://${uuid}@${vDomain}:5401?type=tcp&encryption=none&host=${vDomain}#${u}-VLESS-TCP`;
    const v2rayKey = V.slowdns_key_v2ray || CI.slowdns_key_v2ray  || '—';
    const v2rayNs  = V.slowdns_ns_v2ray  || CI.slowdns_ns_v2ray   || '—';
    const hasSlowDns = (v2rayKey && v2rayKey !== '—') || (v2rayNs && v2rayNs !== '—');
    return `<div class="tr-block v2ray">
      <div class="tr-title">🧩 VLESS TCP + FASTDNS</div>
      <div class="tr-sep"></div>
      <div class="tr-row"><span class="tr-k">📄 Utilisateur</span><span class="tr-v hi">${esc(u)}</span><button class="cpbtn" onclick="cp('${esc(u)}')">📋</button></div>
      <div class="tr-row"><span class="tr-k">🌐 Domaine</span><span class="tr-v">${esc(vDomain)}</span><button class="cpbtn" onclick="cp('${esc(vDomain)}')">📋</button></div>
      <div class="tr-row"><span class="tr-k">🔌 Ports</span><span class="tr-v">FastDNS UDP: 5400 | V2Ray TCP: 5401</span></div>
      <div class="tr-row"><span class="tr-k">🔑 UUID</span><span class="tr-v uu">${esc(uuid)}</span><button class="cpbtn" onclick="cp('${esc(uuid)}')">📋</button></div>
      <div class="tr-row"><span class="tr-k">📅 Expire</span><span class="tr-v">${esc(expH)}</span></div>
      ${quotaLine}
      ${hasSlowDns ? `<div class="tr-sep"></div>
      <div class="tr-section-title">━━━━━ CONFIG SLOWDNS PORT 5400 ━━━━━</div>
      <div class="tr-row"><span class="tr-k">🔐 Clé publique FastDNS</span></div>
      <div class="tr-pubkey">${esc(v2rayKey)}</div>
      <button class="cpbtn" onclick="cp('${esc(v2rayKey)}')">📋 Copier clé</button>
      <div class="tr-row" style="margin-top:.5rem"><span class="tr-k">🌐 NameServer</span><span class="tr-v">${esc(v2rayNs)}</span><button class="cpbtn" onclick="cp('${esc(v2rayNs)}')">📋</button></div>` : ''}
      <div class="tr-sep"></div>
      <div class="tr-links-header">●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●</div>
      <div class="tr-link-row"><span class="tr-lk">┃ Lien VLESS</span><span class="tr-lv">${esc(vlessLink)}</span><button class="cpbtn" onclick="cp(\`${esc(vlessLink)}\`)">📋</button></div>
      <div class="tr-links-header">●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●</div>
      ${statusLine}
    </div>`;
  }

  // ────────────────────────────────────────────────────────────
  // Fallback générique
  // ────────────────────────────────────────────────────────────
  return `<div class="tr-block">
    <div class="tr-row"><span class="tr-k">Username</span><span class="tr-v hi">${esc(u)}</span><button class="cpbtn" onclick="cp('${esc(u)}')">📋</button></div>
    <div class="tr-row"><span class="tr-k">Password</span><span class="tr-v pw">${esc(pw)}</span><button class="cpbtn" onclick="cp('${esc(pw)}')">📋</button></div>
    ${uuid?`<div class="tr-row"><span class="tr-k">UUID</span><span class="tr-v uu">${esc(uuid)}</span><button class="cpbtn" onclick="cp('${esc(uuid)}')">📋</button></div>`:''}
    <div class="tr-row"><span class="tr-k">Tunnel</span><span class="tr-v">${tbadge(esc(t))}</span></div>
    <div class="tr-row"><span class="tr-k">Expire</span><span class="tr-v">${esc(expH)}</span></div>
    ${quotaLine}
    ${statusLine}
  </div>`;
}

async function createT() {
  const u=document.getElementById('cu').value.trim();
  const p=document.getElementById('cp').value.trim();
  const e=document.getElementById('ce').value;
  const n=document.getElementById('cn').value.trim();
  const r=document.getElementById('cr').value;
  if(!selTunnel) return Toast.e('Sélectionnez un type de tunnel');
  if(!u) return Toast.e('Le username est obligatoire');
  if(!e) return Toast.e("La date d'expiration est obligatoire");
  const btn=document.getElementById('csub');
  btn.innerHTML='<span class="spin"></span> Création...'; btn.disabled=true;
  try {
    const res = await API.post('/api/admin/clients',{
      username:u, password:p||undefined, tunnel_type:selTunnel,
      expires_at:e, note:n||undefined, reseller_id:r?parseInt(r):null,
      data_limit_gb: parseFloat(document.getElementById('cdl')?.value)||0
    });
    const resEl=document.getElementById('cres');
    resEl.classList.remove('hidden');
    document.getElementById('cresbody').innerHTML = renderTunnelResult(res);
    sessC.unshift(res); renderSess();
    Toast.s(`Tunnel "${res.username}" créé !`);
    resEl.scrollIntoView({behavior:'smooth',block:'nearest'});
    document.getElementById('cu').value=''; document.getElementById('cp').value=''; document.getElementById('cn').value='';
    if(document.getElementById('cdl')) document.getElementById('cdl').value='0';
  } catch(e){Toast.e(e.message);}
  finally{btn.innerHTML='<span>⬡ Créer le Tunnel</span>'; btn.disabled=false;}
}

function renderSess() {
  const tb=document.getElementById('sess');
  if(!sessC.length){tb.innerHTML='<tr><td colspan="5" style="text-align:center;padding:1.25rem;color:var(--muted)">Aucun tunnel créé cette session</td></tr>';return;}
  tb.innerHTML=sessC.map(r=>`<tr><td class="nm">${esc(r.username)}</td><td><code style="color:var(--yellow);font-size:.76rem">${esc(r.password)}</code> <button class="cpbtn" onclick="cp('${esc(r.password)}')">📋</button></td><td><code style="color:var(--dim);font-size:.7rem">${r.uuid?esc(r.uuid.substring(0,18))+'…':'—'}</code></td><td>${tbadge(esc(r.tunnel_type))}</td><td>${esc(fmtDT(r.expires_at))}</td></tr>`).join('');
}

function resetT() {
  selTunnel=''; document.querySelectorAll('.tc2').forEach(c=>c.classList.remove('sel'));
  document.getElementById('tsel').style.display='none';
  ['cu','cp','ce','cn'].forEach(i=>document.getElementById(i).value='');
  document.getElementById('cr').value='';
  document.getElementById('cres').classList.add('hidden');
}

function cp(text) {
  // Méthode 1 : API Clipboard moderne (HTTPS ou localhost)
  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(text)
      .then(() => Toast.s('Copié !'))
      .catch(() => cpFallback(text));
    return;
  }
  // Méthode 2 : fallback textarea (HTTP, anciens navigateurs)
  cpFallback(text);
}
function cpFallback(text) {
  try {
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.setAttribute('readonly', '');
    ta.style.cssText = 'position:fixed;top:-9999px;left:-9999px;opacity:0;pointer-events:none';
    document.body.appendChild(ta);
    ta.focus();
    ta.select();
    ta.setSelectionRange(0, ta.value.length); // iOS
    const ok = document.execCommand('copy');
    document.body.removeChild(ta);
    if (ok) Toast.s('Copié !');
    else Toast.e('Copie échouée — sélectionnez et copiez manuellement');
  } catch(e) {
    Toast.e('Copie échouée — sélectionnez et copiez manuellement');
  }
}

async function loadROptions() {
  try {
    const rs=await API.get('/api/admin/resellers');
    const sel=document.getElementById('cr');
    while(sel.options.length>1) sel.remove(1);
    rs.forEach(r=>{const o=document.createElement('option');o.value=r.id;o.textContent=`${r.username} — ${r.used_users}/${r.max_users}`;sel.appendChild(o);});
  } catch{}
}

// ============================================================
// CLIENTS
// ============================================================
let allClients=[];

async function loadClients() {
  try {
    allClients=await API.get('/api/admin/clients');
    const a=allClients.filter(c=>c.is_active&&!isExp(c.expires_at)).length;
    const ex=allClients.filter(c=>isExp(c.expires_at)).length;
    document.getElementById('cl0').textContent=allClients.length;
    document.getElementById('cl1').textContent=a;
    document.getElementById('cl2').textContent=ex;
    document.getElementById('cl3').textContent=allClients.filter(c=>['vless','vmess','trojan'].includes(c.tunnel_type)).length;
    document.getElementById('cl4').textContent=allClients.filter(c=>c.tunnel_type.startsWith('ssh')).length;
    document.getElementById('cl5').textContent=allClients.filter(c=>c.tunnel_type.startsWith('udp')).length;
    renderClients(allClients);
  } catch(e){Toast.e(e.message);}
}

function renderClients(data) {
  const tb=document.getElementById('ctbl');
  if(!data.length){tb.innerHTML='<tr><td colspan="12" style="text-align:center;padding:3rem;color:var(--muted)">Aucun client</td></tr>';return;}
  tb.innerHTML=data.map(c=>{
    const ex=isExp(c.expires_at),dy=dLeft(c.expires_at);
    let st;
    if(c.quota_blocked) st='<span class="b br" title="Quota dépassé">🚫 QUOTA</span>';
    else if(!c.is_active) st='<span class="b br">OFF</span>';
    else if(ex) st='<span class="b br">EXPIRÉ</span>';
    else if(dy<=3) st=`<span class="b by">${dy}j</span>`;
    else st='<span class="b bg">ACTIF</span>';
    // Quota data
    const usedGb=(Number(c.total_upload)+Number(c.total_download))/(1024**3);
    let quotaHtml;
    if(c.data_limit_gb>0){
      const pct=Math.min(100,(usedGb/c.data_limit_gb)*100).toFixed(0);
      const cls=pct>=90?'crit':pct>=70?'warn':'';
      quotaHtml=`<div style="font-size:.72rem;white-space:nowrap"><div class="prg" style="width:55px"><div class="prg-b ${cls}" style="width:${pct}%"></div></div><span class="muted">${usedGb.toFixed(1)}/${c.data_limit_gb}GB</span></div>`;
    } else {
      quotaHtml=`<span class="muted" style="font-size:.72rem">${usedGb.toFixed(1)}GB <span style="color:var(--cyan)">∞</span></span>`;
    }
    return `<tr>
      <td class="muted">${c.id}</td>
      <td class="nm">${esc(c.username)}</td>
      <td><code style="color:var(--yellow);font-size:.73rem">${esc(c.password||'—')}</code></td>
      <td><code style="color:var(--dim);font-size:.7rem" title="${esc(c.uuid||'')}">${c.uuid?esc(c.uuid.substring(0,12))+'…':'—'}</code></td>
      <td>${tbadge(esc(c.tunnel_type))}</td>
      <td>${c.reseller_name?`<span style="color:#a78bfa">${esc(c.reseller_name)}</span>`:'<span class="muted">admin</span>'}</td>
      <td>${fmtB(c.total_upload)}</td><td>${fmtB(c.total_download)}</td>
      <td>${quotaHtml}</td>
      <td>${esc(fmtDT(c.expires_at))} <span class="muted sm">${fmtDLeft(c.expires_at)}</span></td>
      <td>${st}</td>
      <td><div class="actg">
        <button class="btn btn-c btn-sm btn-ic" onclick="openEC(${c.id},'${esc(c.username)}','${esc(c.tunnel_type)}','${dInp(c.expires_at)}',${c.is_active},'${esc((c.note||'').replace(/'/g,'`'))}',${c.data_limit_gb||0},'${esc(c.uuid||'')}')">✎</button>
        <button class="btn btn-r btn-sm btn-ic" onclick="delC(${c.id},'${esc(c.username)}')">✕</button>
      </div></td>
    </tr>`;
  }).join('');
}

function filterC() {
  const q=document.getElementById('csrch').value.toLowerCase();
  const t=document.getElementById('ctf').value;
  const s=document.getElementById('csf').value;
  renderClients(allClients.filter(c=>{
    const mq=!q||c.username.toLowerCase().includes(q)||c.tunnel_type.includes(q)||(c.reseller_name||'').toLowerCase().includes(q);
    const mt=!t||c.tunnel_type===t;
    const ms=!s||(s==='a'&&c.is_active&&!isExp(c.expires_at))||(s==='e'&&isExp(c.expires_at));
    return mq&&mt&&ms;
  }));
}

function genUUIDv4(){
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g,c=>{
    const r=Math.random()*16|0, v=c==='x'?r:(r&0x3|0x8); return v.toString(16);
  });
}
function openEC(id,u,t,x,a,n,dl,uuid) {
  document.getElementById('ecid').value=id;
  document.getElementById('ecu').value='';       document.getElementById('ecu').placeholder=u||'(inchangé si vide)';
  document.getElementById('ecpw').value='';
  document.getElementById('ecuuid').value='';    document.getElementById('ecuuid').placeholder=uuid||'(inchangé si vide)';
  document.getElementById('ect').value=t;
  document.getElementById('ecx').value=x;
  document.getElementById('eca').value=a;
  document.getElementById('ecn').value=n||'';
  document.getElementById('ecdl').value=dl||0;
  openM('mec');
}

async function saveC() {
  const id=document.getElementById('ecid').value;
  const d={
    expires_at:   document.getElementById('ecx').value,
    is_active:    parseInt(document.getElementById('eca').value),
    note:         document.getElementById('ecn').value,
    data_limit_gb:parseFloat(document.getElementById('ecdl').value)||0
  };
  const u    =document.getElementById('ecu').value.trim();     if(u)     d.username=u;
  const pw   =document.getElementById('ecpw').value.trim();    if(pw)    d.password=pw;
  const uuid =document.getElementById('ecuuid').value.trim();  if(uuid)  d.uuid=uuid;
  try {
    const r=await API.put(`/api/admin/clients/${id}`,d);
    Toast.s(r.tunnelChanged ? '✓ Client + tunnel recréé' : '✓ Client mis à jour');
    closeM('mec');
    loadClients();
    loadDash();
  } catch(e){Toast.e(e.message);}
}

async function delC(id,u) {
  if(!confirm(`Supprimer "${u}" et révoquer ses accès tunnel ?`)) return;
  try {
    await API.del(`/api/admin/clients/${id}`);
    Toast.s(`"${u}" supprimé`);
    loadClients();   // rafraîchit le tableau clients
    loadDash();      // rafraîchit les stats dashboard
  } catch(e){Toast.e(e.message);}
}

// ============================================================
// REVENDEURS
// ============================================================
let allRes=[];

async function loadResellers() {
  try { allRes=await API.get('/api/admin/resellers'); renderRes(allRes); } catch(e){Toast.e(e.message);}
}

function renderRes(data) {
  const tb=document.getElementById('rtbl');
  if(!data.length){tb.innerHTML='<tr><td colspan="9" style="text-align:center;padding:3rem;color:var(--muted)">Aucun revendeur</td></tr>';return;}
  tb.innerHTML=data.map(r=>{
    const ex=isExp(r.expires_at),dy=dLeft(r.expires_at),pct=r.max_users>0?Math.min(100,(r.used_users/r.max_users)*100).toFixed(0):0;
    const usedGb=(r.total_bytes||0)/(1024**3);
    const dataQuota = r.data_limit_gb>0
      ? `<div style="display:flex;align-items:center;gap:.4rem"><div class="prg" style="width:65px"><div class="prg-b ${usedGb/r.data_limit_gb>=0.9?'crit':usedGb/r.data_limit_gb>=0.7?'warn':''}" style="width:${Math.min(100,(usedGb/r.data_limit_gb)*100).toFixed(0)}%"></div></div><span class="muted sm">${usedGb.toFixed(1)}/${r.data_limit_gb}GB</span></div>`
      : `<span class="muted sm">${usedGb.toFixed(1)}GB <span style="color:var(--cyan)">∞</span></span>`;
    return `<tr>
      <td class="muted">${r.id}</td><td class="nm">${esc(r.username)}</td>
      <td>${r.used_users}/${r.max_users}<div class="prg" style="width:55px;margin-top:2px"><div class="prg-b" style="width:${pct}%"></div></div></td>
      <td>${dataQuota}</td>
      <td>${r.allowed_tunnels&&r.allowed_tunnels.length?r.allowed_tunnels.map(t=>`<span class="b" style="background:rgba(0,180,255,.12);color:var(--ac);font-size:.65rem;padding:.1rem .35rem;border-radius:3px;margin:.1rem">${esc(t)}</span>`).join(' '):'<span class="muted" style="font-size:.72rem">Tous ✓</span>'}</td>
      <td>${esc(fmtDT(r.expires_at))} <span class="muted sm">${fmtDLeft(r.expires_at)}</span></td>
      <td>${ex?'<span class="b br">EXPIRÉ</span>':r.is_active?'<span class="b bg">ACTIF</span>':'<span class="b br">OFF</span>'}</td>
      <td><div class="actg">
        <button class="btn btn-c btn-sm" onclick="openER(${r.id},${r.max_users},'${dInp(r.expires_at)}',${r.is_active},${r.data_limit_gb||0},'${esc(r.username)}',${JSON.stringify(r.allowed_tunnels||[])})">✎</button>
        <button class="btn btn-gh btn-sm" onclick="cleanR(${r.id},'${esc(r.username)}')" title="Nettoyer tous ses clients">🗑</button>
        <button class="btn btn-r btn-sm" onclick="delR(${r.id},'${esc(r.username)}')">✕</button>
      </div></td>
    </tr>`;
  }).join('');
}

function filterR() {
  const q=document.getElementById('rsrch').value.toLowerCase();
  renderRes(allRes.filter(r=>r.username.toLowerCase().includes(q)));
}

async function addR() {
  const d={
    username: document.getElementById('rnu').value.trim(),
    password: document.getElementById('rnp').value,
    max_users: parseInt(document.getElementById('rnm').value),
    data_limit_gb: parseFloat(document.getElementById('rndl').value)||0,
    expires_at: document.getElementById('rnx').value
  };
  if(!d.username||!d.password||!d.expires_at) return Toast.e('Champs requis manquants');
  const rn_tks = getCheckedTunnels('rn');
  d.allowed_tunnels = rn_tks.length ? rn_tks : null;
  try { await API.post('/api/admin/resellers',d); Toast.s(`Revendeur "${d.username}" créé`); closeM('mar'); loadResellers(); loadROptions(); } catch(e){Toast.e(e.message);}
}

function openER(id,m,x,a,dl,un,tunnels){
  document.getElementById('reid').value=id;
  document.getElementById('reun').value='';
  const fi=document.getElementById('reun');
  fi.placeholder=un||'(inchangé si vide)';
  document.getElementById('rem').value=m;
  document.getElementById('rex').value=x;
  document.getElementById('rea').value=a;
  document.getElementById('rep').value='';
  document.getElementById('redl').value=dl||0;
  document.getElementById('re_tunnels_wrap').innerHTML=buildTunnelGrid('re',Array.isArray(tunnels)?tunnels:[]);
  openM('mer');
}

async function editR() {
  const id=document.getElementById('reid').value;
  const d={
    max_users:    parseInt(document.getElementById('rem').value),
    expires_at:   document.getElementById('rex').value,
    is_active:    parseInt(document.getElementById('rea').value),
    data_limit_gb:parseFloat(document.getElementById('redl').value)||0
  };
  const un=document.getElementById('reun').value.trim(); if(un) d.username=un;
  const pw=document.getElementById('rep').value.trim();  if(pw) d.password=pw;
  const tks=getCheckedTunnels('re');
  d.allowed_tunnels = tks.length ? tks : null;
  try {
    await API.put(`/api/admin/resellers/${id}`,d);
    Toast.s('Revendeur mis à jour ✓');
    closeM('mer');
    loadResellers();
    loadDash();
  } catch(e){Toast.e(e.message);}
}

async function cleanR(id,u) {
  if(!confirm(`⚠️ Supprimer TOUS les clients de "${u}" ?\nLeurs accès tunnel seront révoqués.`)) return;
  try {
    await API.post(`/api/admin/resellers/${id}/clean`,{});
    Toast.s('Données nettoyées');
    loadResellers();
    loadDash();
  } catch(e){Toast.e(e.message);}
}

async function delR(id,u) {
  if(!confirm(`⚠️ SUPPRIMER "${u}" et tous ses clients ? Irréversible !`)) return;
  try {
    await API.del(`/api/admin/resellers/${id}`);
    Toast.s(`"${u}" supprimé`);
    loadResellers();
    loadDash();
  } catch(e){Toast.e(e.message);}
}

// ============================================================
// SYSTÈME
// ============================================================
async function loadSystem() {
  try {
    const d=await API.get('/api/admin/stats'); const sys=d.system;
    const cpu=parseFloat(sys.cpu_usage),rP=Math.round(sys.ram_used/sys.ram_total*100),dP=sys.disk?Math.round(sys.disk.used/sys.disk.total*100):0;
    document.getElementById('sc').textContent=cpu.toFixed(1)+'%';
    document.getElementById('srf').textContent=fmtB(sys.ram_free);
    document.getElementById('srt').textContent=fmtB(sys.ram_total);
    document.getElementById('sdf').textContent=sys.disk?fmtB(sys.disk.free):'N/A';
    document.getElementById('scv').textContent=cpu.toFixed(1)+'%'; document.getElementById('scb').style.width=cpu+'%';
    document.getElementById('srv').textContent=`${fmtB(sys.ram_used)}/${fmtB(sys.ram_total)} (${rP}%)`; document.getElementById('srb').style.width=rP+'%';
    if(sys.disk){document.getElementById('sdv').textContent=`${fmtB(sys.disk.used)}/${fmtB(sys.disk.total)} (${dP}%)`; document.getElementById('sdb').style.width=dP+'%';}
  } catch(e){Toast.e(e.message);}
}

// ============================================================
// LOGS
// ============================================================
async function loadLogs() {
  try {
    const logs=await API.get('/api/admin/logs');
    const ac={DELETE:'var(--red)',CREATE:'var(--green)',LOGIN:'var(--cyan)',UPDATE:'var(--yellow)'};
    document.getElementById('ltbl').innerHTML=logs.map(l=>{
      const c=Object.entries(ac).find(([k])=>l.action.includes(k))?.[1]||'var(--dim)';
      return `<tr><td style="font-size:.73rem">${fmtDT(l.created_at)}</td><td class="nm">${esc(l.actor_id)}</td><td><span class="b ${l.actor_type==='admin'?'bc':'bp'}">${esc(l.actor_type)}</span></td><td><span style="color:${c};font-family:var(--mono);font-size:.76rem">${esc(l.action)}</span></td><td class="muted" style="font-size:.73rem">${esc(l.target_type||'—')}${l.target_id?' #'+esc(l.target_id):''}</td><td class="muted mono" style="font-size:.73rem">${esc(l.ip_address||'—')}</td></tr>`;
    }).join('')||'<tr><td colspan="6" style="text-align:center;padding:2rem;color:var(--muted)">Aucun log</td></tr>';
  } catch(e){Toast.e(e.message);}
}

// Auto-refresh
setInterval(()=>{if(curPage==='dash')loadDash();if(curPage==='system')loadSystem();},30000);
</script>
</body>
</html>
ADMEOF
    cp "$DIR/admin.html" "$DIR/frontend/admin/index.html"

    # ── reseller.html ──
    cat > "$DIR/reseller.html" << 'RSLEOF'
<!DOCTYPE html><html lang="fr"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Kighmu Reseller</title><style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:system-ui,sans-serif;background:#1a1a2e;color:#eee;min-height:100vh}.header{background:#16213e;padding:1rem 2rem;display:flex;justify-content:space-between;align-items:center;border-bottom:2px solid #00d4ff}.header h1{color:#00d4ff;font-size:1.3rem}.header span{color:#888;font-size:.9rem}.container{padding:2rem;max-width:1200px;margin:0 auto}.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:1rem;margin-bottom:2rem}.stat-card{background:#16213e;padding:1.5rem;border-radius:8px;border:1px solid #0f3460}.stat-card h3{color:#888;font-size:.8rem;text-transform:uppercase;margin-bottom:.5rem}.stat-card .value{color:#00d4ff;font-size:1.8rem;font-weight:700}.card{background:#16213e;border-radius:8px;border:1px solid #0f3460;padding:1.5rem;margin-bottom:1rem}.card h2{color:#00d4ff;font-size:1.1rem;margin-bottom:1rem}.form-group{margin-bottom:1rem}.form-group label{display:block;color:#aaa;margin-bottom:.3rem;font-size:.9rem}.form-group input,.form-group select{width:100%;padding:.7rem;background:#0f3460;border:1px solid #1a3a6a;color:#eee;border-radius:4px;font-size:.95rem}.btn{background:#00d4ff;color:#1a1a2e;border:none;padding:.7rem 1.5rem;border-radius:4px;cursor:pointer;font-weight:600;font-size:.95rem}.btn:hover{background:#00b8e6}.btn-danger{background:#e74c3c}.btn-danger:hover{background:#c0392b}.inline-flex{display:flex;gap:.5rem;flex-wrap:wrap;align-items:end}table{width:100%;border-collapse:collapse;font-size:.9rem}th,td{padding:.7rem;text-align:left;border-bottom:1px solid #0f3460}th{color:#888;font-weight:600;text-transform:uppercase;font-size:.8rem}td{color:#ddd}.badge{padding:.2rem .6rem;border-radius:999px;font-size:.75rem;font-weight:600}.badge-active{background:#27ae6022;color:#27ae60;border:1px solid #27ae60}.badge-expired{background:#e74c3c22;color:#e74c3c;border:1px solid #e74c3c}.loading{text-align:center;color:#888;padding:2rem}.error{color:#e74c3c;padding:1rem}.toast{position:fixed;top:1rem;right:1rem;padding:1rem 1.5rem;border-radius:8px;z-index:9999;animation:slideIn .3s ease}@keyframes slideIn{from{transform:translateX(100%);opacity:0}to{transform:translateX(0);opacity:1}}.toast-success{background:#27ae60;color:#fff}.toast-error{background:#e74c3c;color:#fff}.nav-tabs{display:flex;gap:0;margin-bottom:1.5rem;border-bottom:2px solid #0f3460}.nav-tab{padding:.8rem 1.5rem;cursor:pointer;color:#888;border-bottom:2px solid transparent;margin-bottom:-2px;font-weight:500}.nav-tab.active{color:#00d4ff;border-bottom-color:#00d4ff}.hidden{display:none}</style></head><body><div class="header"><h1>Kighmu Reseller</h1><span id="resellerName">Reseller</span></div><div class="container"><div id="loginView"><div class="card" style="max-width:400px;margin:4rem auto"><h2>Connexion Reseller</h2><div class="form-group"><label>Identifiant</label><input type="text" id="loginUser" placeholder="reseller"></div><div class="form-group"><label>Mot de passe</label><input type="password" id="loginPass" placeholder="••••••••" onkeydown="if(event.key==='Enter')doLogin()"></div><button class="btn" onclick="doLogin()" style="width:100%">Connexion</button><p id="loginError" class="error hidden"></p></div></div><div id="dashboardView" class="hidden"><div class="stats"><div class="stat-card"><h3>Clients actifs</h3><div class="value" id="statClients">0</div></div><div class="stat-card"><h3>Bande passante</h3><div class="value" id="statBW">0 GB</div></div><div class="stat-card"><h3>Revenu mois</h3><div class="value" id="statRevenue">0 €</div></div></div><div class="nav-tabs"><div class="nav-tab active" onclick="switchTab('clients',this)">Clients</div><div class="nav-tab" onclick="switchTab('create',this)">Créer</div><div class="nav-tab" onclick="switchTab('traffic',this)">Traffic</div></div><div id="tabClients"><div class="card"><h2>Mes clients</h2><table><thead><tr><th>User</th><th>Service</th><th>Expire</th><th>Traffic</th><th>Actions</th></tr></thead><tbody id="clientsTable"><tr><td colspan="5" class="loading">Chargement...</td></tr></tbody></table></div></div><div id="tabCreate" class="hidden"><div class="card"><h2>Créer un client</h2><div class="form-group"><label>Type</label><select id="createType"><option value="ssh">SSH</option><option value="vmess">VMESS</option><option value="vless">VLESS</option><option value="trojan">Trojan</option></select></div><div class="form-group"><label>Username</label><input type="text" id="createUser"></div><div class="form-group"><label>Password (SSH)</label><input type="text" id="createPass"></div><div class="form-group"><label>Expiration (jours)</label><input type="number" id="createDays" value="30"></div><div class="form-group"><label>Limite traffic (GB, 0 = illimité)</label><input type="number" id="createLimit" value="0"></div><button class="btn" onclick="createClient()">Créer</button><p id="createResult" class="hidden" style="margin-top:1rem"></p></div></div><div id="tabTraffic" class="hidden"><div class="card"><h2>Traffic des clients</h2><table><thead><tr><th>User</th><th>Download</th><th>Upload</th><th>Total</th></tr></thead><tbody id="trafficTable"><tr><td colspan="4" class="loading">Chargement...</td></tr></tbody></table></div></div></div></div><script>const API=window.location.origin;let token=localStorage.getItem('resellerToken');function toast(m,t){const d=document.createElement('div');d.className='toast toast-'+t;d.textContent=m;document.body.appendChild(d);setTimeout(()=>d.remove(),3000)}function _(i){return document.getElementById(i)}function show(v){_('loginView').classList.toggle('hidden',v!='login');_('dashboardView').classList.toggle('hidden',v!='dash')}async function api(m,e,b){const h={'Content-Type':'application/json'};if(token)h['Authorization']='Bearer '+token;const r=await fetch(API+e,{method:m,headers:h,body:b?JSON.stringify(b):null});const d=await r.json();if(d.error&&e!='/api/auth/login'){token=null;localStorage.removeItem('resellerToken');show('login');throw new Error(d.error)}return d}async function doLogin(){const u=_('loginUser').value,p=_('loginPass').value;if(!u||!p)return;try{const r=await api('POST','/api/auth/reseller-login',{username:u,password:p});token=r.token;localStorage.setItem('resellerToken',r.token);_('resellerName').textContent=r.user||u;show('dash');loadDashboard()}catch(e){_('loginError').textContent='Erreur de connexion';_('loginError').classList.remove('hidden')}}async function loadDashboard(){try{const r=await api('GET','/api/reseller/stats');_('statClients').textContent=r.clients||0;_('statBW').textContent=(r.bandwidth||'0')+' GB';_('statRevenue').textContent=(r.revenue||'0')+' €';loadClients();loadTraffic()}catch(e){}}async function loadClients(){try{const r=await api('GET','/api/reseller/clients');const t=_('clientsTable');if(!r.clients||!r.clients.length){t.innerHTML='<tr><td colspan="5" class="loading">Aucun client</td></tr>';return}t.innerHTML=r.clients.map(c=>'<tr><td>'+c.username+'</td><td>'+c.type+'</td><td>'+(c.expire||'-')+'</td><td>'+(c.traffic||'0')+'</td><td><button class="btn btn-danger" style="padding:.3rem .8rem;font-size:.8rem" onclick="deleteClient(\''+c.username+'\')">Suppr</button></td></tr>').join('')}catch(e){_('clientsTable').innerHTML='<tr><td colspan="5" class="error">Erreur chargement</td></tr>'}}async function loadTraffic(){try{const r=await api('GET','/api/reseller/traffic');const t=_('trafficTable');if(!r.traffic||!r.traffic.length){t.innerHTML='<tr><td colspan="4" class="loading">Aucune donnée</td></tr>';return}t.innerHTML=r.traffic.map(c=>'<tr><td>'+c.username+'</td><td>'+c.download+'</td><td>'+c.upload+'</td><td>'+c.total+'</td></tr>').join('')}catch(e){}}async function createClient(){const type=_('createType').value,u=_('createUser').value,p=_('createPass').value,d=_('createDays').value,l=_('createLimit').value;if(!u){toast('Nom requis','error');return}try{const r=await api('POST','/api/reseller/create',{type,username:u,password:p,days:parseInt(d),limit:parseInt(l)});_('createResult').textContent='✓ Client '+u+' créé';_('createResult').className='';_('createUser').value='';_('createPass').value='';loadClients();toast('Client créé','success')}catch(e){_('createResult').textContent='✗ Erreur: '+e.message;_('createResult').className=''}}async function deleteClient(u){if(!confirm('Supprimer '+u+' ?'))return;try{await api('DELETE','/api/reseller/client/'+u);loadClients();toast('Client supprimé','success')}catch(e){toast('Erreur','error')}}function switchTab(t,el){document.querySelectorAll('.nav-tab').forEach(e=>e.classList.remove('active'));el.classList.add('active');document.querySelectorAll('[id^=tab]').forEach(e=>e.classList.add('hidden'));_('tab'+t.charAt(0).toUpperCase()+t.slice(1)).classList.remove('hidden')}if(token){show('dash');loadDashboard()}</script></body></html>
RSLEOF
    cp "$DIR/reseller.html" "$DIR/frontend/reseller/index.html"

    # ── schema.sql ──
    cat > "$DIR/schema.sql" << 'SQLEOF'
-- ============================================================
-- KIGHMU PANEL v2 - Base de données
-- Usage: mysql -u root -p < schema.sql
-- ============================================================
CREATE DATABASE IF NOT EXISTS kighmu_panel CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE kighmu_panel;

CREATE TABLE IF NOT EXISTS admins (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP NULL
);

CREATE TABLE IF NOT EXISTS resellers (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    email VARCHAR(100),
    max_users INT DEFAULT 10,
    used_users INT DEFAULT 0,
    data_limit_gb DECIMAL(10,2) DEFAULT 0,
    quota_blocked TINYINT(1) DEFAULT 0,
    allowed_tunnels TEXT DEFAULT NULL,  -- JSON array ex: ["vless","ssh-multi"] — NULL = tous autorisés
    expires_at TIMESTAMP NOT NULL,
    is_active TINYINT(1) DEFAULT 1,
    created_by INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (created_by) REFERENCES admins(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS clients (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    password VARCHAR(255),
    uuid VARCHAR(36),
    reseller_id INT,
    tunnel_type VARCHAR(30) NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    is_active TINYINT(1) DEFAULT 1,
    quota_blocked TINYINT(1) DEFAULT 0,
    data_limit_gb DECIMAL(10,2) DEFAULT 0,
    note TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (reseller_id) REFERENCES resellers(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS usage_stats (
    id INT AUTO_INCREMENT PRIMARY KEY,
    client_id INT,
    reseller_id INT,
    upload_bytes BIGINT DEFAULT 0,
    download_bytes BIGINT DEFAULT 0,
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE CASCADE,
    FOREIGN KEY (reseller_id) REFERENCES resellers(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS activity_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    actor_type ENUM('admin','reseller') NOT NULL,
    actor_id INT NOT NULL,
    action VARCHAR(100) NOT NULL,
    target_type VARCHAR(50),
    target_id INT,
    details TEXT,
    ip_address VARCHAR(45),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS monthly_totals (
    id INT AUTO_INCREMENT PRIMARY KEY,
    year INT NOT NULL,
    month INT NOT NULL,
    total_upload BIGINT DEFAULT 0,
    total_download BIGINT DEFAULT 0,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY ym (year, month)
);

CREATE TABLE IF NOT EXISTS login_attempts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    ip_address VARCHAR(45) NOT NULL,
    attempts INT DEFAULT 1,
    blocked_until TIMESTAMP NULL,
    last_attempt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_ip (ip_address)
);

-- L'admin doit être créé par le script d'installation avec un mot de passe unique
-- Ne JAMAIS laisser de hash par défaut dans le code source

-- ============================================================
-- MIGRATION pour installations existantes (décommenter si upgrade)
-- ============================================================
-- ALTER TABLE resellers ADD COLUMN IF NOT EXISTS data_limit_gb DECIMAL(10,2) DEFAULT 0;
-- ALTER TABLE clients ADD COLUMN IF NOT EXISTS data_limit_gb DECIMAL(10,2) DEFAULT 0;
-- ALTER TABLE clients ADD COLUMN IF NOT EXISTS quota_blocked TINYINT(1) DEFAULT 0;
-- ALTER TABLE resellers ADD COLUMN IF NOT EXISTS allowed_tunnels TEXT DEFAULT NULL;
-- ALTER TABLE resellers ADD COLUMN IF NOT EXISTS quota_blocked TINYINT(1) DEFAULT 0;
SQLEOF

    # ── index.html ──
    cat > "$DIR/frontend/index.html" << 'HTMLEOF'
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Kighmu Panel</title>
<meta http-equiv="refresh" content="0;url=/admin/"></head><body><h1>Kighmu Panel</h1></body></html>
HTMLEOF

    echo "Panel files extracted to $DIR"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    extract_web_panel "$1"
fi
