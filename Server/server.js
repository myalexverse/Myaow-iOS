const { authorizeRoute } = require('./access_control');
//
//  server.js
//  Myaow Zero-Knowledge Relay, X3DH Prekey Directory & WebRTC Signaling Server
//
//  "Tecnología avanzada con una personalidad tranquila"
//

const http = require('http');
const { WebSocketServer, WebSocket } = require('ws');
const crypto = require('crypto');
const relayAuth = require('./relay_auth');
const fs = require('fs');
const path = require('path');
const Database = require('better-sqlite3');
const MyaowAPNsGateway = require('./apns_gateway.js');
const storage = require('./storage.js');
require('dotenv').config();

const PORT = process.env.PORT || 8080;
const UPLOADS_DIR = storage.UPLOADS_DIR;

// Rate Limiting
const rateLimits = new Map(); // key: myaowId/IP, value: { count, windowStart }

function checkRateLimit(identifier, maxRequests = 60, windowMs = 60000) {
    const now = Date.now();
    let entry = rateLimits.get(identifier);
    if (!entry || (now - entry.windowStart) > windowMs) {
        entry = { count: 0, windowStart: now };
    }
    entry.count++;
    rateLimits.set(identifier, entry);
    return entry.count <= maxRequests;
}

// Clean up rate limits every 5 minutes
setInterval(() => {
    const now = Date.now();
    for (const [key, entry] of rateLimits) {
        if (now - entry.windowStart > 120000) rateLimits.delete(key);
    }
}, 300000);

// 📂 Asegurar que el directorio de uploads existe
if (!fs.existsSync(UPLOADS_DIR)) {
    fs.mkdirSync(UPLOADS_DIR, { recursive: true });
}

// ==========================================
// 1. Base de Datos SQLite (better-sqlite3)
// ==========================================
const db = new Database(process.env.MYAOW_DB_PATH || path.join(__dirname, 'myaow.db'));
db.pragma('journal_mode = WAL');
db.pragma('synchronous = FULL');

// 🛠️ Inicializar tablas
db.exec(`
    CREATE TABLE IF NOT EXISTS users (
        username TEXT UNIQUE,
        myaow_id TEXT UNIQUE PRIMARY KEY,
        display_name TEXT,
        identity_key_hex TEXT,
        signed_prekey_hex TEXT,
        apns_token TEXT,
        avatar_url TEXT DEFAULT NULL,
        updated_at TEXT,
        last_seen TEXT
    );
    CREATE TABLE IF NOT EXISTS one_time_prekeys (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        myaow_id TEXT,
        prekey_hex TEXT,
        used INTEGER DEFAULT 0
    );
    CREATE TABLE IF NOT EXISTS offline_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        recipient_myaow_id TEXT,
        packet_json TEXT,
        created_at TEXT
    );
    CREATE TABLE IF NOT EXISTS groups (
        id TEXT PRIMARY KEY,
        name TEXT,
        created_by TEXT,
        created_at TEXT
    );
    CREATE TABLE IF NOT EXISTS group_members (
        group_id TEXT,
        myaow_id TEXT,
        role TEXT DEFAULT 'member',
        joined_at TEXT,
        PRIMARY KEY(group_id, myaow_id)
    );
    CREATE TABLE IF NOT EXISTS blocked_contacts (
        blocker_id TEXT NOT NULL,
        blocked_id TEXT NOT NULL,
        blocked_at TEXT DEFAULT (datetime('now')),
        PRIMARY KEY (blocker_id, blocked_id)
    );
    CREATE TABLE IF NOT EXISTS sessions (
        session_id TEXT PRIMARY KEY,
        myaow_id TEXT NOT NULL,
        device_name TEXT DEFAULT 'Unknown Device',
        created_at TEXT DEFAULT (datetime('now')),
        last_active TEXT DEFAULT (datetime('now'))
    );
    CREATE TABLE IF NOT EXISTS moments (
        id TEXT PRIMARY KEY,
        author_id TEXT NOT NULL,
        author_name TEXT NOT NULL,
        author_avatar_state TEXT DEFAULT 'friendly',
        caption TEXT DEFAULT '',
        media_url TEXT DEFAULT NULL,
        cat_emotion TEXT DEFAULT 'friendly',
        background_index INTEGER DEFAULT 0,
        created_at TEXT DEFAULT (datetime('now')),
        expires_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS scheduled_messages (
        id TEXT PRIMARY KEY,
        sender_myaow_id TEXT NOT NULL,
        recipient_myaow_id TEXT,
        group_id TEXT,
        message_text TEXT NOT NULL,
        scheduled_at TEXT NOT NULL,
        is_sent INTEGER DEFAULT 0,
        created_at TEXT DEFAULT (datetime('now'))
    );
    CREATE TABLE IF NOT EXISTS group_tasks (
        id TEXT PRIMARY KEY,
        group_id TEXT NOT NULL,
        title TEXT NOT NULL,
        assignee_myaow_id TEXT,
        assignee_name TEXT,
        due_label TEXT DEFAULT 'Pronto',
        priority TEXT DEFAULT 'normal',
        is_completed INTEGER DEFAULT 0,
        completed_by_myaow_id TEXT,
        completed_by_name TEXT,
        completed_at TEXT,
        created_by_myaow_id TEXT NOT NULL,
        created_at TEXT DEFAULT (datetime('now'))
    );
`);

try {
    db.prepare('ALTER TABLE users ADD COLUMN last_seen TEXT').run();
} catch (e) {
    // Ignorar si ya existe
}
try {
    db.prepare('ALTER TABLE users ADD COLUMN username TEXT').run();
} catch (e) {
    // Ignorar si ya existe
}


const apns = new MyaowAPNsGateway();
const { BetaAccess } = require('./beta_access');
const betaAccess = new BetaAccess(db);
const { clientAddress } = require('./proxy_address');
const diagnostic = {
    log: (...args) => { if (process.env.NODE_ENV !== 'production') console.log(...args); },
    error: (...args) => {
        if (process.env.NODE_ENV !== 'production') console.error(...args);
        else console.error(JSON.stringify({event:'relay_operation_failed',time:new Date().toISOString()}));
    }
};

// ==========================================
// 2. Almacenamiento en Memoria / Estado
// ==========================================

// Conexiones WebSocket Activas: myaowId -> WebSocket
const activeSockets = new Map();
// Nonces de Autenticación Pendientes: ws -> nonce
const pendingAuthChallenges = new Map();
// Estado del avatar: myaowId -> avatarStateName
const avatarStates = new Map();

// Helper para resolver el socket de un destinatario
function resolveSocketsForRecipient(recipient) {
    if (!recipient) return { sockets: [], myaowId: '' };
    const clean = recipient.trim();
    const lower = clean.toLowerCase();
    let targetMyaowId = clean;
    
    if (activeSockets.has(clean)) {
        targetMyaowId = clean;
    } else {
        let found = false;
        for (const [id, s] of activeSockets.entries()) {
            if (id.toLowerCase() === lower) {
                targetMyaowId = id;
                found = true;
                break;
            }
        }
        if (!found) {
            const stmt = db.prepare('SELECT myaow_id FROM users WHERE LOWER(username) = ? OR LOWER(display_name) = ? OR LOWER(myaow_id) = ?');
            const user = stmt.get(lower, lower, lower);
            if (user) targetMyaowId = user.myaow_id;
        }
    }
    
    const deviceMap = activeSockets.get(targetMyaowId);
    if (!deviceMap) return { sockets: [], myaowId: targetMyaowId };
    
    const sockets = [];
    for (const [sessionId, info] of deviceMap) {
        if (info.ws.readyState === WebSocket.OPEN) {
            sockets.push(info.ws);
        } else {
            deviceMap.delete(sessionId);
        }
    }
    return { sockets, myaowId: targetMyaowId };
}

// Auth middleware - validates session token from Authorization header
function authenticateRequest(req) {
    const authHeader = req.headers['authorization'];
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return null;
    }
    const sessionId = authHeader.slice(7);
    if (!/^sess_[0-9a-f]{64}$/.test(sessionId)) return null;
    const session = db.prepare('SELECT myaow_id, device_name FROM sessions WHERE session_id = ?').get(sessionId);
    if (!session || !activeSockets.get(session.myaow_id)?.has(sessionId)) {
        return null;
    }
    // Update last_active
    db.prepare('UPDATE sessions SET last_active = ? WHERE session_id = ?').run(new Date().toISOString(), sessionId);
    return session; // { myaow_id, device_name }
}

// Helper para parsear body JSON
const parseBody = (req) => {
    return new Promise((resolve, reject) => {
        let body = '';
        let bytes = 0;
        req.on('data', chunk => {
            bytes += chunk.length;
            if (bytes > 5 * 1024 * 1024) { reject(new Error('Request too large')); req.destroy(); return; }
            body += chunk;
        });
        req.on('end', () => {
            try { resolve(JSON.parse(body)); } 
            catch (e) { reject(new Error('Invalid JSON')); }
        });
        req.on('error', reject);
    });
};

// ==========================================
// 3. Servidor HTTP REST (Directorio & Media & Health)
// ==========================================

