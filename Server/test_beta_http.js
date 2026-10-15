'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {spawn}=require('node:child_process');
const {mkdtempSync,rmSync}=require('node:fs');
const path=require('node:path');
const os=require('node:os');
const net=require('node:net');
const crypto=require('node:crypto');
const Database=require('better-sqlite3');
const {BetaAccess}=require('./beta_access');
test('beta HTTP registration requires one-use invitations, preserves retries and closes new admissions',async()=>{
    const root=mkdtempSync(path.join(os.tmpdir(),'myaow-beta-http-')),database=path.join(root,'beta.db');
    let server,db;
    try {
        const probe=net.createServer();await new Promise(resolve=>probe.listen(0,'127.0.0.1',resolve));const port=probe.address().port;await new Promise(resolve=>probe.close(resolve));
        const base=`http://127.0.0.1:${port}`;
        const start=async mode=>{
            server=spawn(process.execPath,[path.join(__dirname,'server.js')],{cwd:root,env:{PATH:process.env.PATH,HOME:root,PORT:String(port),HOST:'127.0.0.1',MYAOW_DB_PATH:database,MYAOW_UPLOADS_DIR:path.join(root,'uploads'),BETA_REGISTRATION_MODE:mode,BETA_MAX_USERS:'2'},stdio:['ignore','ignore','ignore']});
            for(let i=0;i<50;i++) { if(server.exitCode!==null)throw Error('Relay failed');try{if((await fetch(base+'/health')).ok)return;}catch{}await new Promise(r=>setTimeout(r,100)); }
            throw Error('Relay did not start');
        };
        const stop=async()=>{const child=server;const done=new Promise(resolve=>child.once('exit',resolve));child.kill();await done;server=null;};
        await start('invite');db=new Database(database);const gate=new BetaAccess(db);
        const identity=id=>({myaowId:id,username:id.toLowerCase(),displayName:'Test',identityKeyHex:Buffer.from(crypto.generateKeyPairSync('x25519').publicKey.export({format:'jwk'}).x,'base64url').toString('hex'),signedPrekeyHex:'',oneTimePrekeys:[]});
        const register=body=>fetch(base+'/api/v1/directory/register',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
        const alice=identity('MYAOW-ALICE'),bob=identity('MYAOW-BOB01');
        assert.equal((await register(alice)).status,403);
        alice.betaInvite=gate.create();assert.equal((await register(alice)).status,200);
        delete alice.betaInvite;assert.equal((await register(alice)).status,200);
        bob.betaInvite=gate.create();assert.equal((await register({...bob,identityKeyHex:'bad'})).status,400);
        assert.equal((await register(bob)).status,200);
        assert.equal((await register({...identity('MYAOW-CAT01'),betaInvite:gate.create()})).status,403);
        await stop();await start('closed');
        assert.equal((await register(alice)).status,200);
        assert.equal((await register(identity('MYAOW-CAT02'))).status,403);
        const health=await fetch(base+'/health').then(r=>r.json());assert.equal(health.registeredUsers,undefined);assert.equal(health.activeConnections,undefined);
        await stop();
    }finally{if(server&&server.exitCode===null){const done=new Promise(r=>server.once('exit',r));server.kill();await done;}db?.close();rmSync(root,{recursive:true,force:true});}
});
