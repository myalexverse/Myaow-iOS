'use strict';
const crypto = require('node:crypto');
const uuid = x => typeof x === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(x);
class PushDelivery {
    constructor(db, gateway, now = Date.now) {
        this.db = db; this.gateway = gateway; this.now = now; this.running = false;
        db.exec(`CREATE TABLE IF NOT EXISTS push_devices (
            owner TEXT NOT NULL, installation TEXT NOT NULL, environment TEXT NOT NULL,
            alert_token TEXT, voip_token TEXT, callers TEXT NOT NULL, updated INTEGER NOT NULL,
            PRIMARY KEY(owner,installation));
            CREATE TABLE IF NOT EXISTS push_jobs (
            id TEXT PRIMARY KEY, owner TEXT NOT NULL, sender TEXT NOT NULL, message_id TEXT NOT NULL,
            installation TEXT NOT NULL, kind TEXT NOT NULL, payload TEXT NOT NULL, expires INTEGER NOT NULL,
            due INTEGER NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, state TEXT NOT NULL DEFAULT 'pending',
            UNIQUE(sender,message_id,owner,installation,kind));
            CREATE INDEX IF NOT EXISTS push_due ON push_jobs(state,due);`);
    }
    register(owner, data) {
        if (!uuid(data.installation) || !['sandbox','production'].includes(data.environment) ||
            !Array.isArray(data.callers) || data.callers.length > 2000 || data.callers.some(x => typeof x !== 'string' || x.length > 128) ||
            [data.alertToken,data.voipToken].some(x => x != null && (typeof x !== 'string' || !/^[a-f0-9]{32,512}$/i.test(x)))) throw new Error('Invalid device');
        this.db.transaction(() => {
            // A token belongs to one current account. Clear stale bindings on account changes.
            for (const [field, value] of [['alert_token',data.alertToken],['voip_token',data.voipToken]]) if (value)
                this.db.prepare(`UPDATE push_devices SET ${field}=NULL WHERE ${field}=? AND environment=?`).run(value, data.environment);
            const existing = this.db.prepare('SELECT 1 FROM push_devices WHERE owner=? AND installation=?').get(owner,data.installation);
            if (!existing && this.db.prepare('SELECT count(*) n FROM push_devices WHERE owner=?').get(owner).n >= 10) throw new Error('Device limit');
            this.db.prepare(`INSERT INTO push_devices VALUES(?,?,?,?,?,?,?) ON CONFLICT(owner,installation) DO UPDATE SET
                environment=excluded.environment, alert_token=excluded.alert_token, voip_token=excluded.voip_token, callers=excluded.callers, updated=excluded.updated`)
                .run(owner,data.installation,data.environment,data.alertToken || null,data.voipToken || null,JSON.stringify([...new Set(data.callers)]),this.now());
        })();
    }
    devices(owner) { return this.db.prepare('SELECT * FROM push_devices WHERE owner=?').all(owner); }
    allowed(owner, sender, installation) {
        const devices = this.devices(owner).filter(x => !installation || x.installation === installation);
        return devices.some(x => JSON.parse(x.callers).includes(sender)) && !this.blocked(owner,sender);
    }
    blocked(a,b) { return !!this.db.prepare('SELECT 1 FROM blocked_contacts WHERE (blocker_id=? AND blocked_id=?) OR (blocker_id=? AND blocked_id=?)').get(a,b,b,a); }
    enqueueMessage(packet) {
        this.enqueue(packet.recipientMyaowId, packet.senderMyaowId, packet.id, 'alert', {
            aps: { alert: { title: 'Myaow', body: 'Tienes un nuevo mensaje protegido.' }, sound: 'default' },
            kind: 'message', messageId: packet.id
        }, this.now() + 86400000);
    }
    enqueue(owner, sender, messageId, kind, payload, expires) {
        for (const device of this.devices(owner)) {
            if (!device[kind === 'voip' ? 'voip_token' : 'alert_token'] || (kind === 'voip' && !this.allowed(owner,sender,device.installation))) continue;
            this.db.prepare('INSERT OR IGNORE INTO push_jobs(id,owner,sender,message_id,installation,kind,payload,expires,due) VALUES(?,?,?,?,?,?,?,?,?)')
                .run(crypto.randomUUID(),owner,sender,messageId,device.installation,kind,JSON.stringify(payload),expires,this.now());
        }
    }
    async tick() {
        if (this.running) return;
        this.running = true;
        try {
            this.db.prepare("DELETE FROM push_jobs WHERE expires<?").run(this.now() - 86400000);
            this.db.prepare("UPDATE push_jobs SET state='expired' WHERE state='pending' AND expires<=?").run(this.now());
            const jobs = this.db.prepare("SELECT * FROM push_jobs WHERE state='pending' AND due<=? LIMIT 20").all(this.now());
            await Promise.all(jobs.map(async job => {
                const device = this.db.prepare('SELECT * FROM push_devices WHERE owner=? AND installation=?').get(job.owner,job.installation);
                const field = job.kind === 'voip' ? 'voip_token' : 'alert_token';
                let permitted = device?.[field] && !this.blocked(job.owner,job.sender);
                if (permitted && job.kind === 'voip') permitted = this.allowed(job.owner,job.sender,job.installation);
                if (permitted && job.kind === 'alert') {
                    const message = this.db.prepare('SELECT packet_json FROM secure_messages WHERE sender_id=? AND message_id=?').get(job.sender,job.message_id);
                    if (message) {
                        const group = JSON.parse(JSON.parse(message.packet_json).encryptedPayload).groupId;
                        if (group) permitted = [job.owner,job.sender].every(id => this.db.prepare('SELECT 1 FROM group_members WHERE group_id=? AND myaow_id=?').get(group,id));
                    }
                }
                if (!permitted) { this.db.prepare("UPDATE push_jobs SET state='cancelled' WHERE id=?").run(job.id); return; }
                const result = await this.gateway.send({ token:device[field],environment:device.environment }, JSON.parse(job.payload),
                    { kind:job.kind,id:job.id,expiresAt:Math.floor(job.expires/1000) });
                if (result.invalidToken) this.db.prepare(`UPDATE push_devices SET ${field}=NULL WHERE owner=? AND installation=? AND ${field}=?`)
                    .run(job.owner,job.installation,device[field]);
                // VoIP requests are not retried after ambiguous delivery: every push must represent one incoming call.
                const retry = job.kind === 'alert' && result.retryable && job.attempts < 7;
                this.db.prepare('UPDATE push_jobs SET state=?,attempts=attempts+1,due=? WHERE id=? AND state=\'pending\'')
                    .run(result.ok ? 'accepted_by_apns' : retry ? 'pending' : 'failed',this.now()+Math.min(300000,5000*2**job.attempts),job.id);
            }));
        } finally { this.running = false; }
    }
}
module.exports = { PushDelivery, uuid };
