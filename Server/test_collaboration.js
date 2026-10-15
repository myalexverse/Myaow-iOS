const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const { mkdtempSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const path = require('node:path');
const net = require('node:net');
const crypto = require('node:crypto');
const { createChallenge, verifyProof } = require('./relay_auth');
const identities = new Map();
function identity(id) {
    if (!identities.has(id)) identities.set(id, crypto.generateKeyPairSync('x25519'));
    return identities.get(id);
}
function makeProof(id, challenge) {
    const pair = identity(id);
    const peer = crypto.createPublicKey({ format: 'jwk', key: { kty: 'OKP', crv: 'X25519', x: Buffer.from(challenge.serverPublicKeyHex, 'hex').toString('base64url') } });
    const ownHex = Buffer.from(pair.publicKey.export({ format: 'jwk' }).x, 'base64url').toString('hex');
    const context = Buffer.from(['MYAOW-AUTH-V2', id, challenge.nonce, challenge.serverPublicKeyHex, ownHex].join('\0'));
    const secret = crypto.diffieHellman({ privateKey: pair.privateKey, publicKey: peer });
    const key = crypto.hkdfSync('sha256', secret, Buffer.from(challenge.nonce), context, 32);
    return crypto.createHmac('sha256', key).update(context).digest('hex');
}
const { WebSocket } = require('ws');

let server, origin, socketURL, temp;
const profile = (id, username) => ({ myaowId: id, username, displayName: 'Persona de prueba', identityKeyHex: Buffer.from(identity(id).publicKey.export({ format: 'jwk' }).x, 'base64url').toString('hex'), signedPrekeyHex: '22'.repeat(32), oneTimePrekeys: [] });
async function register(body, token) {
    const response = await fetch(`${origin}/api/v1/directory/register`, { method: 'POST', headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) }, body: JSON.stringify(body) });
    return { status: response.status, body: await response.json() };
}
async function receive(ws, predicate) {
    return new Promise((resolve, reject) => {
        const timer = setTimeout(() => { ws.off('message', listener); reject(new Error('WebSocket timeout')); }, 3000);
        function listener(data) {
            const message = JSON.parse(data.toString());
            if (predicate(message)) { clearTimeout(timer); ws.off('message', listener); resolve(message); }
        }
        ws.on('message', listener);
    });
}
async function connect(id, valid = true) {
    const ws = new WebSocket(socketURL);
    const received = [];
    ws.on("message", data => received.push(JSON.parse(data.toString())));
    await new Promise((resolve, reject) => { ws.once('open', resolve); ws.once('error', reject); });
    const challenge = receive(ws, m => m.type === 'auth_challenge');
    ws.send(JSON.stringify({ type: 'auth', myaowId: id }));
    const challengeValue = await challenge;
    const ack = receive(ws, m => m.type === 'auth_ack' || m.type === 'auth_error');
    ws.send(JSON.stringify({ type: 'auth_response', myaowId: id, proof: valid ? makeProof(id, challengeValue) : '00'.repeat(32), displayName: 'Prueba' }));
    const response = await ack;
    return { ws, response, received };
}
before(async () => {
    temp = mkdtempSync(path.join(tmpdir(), 'myaow-registration-'));
    const probe = net.createServer();
    await new Promise(resolve => probe.listen(0, '127.0.0.1', resolve));
    const port = probe.address().port;
    await new Promise(resolve => probe.close(resolve));
    origin = `http://127.0.0.1:${port}`;
    socketURL = `ws://127.0.0.1:${port}/ws`;
    server = spawn(process.execPath, [path.join(__dirname, 'server.js')], {
        cwd: temp,
        env: { PATH: process.env.PATH, HOME: temp, HOST: '127.0.0.1', PORT: String(port), MYAOW_DB_PATH: path.join(temp, 'test.db'), MYAOW_UPLOADS_DIR: path.join(temp, 'uploads') },
        stdio: ['ignore', 'pipe', 'pipe']
    });
    let logs = '';
    server.stdout.on('data', data => { logs += data; });
    server.stderr.on('data', data => { logs += data; });
    for (let i = 0; i < 60; i++) {
        if (server.exitCode !== null) throw new Error(logs);
        try { if ((await fetch(`${origin}/health`)).ok) return; } catch {}
        await new Promise(resolve => setTimeout(resolve, 100));
    }
    throw new Error(`Server did not start: ${logs}`);
});
after(async () => {
    if (server && server.exitCode === null) {
        const closed = new Promise(resolve => server.once('exit', resolve));
        server.kill();
        await closed;
    }
    if (temp) rmSync(temp, { recursive: true, force: true });
});

