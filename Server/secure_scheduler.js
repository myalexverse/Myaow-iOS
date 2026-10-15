'use strict';

// The clock only moves ciphertext into the durable delivery queue. It never claims delivery.
class SecureScheduler {
    constructor(db, relay, now = Date.now) {
        this.db = db; this.relay = relay; this.now = now;
        db.exec(`CREATE TABLE IF NOT EXISTS secure_schedules (
            owner TEXT NOT NULL, id TEXT NOT NULL, due INTEGER NOT NULL, packets TEXT NOT NULL,
            preview TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'pending', PRIMARY KEY(owner,id));
            CREATE INDEX IF NOT EXISTS secure_schedules_due ON secure_schedules(state,due);`);
        this.create = db.transaction((owner, data) => {
            const prior = db.prepare('SELECT * FROM secure_schedules WHERE owner=? AND id=?').get(owner, data.id);
            if (prior) {
                if (prior.packets !== JSON.stringify(data.packets) || prior.due !== data.due || prior.preview !== data.preview) throw new Error('Schedule ID already used');
                return this.item(prior);
            }
            if (!/^[0-9a-f-]{36}$/i.test(data.id || '') || !Number.isSafeInteger(data.due) || data.due <= now() || data.due > now() + 30 * 86400000) throw new Error('Invalid schedule');
            if (typeof data.preview !== 'string' || !/^[A-Za-z0-9+/]+={0,2}$/.test(data.preview) || Buffer.from(data.preview,'base64').length < 28 || data.preview.length < 32 || data.preview.length > 200000) throw new Error('Invalid encrypted preview');
            this.validateBatch(owner, data.packets);
            if (db.prepare("SELECT count(*) AS n FROM secure_schedules WHERE owner=? AND state IN ('pending','attention')").get(owner).n >= 100) throw new Error('Schedule limit reached');
            db.prepare('INSERT INTO secure_schedules(owner,id,due,packets,preview) VALUES(?,?,?,?,?)')
                .run(owner, data.id, data.due, JSON.stringify(data.packets), data.preview);
            return this.item(db.prepare('SELECT * FROM secure_schedules WHERE owner=? AND id=?').get(owner, data.id));
        });
        this.dispatch = db.transaction(row => {
            // Transaction makes cancellation and enqueue mutually exclusive.
            const current = db.prepare('SELECT * FROM secure_schedules WHERE owner=? AND id=?').get(row.owner, row.id);
            if (current?.state !== 'pending' || current.due > now()) return;
            this.validateBatch(current.owner, JSON.parse(current.packets));
            for (const packet of JSON.parse(current.packets)) relay.accept(packet, current.owner);
            db.prepare("UPDATE secure_schedules SET state='queued' WHERE owner=? AND id=?").run(current.owner, current.id);
        });
    }
    validateBatch(owner, packets) {
        if (!Array.isArray(packets) || !packets.length || packets.length > 100 || Buffer.byteLength(JSON.stringify(packets)) > 4 * 1024 * 1024) throw new Error('Invalid encrypted batch');
        const recipients = new Set(), ids = new Set();
        let group;
        for (const packet of packets) {
            const fields = new Set(['id','type','senderMyaowId','senderDisplayName','recipientMyaowId','encryptedPayload']);
            if (Object.keys(packet).some(key => !fields.has(key))) throw new Error('Only encrypted content is accepted');
            const valid = this.relay.validate(packet, owner);
            if (group === undefined) group = valid.groupId;
            if (group !== valid.groupId || recipients.has(valid.recipient) || ids.has(packet.id)) throw new Error('Invalid recipients');
            recipients.add(valid.recipient); ids.add(packet.id);
        }
        if (packets.length > 1 && !group) throw new Error('Group required');
        if (group) {
            const members = this.db.prepare('SELECT myaow_id FROM group_members WHERE group_id=? AND myaow_id != ?').all(group, owner);
            if (members.length !== recipients.size || members.some(m => !recipients.has(m.myaow_id))) throw new Error('Group changed; prepare the message again');
        }
    }
    item(row) { return { id: row.id, due: row.due, preview: row.preview, state: row.state }; }
    list(owner) {
        this.db.prepare(`UPDATE secure_schedules SET state='delivered' WHERE owner=? AND state='queued'
            AND NOT EXISTS (SELECT 1 FROM json_each(secure_schedules.packets) p
                LEFT JOIN secure_messages m ON m.sender_id=secure_schedules.owner AND m.message_id=json_extract(p.value,'$.id')
                WHERE m.delivered_at IS NULL)`).run(owner);
        return this.db.prepare("SELECT * FROM secure_schedules WHERE owner=? AND state != 'cancelled' ORDER BY CASE WHEN state IN ('pending','attention') THEN 0 ELSE 1 END, CASE WHEN state IN ('queued','delivered') THEN -due ELSE due END LIMIT 200")
            .all(owner).map(row => this.item(row));
    }

    cancel(owner, id) {
        const row = this.db.prepare('SELECT state FROM secure_schedules WHERE owner=? AND id=?').get(owner, id);
        if (!row) return false;
        if (row.state === 'cancelled') return true;
        return this.db.prepare("UPDATE secure_schedules SET state='cancelled' WHERE owner=? AND id=? AND state IN ('pending','attention')").run(owner,id).changes === 1;
    }
    tick() {
        const due = this.db.prepare("SELECT * FROM secure_schedules WHERE state='pending' AND due<=? ORDER BY due LIMIT 50").all(this.now());
        for (const row of due) {
            try { this.dispatch(row); }
            catch (error) {
                // Capacity errors retry later; changed membership / blocks require the sender's attention.
                if (!error.message.includes('queue full')) this.db.prepare("UPDATE secure_schedules SET state='attention' WHERE owner=? AND id=? AND state='pending'").run(row.owner,row.id);
            }
        }
    }
}
module.exports = { SecureScheduler };