const server = http.createServer(async (req, res) => {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Myaow-Id, X-Content-Type, X-Filename');

    if (req.method === 'OPTIONS') {
        res.writeHead(204);
        return res.end();
    }

    const url = new URL(req.url, 'http://relay.internal');
    const routeActor = authenticateRequest(req);
    const clientIp = clientAddress(req, process.env.MYAOW_TRUST_PROXY === '1');
    if (!checkRateLimit(routeActor ? `http_user_${routeActor.myaow_id}` : `http_ip_${clientIp}`, routeActor ? 3000 : 100, 60000)) {
        res.writeHead(429, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: 'Too many requests' }));
    }
    const access = authorizeRoute(db, url.pathname, req.method, routeActor);
    if (access !== 200) {
        res.writeHead(access, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: access === 401 ? 'Authentication required' : access === 409 ? 'Encrypted scheduling is not available yet' : 'Access denied' }));
    }


    // 🩺 Health Check
    if (url.pathname === '/health' || url.pathname === '/') {
        db.prepare('SELECT 1').get();
        res.writeHead(200, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({
            status: 'ok',
            service: 'myaow-relay-server',
            timestamp: new Date().toISOString()
        }));
    }

    // 🌐 Status Online (Presence)
    if (url.pathname === '/api/v1/presence/online' && req.method === 'GET') {
        const onlineIds = [];
        for (const [myaowId, deviceMap] of activeSockets) {
            if (deviceMap.size > 0) {
                // Check at least one socket is open
                let hasOpenSocket = false;
                for (const [, info] of deviceMap) {
                    if (info.ws.readyState === WebSocket.OPEN) {
                        hasOpenSocket = true;
                        break;
                    }
                }
                if (hasOpenSocket && myaowId === routeActor.myaow_id) onlineIds.push(myaowId);
            }
        }
        res.writeHead(200, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ online: onlineIds }));
    }

    if (url.pathname.startsWith('/api/v1/presence/status/') && req.method === 'GET') {
        const myaowId = url.pathname.split('/').pop();
        const user = db.prepare('SELECT last_seen FROM users WHERE myaow_id = ?').get(myaowId);
        
        let isOnline = false;
        const deviceMap = activeSockets.get(myaowId);
        if (deviceMap && deviceMap.size > 0) {
            for (const [, info] of deviceMap) {
                if (info.ws.readyState === WebSocket.OPEN) {
                    isOnline = true;
                    break;
                }
            }
        }
        
        res.writeHead(200, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ 
            myaowId, 
            isOnline, 
            lastSeen: user ? user.last_seen : null 
        }));
    }

    // 📁 Subida de Media (POST /api/v1/media/upload)
    if (url.pathname === '/api/v1/media/upload' && req.method === 'POST') {
        const authUser = authenticateRequest(req);
        if (!authUser) {
            res.writeHead(401, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: 'Authentication required' }));
        }
        const uploaderId = authUser.myaow_id;
        const ext = path.extname(req.headers['x-filename'] || '') || '.bin';
        const mediaId = crypto.randomUUID();
        const fileName = `${mediaId}${ext}`;
        const contentType = req.headers['content-type'] || req.headers['x-content-type'] || 'application/octet-stream';
        
        const chunks = [];
        let fileSize = 0;
        const maxFileSize = 100 * 1024 * 1024; // 100 MB

        req.on('data', chunk => {
            fileSize += chunk.length;
            if (fileSize > maxFileSize) {
                req.destroy();
            } else {
                chunks.push(chunk);
            }
        });

        req.on('end', async () => {
            if (fileSize > maxFileSize) {
                res.writeHead(413, { 'Content-Type': 'application/json' });
                return res.end(JSON.stringify({ error: 'Archivo demasiado grande (máximo 100MB)' }));
            }
            const buffer = Buffer.concat(chunks);
            try {
                const result = await storage.uploadFile({ buffer, fileName, contentType });
                diagnostic.log(`📸 [Media] Archivo subido: ${fileName} por ${uploaderId} (${fileSize} bytes) -> ${result.mediaUrl}`);
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify(result));
            } catch (err) {
                diagnostic.error(`❌ [Media] Error procesando subida: ${err.message}`);
                res.writeHead(500, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ error: 'Error guardando archivo multimedia' }));
            }
        });
        return;
    }

    // 🖼️ Descarga de Media (GET /api/v1/media/:id)
    if (url.pathname.startsWith('/api/v1/media/') && req.method === 'GET') {
        const fileId = url.pathname.split('/').pop();
        storage.getFile(fileId).then(fileResult => {
            if (fileResult.notFound) {
                res.writeHead(404, { 'Content-Type': 'application/json' });
                return res.end(JSON.stringify({ error: 'Archivo no encontrado' }));
            }
            if (fileResult.size) {
                res.setHeader('Content-Length', fileResult.size);
            }
            res.setHeader('Content-Type', 'application/octet-stream');
            res.writeHead(200);

            if (fileResult.stream && typeof fileResult.stream.pipe === 'function') {
                fileResult.stream.pipe(res);
            } else if (fileResult.stream) {
                // S3 SDK v3 Body stream
                fileResult.stream.transformToString ? fileResult.stream.pipe(res) : fileResult.stream.pipe(res);
            } else {
                res.end();
            }
        }).catch(err => {
            diagnostic.error(`❌ [Media] Error descargando ${fileId}: ${err.message}`);
            res.writeHead(500, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ error: 'Error obteniendo archivo' }));
        });
        return;
    }

    // 👤 Subir Avatar de Perfil (POST /api/v1/profile/avatar)
    if (url.pathname === '/api/v1/profile/avatar' && req.method === 'POST') {
        const authUser = authenticateRequest(req);
        if (!authUser) {
            res.writeHead(401, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: 'Authentication required' }));
        }
        const uploaderId = authUser.myaow_id;

        const ext = path.extname(req.headers['x-filename'] || '') || '.jpg';
        const fileName = `avatar_${uploaderId}${ext}`;
        const contentType = 'image/jpeg';
        
        const chunks = [];
        let fileSize = 0;
        const maxFileSize = 10 * 1024 * 1024; // 10 MB

        req.on('data', chunk => {
            fileSize += chunk.length;
            if (fileSize > maxFileSize) {
                req.destroy();
            } else {
                chunks.push(chunk);
            }
        });

        req.on('end', async () => {
            if (fileSize > maxFileSize) {
                res.writeHead(413, { 'Content-Type': 'application/json' });
                return res.end(JSON.stringify({ error: 'Avatar demasiado grande (máximo 10MB)' }));
            }
            const buffer = Buffer.concat(chunks);
            try {
                const result = await storage.uploadFile({ buffer, fileName, contentType });
                db.prepare('UPDATE users SET avatar_url = ? WHERE myaow_id = ?').run(result.mediaUrl, uploaderId);
                diagnostic.log(`🖼️ [Perfil] Avatar actualizado para ${uploaderId} -> ${result.mediaUrl}`);
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ avatarUrl: result.mediaUrl }));
            } catch (err) {
                diagnostic.error(`❌ [Perfil] Error guardando avatar: ${err.message}`);
                res.writeHead(500, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ error: 'Error guardando avatar' }));
            }
        });
        return;
    }

    // 👤 Obtener Perfil (GET /api/v1/profile/:myaowId)
    const profileMatch = url.pathname.match(/^\/api\/v1\/profile\/([^\/]+)$/);
    if (profileMatch && req.method === 'GET') {
        const myaowId = profileMatch[1];
        if (myaowId === 'avatar') return; // conflict with /api/v1/profile/avatar

        const user = db.prepare('SELECT display_name, avatar_url FROM users WHERE myaow_id = ?').get(myaowId);
        if (user && !db.prepare('SELECT 1 FROM blocked_contacts WHERE (blocker_id=? AND blocked_id=?) OR (blocker_id=? AND blocked_id=?)').get(routeActor.myaow_id, myaowId, myaowId, routeActor.myaow_id)) {
            res.writeHead(200, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({
                myaowId: myaowId,
                displayName: user.display_name,
                avatarUrl: user.avatar_url
            }));
        } else {
            res.writeHead(404, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: 'Usuario no encontrado' }));
        }
    }

    // 📖 Registro de Identidad & Prekeys X3DH (POST /api/v1/directory/register)
    if (url.pathname === '/api/v1/directory/register' && req.method === 'POST') {
        try {
            const data = await parseBody(req);
            const { username, myaowId, displayName, identityKeyHex, signedPrekeyHex, oneTimePrekeys, apnsToken } = data;

            if (typeof myaowId !== 'string' || !/^MYAOW-[A-Z0-9]{4,32}$/.test(myaowId)) {
                res.writeHead(400, { 'Content-Type': 'application/json' });
                return res.end(JSON.stringify({ error: 'Falta campo obligatorio myaowId' }));
            }

            if (username != null && typeof username !== 'string') {
                res.writeHead(400, { 'Content-Type': 'application/json' });
                return res.end(JSON.stringify({ error: 'El nombre de usuario no es válido.' }));
            }
            const sanitizedUsername = (username || myaowId).toLowerCase().trim();
            if (sanitizedUsername !== myaowId.toLowerCase() && !/^[a-z0-9_]{3,30}$/.test(sanitizedUsername)) {
                res.writeHead(400, { 'Content-Type': 'application/json' });
                return res.end(JSON.stringify({ error: 'Usa de 3 a 30 letras, números o guion bajo.' }));
            }
            const usernameOwner = db.prepare('SELECT myaow_id FROM users WHERE username = ? COLLATE NOCASE').get(sanitizedUsername);
            if (usernameOwner && usernameOwner.myaow_id !== myaowId) {
                res.writeHead(409, { 'Content-Type': 'application/json' });
                return res.end(JSON.stringify({ error: 'Ese nombre de usuario ya está en uso. Prueba con otro.' }));
            }
            const existingIdentity = db.prepare('SELECT * FROM users WHERE myaow_id = ?').get(myaowId);
            if (existingIdentity?.identity_key_hex && existingIdentity.identity_key_hex !== identityKeyHex) {
                res.writeHead(409, { 'Content-Type': 'application/json' });
                return res.end(JSON.stringify({ error: 'Ese identificador pertenece a otra identidad.' }));
            }
            
            if (!relayAuth.validPublicKey(identityKeyHex)) {
                res.writeHead(400, { 'Content-Type': 'application/json' });
                return res.end(JSON.stringify({ error: 'La clave pública de identidad no es válida.' }));
            }
            if (existingIdentity) {
                const owner = authenticateRequest(req);
                if (owner?.myaow_id !== myaowId) {
                    const exactRetry = existingIdentity.username === sanitizedUsername &&
                        existingIdentity.display_name === (displayName || username || myaowId) &&
                        existingIdentity.identity_key_hex === identityKeyHex &&
                        existingIdentity.signed_prekey_hex === (signedPrekeyHex || '') &&
                        existingIdentity.apns_token === (apnsToken || null) &&
                        (!oneTimePrekeys || (Array.isArray(oneTimePrekeys) && oneTimePrekeys.length === 0));
                    res.writeHead(exactRetry ? 200 : 401, { 'Content-Type': 'application/json' });
                    return res.end(JSON.stringify(exactRetry ? { success: true, myaowId } : { error: 'Inicia sesión para actualizar esta identidad.' }));
                }
            }

            db.transaction(() => {
                if (!existingIdentity) betaAccess.consume(myaowId, data.betaInvite);
            // Insertar o actualizar usuario
            const stmt = db.prepare(`
                INSERT INTO users (username, myaow_id, display_name, identity_key_hex, signed_prekey_hex, apns_token, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(myaow_id) DO UPDATE SET
                    username = excluded.username,
                    display_name = excluded.display_name,
                    identity_key_hex = excluded.identity_key_hex,
                    signed_prekey_hex = excluded.signed_prekey_hex,
                    apns_token = excluded.apns_token,
                    updated_at = excluded.updated_at
            `);
            stmt.run(
                sanitizedUsername,
                myaowId.trim(),
                displayName || username || myaowId,
                identityKeyHex || '',
                signedPrekeyHex || '',
                apnsToken || null,
                new Date().toISOString()
            );

            // Insertar One-Time Prekeys
            if (Array.isArray(oneTimePrekeys) && oneTimePrekeys.length > 0) {
                const insertPrekey = db.prepare('INSERT INTO one_time_prekeys (myaow_id, prekey_hex) VALUES (?, ?)');
                const insertMany = db.transaction((keys) => {
                    for (const key of keys) insertPrekey.run(myaowId.trim(), key);
                });
                insertMany(oneTimePrekeys);
            }

            })();
            diagnostic.log(`📇 [Directorio] Usuario registrado: ${displayName} (${myaowId})`);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ success: true, message: 'Identidad registrada', myaowId }));
        } catch (err) {
            diagnostic.error(err);
            res.writeHead(err.status || 400, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: err.status === 403 ? err.message : 'No pudimos completar el registro.' }));
        }
    }

    // 🔍 Búsqueda de Usuario y Prekeys X3DH (GET /api/v1/directory/lookup?username=@bob)
    if (url.pathname === '/api/v1/directory/lookup' && req.method === 'GET') {
        const queryUsername = (url.searchParams.get('username') || '').toLowerCase().trim();
        const stmt = db.prepare('SELECT * FROM users WHERE LOWER(username) = ? OR LOWER(myaow_id) = ?');
        const user = stmt.get(queryUsername, queryUsername);

        if (!user || db.prepare('SELECT 1 FROM blocked_contacts WHERE (blocker_id = ? AND blocked_id = ?) OR (blocker_id = ? AND blocked_id = ?)').get(routeActor.myaow_id, user.myaow_id, user.myaow_id, routeActor.myaow_id)) {
            res.writeHead(404, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: 'Usuario no encontrado' }));
        }

        res.writeHead(200, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({
            username: user.username,
            myaowId: user.myaow_id,
            displayName: user.display_name,
            identityKeyHex: user.identity_key_hex,
            signedPrekeyHex: user.signed_prekey_hex,
            oneTimePrekeyHex: null,
            isOnline: user.myaow_id === routeActor.myaow_id && activeSockets.has(user.myaow_id)
        }));
    }

    // Check username availability
    if (url.pathname.startsWith('/api/v1/directory/check-username/') && req.method === 'GET') {
        let username;
        try {
            username = decodeURIComponent(url.pathname.split('/').pop()).trim().toLowerCase();
        } catch {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: 'El nombre de usuario no es válido.' }));
        }
        if (!/^[a-z0-9_]{3,30}$/.test(username)) {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: 'Usa de 3 a 30 letras, números o guion bajo.' }));
        }
        const existing = db.prepare('SELECT myaow_id FROM users WHERE username = ? COLLATE NOCASE').get(username);
        const available = !existing;
        res.writeHead(200, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ available, username }));
    }

    // 🌍 Búsqueda General de Contactos (GET /api/v1/directory/search?q=...)
    if (url.pathname === '/api/v1/directory/search' && req.method === 'GET') {
        const query = (url.searchParams.get('q') || '').replace(/^@/, '').toLowerCase().trim();
        const results = query.length < 3 ? [] : db.prepare(`SELECT username, myaow_id, display_name, identity_key_hex FROM users
            WHERE (LOWER(username) = ? OR LOWER(myaow_id) = ?) AND NOT EXISTS (
                SELECT 1 FROM blocked_contacts WHERE (blocker_id = ? AND blocked_id = users.myaow_id)
                OR (blocker_id = users.myaow_id AND blocked_id = ?)) LIMIT 1`)
            .all(query, query, routeActor.myaow_id, routeActor.myaow_id).map(u => ({
                username: u.username, myaowId: u.myaow_id, displayName: u.display_name,
                identityKeyHex: u.identity_key_hex, isOnline: false
            }));

        res.writeHead(200, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ results }));
    }

    if (url.pathname === '/api/v1/webrtc/ice-servers' && req.method === 'GET') {
        if (!checkRateLimit(`ice_${routeActor.myaow_id}`, 30)) { res.writeHead(429); return res.end(); }
        try {
            const config = require('./ice_configuration').iceConfiguration(routeActor.myaow_id);
            res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
            return res.end(JSON.stringify(config));
        } catch { res.writeHead(503); return res.end(JSON.stringify({error:'Calling relay is not configured'})); }
    }
    if (url.pathname === '/api/v1/push/device' && req.method === 'PUT') {
        try {
            pushDelivery.register(routeActor.myaow_id, await parseBody(req));
            res.writeHead(200); return res.end('{}');
        } catch { res.writeHead(400); return res.end('{}'); }
    }
    if (url.pathname === '/api/v1/calls/signal' && req.method === 'POST') {
        if (!checkRateLimit(`call_${routeActor.myaow_id}`, 300)) { res.writeHead(429); return res.end(); }
        try {
            const data = await parseBody(req);
            if (data.signalType === 'call_offer' && !checkRateLimit(`call_offer_${routeActor.myaow_id}`, 10)) { res.writeHead(429); return res.end(); }
            const result = callRelay.accept(routeActor.myaow_id, data);
            if (result.fresh) for (const socket of resolveSocketsForRecipient(result.packet.recipientMyaowId).sockets) socket.send(JSON.stringify(result.packet));
            res.writeHead(200); return res.end('{}');
        } catch { res.writeHead(409); return res.end(JSON.stringify({error:'Call unavailable'})); }
    }

    if (url.pathname === '/api/v1/groups/invite/create' && req.method === 'POST') {
        try {
            const data = await parseBody(req);
            const admin = db.prepare('SELECT role FROM group_members WHERE group_id=? AND myaow_id=?').get(data.groupId, routeActor.myaow_id);
            if (admin?.role !== 'admin') { res.writeHead(403); return res.end(); }
            const target = db.prepare('SELECT myaow_id FROM users WHERE LOWER(username)=? OR myaow_id=?').get(String(data.target || '').replace(/^@/, '').toLowerCase(), data.target);
            if (!target || target.myaow_id === routeActor.myaow_id || db.prepare('SELECT 1 FROM blocked_contacts WHERE (blocker_id=? AND blocked_id=?) OR (blocker_id=? AND blocked_id=?)').get(target.myaow_id, routeActor.myaow_id, routeActor.myaow_id, target.myaow_id)) throw new Error('Unavailable contact');
            const token = crypto.randomBytes(32).toString('hex');
            db.prepare('DELETE FROM group_invites WHERE group_id=? AND target=?').run(data.groupId,target.myaow_id);
            db.prepare('INSERT INTO group_invites(hash,group_id,target,creator,expires) VALUES(?,?,?,?,?)').run(crypto.createHash('sha256').update(token).digest('hex'), data.groupId, target.myaow_id, routeActor.myaow_id, Date.now()+48*3600000);
            res.writeHead(200, { 'Content-Type': 'application/json' }); return res.end(JSON.stringify({ token }));
        } catch (error) { res.writeHead(400); return res.end(JSON.stringify({ error: error.message })); }
    }
    if (url.pathname === '/api/v1/groups/invite/accept' && req.method === 'POST') {
        try {
            const data = await parseBody(req);
            const groupId = db.transaction(() => {
                const hash = crypto.createHash('sha256').update(String(data.token || '')).digest('hex');
                const invite = db.prepare('SELECT * FROM group_invites WHERE hash=? AND target=? AND expires>?').get(hash,routeActor.myaow_id,Date.now());
                if (!invite) throw new Error('Invalid invitation');
                if (db.prepare('SELECT role FROM group_members WHERE group_id=? AND myaow_id=?').get(invite.group_id,invite.creator)?.role !== 'admin') throw new Error('Invitation revoked');
                if (db.prepare('SELECT 1 FROM blocked_contacts WHERE (blocker_id=? AND blocked_id=?) OR (blocker_id=? AND blocked_id=?)').get(invite.target,invite.creator,invite.creator,invite.target)) throw new Error('Unavailable invitation');
                if (db.prepare('SELECT count(*) AS n FROM group_members WHERE group_id=?').get(invite.group_id).n >= 101) throw new Error('Group full');
                db.prepare('INSERT OR IGNORE INTO group_members(group_id,myaow_id,role,joined_at) VALUES(?,?,?,?)').run(invite.group_id,routeActor.myaow_id,'member',new Date().toISOString());
                db.prepare('DELETE FROM group_invites WHERE hash=?').run(hash);
                return invite.group_id;
            })();
            res.writeHead(200, { 'Content-Type': 'application/json' }); return res.end(JSON.stringify({ groupId }));
        } catch (error) { res.writeHead(400); return res.end(JSON.stringify({ error: error.message })); }
    }

    // 👥 Grupos - Crear (POST /api/v1/groups/create)
    if (url.pathname === '/api/v1/groups/create' && req.method === 'POST') {
        const authUser = authenticateRequest(req);
        if (!authUser) {
            res.writeHead(401, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: 'Authentication required' }));
        }
        try {
            const data = await parseBody(req);
            data.creatorMyaowId = authUser.myaow_id; // override with auth
            const groupId = crypto.randomUUID();
            if (data.taskPolicy !== undefined && !['open','admins','assigned'].includes(data.taskPolicy)) throw new Error('Invalid task policy');
            db.prepare('INSERT INTO groups (id, name, created_by, created_at, category) VALUES (?, ?, ?, ?, ?)').run(
                groupId, String(data.name || 'Nuevo Grupo').trim().slice(0, 100), data.creatorMyaowId, new Date().toISOString(), String(data.category || 'General').slice(0, 40)
            );
            // Añadir al creador
            if (data.creatorMyaowId) {
                db.prepare('INSERT INTO group_members (group_id, myaow_id, role, joined_at) VALUES (?, ?, ?, ?)').run(
                    groupId, data.creatorMyaowId, 'admin', new Date().toISOString()
                );
            }
            if (data.taskPolicy) db.prepare('UPDATE groups SET task_policy=? WHERE id=?').run(data.taskPolicy, groupId);
            diagnostic.log(`👨‍👩‍👧‍👦 [Grupos] Grupo creado: ${data.name} (${groupId})`);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ success: true, groupId }));
        } catch (err) {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: err.message }));
        }
    }

    // 👥 Grupos - Unirse (POST /api/v1/groups/:id/join)
    const joinMatch = url.pathname.match(/^\/api\/v1\/groups\/([^\/]+)\/join$/);
    if (joinMatch && req.method === 'POST') {
        const authUser = authenticateRequest(req);
        if (!authUser) {
            res.writeHead(401, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: 'Authentication required' }));
        }
        try {
            const groupId = joinMatch[1];
            const data = await parseBody(req);
            db.prepare('INSERT OR IGNORE INTO group_members (group_id, myaow_id, role, joined_at) VALUES (?, ?, ?, ?)').run(
                groupId, authUser.myaow_id, 'member', new Date().toISOString()
            );
            diagnostic.log(`👋 [Grupos] ${data.myaowId} se unió al grupo ${groupId}`);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ success: true }));
        } catch (err) {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: err.message }));
        }
    }

    // 👥 Grupos - Salir (POST /api/v1/groups/:id/leave)
    const leaveMatch = url.pathname.match(/^\/api\/v1\/groups\/([^\/]+)\/leave$/);
    if (leaveMatch && req.method === 'POST') {
        const authUser = authenticateRequest(req);
        if (!authUser) {
            res.writeHead(401, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: 'Authentication required' }));
        }
        try {
            const groupId = leaveMatch[1];
            const data = await parseBody(req);
            const ownRole = db.prepare('SELECT role FROM group_members WHERE group_id=? AND myaow_id=?').get(groupId, authUser.myaow_id);
            if (ownRole?.role === 'admin' && db.prepare("SELECT count(*) AS n FROM group_members WHERE group_id=? AND role='admin'").get(groupId).n === 1 && db.prepare('SELECT count(*) AS n FROM group_members WHERE group_id=?').get(groupId).n > 1) {
                res.writeHead(409); return res.end(JSON.stringify({ error: 'Assign another administrator first' }));
            }
            db.prepare('DELETE FROM group_members WHERE group_id = ? AND myaow_id = ?').run(
                groupId, authUser.myaow_id
            );
            diagnostic.log(`🚪 [Grupos] ${data.myaowId} salió del grupo ${groupId}`);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ success: true }));
        } catch (err) {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: err.message }));
        }
    }

    // 👥 Grupos - Miembros (GET /api/v1/groups/:id/members)
    const membersMatch = url.pathname.match(/^\/api\/v1\/groups\/([^\/]+)\/members$/);
    if (membersMatch && req.method === 'GET') {
        try {
            const groupId = membersMatch[1];
            const members = db.prepare('SELECT m.myaow_id, m.role, u.display_name FROM group_members m JOIN users u ON u.myaow_id = m.myaow_id WHERE m.group_id = ?').all(groupId);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ members }));
        } catch (err) {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: err.message }));
        }
    }
    
    // 👥 Grupos - Mis Grupos (GET /api/v1/groups/my/:myaowId)
    const myGroupsMatch = url.pathname.match(/^\/api\/v1\/groups\/my\/([^\/]+)$/);
    if (myGroupsMatch && req.method === 'GET') {
        try {
            const myaowId = myGroupsMatch[1];
            const groups = db.prepare(`
                SELECT g.*, (SELECT count(*) FROM group_members WHERE group_id=g.id) AS memberCount FROM groups g 
                JOIN group_members gm ON g.id = gm.group_id 
                WHERE gm.myaow_id = ?
            `).all(myaowId);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ groups }));
        } catch (err) {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: err.message }));
        }
    }

    // 👥 Grupos - Info Update (PUT /api/v1/groups/:id/info)
    const infoMatch = url.pathname.match(/^\/api\/v1\/groups\/([^\/]+)\/info$/);
    if (infoMatch && req.method === 'PUT') {
        const authUser = authenticateRequest(req);
        if (!authUser) {
            res.writeHead(401, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: 'Authentication required' }));
        }
        try {
            const groupId = infoMatch[1];
            const data = await parseBody(req);
            const { name, description, avatarUrl } = data;
            if (data.taskPolicy !== undefined && !['open','admins','assigned'].includes(data.taskPolicy)) throw new Error('Invalid task policy');
            const myaowId = authUser.myaow_id;
            
            const member = db.prepare('SELECT role FROM group_members WHERE group_id = ? AND myaow_id = ?').get(groupId, myaowId);
            if (!member || member.role !== 'admin') {
                res.writeHead(403, { 'Content-Type': 'application/json' });
                return res.end(JSON.stringify({ error: 'Solo los administradores pueden actualizar la información del grupo' }));
            }
            
            db.prepare('UPDATE groups SET name = ?, description = COALESCE(?, description), avatar_url = COALESCE(?, avatar_url), task_policy = COALESCE(?, task_policy) WHERE id = ?').run(
                name || db.prepare('SELECT name FROM groups WHERE id=?').get(groupId)?.name || 'Grupo', description ?? null, avatarUrl ?? null, data.taskPolicy ?? null, groupId
            );
            
            diagnostic.log(`📝 [Grupos] Info actualizada para el grupo ${groupId} por ${myaowId}`);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ success: true }));
        } catch (err) {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: err.message }));
        }
    }

    // 👥 Grupos - Kick (POST /api/v1/groups/:id/kick)
    const kickMatch = url.pathname.match(/^\/api\/v1\/groups\/([^\/]+)\/kick$/);
    if (kickMatch && req.method === 'POST') {
        const authUser = authenticateRequest(req);
        if (!authUser) {
            res.writeHead(401, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: 'Authentication required' }));
        }
        try {
            const groupId = kickMatch[1];
            const { targetMyaowId } = await parseBody(req);
            const adminMyaowId = authUser.myaow_id;
            
            const admin = db.prepare('SELECT role FROM group_members WHERE group_id = ? AND myaow_id = ?').get(groupId, adminMyaowId);
            if (!admin || admin.role !== 'admin') {
                res.writeHead(403, { 'Content-Type': 'application/json' });
                return res.end(JSON.stringify({ error: 'Solo los administradores pueden expulsar miembros' }));
            }
            
            if (targetMyaowId === authUser.myaow_id) throw new Error('Use leave group');
            db.prepare('DELETE FROM group_members WHERE group_id = ? AND myaow_id = ?').run(groupId, targetMyaowId);
            
            // Notificar via WebSocket
            const { sockets: targetSockets } = resolveSocketsForRecipient(targetMyaowId);
            for (const sock of targetSockets) {
                sock.send(JSON.stringify({
                    type: 'group_kick',
                    groupId,
                    message: 'Has sido expulsado del grupo'
                }));
            }
            
            diagnostic.log(`👢 [Grupos] ${targetMyaowId} expulsado del grupo ${groupId} por ${adminMyaowId}`);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ success: true }));
        } catch (err) {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: err.message }));
        }
    }

    // 👥 Grupos - Promote (POST /api/v1/groups/:id/promote)
    const promoteMatch = url.pathname.match(/^\/api\/v1\/groups\/([^\/]+)\/promote$/);
    if (promoteMatch && req.method === 'POST') {
        const authUser = authenticateRequest(req);
        if (!authUser) {
            res.writeHead(401, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: 'Authentication required' }));
        }
        try {
            const groupId = promoteMatch[1];
            const { targetMyaowId } = await parseBody(req);
            const adminMyaowId = authUser.myaow_id;
            
            const admin = db.prepare('SELECT role FROM group_members WHERE group_id = ? AND myaow_id = ?').get(groupId, adminMyaowId);
            if (!admin || admin.role !== 'admin') {
                res.writeHead(403, { 'Content-Type': 'application/json' });
                return res.end(JSON.stringify({ error: 'Solo los administradores pueden promover miembros' }));
            }
            
            db.prepare('UPDATE group_members SET role = "admin" WHERE group_id = ? AND myaow_id = ?').run(groupId, targetMyaowId);
            
            diagnostic.log(`👑 [Grupos] ${targetMyaowId} promovido a admin en el grupo ${groupId} por ${adminMyaowId}`);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ success: true }));
        } catch (err) {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: err.message }));
        }
    }

    // 👥 Grupos - Demote (POST /api/v1/groups/:id/demote)
    const demoteMatch = url.pathname.match(/^\/api\/v1\/groups\/([^\/]+)\/demote$/);
    if (demoteMatch && req.method === 'POST') {
        const authUser = authenticateRequest(req);
        if (!authUser) {
            res.writeHead(401, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: 'Authentication required' }));
        }
        try {
            const groupId = demoteMatch[1];
            const { targetMyaowId } = await parseBody(req);
            const adminMyaowId = authUser.myaow_id;
            
            const admin = db.prepare('SELECT role FROM group_members WHERE group_id = ? AND myaow_id = ?').get(groupId, adminMyaowId);
            if (!admin || admin.role !== 'admin') {
                res.writeHead(403, { 'Content-Type': 'application/json' });
                return res.end(JSON.stringify({ error: 'Solo los administradores pueden degradar miembros' }));
            }
            
            const adminCount = db.prepare('SELECT COUNT(*) as count FROM group_members WHERE group_id = ? AND role = "admin"').get(groupId).count;
            if (adminCount <= 1 && adminMyaowId === targetMyaowId) {
                res.writeHead(400, { 'Content-Type': 'application/json' });
                return res.end(JSON.stringify({ error: 'No puedes degradarte a ti mismo si eres el único administrador' }));
            }
            
            db.prepare('UPDATE group_members SET role = "member" WHERE group_id = ? AND myaow_id = ?').run(groupId, targetMyaowId);
            
            diagnostic.log(`🔻 [Grupos] ${targetMyaowId} degradado a miembro en el grupo ${groupId} por ${adminMyaowId}`);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ success: true }));
        } catch (err) {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: err.message }));
        }
    }

    // 🚫 Contactos - Bloquear (POST /api/v1/contacts/block)
    if (url.pathname === '/api/v1/contacts/block' && req.method === 'POST') {
        const authUser = authenticateRequest(req);
        if (!authUser) {
            res.writeHead(401, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: 'Authentication required' }));
        }
        try {
            const data = await parseBody(req);
            const { blockedId } = data;
            const blockerId = authUser.myaow_id;
            db.prepare('INSERT OR IGNORE INTO blocked_contacts (blocker_id, blocked_id) VALUES (?, ?)').run(blockerId, blockedId);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ success: true }));
        } catch (err) {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: err.message }));
        }
    }

    // 🚫 Contactos - Desbloquear (POST /api/v1/contacts/unblock)
    if (url.pathname === '/api/v1/contacts/unblock' && req.method === 'POST') {
        const authUser = authenticateRequest(req);
        if (!authUser) {
            res.writeHead(401, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: 'Authentication required' }));
        }
        try {
            const data = await parseBody(req);
            const { blockedId } = data;
            const blockerId = authUser.myaow_id;
            db.prepare('DELETE FROM blocked_contacts WHERE blocker_id = ? AND blocked_id = ?').run(blockerId, blockedId);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ success: true }));
        } catch (err) {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: err.message }));
        }
    }

    // 🚫 Contactos - Lista de bloqueados (GET /api/v1/contacts/blocked/:myaowId)
    const blockedMatch = url.pathname.match(/^\/api\/v1\/contacts\/blocked\/([^\/]+)$/);
    if (blockedMatch && req.method === 'GET') {
        try {
            const myaowId = blockedMatch[1];
            const rows = db.prepare('SELECT blocked_id FROM blocked_contacts WHERE blocker_id = ?').all(myaowId);
            const blockedIds = rows.map(r => r.blocked_id);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ blockedIds }));
        } catch (err) {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: err.message }));
        }
    }

    // 📸 Momentos - Crear (POST /api/v1/moments)
    if (url.pathname === '/api/v1/moments' && req.method === 'POST') {
        const authUser = authenticateRequest(req);
        if (!authUser) {
            res.writeHead(401, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: 'Authentication required' }));
        }
        try {
            const data = await parseBody(req);
            const { id, authorAvatarState, caption, mediaUrl, catEmotion, backgroundIndex, expiresAt } = data;
            const authorId = authUser.myaow_id;
            const authorName = db.prepare('SELECT display_name FROM users WHERE myaow_id = ?').get(authUser.myaow_id)?.display_name || authUser.myaow_id;
            
            db.prepare(`
                INSERT INTO moments (id, author_id, author_name, author_avatar_state, caption, media_url, cat_emotion, background_index, expires_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            `).run(
                id, authorId, authorName, authorAvatarState || 'friendly', caption || '', 
                mediaUrl || null, catEmotion || 'friendly', backgroundIndex || 0, expiresAt
            );
            
            diagnostic.log(`✨ [Momentos] Nuevo momento publicado por ${authorId}`);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ success: true }));
        } catch (err) {
            diagnostic.error(`❌ [Momentos] Error al crear momento:`, err);
            res.writeHead(400, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: err.message }));
        }
    }

    // 📸 Momentos - Obtener Feed (GET /api/v1/moments/feed/:myaowId)
    const feedMatch = url.pathname.match(/^\/api\/v1\/moments\/feed\/([^\/]+)$/);
    if (feedMatch && req.method === 'GET') {
        try {
            const myaowId = feedMatch[1];
            // En el futuro: Filtrar sólo por contactos. Por ahora retornamos todos los activos de otros usuarios.
            const moments = db.prepare(`
                SELECT id, author_id, author_name, author_avatar_state, caption, media_url, 
                       cat_emotion, background_index, created_at, expires_at
                FROM moments
                WHERE author_id != ? AND expires_at > datetime('now')
                ORDER BY created_at DESC
            `).all(myaowId);
            
            res.writeHead(200, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ moments }));
        } catch (err) {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: err.message }));
        }
    }

    // 📸 Momentos - Eliminar (DELETE /api/v1/moments/:id)
    const momentDelMatch = url.pathname.match(/^\/api\/v1\/moments\/([^\/]+)$/);
    if (momentDelMatch && req.method === 'DELETE') {
        const authUser = authenticateRequest(req);
        if (!authUser) {
            res.writeHead(401, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: 'Authentication required' }));
        }
        try {
            const momentId = momentDelMatch[1];
            // Se debería verificar la autorización del usuario mediante headers,
            // pero para el MVP de Zero-Knowledge Relay lo eliminamos directamente.
            db.prepare('DELETE FROM moments WHERE id = ?').run(momentId);
            diagnostic.log(`🗑️ [Momentos] Momento eliminado: ${momentId}`);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ success: true }));
        } catch (err) {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: err.message }));
        }
    }

            // 📱 Sesiones - Lista (GET) y Borrar (DELETE)
    const sessionsMatch = url.pathname.match(/^\/api\/v1\/sessions\/([^\/]+)$/);
    if (sessionsMatch) {
        const id = sessionsMatch[1];
        if (req.method === 'GET') {
            try {
                const sessions = db.prepare('SELECT session_id as sessionId, device_name as deviceName, created_at as connectedAt FROM sessions WHERE myaow_id = ?').all(id);
                res.writeHead(200, { 'Content-Type': 'application/json' });
                return res.end(JSON.stringify({ sessions }));
            } catch (err) {
                res.writeHead(400, { 'Content-Type': 'application/json' });
                return res.end(JSON.stringify({ error: err.message }));
            }
        } else if (req.method === 'DELETE') {
            try {
                const sessionRecord = db.prepare('SELECT myaow_id FROM sessions WHERE session_id = ?').get(id);
                if (sessionRecord) {
                    const myaowId = sessionRecord.myaow_id;
                    db.prepare('DELETE FROM sessions WHERE session_id = ?').run(id);
                    const deviceMap = activeSockets.get(myaowId);
                    if (deviceMap && deviceMap.has(id)) {
                        const wsToClose = deviceMap.get(id).ws;
                        if (wsToClose.readyState === WebSocket.OPEN) wsToClose.close();
                        deviceMap.delete(id);
                        if (deviceMap.size === 0) activeSockets.delete(myaowId);
                    }
                    diagnostic.log(`🔌 [API] Sesión cerrada forzosamente: ${id}`);
                }
                res.writeHead(200, { 'Content-Type': 'application/json' });
                return res.end(JSON.stringify({ success: true }));
            } catch (err) {
                res.writeHead(400, { 'Content-Type': 'application/json' });
                return res.end(JSON.stringify({ error: err.message }));
            }
        }
    }

    // Versioned ciphertext-only delivery and scheduling.
    if (url.pathname.startsWith('/api/v1/scheduled-v2') || url.pathname === '/api/v1/messages-v2/batch') {
        try {
            const own = routeActor.myaow_id;
            let result;
            if (url.pathname === '/api/v1/messages-v2/batch' && req.method === 'POST') {
                const data = await parseBody(req);
                result = db.transaction(() => {
                    secureScheduler.validateBatch(own, data.packets);
                    return { status: 'queued', messages: data.packets.map(p => durableRelay.accept(p, own).packet.id) };
                })();
                for (const map of activeSockets.values()) for (const info of map.values()) drainSecureMessages(info.ws);
            } else if (url.pathname === '/api/v1/scheduled-v2' && req.method === 'POST') {
                result = secureScheduler.create(own, await parseBody(req));
            } else if (url.pathname === '/api/v1/scheduled-v2' && req.method === 'GET') {
                result = { messages: secureScheduler.list(own) };
            } else if (/^\/api\/v1\/scheduled-v2\/[^/]+$/.test(url.pathname) && req.method === 'DELETE') {
                if (!secureScheduler.cancel(own, url.pathname.split('/').pop())) {
                    res.writeHead(409, { 'Content-Type': 'application/json' });
                    return res.end(JSON.stringify({ error: 'Already queued or unavailable' }));
                }
                result = { success: true };
            } else { res.writeHead(404); return res.end(); }
            res.writeHead(200, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify(result));
        } catch (error) {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: error.message }));
        }
    }

    // 🗓️ Mensajes Programados - Crear (POST /api/v1/scheduled/create)
    if (url.pathname === '/api/v1/scheduled/create' && req.method === 'POST') {
        const authUser = authenticateRequest(req);
        if (!authUser) {
            res.writeHead(401, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: 'Authentication required' }));
        }
        try {
            const data = await parseBody(req);
            const { senderMyaowId, recipientMyaowId, groupId, text, scheduledAt } = data;
            const id = crypto.randomUUID();
            db.prepare(`
                INSERT INTO scheduled_messages (id, sender_myaow_id, recipient_myaow_id, group_id, message_text, scheduled_at)
                VALUES (?, ?, ?, ?, ?, ?)
            `).run(id, senderMyaowId, recipientMyaowId || null, groupId || null, text, scheduledAt);
            
            diagnostic.log(`⏰ [Programados] Mensaje de ${senderMyaowId} programado para ${scheduledAt}`);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ success: true, id }));
        } catch (err) {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: err.message }));
        }
    }

    // 🗓️ Mensajes Programados - Leer (GET /api/v1/scheduled/:myaowId)
    const scheduledMatch = url.pathname.match(/^\/api\/v1\/scheduled\/([^\/]+)$/);
    if (scheduledMatch && req.method === 'GET') {
        try {
            const myaowId = scheduledMatch[1];
            const messages = db.prepare('SELECT * FROM scheduled_messages WHERE sender_myaow_id = ? AND is_sent = 0 ORDER BY scheduled_at ASC').all(myaowId);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ messages }));
        } catch (err) {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: err.message }));
        }
    }

    // 🗓️ Mensajes Programados - Cancelar (DELETE /api/v1/scheduled/:id)
    if (scheduledMatch && req.method === 'DELETE') {
        const authUser = authenticateRequest(req);
        if (!authUser) {
            res.writeHead(401, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: 'Authentication required' }));
        }
        try {
            const id = scheduledMatch[1];
            db.prepare('DELETE FROM scheduled_messages WHERE id = ?').run(id);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ success: true }));
        } catch (err) {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: err.message }));
        }
    }

    // ✅ Tareas de Grupo - Crear (POST /api/v1/groups/:groupId/tasks)
    const tasksMatch = url.pathname.match(/^\/api\/v1\/groups\/([^\/]+)\/tasks$/);
    if (tasksMatch && req.method === 'POST') {
        const authUser = authenticateRequest(req);
        if (!authUser) {
            res.writeHead(401, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: 'Authentication required' }));
        }
        try {
            const groupId = tasksMatch[1];
            const data = await parseBody(req);
            const title = typeof data.title === 'string' ? data.title.trim() : '';
            if (!title || title.length > 240) throw new Error('Invalid task title');
            const { assigneeMyaowId, dueLabel, priority } = data;
            if (dueLabel && (!['Hoy', 'Mañana', 'Esta semana', 'Pronto'].includes(dueLabel))) throw new Error('Invalid due label');
            if (priority && !['normal','high','urgent','Normal','Importante','Urgente'].includes(priority)) throw new Error('Invalid priority');
            const assignee = assigneeMyaowId ? db.prepare('SELECT u.display_name FROM users u JOIN group_members m ON m.myaow_id = u.myaow_id WHERE m.group_id = ? AND m.myaow_id = ?').get(groupId, assigneeMyaowId) : null;
            if (assigneeMyaowId && !assignee) throw new Error('Assignee is not a member');
            const assigneeName = assignee?.display_name || null;
            const createdByMyaowId = authUser.myaow_id;
            const taskId = (data.id || crypto.randomUUID()).toLowerCase();
            if (!/^[0-9a-f-]{36}$/i.test(taskId)) throw new Error('Invalid task ID');
            const previous = db.prepare('SELECT * FROM group_tasks WHERE id = ?').get(taskId);
            if (previous) {
                if (previous.group_id !== groupId || previous.created_by_myaow_id !== createdByMyaowId) throw new Error('Task ID already used');
                res.writeHead(200, { 'Content-Type': 'application/json' });
                return res.end(JSON.stringify({ success: true, task: previous }));
            }
            
            const task = {
                id: taskId,
                group_id: groupId,
                title,
                assignee_myaow_id: assigneeMyaowId || null,
                assignee_name: assigneeName || null,
                due_label: dueLabel || 'Pronto',
                priority: priority || 'normal',
                is_completed: 0,
                completed_by_myaow_id: null,
                completed_by_name: null,
                completed_at: null,
                created_by_myaow_id: createdByMyaowId,
                created_at: new Date().toISOString()
            };
            
            db.prepare(`
                INSERT INTO group_tasks (id, group_id, title, assignee_myaow_id, assignee_name, due_label, priority, created_by_myaow_id, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            `).run(taskId, groupId, title, assigneeMyaowId || null, assigneeName || null, dueLabel || 'Pronto', priority || 'normal', createdByMyaowId, task.created_at);
            
            // Notificar por WebSocket
            const members = db.prepare('SELECT myaow_id FROM group_members WHERE group_id = ?').all(groupId);
            for (const member of members) {
                const { sockets } = resolveSocketsForRecipient(member.myaow_id);
                for (const sock of sockets) {
                    sock.send(JSON.stringify({
                        type: 'task_update',
                        groupId,
                        action: 'created',
                        task
                    }));
                }
            }
            
            // Task contents must not be copied into application logs.
            res.writeHead(200, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ success: true, task }));
        } catch (err) {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: err.message }));
        }
    }

    // ✅ Tareas de Grupo - Leer (GET /api/v1/groups/:groupId/tasks)
    if (tasksMatch && req.method === 'GET') {
        try {
            const groupId = tasksMatch[1];
            const tasks = db.prepare('SELECT * FROM group_tasks WHERE group_id = ? ORDER BY created_at DESC').all(groupId);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ tasks, task_policy: db.prepare('SELECT task_policy FROM groups WHERE id=?').get(groupId)?.task_policy }));
        } catch (err) {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: err.message }));
        }
    }

    // ✅ Tareas de Grupo - Completar (PUT /api/v1/tasks/:taskId/complete)
    const taskCompleteMatch = url.pathname.match(/^\/api\/v1\/tasks\/([^\/]+)\/complete$/);
    if (taskCompleteMatch && req.method === 'PUT') {
        const authUser = authenticateRequest(req);
        if (!authUser) {
            res.writeHead(401, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: 'Authentication required' }));
        }
        try {
            const taskId = taskCompleteMatch[1];
            const data = await parseBody(req);
            const completedByMyaowId = authUser.myaow_id;
            const completedByName = db.prepare('SELECT display_name FROM users WHERE myaow_id = ?').get(authUser.myaow_id)?.display_name || authUser.myaow_id;
            if (data.progress !== undefined && (!Number.isInteger(data.progress) || data.progress < 0 || data.progress > 100)) throw new Error('Invalid progress');
            const progress = data.progress ?? (data.completed !== false ? 100 : 0);
            const completed = progress === 100;
            const completedAt = completed ? new Date().toISOString() : null;
            
            db.prepare(`
                UPDATE group_tasks 
                SET is_completed = ?, completed_by_myaow_id = ?, completed_by_name = ?, completed_at = ?, progress = ? 
                WHERE id = ?
            `).run(completed ? 1 : 0, completed ? completedByMyaowId : null, completed ? completedByName : null, completedAt, progress, taskId);
            
            const task = db.prepare('SELECT * FROM group_tasks WHERE id = ?').get(taskId);
            
            if (task) {
                // Notificar por WebSocket
                const members = db.prepare('SELECT myaow_id FROM group_members WHERE group_id = ?').all(task.group_id);
                for (const member of members) {
                    const { sockets } = resolveSocketsForRecipient(member.myaow_id);
                    for (const sock of sockets) {
                        sock.send(JSON.stringify({
                            type: 'task_update',
                            groupId: task.group_id,
                            action: 'completed',
                            task
                        }));
                    }
                }
                diagnostic.log(`✅ [Tareas] Tarea completada: ${taskId}`);
            }
            
            res.writeHead(200, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ success: true, task }));
        } catch (err) {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: err.message }));
        }
    }

    // ✅ Tareas de Grupo - Eliminar (DELETE /api/v1/tasks/:taskId)
    const taskDelMatch = url.pathname.match(/^\/api\/v1\/tasks\/([^\/]+)$/);
    if (taskDelMatch && req.method === 'DELETE') {
        const authUser = authenticateRequest(req);
        if (!authUser) {
            res.writeHead(401, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: 'Authentication required' }));
        }
        try {
            const taskId = taskDelMatch[1];
            const task = db.prepare('SELECT * FROM group_tasks WHERE id = ?').get(taskId);
            
            if (task) {
                db.prepare('DELETE FROM group_tasks WHERE id = ?').run(taskId);
                
                // Notificar por WebSocket
                const members = db.prepare('SELECT myaow_id FROM group_members WHERE group_id = ?').all(task.group_id);
                for (const member of members) {
                    const { sockets } = resolveSocketsForRecipient(member.myaow_id);
                    for (const sock of sockets) {
                        sock.send(JSON.stringify({
                            type: 'task_update',
                            groupId: task.group_id,
                            action: 'deleted',
                            task: { id: taskId }
                        }));
                    }
                }
                diagnostic.log(`🗑️ [Tareas] Tarea eliminada: ${taskId}`);
            }
            
            res.writeHead(200, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ success: true }));
        } catch (err) {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: err.message }));
        }
    }

    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Ruta no encontrada' }));
});

