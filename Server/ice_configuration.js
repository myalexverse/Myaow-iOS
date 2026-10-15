'use strict';
const crypto = require('node:crypto');
const fs = require('node:fs');

function iceConfiguration(owner, env = process.env, now = Date.now()) {
    const urls = (env.TURN_URLS || '').split(',').map(x => x.trim()).filter(Boolean);
    const secret = env.TURN_SHARED_SECRET_FILE ? fs.readFileSync(env.TURN_SHARED_SECRET_FILE, 'utf8').trim() : env.TURN_SHARED_SECRET || ''; 
    if (!urls.length || secret.length < 32 || urls.some(x => !/^turns?:[a-zA-Z0-9.\-]+:\d+(\?transport=(udp|tcp))?$/.test(x))) {
        const error = new Error('Calling relay is not configured'); error.status = 503; throw error;
    }
    const expiresAt = Math.floor(now / 1000) + 4 * 3600;
    // No account identifier in coturn logs. The shared secret never leaves this server.
    const username = `${expiresAt}:${crypto.createHmac('sha256', secret).update(owner).digest('hex').slice(0, 24)}`;
    const credential = crypto.createHmac('sha1', secret).update(username).digest('base64');
    return { iceServers: [{ urls, username, credential }], expiresAt, iceTransportPolicy: 'relay' };
}
module.exports = { iceConfiguration };
