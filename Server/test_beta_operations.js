'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const Database=require('better-sqlite3');
const fs=require('node:fs/promises');
const path=require('node:path');
const os=require('node:os');
const {BetaAccess}=require('./beta_access');
const {clientAddress}=require('./proxy_address');
const {makeBackup,verifyBackup}=require('./backup');
test('beta invitations expire, are single use and roll back with failed registration',()=>{
    const db=new Database(':memory:');db.exec('CREATE TABLE users(myaow_id TEXT PRIMARY KEY)');
    try{
        let now=1000;const env={BETA_REGISTRATION_MODE:'invite',BETA_MAX_USERS:'2'};
        const gate=new BetaAccess(db,env,()=>now);const code=gate.create();
        assert.equal(db.prepare('SELECT hash FROM beta_invites').get().hash.includes(code),false);
        assert.throws(()=>gate.consume('alice','wrong'));
        assert.throws(()=>db.transaction(()=>{gate.consume('alice',code);throw Error('failed insert');})());
        db.transaction(()=>{gate.consume('alice',code);db.prepare('INSERT INTO users VALUES(?)').run('alice');})();
        assert.throws(()=>gate.consume('bob',code));
        const expired=gate.create(1);now+=86400001;assert.throws(()=>gate.consume('bob',expired));
        const valid=gate.create();gate.consume('bob',valid);db.prepare('INSERT INTO users VALUES(?)').run('bob');
        assert.throws(()=>gate.consume('cat',gate.create()),/completos/);
        env.BETA_REGISTRATION_MODE='closed';assert.throws(()=>gate.consume('cat',gate.create()),/pausados/);
    }finally{db.close();}
});
test('forwarded IP is ignored unless explicitly trusted and never accepts lists or arbitrary text',()=>{
    const request={headers:{'x-myaow-client-ip':'203.0.113.5'},socket:{remoteAddress:'172.18.0.2'}};
    assert.equal(clientAddress(request), '172.18.0.2');assert.equal(clientAddress(request,true),'203.0.113.5');
    for(const value of ['1.2.3.4, 5.6.7.8','forged','']){request.headers['x-myaow-client-ip']=value;assert.equal(clientAddress(request,true),'172.18.0.2');}
});
test('online SQLite backup restores committed WAL data and media without overwriting existing snapshots',async()=>{
    const root=await fs.mkdtemp(path.join(os.tmpdir(),'myaow-backup-test-'));
    const database=path.join(root,'live.db'),uploads=path.join(root,'uploads'),destination=path.join(root,'snapshot');
    const live=new Database(database);live.pragma('journal_mode = WAL');live.exec("CREATE TABLE messages(text TEXT); INSERT INTO messages VALUES('fictional encrypted payload')");
    try{
        await fs.mkdir(uploads);await fs.writeFile(path.join(uploads,'ciphertext.bin'),Buffer.from([1,2,3]));
        await makeBackup({database,uploads,destination});assert.equal(await verifyBackup(destination),true);
        const restored=new Database(path.join(destination,'myaow.db'),{readonly:true});
        try{assert.equal(restored.prepare('SELECT count(*) n FROM messages').get().n,1);}finally{restored.close();}
        assert.deepEqual(await fs.readFile(path.join(destination,'uploads/ciphertext.bin')),Buffer.from([1,2,3]));
        await assert.rejects(()=>makeBackup({database,uploads,destination}));
        await fs.appendFile(path.join(destination,'myaow.db'),'damaged');await assert.rejects(()=>verifyBackup(destination),/checksum/);
    }finally{live.close();await fs.rm(root,{recursive:true,force:true});}
});
