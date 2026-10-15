'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');
const { betaConfiguration } = require('./beta_configuration');

function fixture(t) {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'myaow-beta-config-'));
    t.after(() => fs.rmSync(root, { recursive: true, force: true }));
    const key = path.join(root, 'key.p8'), secret = path.join(root, 'turn.txt');
    fs.writeFileSync(key, crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' }).privateKey.export({ type: 'pkcs8', format: 'pem' }));
    fs.writeFileSync(secret, crypto.randomBytes(32).toString('hex'));
    return { root, env: { NODE_ENV: 'production', BETA_REGISTRATION_MODE: 'invite', BETA_MAX_USERS: '30',
        MYAOW_DB_PATH: '/data/myaow.db', MYAOW_UPLOADS_DIR: '/data/uploads',
        APNS_TEAM_ID: 'ABCDEFGHIJ', APNS_KEY_ID: '1234567890', APNS_TOPIC: 'com.ScendLabs.Myaow', APNS_KEY_PATH: key,
        TURN_SHARED_SECRET_FILE: secret, TURN_URLS: 'turn:turn.myaow.app:3478?transport=udp,turns:turn.myaow.app:5349?transport=tcp',
        API_DOMAIN: 'api-beta.myaow.app', ACME_EMAIL: 'operator@myaow.app', CADDY_IMAGE: 'caddy:2.10.2' } };
}

test('beta preflight verifies a signing key and credentials without revealing secrets', t => {
    const { env } = fixture(t);
    const result = betaConfiguration(env, { deployment: true });
    assert.equal(result.configured, true);
    const output = JSON.stringify(result);
    for (const privateValue of [env.APNS_TEAM_ID, env.APNS_KEY_ID, env.APNS_KEY_PATH,
        fs.readFileSync(env.APNS_KEY_PATH, 'utf8'), fs.readFileSync(env.TURN_SHARED_SECRET_FILE, 'utf8')]) {
        assert.equal(output.includes(privateValue), false);
    }
    assert.equal(betaConfiguration({ ...env, BETA_REGISTRATION_MODE: 'closed' }).configured, true);
});

test('beta preflight rejects invalid Apple keys, identities and unsafe deployment values', t => {
    const { env } = fixture(t);
    for (const overrides of [
        { APNS_TEAM_ID: 'REPLACE' }, { APNS_KEY_ID: '' }, { APNS_TOPIC: 'other.application' },
        { BETA_REGISTRATION_MODE: 'open' }, { BETA_MAX_USERS: '0' }, { BETA_MAX_USERS: '31' }, { BETA_MAX_USERS: 'NaN' },
        { NODE_ENV: 'development' }, { MYAOW_DB_PATH: '/tmp/myaow.db' }, { MYAOW_UPLOADS_DIR: '/data/../tmp' },
        { API_DOMAIN: 'api-beta.example.com' }, { API_DOMAIN: 'https://myaow.app' }, { API_DOMAIN: '127.0.0.1' },
        { ACME_EMAIL: 'operator@example.com' }, { CADDY_IMAGE: 'caddy:2' },
        { TURN_URLS: 'turns:turn.example.com:5349' }, { TURN_URLS: 'turns:turn.myaow.app:99999' },
        { TURN_URLS: 'turns:turn.myaow.app:5349?transport=udp' }, { TURN_URLS: 'turn:turn.myaow.app:3478' },
    ]) assert.equal(betaConfiguration({ ...env, ...overrides }, { deployment: true }).configured, false, Object.keys(overrides).join());
    for (const content of ['not a private key', crypto.generateKeyPairSync('ec', { namedCurve: 'secp384r1' }).privateKey.export({ type: 'pkcs8', format: 'pem' })]) {
        fs.writeFileSync(env.APNS_KEY_PATH, content);
        assert.equal(betaConfiguration(env).checks.find(check => check.id === 'apns_signing_key').ready, false);
    }
});

test('deployment file is parsed without executing shell text or inheriting missing secrets', t => {
    const { env, root } = fixture(t);
    const file = path.join(root, '.env.beta');
    const values = { ...env, APNS_KEY_FILE: env.APNS_KEY_PATH, TURN_SECRET_FILE: env.TURN_SHARED_SECRET_FILE };
    delete values.APNS_KEY_PATH; delete values.TURN_SHARED_SECRET_FILE;
    const write = data => fs.writeFileSync(file, Object.entries(data).map(([k, v]) => `${k}=${v}`).join('\n'));
    const run = () => spawnSync(process.execPath, [path.join(__dirname, 'check_beta_configuration.js'), '--env', file], { env: { ...process.env, ...env }, encoding: 'utf8' });
    write(values);
    assert.equal(run().status, 0);
    delete values.APNS_KEY_ID; write(values);
    const missing = run(); assert.equal(missing.status, 1);
    assert.equal(JSON.parse(missing.stdout).checks.find(check => check.id === 'apns_identifiers').ready, false);
    values.APNS_KEY_ID = '1234567890';
    values.API_DOMAIN = '$(touch ' + path.join(root, 'must-not-exist') + ')'; write(values);
    assert.equal(run().status, 1); assert.equal(fs.existsSync(path.join(root, 'must-not-exist')), false);
});

test('beta entry point exits before creating a database when configuration is incomplete', t => {
    const { root } = fixture(t);
    const result = spawnSync(process.execPath, [path.join(__dirname, 'start_beta.js')], {
        cwd: root, env: { NODE_ENV: 'production', MYAOW_DB_PATH: path.join(root, 'must-not-exist.db') }, encoding: 'utf8', timeout: 5000
    });
    assert.equal(result.status, 1);
    assert.equal(JSON.parse(result.stderr).error, 'BetaConfigurationIncomplete');
    assert.equal(fs.existsSync(path.join(root, 'must-not-exist.db')), false);
});
