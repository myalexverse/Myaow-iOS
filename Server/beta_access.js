'use strict';
const crypto=require('node:crypto');
class BetaAccess {
    constructor(db, env=process.env, now=Date.now) {
        this.db=db;this.env=env;this.now=now;
        db.exec('CREATE TABLE IF NOT EXISTS beta_invites(hash TEXT PRIMARY KEY,expires INTEGER NOT NULL,used_by TEXT UNIQUE)');
    }
    create(days=7) {
        if (!Number.isInteger(days)||days<1||days>30)throw Error('Invalid validity');
        const code=crypto.randomBytes(18).toString('base64url');
        this.db.prepare('INSERT INTO beta_invites(hash,expires) VALUES(?,?)').run(this.hash(code),this.now()+days*86400000);
        return code;
    }
    hash(code) { return crypto.createHash('sha256').update(code).digest('hex'); }
    consume(owner, code) {
        const mode=this.env.BETA_REGISTRATION_MODE || (this.env.NODE_ENV === 'production' ? 'closed' : 'open');
        const deny=message=>{const error=new Error(message);error.status=403;throw error;};
        if (mode==='closed')deny('Los nuevos registros están pausados. Intenta más tarde.');
        const maximum=Number(this.env.BETA_MAX_USERS || 0);
        if(maximum>0&&this.db.prepare('SELECT count(*) n FROM users').get().n>=maximum)deny('Los lugares de esta beta están completos.');
        if(mode==='open')return;
        if(mode!=='invite')deny('Los registros no están disponibles.');
        if(typeof code!=='string'||!/^[A-Za-z0-9_-]{24}$/.test(code))deny('Necesitas un código de invitación válido para entrar a la beta.');
        const result=this.db.prepare('UPDATE beta_invites SET used_by=? WHERE hash=? AND used_by IS NULL AND expires>?').run(owner,this.hash(code),this.now());
        if(result.changes!==1)deny('La invitación venció o ya fue utilizada.');
    }
}
module.exports={BetaAccess};