function securePacket(sender, recipient, id = crypto.randomUUID()) {
    return { id, type: 'message', recipientMyaowId: recipient, senderMyaowId: sender,
        encryptedPayload: JSON.stringify({ version: 2, messageId: id, senderId: sender, recipientId: recipient,
            senderPublicKey: profile(sender, '').identityKeyHex,
            encapsulatedKey: crypto.randomBytes(32).toString('base64'), ciphertext: crypto.randomBytes(40).toString('base64') }) };
}
test('privacy, invitations, task persistence and encrypted group scheduling use authenticated contracts', async () => {
    for (const [id, name] of [['MYAOW-ALICE','alice_collab'], ['MYAOW-BOB01','bob_collab'], ['MYAOW-MALLORY','mallory_collab']]) assert.equal((await register(profile(id,name))).status,200);
    const alice = await connect('MYAOW-ALICE'), bob = await connect('MYAOW-BOB01'), mallory = await connect('MYAOW-MALLORY');
    const api = async (actor, route, method='GET', data) => {
        const response = await fetch(origin+'/api/v1/'+route,{method,headers:{'Content-Type':'application/json', ...(actor ? {Authorization:`Bearer ${actor.response.sessionId}`} : {})},body:data ? JSON.stringify(data):undefined});
        return {status:response.status,body:await response.text().then(x=>{try{return JSON.parse(x)}catch{return x}})};
    };
    try {
        for (const route of ['presence/online','presence/status/MYAOW-ALICE','directory/search?q=alice_collab','directory/lookup?username=alice_collab','profile/MYAOW-ALICE','scheduled-v2','groups/my/MYAOW-ALICE','push/device','calls/signal','webrtc/ice-servers']) assert.equal((await api(null,route)).status,401,route);
        assert.equal((await api(alice,'webrtc/ice-servers')).status,503);
        const device={installation:crypto.randomUUID(),environment:'sandbox',alertToken:null,voipToken:null,callers:['MYAOW-ALICE']};
        assert.equal((await api(bob,'push/device','PUT',device)).status,200);
        const callId=crypto.randomUUID();
        const signal={callId,signalType:'call_offer',expiresAt:Date.now()/1000+90,packet:securePacket('MYAOW-ALICE','MYAOW-BOB01')};
        assert.equal((await api(mallory,'calls/signal','POST',signal)).status,409);
        assert.equal((await api(alice,'calls/signal','POST',signal)).status,200);
        assert.equal((await api(alice,'calls/signal','POST',signal)).status,200);
        assert.equal((await api(alice,'calls/signal','POST',{...signal,signalType:'call_hangup',packet:securePacket('MYAOW-ALICE','MYAOW-BOB01')})).status,200);
        assert.deepEqual((await api(alice,'presence/online')).body.online,['MYAOW-ALICE']);
        assert.equal((await api(alice,'presence/status/MYAOW-BOB01')).status,403);
        assert.deepEqual((await api(alice,'directory/search?q=')).body.results,[]);
        assert.deepEqual((await api(alice,'directory/search?q=collab')).body.results,[]);
        assert.equal((await api(alice,'directory/search?q=bob_collab')).body.results[0].isOnline,false);
        const created = await api(alice,'groups/create','POST',{name:'Proyecto',category:'General'});
        assert.equal(created.status,200);
        const group = created.body.groupId;
        assert.equal((await api(bob,`groups/${group}/join`,'POST',{})).status,403);
        assert.equal((await api(bob,`groups/${group}/members`)).status,403);
        assert.equal((await api(bob,'groups/invite/create','POST',{groupId:group,target:'mallory_collab'})).status,403);
        const invitation = await api(alice,'groups/invite/create','POST',{groupId:group,target:'bob_collab'});
        assert.equal(invitation.status,200);
        assert.equal((await api(mallory,'groups/invite/accept','POST',{token:invitation.body.token})).status,400);
        assert.equal((await api(bob,'groups/invite/accept','POST',{token:invitation.body.token})).status,200);
        assert.equal((await api(bob,'groups/invite/accept','POST',{token:invitation.body.token})).status,400);
        assert.equal((await api(bob,`groups/${group}/members`)).body.members.length,2);
        assert.equal((await api(alice,`groups/${group}/leave`,'POST',{})).status,409);
        assert.equal((await api(alice,`groups/${group}/tasks`,'POST',{title:'Incorrecta',assigneeMyaowId:'MYAOW-MALLORY'})).status,400);
        const id = crypto.randomUUID();
        const payload={id,title:'Preparar la beta',assigneeMyaowId:'MYAOW-BOB01',assigneeName:'Forged',priority:'Importante',dueLabel:'Hoy'};
        const task = await api(alice,`groups/${group}/tasks`,'POST',payload);
        assert.equal(task.status,200); assert.equal(task.body.task.assignee_name,'Persona de prueba');
        assert.equal((await api(alice,`groups/${group}/tasks`,'POST',payload)).body.task.id,id);
        assert.equal((await api(mallory,`tasks/${id}/complete`,'PUT',{completed:true})).status,403);
        assert.equal((await api(bob,`tasks/${id}/complete`,'PUT',{completed:true})).body.task.is_completed,1);
        assert.equal((await api(alice,`groups/${group}/tasks`)).body.tasks[0].completed_by_myaow_id,'MYAOW-BOB01');
        assert.equal((await api(bob,`tasks/${id}/complete`,'PUT',{completed:false})).body.task.is_completed,0);
        // Open and administrator-only policies apply to every task mutation, including existing tasks.
        const sharedID = crypto.randomUUID();
        assert.equal((await api(alice,`groups/${group}/tasks`,'POST',{id:sharedID,title:'Shared task'})).status,200);
        assert.equal((await api(bob,`tasks/${sharedID}/complete`,'PUT',{progress:33})).status,403);
        assert.equal((await api(bob,`groups/${group}/info`,'PUT',{taskPolicy:'open'})).status,403);
        assert.equal((await api(alice,`groups/${group}/info`,'PUT',{taskPolicy:'open'})).status,200);
        assert.equal((await api(bob,`tasks/${sharedID}/complete`,'PUT',{progress:33})).body.task.progress,33);
        assert.equal((await api(bob,`tasks/${sharedID}/complete`,'PUT',{progress:101})).status,400);
        assert.equal((await api(bob,`tasks/${sharedID}/complete`,'PUT',{progress:100})).body.task.is_completed,1);
        assert.equal((await api(bob,`tasks/${sharedID}`,'DELETE')).status,403);
        assert.equal((await api(alice,`groups/${group}/info`,'PUT',{taskPolicy:'admins'})).status,200);
        assert.equal((await api(bob,`tasks/${id}/complete`,'PUT',{progress:75})).status,403);
        assert.equal((await api(bob,`groups/${group}/tasks`,'POST',{title:'Forbidden'})).status,403);
        assert.equal((await api(alice,`tasks/${sharedID}/complete`,'PUT',{progress:67})).body.task.progress,67);
        assert.equal((await api(alice,`groups/${group}/tasks`)).body.task_policy,'admins');
        assert.equal((await api(alice,'groups/my/MYAOW-ALICE')).body.groups.find(g=>g.id===group).task_policy,'admins');
        assert.equal((await api(alice,`groups/${group}/info`,'PUT',{taskPolicy:'invalid'})).status,400);
        assert.equal((await api(alice,`groups/${group}/info`,'PUT',{taskPolicy:'assigned'})).status,200);
        const openGroup = await api(alice,'groups/create','POST',{name:'Open project',taskPolicy:'open'});
        assert.equal(openGroup.status,200);
        assert.equal((await api(alice,'groups/my/MYAOW-ALICE')).body.groups.find(g=>g.id===openGroup.body.groupId).task_policy,'open');
        const packet=securePacket('MYAOW-ALICE','MYAOW-BOB01');
        packet.encryptedPayload=JSON.stringify({...JSON.parse(packet.encryptedPayload),groupId:group});
        assert.equal((await api(alice,'messages-v2/batch','POST',{packets:[packet]})).status,200);
        assert.equal((await api(alice,'messages-v2/batch','POST',{packets:[packet]})).status,200);
        const schedule={id:crypto.randomUUID(),due:Date.now()+60000,preview:crypto.randomBytes(64).toString('base64'),packets:[securePacket('MYAOW-ALICE','MYAOW-BOB01')]};
        assert.equal((await api(alice,'scheduled-v2','POST',schedule)).status,200);
        assert.equal((await api(alice,'scheduled-v2','POST',schedule)).status,200);
        assert.equal((await api(bob,'scheduled-v2')).body.messages.length,0);
        assert.equal((await api(bob,`scheduled-v2/${schedule.id}`,'DELETE')).status,409);
        assert.equal((await api(alice,'scheduled-v2')).body.messages.length,1);
        assert.equal((await api(alice,`scheduled-v2/${schedule.id}`,'DELETE')).status,200);
        assert.equal((await api(alice,'scheduled-v2')).body.messages.length,0);
        assert.equal((await api(bob,`tasks/${id}`,'DELETE')).status,403);
        assert.equal((await api(alice,`tasks/${id}`,'DELETE')).status,200);
    } finally { alice.ws.close();bob.ws.close();mallory.ws.close(); }
});