// Auto-cleanup: Delete expired moments every hour
setInterval(() => {
    try {
        const info = db.prepare("DELETE FROM moments WHERE expires_at < datetime('now')").run();
        if (info.changes > 0) {
            diagnostic.log(`🧹 [Momentos] Se eliminaron ${info.changes} momentos expirados`);
        }
    } catch (err) {
        diagnostic.error('❌ [Momentos] Error limpiando momentos expirados:', err.message);
    }
}, 3600000);

// ==========================================
// 4. Servidor WebSocket (Relay & Signaling)
// ==========================================

const { DurableRelay } = require('./durable_relay');
const groupColumns = new Set(db.prepare('PRAGMA table_info(groups)').all().map(row => row.name));
for (const [name, definition] of [['category', "TEXT DEFAULT 'General'"], ['description', "TEXT DEFAULT ''"], ['avatar_url', 'TEXT'], ['task_policy', "TEXT NOT NULL DEFAULT 'assigned' CHECK(task_policy IN ('open','admins','assigned'))"]]) {
    if (!groupColumns.has(name)) db.exec(`ALTER TABLE groups ADD COLUMN ${name} ${definition}`);
}
if (!db.prepare('PRAGMA table_info(group_tasks)').all().some(row => row.name === 'progress')) db.exec('ALTER TABLE group_tasks ADD COLUMN progress INTEGER NOT NULL DEFAULT 0 CHECK(progress BETWEEN 0 AND 100)');
const { PushDelivery } = require('./push_delivery');
const pushDelivery = new PushDelivery(db, apns);
const durableRelay = new DurableRelay(db, packet => pushDelivery.enqueueMessage(packet));
const { CallRelay } = require('./call_relay');
const callRelay = new CallRelay(db, durableRelay, pushDelivery);
setInterval(() => { pushDelivery.tick().catch(() => diagnostic.error('[Push] Delivery cycle failed')); callRelay.prune(); }, 1000).unref();
const { SecureScheduler } = require('./secure_scheduler');
const secureScheduler = new SecureScheduler(db, durableRelay);
db.exec('CREATE TABLE IF NOT EXISTS group_invites(hash TEXT PRIMARY KEY, group_id TEXT NOT NULL,target TEXT NOT NULL,creator TEXT NOT NULL,expires INTEGER NOT NULL)');
const wss = new WebSocketServer({ server, path: '/ws', maxPayload: 256 * 1024 });
function drainSecureMessages(ws) {
    if (!ws.myaowId || ws.readyState !== 1) return;
    for (const packet of durableRelay.pending(ws.myaowId)) {
        const key = `${packet.senderMyaowId}:${packet.id}`;
        if (ws.pendingDeliveries.has(key)) continue;
        if (ws.bufferedAmount > 1024 * 1024) { ws.close(1013, 'Slow consumer; reconnect to resume'); return; }
        ws.pendingDeliveries.add(key);
        ws.send(JSON.stringify(packet));
    }
}
setInterval(() => durableRelay.pruneReceipts(), 3600000).unref();

