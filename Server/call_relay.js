'use strict';
const { uuid } = require('./push_delivery');
class CallRelay {
    constructor(db, relay, push, now = Date.now) {
        this.db=db; this.relay=relay; this.push=push; this.now=now;
        db.exec(`CREATE TABLE IF NOT EXISTS call_sessions(id TEXT PRIMARY KEY,caller TEXT NOT NULL,callee TEXT NOT NULL,state TEXT NOT NULL,expires INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS call_signals(id TEXT PRIMARY KEY,call_id TEXT NOT NULL,sender TEXT NOT NULL,recipient TEXT NOT NULL,packet TEXT NOT NULL,expires INTEGER NOT NULL);`);
        this.accept = db.transaction((actor, data) => {
            const { packet, callId, signalType, expiresAt } = data;
            if (!uuid(callId) || !['call_offer','call_answer','call_hangup','webrtc_offer','webrtc_answer','webrtc_ice_candidate'].includes(signalType) ||
                !Number.isFinite(expiresAt) || expiresAt <= now()/1000 || expiresAt > now()/1000+95) throw new Error('Invalid call signal');
            const valid = relay.validate(packet,actor);
            if (valid.groupId) throw new Error('Group calls unavailable');
            const recipient=valid.recipient;
            const clean={type:'call_signal',id:packet.id,senderMyaowId:actor,recipientMyaowId:recipient,
                encryptedPayload:packet.encryptedPayload,callId,signalType,expiresAt};
            if (Buffer.byteLength(JSON.stringify(clean)) > (signalType==='call_offer' ? 4000 : 60000)) throw new Error('Call signal too large');
            const prior=db.prepare('SELECT packet FROM call_signals WHERE id=?').get(packet.id);
            if (prior) {
                if (prior.packet!==JSON.stringify(clean)) throw new Error('Signal identifier already used');
                return {packet:clean,fresh:false};
            }
            let session=db.prepare('SELECT * FROM call_sessions WHERE id=?').get(callId);
            if (signalType==='call_offer') {
                if (session || !push.allowed(recipient,actor)) throw new Error('Call unavailable');
                if (db.prepare("SELECT 1 FROM call_sessions WHERE state!='ended' AND expires>? AND (caller IN (?,?) OR callee IN (?,?))").get(now(),actor,recipient,actor,recipient)) throw new Error('Call unavailable');
                db.prepare('INSERT INTO call_sessions VALUES(?,?,?,?,?)').run(callId,actor,recipient,'ringing',now()+45000);
                push.enqueue(recipient,actor,packet.id,'voip',{aps:{},...clean},now()+45000);
            } else {
                if (!session || session.expires<=now() || session.state==='ended' ||
                    !((session.caller===actor && session.callee===recipient)||(session.callee===actor && session.caller===recipient))) throw new Error('Call unavailable');
                if (signalType==='call_answer') {
                    if (session.callee!==actor || session.state!=='ringing') throw new Error('Invalid answer');
                    db.prepare("UPDATE call_sessions SET state='accepted',expires=? WHERE id=?").run(now()+3*3600000,callId);
                } else if (signalType==='call_hangup') {
                    db.prepare("UPDATE call_sessions SET state='ended',expires=? WHERE id=?").run(now()+90000,callId);
                    db.prepare("UPDATE push_jobs SET state='cancelled' WHERE kind='voip' AND state='pending' AND json_extract(payload,'$.callId')=?").run(callId);
                } else if (session.state!=='accepted') throw new Error('Call has not been accepted');
            }
            db.prepare('INSERT INTO call_signals VALUES(?,?,?,?,?,?)').run(packet.id,callId,actor,recipient,JSON.stringify(clean),expiresAt*1000);
            return {packet:clean,fresh:true};
        });
    }
    pending(owner) {
        return this.db.prepare(`SELECT s.packet FROM call_signals s JOIN call_sessions c ON c.id=s.call_id
            WHERE s.recipient=? AND s.expires>? AND c.expires>? AND (c.state!='ended' OR json_extract(s.packet,'$.signalType')='call_hangup')
            ORDER BY s.rowid LIMIT 300`).all(owner,this.now(),this.now()).map(x=>JSON.parse(x.packet))
            .filter(x=>!this.push.blocked(owner,x.senderMyaowId));
    }
    prune() {
        this.db.prepare('DELETE FROM call_signals WHERE expires<=?').run(this.now());
        this.db.prepare('DELETE FROM call_sessions WHERE expires<=?').run(this.now());
    }
}
module.exports={CallRelay};
