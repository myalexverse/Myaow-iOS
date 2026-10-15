const { test } = require('node:test');
const assert = require('node:assert/strict');
const Database = require('better-sqlite3');
const crypto = require('node:crypto');
const { mkdtempSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const path = require('node:path');
const { DurableRelay } = require('./durable_relay');
const { authorizeRoute } = require('./access_control');

function setup(file = ':memory:') {
    const db = new Database(file);
    db.exec(`CREATE TABLE IF NOT EXISTS users(myaow_id TEXT PRIMARY KEY, identity_key_hex TEXT);
        CREATE TABLE IF NOT EXISTS blocked_contacts(blocker_id TEXT, blocked_id TEXT);
        CREATE TABLE IF NOT EXISTS sessions(session_id TEXT, myaow_id TEXT);
        CREATE TABLE IF NOT EXISTS group_members(group_id TEXT, myaow_id TEXT, role TEXT);
        CREATE TABLE IF NOT EXISTS groups(id TEXT, task_policy TEXT DEFAULT 'assigned');
        CREATE TABLE IF NOT EXISTS group_tasks(id TEXT, group_id TEXT, created_by_myaow_id TEXT, assignee_myaow_id TEXT);
        CREATE TABLE IF NOT EXISTS scheduled_messages(id TEXT, sender_myaow_id TEXT);
        CREATE TABLE IF NOT EXISTS moments(id TEXT, author_id TEXT);`);
    for (const name of ['alice', 'bob', 'mallory']) db.prepare('INSERT OR IGNORE INTO users VALUES (?,?)').run(name, '11'.repeat(32));
    return db;
}
function packet(id = crypto.randomUUID()) {
    return { type: 'message', id, recipientMyaowId: 'bob', encryptedPayload: JSON.stringify({
        version: 2, messageId: id, senderId: 'alice', recipientId: 'bob', senderPublicKey: '11'.repeat(32),
        encapsulatedKey: Buffer.alloc(32, 1).toString('base64'), ciphertext: Buffer.alloc(40, 2).toString('base64')
    }) };
}
test('server restart preserves unacknowledged messages and delivered tombstones', () => {
    const root = mkdtempSync(path.join(tmpdir(), 'myaow-durable-'));
    let db;
    try {
        const file = path.join(root, 'relay.db');
        db = setup(file);
        const input = packet();
        new DurableRelay(db).accept(input, 'alice');
        db.close(); db = setup(file);
        const relay = new DurableRelay(db);
        assert.equal(relay.pending('bob')[0].id, input.id);
        assert.equal(relay.acknowledge('mallory', 'alice', input.id), false);
        assert.equal(relay.pending('bob').length, 1);
        assert.equal(relay.acknowledge('bob', 'alice', input.id), true);
        db.close(); db = setup(file);
        const restarted = new DurableRelay(db);
        assert.equal(restarted.pending('bob').length, 0);
        assert.equal(restarted.accept(input, 'alice').status, 'delivered');
    } finally { db?.close(); rmSync(root, { recursive: true, force: true }); }
});
test('replay batches are bounded and acknowledging frees the next batch', () => {
    const db = setup();
    try {
        const relay = new DurableRelay(db);
        for (let i = 0; i < 123; i++) relay.accept(packet(), 'alice');
        assert.equal(relay.pending('bob').length, 50);
        for (const item of relay.pending('bob')) relay.acknowledge('bob', 'alice', item.id);
        assert.equal(relay.pending('bob').length, 50);
        for (const item of relay.pending('bob')) relay.acknowledge('bob', 'alice', item.id);
        assert.equal(relay.pending('bob').length, 23);
    } finally { db.close(); }
});
test('blocked recipients, unknown users, downgrade and changed ciphertext are rejected', () => {
    const db = setup();
    try {
        const relay = new DurableRelay(db);
        const input = packet(); relay.accept(input, 'alice');
        assert.throws(() => relay.accept({ ...input, encryptedPayload: input.encryptedPayload.replace('AgIC', 'AwMD') }, 'alice'));
        assert.throws(() => relay.accept({ ...packet(), recipientMyaowId: 'unknown' }, 'alice'));
        assert.throws(() => relay.accept({ ...packet(), encryptedPayload: '{}' }, 'alice'));
        db.prepare('INSERT INTO blocked_contacts VALUES (?,?)').run('bob', 'alice');
        assert.throws(() => relay.accept(packet(), 'alice'));
    } finally { db.close(); }
});
test('resource ownership cannot be supplied by another authenticated user', () => {
    const db = setup();
    try {
        db.exec(`INSERT INTO sessions VALUES('session-bob','bob');
            INSERT INTO group_members VALUES('group','bob','admin'),('group','alice','member');
            INSERT INTO groups(id) VALUES('group');
            INSERT INTO group_tasks(id,group_id,created_by_myaow_id) VALUES('task','group','bob');
            INSERT INTO moments VALUES('moment','bob');
            INSERT INTO scheduled_messages VALUES('scheduled','bob');`);
        const alice = { myaow_id: 'alice' };
        for (const [route, method] of [['sessions/bob','GET'], ['sessions/session-bob','DELETE'],
            ['groups/group/kick','POST'], ['groups/my/bob','GET'], ['contacts/blocked/bob','GET'],
            ['tasks/task','DELETE'], ['moments/moment','DELETE'], ['scheduled/scheduled','DELETE']]) {
            assert.equal(authorizeRoute(db, '/api/v1/' + route, method, alice), 403, route);
        }
        assert.equal(authorizeRoute(db, '/api/v1/groups/group/members', 'GET', null), 401);
        assert.equal(authorizeRoute(db, '/api/v1/groups/group/members', 'GET', alice), 200);
        assert.equal(authorizeRoute(db, '/api/v1/groups/group/join', 'POST', { myaow_id: 'mallory' }), 403);
        assert.equal(authorizeRoute(db, '/api/v1/groups/group/kick', 'POST', { myaow_id: 'bob' }), 200);
        assert.equal(authorizeRoute(db, '/api/v1/scheduled/create', 'POST', alice), 409);
    } finally { db.close(); }
});
test('a block or group removal also prevents replay of already queued messages', () => {
    const db = setup();
    try {
        const relay = new DurableRelay(db), input = packet();
        relay.accept(input, 'alice');
        db.exec("INSERT INTO blocked_contacts VALUES('alice','bob')");
        assert.equal(relay.pending('bob').length, 0);
        db.exec('DELETE FROM blocked_contacts');
        assert.equal(relay.pending('bob').length, 1);
        relay.acknowledge('bob','alice',input.id);
        db.exec("INSERT INTO group_members VALUES('g','alice','admin'),('g','bob','member')");
        const grouped = packet(); grouped.encryptedPayload = JSON.stringify({...JSON.parse(grouped.encryptedPayload), groupId:'g'});
        relay.accept(grouped,'alice'); assert.equal(relay.pending('bob').length,1);
        db.exec("DELETE FROM group_members WHERE myaow_id='bob'");
        assert.equal(relay.pending('bob').length,0);
    } finally { db.close(); }
});
