'use strict';
const http2 = require('node:http2');
const fs = require('node:fs');
const crypto = require('node:crypto');

class MyaowAPNsGateway {
    constructor(config = {}) {
        this.teamId = config.teamId || process.env.APNS_TEAM_ID;
        this.keyId = config.keyId || process.env.APNS_KEY_ID;
        this.bundleId = config.bundleId || process.env.APNS_TOPIC || 'com.ScendLabs.Myaow';
        this.keyPath = config.keyPath || process.env.APNS_KEY_PATH;
        this.connect = config.connect || http2.connect;
        this.cachedToken = null;
        this.tokenGeneratedAt = 0;
    }
    get configured() { return !!(this.teamId && this.keyId && this.keyPath && fs.existsSync(this.keyPath)); }
    generateJWT() {
        const now = Math.floor(Date.now() / 1000);
        if (this.cachedToken && now - this.tokenGeneratedAt < 3000) return this.cachedToken;
        const header = Buffer.from(JSON.stringify({ alg: 'ES256', kid: this.keyId })).toString('base64url');
        const claims = Buffer.from(JSON.stringify({ iss: this.teamId, iat: now })).toString('base64url');
        const input = `${header}.${claims}`;
        const signature = crypto.sign('sha256', Buffer.from(input), { key: fs.readFileSync(this.keyPath), dsaEncoding: 'ieee-p1363' }).toString('base64url');
        this.tokenGeneratedAt = now;
        return this.cachedToken = `${input}.${signature}`;
    }
    async send(device, payload, { kind = 'alert', id = crypto.randomUUID(), expiresAt = 0 } = {}) {
        if (!this.configured) return { ok: false, retryable: true, reason: 'NotConfigured' };
        if (!/^[a-f0-9]{32,512}$/i.test(device.token) || !['sandbox', 'production'].includes(device.environment) || !['alert', 'voip'].includes(kind))
            return { ok: false, retryable: false, reason: 'InvalidDevice' };
        const bytes = JSON.stringify(payload);
        if (Buffer.byteLength(bytes) > (kind === 'voip' ? 5120 : 4096)) return { ok: false, retryable: false, reason: 'PayloadTooLarge' };
        let jwt;
        try { jwt = this.generateJWT(); } catch { return { ok: false, retryable: false, reason: 'InvalidConfiguration' }; }
        return new Promise(resolve => {
            let client, request, settled = false;
            const finish = result => {
                if (settled) return; settled = true;
                clearTimeout(timeout); request?.close(); client?.destroy(); resolve(result);
            };
            const timeout = setTimeout(() => finish({ ok: false, retryable: true, reason: 'Timeout' }), 8000);
            try {
                client = this.connect(device.environment === 'production' ? 'https://api.push.apple.com' : 'https://api.sandbox.push.apple.com');
                client.on('error', () => finish({ ok: false, retryable: true, reason: 'ConnectionError' }));
                request = client.request({ ':method': 'POST', ':path': `/3/device/${device.token}`,
                    authorization: `bearer ${jwt}`, 'apns-topic': this.bundleId + (kind === 'voip' ? '.voip' : ''),
                    'apns-push-type': kind, 'apns-priority': '10', 'apns-id': id,
                    'apns-expiration': String(kind === 'voip' ? 0 : expiresAt) });
                let status = 0, body = '';
                request.on('response', headers => { status = Number(headers[':status']); });
                request.on('data', chunk => { if (body.length < 4096) body += chunk; });
                request.on('end', () => {
                    let reason; try { reason = JSON.parse(body).reason; } catch {}
                    finish({ ok: status === 200, status, reason,
                        invalidToken: status === 410 || ['BadDeviceToken','DeviceTokenNotForTopic'].includes(reason),
                        retryable: status === 429 || status >= 500 });
                });
                request.on('error', () => finish({ ok: false, retryable: true, reason: 'RequestError' }));
                request.end(bytes);
            } catch { finish({ ok: false, retryable: true, reason: 'ConnectionError' }); }
        });
    }
}
module.exports = MyaowAPNsGateway;
