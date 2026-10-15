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

test('registration works without an APNs token and returns the same identifier', async () => {
    const result = await register(profile('MYAOW-TEST01', 'alice_test'));
    assert.equal(result.status, 200);
    assert.equal(result.body.myaowId, 'MYAOW-TEST01');
});
test('availability is case insensitive and reflects a registered name', async () => {
    const result = await fetch(`${origin}/api/v1/directory/check-username/ALICE_TEST`);
    assert.equal((await result.json()).available, false);
});
test('duplicate username returns actionable conflict and preserves the owner', async () => {
    const result = await register(profile('MYAOW-TEST02', 'alice_test'));
    assert.equal(result.status, 409);
    const session = await connect('MYAOW-TEST01');
    try {
        const found = await fetch(`${origin}/api/v1/directory/lookup?username=alice_test`, { headers: { Authorization: `Bearer ${session.response.sessionId}` } });
        assert.equal((await found.json()).myaowId, 'MYAOW-TEST01');
    } finally { session.ws.close(); }
});
test('invalid handles are rejected by both availability and registration', async () => {
    for (const username of ['ab', 'bad/name', 'álex', 'a'.repeat(31), 'bad name']) {
        assert.equal((await register(profile('MYAOW-TEST03', username))).status, 400);
        assert.equal((await fetch(`${origin}/api/v1/directory/check-username/${encodeURIComponent(username)}`)).status, 400);
    }
});
test('malformed URL encoding returns 400 and does not crash server', async () => {
    assert.equal((await fetch(`${origin}/api/v1/directory/check-username/%E0%A4%A`)).status, 400);
    assert.equal((await fetch(`${origin}/health`)).status, 200);
});
test('retry is idempotent and another key cannot overwrite an identifier', async () => {
    assert.equal((await register(profile('MYAOW-TEST01', 'alice_test'))).status, 200);
    const result = await register({ ...profile('MYAOW-TEST01', 'other_name'), identityKeyHex: '33'.repeat(32) });
    assert.equal(result.status, 409);
});
test('automatic ID works when no custom handle is selected', async () => {
    assert.equal((await register(profile('MYAOW-TEST04', undefined))).status, 200);
});
test('relay delivers a message between two connected test identities', async () => {
    await register(profile('MYAOW-TEST05', 'bob_test'));
    const alice = await connect('MYAOW-TEST01');
    const bob = await connect('MYAOW-TEST05');
    try {
        assert.equal(alice.response.type, 'auth_ack');
        assert.equal(bob.response.type, 'auth_ack');
        const packet = securePacket('MYAOW-TEST01', 'MYAOW-TEST05');
        const delivery = receive(bob.ws, m => m.id === packet.id);
        alice.ws.send(JSON.stringify(packet));
        assert.equal((await delivery).encryptedPayload, packet.encryptedPayload);
        bob.ws.send(JSON.stringify({ type: 'message_received', messageId: packet.id, originalSenderId: 'MYAOW-TEST01' }));
    } finally { alice.ws.close(); bob.ws.close(); }
});
test('invalid proof cannot authenticate a registered identity', async () => {
    const session = await connect('MYAOW-TEST01', false);
    try {
        assert.equal(session.response.type, 'auth_error');
    } finally { session.ws.close(); }
});

