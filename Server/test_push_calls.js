'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const crypto=require('node:crypto');
const Database=require('better-sqlite3');
const {EventEmitter}=require('node:events');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {DurableRelay}=require('./durable_relay');
const {SecureScheduler}=require('./secure_scheduler');
const {PushDelivery}=require('./push_delivery');
const {CallRelay}=require('./call_relay');
const {iceConfiguration}=require('./ice_configuration');
const {authorizeRoute}=require('./access_control');
const Gateway=require('./apns_gateway');
function setup() {
    const db=new Database(':memory:');
    db.exec(`CREATE TABLE users(myaow_id TEXT PRIMARY KEY,identity_key_hex TEXT);
        CREATE TABLE blocked_contacts(blocker_id TEXT,blocked_id TEXT);
        CREATE TABLE group_members(group_id TEXT,myaow_id TEXT,role TEXT);`);
    for(const id of ['alice','bob','mallory'])db.prepare('INSERT INTO users VALUES(?,?)').run(id,'11'.repeat(32));
    let clock=100000;
    const sent=[];const gateway={send:async(...args)=>{sent.push(args);return {ok:true};}};
    const push=new PushDelivery(db,gateway,()=>clock);
    const relay=new DurableRelay(db,p=>push.enqueueMessage(p));
    const calls=new CallRelay(db,relay,push,()=>clock);
    const device={installation:crypto.randomUUID(),environment:'sandbox',alertToken:'ab'.repeat(32),voipToken:'cd'.repeat(32),callers:['alice']};
    push.register('bob',device);
    return {db,push,relay,calls,device,sent,gateway,now:()=>clock,advance:n=>{clock+=n;}};
}
function packet(sender='alice',recipient='bob',groupId) {
    const id=crypto.randomUUID();return {id,type:'message',recipientMyaowId:recipient,encryptedPayload:JSON.stringify({version:2,messageId:id,senderId:sender,recipientId:recipient,senderPublicKey:'11'.repeat(32),encapsulatedKey:Buffer.alloc(32,1).toString('base64'),ciphertext:Buffer.alloc(50,2).toString('base64'),...(groupId?{groupId}:{})})};
}
function signal(s,signalType='call_offer',callId=crypto.randomUUID(),sender='alice',recipient='bob') {
    return {packet:packet(sender,recipient),signalType,callId,expiresAt:s.now()/1000+90};
}
test('TURN credentials expire, use coturn HMAC, hide account IDs and fail closed when missing',()=>{
    assert.throws(()=>iceConfiguration('alice',{}),/not configured/);
    assert.throws(()=>iceConfiguration('alice',{TURN_URLS:'turn:server:3478',TURN_SHARED_SECRET:'short'}));
    const env={TURN_URLS:'turn:relay.example:3478?transport=udp,turns:relay.example:5349?transport=tcp',TURN_SHARED_SECRET:'s'.repeat(48)};
    const result=iceConfiguration('alice',env,100000);
    assert.equal(result.iceTransportPolicy,'relay');assert.equal(result.expiresAt,14500);
    assert.equal(result.iceServers[0].credential,crypto.createHmac('sha1',env.TURN_SHARED_SECRET).update(result.iceServers[0].username).digest('base64'));
    assert.equal(JSON.stringify(result).includes('alice'),false);assert.equal(JSON.stringify(result).includes(env.TURN_SHARED_SECRET),false);
});
test('push, call and ICE routes require an authenticated session',()=>{
    for(const route of ['push/device','calls/signal','webrtc/ice-servers'])assert.equal(authorizeRoute(null,'/api/v1/'+route,'GET',null),401);
});
test('device tokens rotate, null removes tokens and account rebinding clears the former owner',()=>{
    const s=setup();try{
        s.push.register('alice',{...s.device,callers:[]});
        assert.equal(s.push.devices('bob')[0].voip_token,null);
        s.push.register('alice',{...s.device,alertToken:null,voipToken:null,callers:[]});
        assert.equal(s.push.devices('alice')[0].alert_token,null);
        assert.throws(()=>s.push.register('bob',{...s.device,environment:'anything'}));
    }finally{s.db.close();}
});
test('direct and scheduled group messages queue generic alerts transactionally and never duplicate on retry',async()=>{
    const s=setup();try{
        const p=packet();s.relay.accept(p,'alice');s.relay.accept(p,'alice');
        s.db.exec("INSERT INTO group_members VALUES('g','alice','admin'),('g','bob','member')");
        const scheduler=new SecureScheduler(s.db,s.relay,s.now);
        scheduler.create('alice',{id:crypto.randomUUID(),due:s.now()+1000,preview:Buffer.alloc(64,3).toString('base64'),packets:[packet('alice','bob','g')]});
        s.advance(2000);scheduler.tick();await s.push.tick();
        assert.equal(s.sent.length,2);assert.equal(s.sent[0][1].aps.alert.title,'Myaow');
        assert.equal(s.sent[0][1].senderMyaowId,undefined);assert.equal(s.sent[0][1].aps.badge,undefined);
        assert.equal(s.db.prepare("SELECT count(*) n FROM push_jobs WHERE state='accepted_by_apns'").get().n,2);
    }finally{s.db.close();}
});
test('rolled back batch cannot send a notification',async()=>{
    const s=setup();try{
        assert.throws(()=>s.db.transaction(()=>{s.relay.accept(packet(),'alice');throw Error('rollback');})());
        await s.push.tick();assert.equal(s.sent.length,0);
    }finally{s.db.close();}
});
test('blocking or removal from group suppresses pending notifications',async()=>{
    const s=setup();try{
        s.db.exec("INSERT INTO group_members VALUES('g','alice','admin'),('g','bob','member')");
        s.relay.accept(packet('alice','bob','g'),'alice');s.db.exec("DELETE FROM group_members WHERE myaow_id='bob'");
        await s.push.tick();assert.equal(s.sent.length,0);
        s.relay.accept(packet(),'alice');s.db.exec("INSERT INTO blocked_contacts VALUES('bob','alice')");
        await s.push.tick();assert.equal(s.sent.length,0);
    }finally{s.db.close();}
});
test('APNs invalid token is removed, transient alerts retry, overlapping ticks do not double send',async()=>{
    const s=setup();try{
        s.gateway.send=async()=>({ok:false,retryable:true});s.relay.accept(packet(),'alice');
        await Promise.all([s.push.tick(),s.push.tick()]);assert.equal(s.db.prepare('SELECT attempts FROM push_jobs').get().attempts,1);
        s.gateway.send=async()=>({ok:false,invalidToken:true});s.advance(6000);await s.push.tick();
        assert.equal(s.push.devices('bob')[0].alert_token,null);assert.equal(s.db.prepare('SELECT state FROM push_jobs').get().state,'failed');
    }finally{s.db.close();}
});
test('only saved callers can ring; expiry, recipient, group and session ownership are enforced',()=>{
    const s=setup();try{
        assert.throws(()=>s.calls.accept('mallory',signal(s,'call_offer',crypto.randomUUID(),'mallory')));
        const offer=signal(s);const first=s.calls.accept('alice',offer);assert.equal(first.fresh,true);
        assert.equal(s.calls.accept('alice',offer).fresh,false);assert.equal(s.calls.pending('bob').length,1);
        assert.throws(()=>s.calls.accept('alice',signal(s,'call_offer')));
        assert.throws(()=>s.calls.accept('mallory',signal(s,'call_answer',offer.callId,'mallory','alice')));
        assert.throws(()=>s.calls.accept('alice',signal(s,'call_answer',offer.callId)));
        s.advance(46000);assert.equal(s.calls.pending('bob').length,0);
        assert.throws(()=>s.calls.accept('bob',signal(s,'call_answer',offer.callId,'bob','alice')));
    }finally{s.db.close();}
});
test('accept/reconnect/hangup replay is private and a hangup cancels queued VoIP ringing',async()=>{
    const s=setup();try{
        const offer=signal(s);s.calls.accept('alice',offer);
        s.calls.accept('bob',signal(s,'call_answer',offer.callId,'bob','alice'));
        s.calls.accept('alice',signal(s,'webrtc_offer',offer.callId));
        assert.equal(s.calls.pending('alice')[0].signalType,'call_answer');
        s.calls.accept('alice',signal(s,'call_hangup',offer.callId));
        assert.deepEqual(s.calls.pending('bob').map(x=>x.signalType),['call_hangup']);
        await s.push.tick();assert.equal(s.sent.length,0);
        assert.equal(s.relay.pending('bob').length,0); // Call signals never enter message history/offline queue.
    }finally{s.db.close();}
});
test('VoIP contains encrypted offer, no message alert, and does not retry ambiguous delivery',async()=>{
    const s=setup();try{
        const offer=signal(s);s.calls.accept('alice',offer);await s.push.tick();
        assert.equal(s.sent[0][2].kind,'voip');assert.equal(s.sent[0][1].callId,offer.callId);
        assert.equal(s.sent[0][1].aps.alert,undefined);assert.equal(s.sent[0][1].encryptedPayload,offer.packet.encryptedPayload);
    }finally{s.db.close();}
    const t=setup();try{
        t.gateway.send=async()=>({ok:false,retryable:true});t.calls.accept('alice',signal(t));await t.push.tick();
        assert.equal(t.db.prepare('SELECT state FROM push_jobs').get().state,'failed');
    }finally{t.db.close();}
});
test('APNs uses the device environment, signed JWT, VoIP topic and zero expiry; HTTP errors settle',async()=>{
    const root=fs.mkdtempSync(path.join(os.tmpdir(),'myaow-apns-test-'));
    try {
        const keyPath=path.join(root,'test.p8');fs.writeFileSync(keyPath,crypto.generateKeyPairSync('ec',{namedCurve:'P-256'}).privateKey.export({type:'pkcs8',format:'pem'}));
        let host,headers,body;
        const gateway=new Gateway({teamId:'TEST',keyId:'TESTKEY',bundleId:'test.myaow',keyPath,connect:url=>{
            host=url;const client=new EventEmitter();client.destroy=()=>{};
            client.request=h=>{headers=h;const request=new EventEmitter();request.close=()=>{};
                request.end=b=>{body=b;queueMicrotask(()=>{request.emit('response',{':status':410});request.emit('data',Buffer.from('{"reason":"Unregistered"}'));request.emit('end');});};return request;};return client;
        }});
        const result=await gateway.send({token:'ab'.repeat(32),environment:'production'},{aps:{},callId:crypto.randomUUID()},{kind:'voip'});
        assert.equal(host,'https://api.push.apple.com');assert.equal(headers['apns-topic'],'test.myaow.voip');assert.equal(headers['apns-expiration'],'0');
        assert.equal(headers['apns-push-type'],'voip');assert.equal(headers.authorization.split('.')[2].length,86);assert.equal(result.invalidToken,true);
        assert.equal(JSON.parse(body).aps.alert,undefined);
        await gateway.send({token:'ab'.repeat(32),environment:'sandbox'},{aps:{alert:'Test'}},{expiresAt:999});
        assert.equal(host,'https://api.sandbox.push.apple.com');assert.equal(headers['apns-topic'],'test.myaow');assert.equal(headers['apns-expiration'],'999');
    }finally{fs.rmSync(root,{recursive:true,force:true});}
});
