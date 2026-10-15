'use strict';

// SQLite adapter for the local relay. Production gateways must share a durable store.
class DurableRelay {
    constructor(db, onAccepted = () => {}) {
        this.db = db;
        db.exec(`CREATE TABLE IF NOT EXISTS secure_messages (
            sender_id TEXT NOT NULL, message_id TEXT NOT NULL, recipient_id TEXT NOT NULL,
            packet_json TEXT NOT NULL, created_at INTEGER NOT NULL, delivered_at INTEGER,
            PRIMARY KEY(sender_id, message_id));
            CREATE INDEX IF NOT EXISTS secure_pending ON secure_messages(recipient_id, delivered_at, created_at);`);
        this.accept = db.transaction((packet, sender) => {
            const { recipient } = this.validate(packet, sender);
            const existing = db.prepare('SELECT * FROM secure_messages WHERE sender_id = ? AND message_id = ?').get(sender, packet.id);
            if (existing) {
                if (existing.recipient_id !== recipient || JSON.parse(existing.packet_json).encryptedPayload !== packet.encryptedPayload)
                    throw new Error('Message identifier already used');
                return { packet: JSON.parse(existing.packet_json), status: existing.delivered_at ? 'delivered' : 'queued_on_server', fresh: false };
            }
            if (db.prepare('SELECT 1 FROM blocked_contacts WHERE (blocker_id = ? AND blocked_id = ?) OR (blocker_id = ? AND blocked_id = ?)').get(recipient, sender, sender, recipient))
                throw new Error('Message unavailable');
            const usage = db.prepare('SELECT count(*) AS count, coalesce(sum(length(packet_json)),0) AS bytes FROM secure_messages WHERE recipient_id = ? AND delivered_at IS NULL').get(recipient);
            if (usage.count >= 10000 || usage.bytes >= 64 * 1024 * 1024) throw new Error('Recipient queue full; retry later');
            const clean = { type: 'message', id: packet.id, senderMyaowId: sender,
                senderDisplayName: packet.senderDisplayName || sender, recipientMyaowId: recipient,
                conversationId: '', messageType: 'secure-v2', text: 'Mensaje protegido',
                timestamp: new Date().toISOString(), encryptedPayload: packet.encryptedPayload };
            db.prepare('INSERT INTO secure_messages(sender_id,message_id,recipient_id,packet_json,created_at) VALUES(?,?,?,?,?)')
                .run(sender, packet.id, recipient, JSON.stringify(clean), Date.now());
            onAccepted(clean); // Runs in the same transaction as durable acceptance (including scheduled batches).
            return { packet: clean, status: 'queued_on_server', fresh: true };
        });
    }
    validate(packet, sender) {
        const db = this.db;
            const envelope = JSON.parse(packet.encryptedPayload);
            if (!envelope || typeof envelope !== 'object' || Array.isArray(envelope) || Object.keys(envelope).some(key => !['version','messageId','senderId','recipientId','senderPublicKey','encapsulatedKey','ciphertext','groupId','notificationSound'].includes(key))) throw new Error('Invalid envelope fields');
            if ('notificationSound' in envelope && !['classic','electric','cosmic','melodic','claw','lazy','kiss','giggle','party','question','sleepy','echo','mentada','admiration'].includes(envelope.notificationSound)) throw new Error('Invalid notification sound');
            const recipient = packet.recipientMyaowId;
            const key = db.prepare('SELECT identity_key_hex FROM users WHERE myaow_id = ?').get(sender);
            if (packet.type !== 'message' || !/^[0-9a-f-]{36}$/i.test(packet.id || '') ||
                !key || envelope.version !== 2 || envelope.messageId !== packet.id ||
                envelope.senderId !== sender || envelope.recipientId !== recipient || sender === recipient ||
                envelope.senderPublicKey?.toLowerCase() !== key.identity_key_hex.toLowerCase() ||
                typeof envelope.encapsulatedKey !== 'string' || Buffer.from(envelope.encapsulatedKey, 'base64').length !== 32 ||
                typeof envelope.ciphertext !== 'string' || Buffer.from(envelope.ciphertext, 'base64').length < 16 ||
                Buffer.byteLength(packet.encryptedPayload) > 192 * 1024 ||
                !db.prepare('SELECT 1 FROM users WHERE myaow_id = ?').get(recipient)) throw new Error('Invalid secure message');
        if (envelope.groupId) {
            for (const id of [sender, recipient]) {
                if (!db.prepare('SELECT 1 FROM group_members WHERE group_id = ? AND myaow_id = ?').get(envelope.groupId, id)) throw new Error('Group membership required');
            }
        }
        if (db.prepare('SELECT 1 FROM blocked_contacts WHERE (blocker_id = ? AND blocked_id = ?) OR (blocker_id = ? AND blocked_id = ?)').get(recipient, sender, sender, recipient)) throw new Error('Message unavailable');
        return { recipient, groupId: envelope.groupId || null };
    }
    pending(recipient) {
        return this.db.prepare(`SELECT packet_json FROM secure_messages s WHERE recipient_id = ? AND delivered_at IS NULL
            AND NOT EXISTS (SELECT 1 FROM blocked_contacts b WHERE (b.blocker_id=s.sender_id AND b.blocked_id=s.recipient_id) OR (b.blocker_id=s.recipient_id AND b.blocked_id=s.sender_id))
            AND (json_extract(json_extract(packet_json, '$.encryptedPayload'), '$.groupId') IS NULL OR (
                EXISTS (SELECT 1 FROM group_members m WHERE m.group_id=json_extract(json_extract(packet_json, '$.encryptedPayload'), '$.groupId') AND m.myaow_id=s.sender_id)
                AND EXISTS (SELECT 1 FROM group_members m WHERE m.group_id=json_extract(json_extract(packet_json, '$.encryptedPayload'), '$.groupId') AND m.myaow_id=s.recipient_id)))
            ORDER BY created_at, s.rowid LIMIT 50`)
            .all(recipient).map(row => JSON.parse(row.packet_json));
    }
    acknowledge(recipient, sender, id) {
        return this.db.prepare('UPDATE secure_messages SET delivered_at = coalesce(delivered_at, ?) WHERE recipient_id = ? AND sender_id = ? AND message_id = ?')
            .run(Date.now(), recipient, sender, id).changes > 0;
    }
    pruneReceipts() {
        this.db.prepare('DELETE FROM secure_messages WHERE delivered_at < ?').run(Date.now() - 7 * 86400000);
    }
}
module.exports = { DurableRelay };