test('public directory information cannot authorize a profile update', async () => {
    const update = { ...profile('MYAOW-TEST01', 'alice_test'), displayName: 'Changed without a credential' };
    assert.equal((await register(update)).status, 401);
    const session = await connect('MYAOW-TEST01');
    try { assert.equal((await register(update, session.response.sessionId)).status, 200); }
    finally { session.ws.close(); }
});
test('unauthenticated socket cannot send application traffic or register a fallback identity', async () => {
    const ws = new WebSocket(socketURL);
    await new Promise(resolve => ws.once('open', resolve));
    try {
        let result = receive(ws, m => m.type === 'auth_error');
        ws.send(JSON.stringify({ type: 'message', senderMyaowId: 'MYAOW-TEST01', recipientMyaowId: 'MYAOW-TEST05', text: 'unauthenticated' }));
        assert.equal((await result).type, 'auth_error');
        result = receive(ws, m => m.type === 'auth_error');
        ws.send(JSON.stringify({ type: 'auth', myaowId: 'MYAOW-UNKNOWN' }));
        assert.equal((await result).type, 'auth_error');
        assert.equal((await fetch(`${origin}/api/v1/directory/lookup?username=myaow-unknown`)).status, 401);
    } finally { ws.close(); }
});
test('a proof is bound to the challenge identity and expires', () => {
    const challenge = createChallenge('MYAOW-TEST01', profile('MYAOW-TEST01', 'alice_test').identityKeyHex);
    const proof = makeProof('MYAOW-TEST01', challenge);
    assert.equal(verifyProof(challenge, 'MYAOW-TEST01', proof), true);
    assert.equal(verifyProof(challenge, 'MYAOW-TEST05', proof), false);
    assert.equal(verifyProof({ ...challenge, expiresAt: Date.now() - 1 }, 'MYAOW-TEST01', proof), false);
    assert.equal(verifyProof(challenge, 'MYAOW-TEST01', 'xx'.repeat(32)), false);
});
test('failed proof consumes the challenge and cannot be retried with a replay', async () => {
    const ws = new WebSocket(socketURL);
    await new Promise(resolve => ws.once('open', resolve));
    try {
        const challengePromise = receive(ws, m => m.type === 'auth_challenge');
        ws.send(JSON.stringify({ type: 'auth', myaowId: 'MYAOW-TEST01' }));
        const challenge = await challengePromise;
        let error = receive(ws, m => m.type === 'auth_error');
        ws.send(JSON.stringify({ type: 'auth_response', myaowId: 'MYAOW-TEST01', proof: '00'.repeat(32) }));
        await error;
        error = receive(ws, m => m.type === 'auth_error');
        ws.send(JSON.stringify({ type: 'auth_response', myaowId: 'MYAOW-TEST01', proof: makeProof('MYAOW-TEST01', challenge) }));
        await error;
    } finally { ws.close(); }
});
// Opaque envelope fixtures exercise relay validation; CryptoKit checks authenticate the ciphertext separately.
function securePacket(sender, recipient, id = crypto.randomUUID()) {
    return { id, type: 'message', recipientMyaowId: recipient, senderMyaowId: sender,
        encryptedPayload: JSON.stringify({ version: 2, messageId: id, senderId: sender, recipientId: recipient,
            senderPublicKey: profile(sender, '').identityKeyHex,
            encapsulatedKey: crypto.randomBytes(32).toString('base64'), ciphertext: crypto.randomBytes(40).toString('base64') }) };
}
test('relay binds identity, strips plaintext and waits for recipient persistence before delivery', async () => {
    const alice = await connect('MYAOW-TEST01');
    const bob = await connect('MYAOW-TEST05');
    try {
        const packet = securePacket('MYAOW-TEST01', 'MYAOW-TEST05');
        const accepted = receive(alice.ws, m => m.type === 'delivery_ack' && m.messageId === packet.id);
        const delivered = receive(bob.ws, m => m.id === packet.id);
        alice.ws.send(JSON.stringify({ ...packet, senderMyaowId: 'MYAOW-TEST04', senderDisplayName: 'Forged', text: 'Must never be relayed', mediaUrl: 'secret' }));
        assert.equal((await accepted).status, 'queued_on_server');
        const wire = await delivered;
        assert.equal(wire.senderMyaowId, 'MYAOW-TEST01');
        assert.equal(wire.mediaUrl, undefined);
        assert.equal(wire.text, 'Mensaje protegido');
        const ack = receive(alice.ws, m => m.type === 'delivery_ack' && m.status === 'delivered');
        bob.ws.send(JSON.stringify({ type: 'message_received', messageId: packet.id, originalSenderId: 'MYAOW-TEST01' }));
        assert.equal((await ack).messageId, packet.id);
        const forbidden = receive(alice.ws, m => m.type === 'error');
        alice.ws.send(JSON.stringify({ type: 'group_message', groupId: 'not-a-member' }));
        assert.equal((await forbidden).message, 'Use encrypted group delivery');
    } finally { alice.ws.close(); bob.ws.close(); }
});
test('recipient disconnect before saving preserves the message and duplicate sends stay idempotent', async () => {
    const alice = await connect('MYAOW-TEST01');
    let bob = await connect('MYAOW-TEST05');
    const packet = securePacket('MYAOW-TEST01', 'MYAOW-TEST05');
    try {
        let incoming = receive(bob.ws, m => m.id === packet.id);
        alice.ws.send(JSON.stringify(packet));
        await incoming;
        await new Promise(resolve => { bob.ws.once('close', resolve); bob.ws.close(); });
        bob = await connect('MYAOW-TEST05');
        await new Promise(resolve => setTimeout(resolve, 100));
        assert.equal(bob.received.filter(m => m.id === packet.id).length, 1);
        const accepted = receive(alice.ws, m => m.type === 'delivery_ack' && m.messageId === packet.id);
        alice.ws.send(JSON.stringify(packet));
        assert.equal((await accepted).status, 'queued_on_server');
        // A sender cannot acknowledge its own packet on the recipient's behalf.
        alice.ws.send(JSON.stringify({ type: 'message_received', messageId: packet.id, originalSenderId: 'MYAOW-TEST01' }));
        const ack = receive(alice.ws, m => m.status === 'delivered' && m.messageId === packet.id);
        bob.ws.send(JSON.stringify({ type: 'message_received', messageId: packet.id, originalSenderId: 'MYAOW-TEST01' }));
        await ack;
        await new Promise(resolve => { bob.ws.once('close', resolve); bob.ws.close(); });
        bob = await connect('MYAOW-TEST05');
        await new Promise(resolve => setTimeout(resolve, 100));
        assert.equal(bob.received.filter(m => m.id === packet.id).length, 0);
        const duplicate = receive(alice.ws, m => m.type === 'delivery_ack' && m.messageId === packet.id);
        alice.ws.send(JSON.stringify(packet));
        assert.equal((await duplicate).status, 'delivered');
    } finally { alice.ws.close(); bob.ws.close(); }
});
test('plaintext, mismatched envelope identity and reused identifiers are rejected', async () => {
    const alice = await connect('MYAOW-TEST01');
    try {
        const packet = securePacket('MYAOW-TEST01', 'MYAOW-TEST05');
        for (const invalid of [ { ...packet, encryptedPayload: undefined, text: 'plain' },
            { ...securePacket('MYAOW-TEST05', 'MYAOW-TEST01') } ]) {
            const failure = receive(alice.ws, m => m.type === 'message_error');
            alice.ws.send(JSON.stringify(invalid));
            await failure;
        }
        const accepted = receive(alice.ws, m => m.type === 'delivery_ack' && m.messageId === packet.id);
        alice.ws.send(JSON.stringify(packet)); await accepted;
        const failure = receive(alice.ws, m => m.type === 'message_error');
        alice.ws.send(JSON.stringify(securePacket('MYAOW-TEST01', 'MYAOW-TEST05', packet.id)));
        assert.match((await failure).message, /identifier/);
    } finally { alice.ws.close(); }
});