wss.on('connection', (ws, req) => {
    let clientMyaowId = null;
    ws.pendingDeliveries = new Set();
    const authenticationDeadline = setTimeout(() => { if (!clientMyaowId) ws.close(1008, 'Authentication timeout'); }, 15000);
    authenticationDeadline.unref();

    ws.on('message', (messageBuffer) => {
        try {
            const messageStr = messageBuffer.toString();
            const packet = JSON.parse(messageStr);

            if (!['auth', 'auth_response', 'pong', 'ping'].includes(packet.type)) {
                if (!clientMyaowId) {
                    ws.send(JSON.stringify({ type: 'auth_error', message: 'Authentication required' }));
                    return;
                }
                if (!checkRateLimit(`ws_${packet.type === 'message_received' ? 'receipt_' : ''}${clientMyaowId}`, packet.type === 'message_received' ? 6000 : 120, 60000)) {
                    ws.send(JSON.stringify({ type: 'error', message: 'Rate limit exceeded. Please slow down.' }));
                    return;
                }
                packet.senderMyaowId = clientMyaowId;
                const sender = db.prepare('SELECT display_name FROM users WHERE myaow_id = ?').get(clientMyaowId);
                packet.senderDisplayName = sender?.display_name || clientMyaowId;
                db.prepare('UPDATE users SET last_seen = ? WHERE myaow_id = ?').run(new Date().toISOString(), clientMyaowId);
            }

            switch (packet.type) {
                // 🔐 1. Autenticación de Socket (Challenge)
                case 'auth': {
                    if (clientMyaowId) break;
                    const user = db.prepare('SELECT identity_key_hex FROM users WHERE myaow_id = ?').get(packet.myaowId || '');
                    try {
                        if (!user) throw new Error('Unknown identity');
                        const challenge = relayAuth.createChallenge(packet.myaowId, user.identity_key_hex);
                        pendingAuthChallenges.set(ws, challenge);
                        ws.send(JSON.stringify({ type: 'auth_challenge', nonce: challenge.nonce, serverPublicKeyHex: challenge.serverPublicKeyHex, protocol: challenge.protocol }));
                    } catch {
                        pendingAuthChallenges.delete(ws);
                        ws.send(JSON.stringify({ type: 'auth_error', message: 'Identidad no registrada o clave inválida' }));
                    }
                    break;
                }

                case 'auth_response': {
                    if (clientMyaowId) break;
                    const { myaowId, proof, displayName } = packet;
                    const challenge = pendingAuthChallenges.get(ws);
                    pendingAuthChallenges.delete(ws);
                    if (!relayAuth.verifyProof(challenge, myaowId, proof)) {
                        ws.send(JSON.stringify({ type: 'auth_error', message: 'Prueba de identidad inválida o expirada' }));
                        return;
                    }

                    clientMyaowId = myaowId;
                    clearTimeout(authenticationDeadline);
                    const sessionId = `sess_${crypto.randomBytes(32).toString('hex')}`;
                    
                    if (!activeSockets.has(clientMyaowId)) {
                        activeSockets.set(clientMyaowId, new Map());
                    }
                    const deviceName = packet.deviceName || 'Dispositivo';
                    activeSockets.get(clientMyaowId).set(sessionId, {
                        ws: ws,
                        deviceName: deviceName,
                        connectedAt: new Date().toISOString()
                    });
                    
                    ws.sessionId = sessionId;
                    ws.myaowId = clientMyaowId;

                    db.prepare('INSERT INTO sessions (session_id, myaow_id, device_name) VALUES (?, ?, ?)').run(sessionId, clientMyaowId, deviceName);

                    diagnostic.log(`✅ [WebSocket] Cliente autenticado: ${clientMyaowId} (${deviceName})`);

                    ws.send(JSON.stringify({
                        type: 'auth_ack',
                        myaowId: clientMyaowId,
                        sessionId: sessionId,
                        displayName: displayName,
                        status: 'connected',
                        serverTime: new Date().toISOString()
                    }));

                    // Legacy queue is preserved on disk; only authenticated v2 traffic is replayed.
                    drainSecureMessages(ws);
                    for (const signal of callRelay.pending(clientMyaowId)) ws.send(JSON.stringify(signal));
                    break;
                }

                // 📬 3. Retransmisión de Mensajes a Grupos
                case 'group_message': {
                    ws.send(JSON.stringify({ type: 'error', message: 'Use encrypted group delivery' }));
                    break;
                }

                // 🤫 4. Retransmisión Cero-Conocimiento (1:1)
                case 'message':
                case 'nudge':
                case 'media':
                case 'image':
                case 'video':
                case 'voice':
                case 'audio': {
                    try {
                        const result = durableRelay.accept(packet, clientMyaowId);
                        ws.send(JSON.stringify({ type: 'delivery_ack', messageId: packet.id, status: result.status }));
                        for (const target of resolveSocketsForRecipient(result.packet.recipientMyaowId).sockets) drainSecureMessages(target);

                    } catch (error) {
                        ws.send(JSON.stringify({ type: 'message_error', messageId: packet.id, message: error.message }));
                    }
                    break;
                }
                case 'message_received': {
                    if (typeof packet.messageId !== 'string' || typeof packet.originalSenderId !== 'string') break;
                    if (durableRelay.acknowledge(clientMyaowId, packet.originalSenderId, packet.messageId)) {
                        for (const target of resolveSocketsForRecipient(packet.originalSenderId).sockets) {
                            target.send(JSON.stringify({ type: 'delivery_ack', messageId: packet.messageId, status: 'delivered' }));
                        }
                        ws.pendingDeliveries.delete(`${packet.originalSenderId}:${packet.messageId}`);
                        drainSecureMessages(ws);
                    }
                    break;
                }

                // 🎙️ Walkie Talkie Audio (Real-Time Only)
                case 'walkie_audio': {
                    const rawRecipient = packet.recipientMyaowId || packet.targetMyaowId;
                    if (rawRecipient) {
                        const { sockets: targetSockets, myaowId: resolvedRecipientId } = resolveSocketsForRecipient(rawRecipient);
                        const finalRecipient = resolvedRecipientId || rawRecipient;
                        const isBlocked = db.prepare('SELECT 1 FROM blocked_contacts WHERE blocker_id = ? AND blocked_id = ?').get(finalRecipient, packet.senderMyaowId);
                        if (isBlocked) {
                            diagnostic.log(`🚫 [Relay] WalkieAudio bloqueado: ${packet.senderMyaowId} -> ${finalRecipient}`);
                            return;
                        }
                        for (const sock of targetSockets) sock.send(JSON.stringify(packet));
                    }
                    break;
                }

                // ⌨️ 5. Indicadores de Escritura
                case 'typing_start':
                case 'typing_stop': {
                    const rawRecipient = packet.recipientMyaowId || packet.targetMyaowId;
                    const groupId = packet.groupId;
                    
                    if (groupId) {
                        const members = db.prepare('SELECT myaow_id FROM group_members WHERE group_id = ?').all(groupId);
                        for (const member of members) {
                            if (member.myaow_id === packet.senderMyaowId) continue;
                            const isBlocked = db.prepare('SELECT 1 FROM blocked_contacts WHERE blocker_id = ? AND blocked_id = ?').get(member.myaow_id, packet.senderMyaowId);
                            if (isBlocked) continue;
                            const { sockets: targetSockets } = resolveSocketsForRecipient(member.myaow_id);
                            for (const sock of targetSockets) sock.send(JSON.stringify(packet));
                        }
                    } else if (rawRecipient) {
                        const { sockets: targetSockets, myaowId: resolvedRecipientId } = resolveSocketsForRecipient(rawRecipient);
                        const finalRecipient = resolvedRecipientId || rawRecipient;
                        const isBlocked = db.prepare('SELECT 1 FROM blocked_contacts WHERE blocker_id = ? AND blocked_id = ?').get(finalRecipient, packet.senderMyaowId);
                        if (isBlocked) {
                            diagnostic.log(`🚫 [Relay] Typing bloqueado: ${packet.senderMyaowId} -> ${finalRecipient}`);
                            return;
                        }
                        for (const sock of targetSockets) sock.send(JSON.stringify(packet));
                    }
                    // NO SE ENCOLAN OFFLINE
                    break;
                }

                // 👀 6. Confirmación de Lectura (Read Receipt)
                case 'read_ack':
                case 'read_receipt': {
                    const rawRecipient = packet.recipientMyaowId || packet.targetMyaowId;
                    if (!db.prepare('SELECT 1 FROM secure_messages WHERE message_id = ? AND sender_id = ? AND recipient_id = ?').get(packet.messageId || '', rawRecipient || '', clientMyaowId)) break;
                    const { sockets: targetSockets } = resolveSocketsForRecipient(rawRecipient);
                    diagnostic.log(`👀 [Relay] Read receipt de ${packet.senderMyaowId || packet.readBy || clientMyaowId} -> ${rawRecipient}`);
                    
                    if (targetSockets.length > 0) {
                        const outPacket = {
                            type: 'read_ack',
                            messageId: packet.messageId,
                            readBy: clientMyaowId,
                            readAt: packet.readAt || new Date().toISOString()
                        };
                        for (const sock of targetSockets) sock.send(JSON.stringify(outPacket));
                    }
                    break;
                }

                // 🎭 7. Actualización de Emoción / Avatar en Tiempo Real
                case 'avatar_status_update': {
                    diagnostic.log(`🎭 [Relay] Actualización de estado de avatar de ${packet.senderMyaowId}: ${packet.avatarStateName}`);
                    avatarStates.set(packet.senderMyaowId, packet.avatarStateName);
                    
                    // Incluir avatarUrl de la DB si existe
                    try {
                        const user = db.prepare('SELECT avatar_url FROM users WHERE myaow_id = ?').get(packet.senderMyaowId);
                        if (user && user.avatar_url) {
                            packet.avatarUrl = user.avatar_url;
                        }
                    } catch (e) {
                        diagnostic.error(`❌ [Relay] Error obteniendo avatar_url: ${e.message}`);
                    }
                    
                    const jsonString = JSON.stringify(packet);
                    for (const [id, deviceMap] of activeSockets.entries()) {
                        if (id !== clientMyaowId) continue; // No presence broadcast to unrelated accounts.
                        for (const [sessionId, info] of deviceMap) {
                            if (info.ws !== ws && info.ws.readyState === WebSocket.OPEN) {
                                info.ws.send(jsonString);
                            }
                        }
                    }
                    break;
                }

                // 📞 8. WebRTC Signaling para Llamadas
                case 'call_offer':
                case 'call_answer':
                case 'call_hangup':
                case 'call_reaction':
                case 'webrtc_offer':
                case 'webrtc_answer':
                case 'webrtc_ice_candidate': {
                    ws.send(JSON.stringify({ type: 'error', message: 'Encrypted signaling required' }));
                    break;
                }

                // 🏓 9. Ping / Pong Keepalive
                case 'ping': {
                    ws.pendingDeliveries.clear();
                    drainSecureMessages(ws);
                    ws.send(JSON.stringify({ type: 'pong', timestamp: new Date().toISOString() }));
                    break;
                }

                // 🗑️ 10. Eliminar mensaje
                case 'message_delete':
                case 'message_edit': {
                    ws.send(JSON.stringify({ type: 'error', message: 'Authenticated message mutations required' }));
                    break;
                }

                // ✨ 12. Reacción a mensaje
                case 'message_reaction': {
                    const rawRecipient = packet.recipientMyaowId || packet.targetMyaowId;
                    diagnostic.log(`✨ [Relay] Reacción a mensaje ${packet.messageId} por ${packet.senderMyaowId}`);
                    
                    const { sockets: targetSockets, myaowId: resolvedRecipientId } = resolveSocketsForRecipient(rawRecipient);
                    const finalRecipient = resolvedRecipientId || rawRecipient;
                    if (targetSockets.length > 0) {
                        for (const sock of targetSockets) sock.send(JSON.stringify(packet));
                    } else {
                        db.prepare('INSERT INTO offline_messages (recipient_myaow_id, packet_json, created_at) VALUES (?, ?, ?)')
                          .run(finalRecipient, JSON.stringify(packet), new Date().toISOString());
                    }
                    break;
                }

                default:
                    diagnostic.log(`⚠️ [WebSocket] Tipo de paquete desconocido: ${packet.type}`);
            }
        } catch (err) {
            diagnostic.error('❌ [WebSocket] Error al procesar mensaje:', err);
        }
    });

    ws.on('close', () => {
        clearTimeout(authenticationDeadline);
        pendingAuthChallenges.delete(ws);
        const myaowId = ws.myaowId;
        const sessionId = ws.sessionId;
        if (myaowId && sessionId) {
            const deviceMap = activeSockets.get(myaowId);
            if (deviceMap) {
                deviceMap.delete(sessionId);
                if (deviceMap.size === 0) {
                    activeSockets.delete(myaowId);
                }
            }
            db.prepare('DELETE FROM sessions WHERE session_id = ?').run(sessionId);
            diagnostic.log(`🔌 [WebSocket] Sesión desconectada: ${myaowId}`);
        }
    });

    ws.on('error', (err) => {
        diagnostic.error('❌ [WebSocket] Error en socket:', err.message);
    });
});

// ==========================================
// 4.5. Tareas Programadas (Scheduled Messages)
// ==========================================

setInterval(() => {
    try {
        secureScheduler.tick();
        for (const map of activeSockets.values()) for (const info of map.values()) drainSecureMessages(info.ws);
    } catch (error) { diagnostic.error('Encrypted scheduling temporarily unavailable'); }
}, 1000).unref();

// ==========================================
// 5. Iniciar Servidor
// ==========================================

server.listen(PORT, process.env.HOST || '0.0.0.0', () => {
    console.info('Myaow relay listening');
    diagnostic.log(`  🚀 Servidor Relay Zero-Knowledge de MYAOW Activo (v2)`);
    diagnostic.log(`  📡 HTTP & REST API: http://localhost:${PORT}`);
    diagnostic.log(`  ⚡️ WebSocket Relay: ws://localhost:${PORT}/ws`);
    diagnostic.log(`  🔒 Base de Datos SQLite & APNs Integrados`);
    diagnostic.log(`=======================================================`);
});
