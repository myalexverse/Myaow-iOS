const {test} = require('node:test');
const assert = require('node:assert/strict');
const Database = require('better-sqlite3');
const crypto = require('node:crypto');
const {mkdtempSync,rmSync} = require('node:fs');
const {tmpdir} = require('node:os');
const path = require('node:path');
const {DurableRelay} = require('./durable_relay');
const {SecureScheduler} = require('./secure_scheduler');
function setup(file=':memory:') {
    const db = new Database(file);
    db.exec(`CREATE TABLE IF NOT EXISTS users(myaow_id TEXT PRIMARY KEY,identity_key_hex TEXT);
        CREATE TABLE IF NOT EXISTS blocked_contacts(blocker_id TEXT,blocked_id TEXT);
        CREATE TABLE IF NOT EXISTS group_members(group_id TEXT,myaow_id TEXT,role TEXT);`);
    for(const id of ['alice','bob','cat']) db.prepare('INSERT OR IGNORE INTO users VALUES(?,?)').run(id,'11'.repeat(32));
    return db;
}
function packet(recipient='bob',groupId) {
    const id=crypto.randomUUID();return {id,type:'message',recipientMyaowId:recipient,encryptedPayload:JSON.stringify({version:2,messageId:id,senderId:'alice',recipientId:recipient,senderPublicKey:'11'.repeat(32),encapsulatedKey:Buffer.alloc(32,1).toString('base64'),ciphertext:Buffer.alloc(50,2).toString('base64'),...(groupId?{groupId}:{})})};
}
function input(packets=[packet()]) {return {id:crypto.randomUUID(),due:2000,preview:Buffer.alloc(64,3).toString('base64'),packets};}
test('scheduled ciphertext survives restart and queues exactly once; queued is not delivered',()=>{
    const root=mkdtempSync(path.join(tmpdir(),'myaow-schedule-'));let db;
    try {
        const file=path.join(root,'db'); db=setup(file);let now=1000;
        let relay=new DurableRelay(db), scheduler=new SecureScheduler(db,relay,()=>now);
        const data=input(); scheduler.create('alice',data); scheduler.create('alice',data);
        assert.equal(scheduler.list('alice').length,1);assert.equal(scheduler.list('bob').length,0);
        assert.throws(()=>scheduler.create('alice',{...data,preview:'different'.repeat(10)}));
        scheduler.tick(); assert.equal(relay.pending('bob').length,0);
        db.close();db=setup(file);relay=new DurableRelay(db);scheduler=new SecureScheduler(db,relay,()=>now);
        now=3000;scheduler.tick();scheduler.tick();
        assert.equal(scheduler.list('alice')[0].state,'queued');assert.equal(relay.pending('bob').length,1);
        assert.equal(scheduler.cancel('alice',data.id),false);
        assert.equal(scheduler.create('alice',data).state,'queued');
        assert.equal(relay.acknowledge('bob','alice',data.packets[0].id),true);
        scheduler.tick();assert.equal(relay.pending('bob').length,0);
        assert.equal(scheduler.list('alice')[0].state,'delivered');
    }finally{db?.close();rmSync(root,{recursive:true,force:true});}
});
test('cancellation enforces ownership and prevents dispatch',()=>{
    const db=setup();try{let now=1000;const relay=new DurableRelay(db),scheduler=new SecureScheduler(db,relay,()=>now),data=input();
        scheduler.create('alice',data);assert.equal(scheduler.cancel('bob',data.id),false);
        assert.equal(scheduler.cancel('alice',data.id),true);assert.equal(scheduler.cancel('alice',data.id),true);
        now=5000;scheduler.tick();assert.equal(relay.pending('bob').length,0);
    }finally{db.close();}
});
test('full queue retries atomically without losing the schedule or partially sending a group',()=>{
    const db=setup();try{let now=1000;const relay=new DurableRelay(db),scheduler=new SecureScheduler(db,relay,()=>now);
        db.exec("INSERT INTO group_members VALUES('g','alice','admin'),('g','bob','member'),('g','cat','member')");
        const data=input([packet('bob','g'),packet('cat','g')]);scheduler.create('alice',data);
        const accept=relay.accept;relay.accept=(p,s)=>{if(p.recipientMyaowId==='cat')throw Error('Recipient queue full; retry later');return accept(p,s);};
        now=5000;scheduler.tick();assert.equal(relay.pending('bob').length,0);assert.equal(scheduler.list('alice')[0].state,'pending');
        relay.accept=accept;scheduler.tick();assert.equal(relay.pending('bob').length,1);assert.equal(relay.pending('cat').length,1);
    }finally{db.close();}
});
test('changed membership and blocks require attention without sending to removed contacts',()=>{
    const db=setup();try{let now=1000;const relay=new DurableRelay(db),scheduler=new SecureScheduler(db,relay,()=>now);
        db.exec("INSERT INTO group_members VALUES('g','alice','admin'),('g','bob','member')");
        const data=input([packet('bob','g')]);scheduler.create('alice',data);db.exec("DELETE FROM group_members WHERE myaow_id='bob'");
        now=5000;scheduler.tick();assert.equal(scheduler.list('alice')[0].state,'attention');assert.equal(relay.pending('bob').length,0);
        now=1000;const blocked=input();scheduler.create('alice',blocked);db.exec("INSERT INTO blocked_contacts VALUES('alice','bob')");
        now=5000;scheduler.tick();assert.equal(scheduler.list('alice')[1].state,'attention');assert.equal(relay.pending('bob').length,0);
    }finally{db.close();}
});
test('rejects plaintext, forged senders, invalid times, incomplete group batches and excessive payloads',()=>{
    const db=setup();try{const scheduler=new SecureScheduler(db,new DurableRelay(db),()=>1000);
        for(const data of [input([]),{...input(),due:999},{...input(),due:1000+31*86400000},{...input(),packets:[{text:'secret'}]}])assert.throws(()=>scheduler.create('alice',data));
        assert.throws(()=>scheduler.create('cat',input()));
        db.exec("INSERT INTO group_members VALUES('g','alice','admin'),('g','bob','member'),('g','cat','member')");
        assert.throws(()=>scheduler.create('alice',input([packet('bob','g')])));
    }finally{db.close();}
});
