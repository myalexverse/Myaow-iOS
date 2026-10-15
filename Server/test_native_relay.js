const { test } = require('node:test');
const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const { mkdtempSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const path = require('node:path');
const net = require('node:net');

test('native Swift client interoperates with an isolated relay', { timeout: 60000 }, async () => {
    assert.ok(process.env.MYAOW_NATIVE_CHECKS, 'Set MYAOW_NATIVE_CHECKS to the compiled NativeRelayChecks binary');
    const temp = mkdtempSync(path.join(tmpdir(), 'myaow-native-relay-'));
    const probe = net.createServer();
    await new Promise(resolve => probe.listen(0, '127.0.0.1', resolve));
    const port = probe.address().port;
    await new Promise(resolve => probe.close(resolve));
    const origin = `http://127.0.0.1:${port}`;
    const server = spawn(process.execPath, [path.join(__dirname, 'server.js')], {
        cwd: temp,
        env: { PATH: process.env.PATH, HOME: temp, HOST: '127.0.0.1', PORT: String(port),
            MYAOW_DB_PATH: path.join(temp, 'test.db'), MYAOW_UPLOADS_DIR: path.join(temp, 'uploads') },
        stdio: ['ignore', 'pipe', 'pipe']
    });
    let serverLog = '';
    server.stdout.on('data', value => { serverLog += value; });
    server.stderr.on('data', value => { serverLog += value; });
    try {
        let ready = false;
        for (let i = 0; i < 60; i++) {
            if (server.exitCode !== null) throw new Error(serverLog);
            try { if ((await fetch(`${origin}/health`)).ok) { ready = true; break; } } catch {}
            await new Promise(resolve => setTimeout(resolve, 100));
        }
        assert.ok(ready, serverLog);
        const native = spawn(process.env.MYAOW_NATIVE_CHECKS, [origin], { timeout: 45000, stdio: ['ignore', 'pipe', 'pipe'] });
        let output = '';
        native.stdout.on('data', value => { output += value; });
        native.stderr.on('data', value => { output += value; });
        const code = await new Promise((resolve, reject) => { native.once('error', reject); native.once('exit', resolve); });
        assert.equal(code, 0, output + '\n' + serverLog);
        assert.match(output, /PASS:/);
        console.log(output.trim());
    } finally {
        if (server.exitCode === null) {
            const closed = new Promise(resolve => server.once('exit', resolve));
            server.kill(); await closed;
        }
        rmSync(temp, { recursive: true, force: true });
    }
});
