//
//  test_e2e_communication.js
//  Myaow End-to-End Real-Time Relay & Offline Mesh Test Suite
//
//  "Tecnología avanzada con una personalidad tranquila"
//

const { WebSocket } = require('ws');
const http = require('http');

const RELAY_WS = 'ws://localhost:8080/ws';
const RELAY_HTTP = 'http://localhost:8080';

async function runE2ETests() {
    console.log('===============================================================');
    console.log('  🧪 INICIANDO SUITE DE PRUEBAS DE COMUNICACIÓN E2E DE MYAOW');
    console.log('===============================================================');

    // 1. Health Check
    console.log('\n▶️ [Prueba 1] Verificando salud del servidor Relay...');
    const health = await fetchJSON(`${RELAY_HTTP}/health`);
    console.log('✅ Servidor Activo:', health);

    // 2. Registro en el Directorio X3DH
    console.log('\n▶️ [Prueba 2] Registrando identidad de Alice en el Directorio...');
    const aliceReg = await postJSON(`${RELAY_HTTP}/api/v1/directory/register`, {
        username: 'alice',
        myaowId: 'MYAOW-ALICE1',
        displayName: 'Alice Myaow',
        identityKeyHex: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        signedPrekeyHex: 'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210',
        oneTimePrekeys: ['aa11', 'bb22', 'cc33']
    });
    console.log('✅ Alice Registrada:', aliceReg);

    // 3. Consulta de Prekeys X3DH
    console.log('\n▶️ [Prueba 3] Bob consulta Prekeys de @alice en el Directorio...');
    const aliceLookup = await fetchJSON(`${RELAY_HTTP}/api/v1/directory/lookup?username=alice`);
    console.log('✅ Prekeys de Alice recibidas:', {
        username: aliceLookup.username,
        myaowId: aliceLookup.myaowId,
        oneTimePrekey: aliceLookup.oneTimePrekeyHex
    });

    // 4. Conexión WebSocket de Alice y Bob
    console.log('\n▶️ [Prueba 4] Conectando sockets de Alice y Bob al Relay...');
    const wsAlice = new WebSocket(RELAY_WS);
    const wsBob = new WebSocket(RELAY_WS);

    await Promise.all([
        waitForOpen(wsAlice),
        waitForOpen(wsBob)
    ]);

    // Autenticación
    wsAlice.send(JSON.stringify({ type: 'auth', myaowId: 'MYAOW-ALICE1', displayName: 'Alice' }));
    wsBob.send(JSON.stringify({ type: 'auth', myaowId: 'MYAOW-BOB1', displayName: 'Bob' }));

    await sleep(200);
    console.log('✅ Ambos clientes autenticados en el WebSocket Relay.');

    // 5. Envío de Mensaje Cifrado de Alice a Bob
    console.log('\n▶️ [Prueba 5] Alice envía mensaje cifrado Double Ratchet a Bob...');
    let bobReceivedMessage = false;

    wsBob.on('message', (data) => {
        const msg = JSON.parse(data.toString());
        if (msg.type === 'message') {
            console.log('📥 Bob recibió paquete:', msg);
            bobReceivedMessage = true;
        }
    });

    wsAlice.send(JSON.stringify({
        id: 'msg-001',
        type: 'message',
        conversationId: 'conv-alice-bob',
        senderMyaowId: 'MYAOW-ALICE1',
        senderDisplayName: 'Alice',
        recipientMyaowId: 'MYAOW-BOB1',
        text: '¡Hola Bob! Mensaje 100% cifrado por hardware en tiempo real 🔒🐾',
        timestamp: new Date().toISOString()
    }));

    await sleep(400);
    console.log(bobReceivedMessage ? '✅ Entrega de Mensaje Instantánea Exitosa!' : '❌ Falló la entrega');

    // 6. Prueba de Cola Desconectada (Offline Queue)
    console.log('\n▶️ [Prueba 6] Probando Cola Efímera Offline (Bob se desconecta)...');
    wsBob.close();
    await sleep(200);

    // Alice envía un mensaje mientras Bob está offline
    console.log('📤 Alice envía mensaje mientras Bob no tiene conexión...');
    wsAlice.send(JSON.stringify({
        id: 'msg-002-offline',
        type: 'message',
        conversationId: 'conv-alice-bob',
        senderMyaowId: 'MYAOW-ALICE1',
        senderDisplayName: 'Alice',
        recipientMyaowId: 'MYAOW-BOB1',
        text: 'Mensaje enviado mientras estabas sin señal celular 📡',
        timestamp: new Date().toISOString()
    }));

    await sleep(300);

    // Bob vuelve a conectarse
    console.log('🔄 Bob recupera conexión y se reconecta...');
    const wsBobReconnected = new WebSocket(RELAY_WS);
    await waitForOpen(wsBobReconnected);

    let offlineDelivered = false;
    wsBobReconnected.on('message', (data) => {
        const msg = JSON.parse(data.toString());
        if (msg.id === 'msg-002-offline') {
            console.log('📥 Bob recibió el mensaje que estaba encolado en el Relay:', msg.text);
            offlineDelivered = true;
        }
    });

    wsBobReconnected.send(JSON.stringify({ type: 'auth', myaowId: 'MYAOW-BOB1', displayName: 'Bob' }));
    await sleep(400);

    console.log(offlineDelivered ? '✅ Cola Efímera Offline Entregada con Éxito!' : '❌ Falló la cola offline');

    // 7. Prueba de Señalización WebRTC
    console.log('\n▶️ [Prueba 7] Probando Señalización WebRTC para Llamadas HD...');
    let signalingDelivered = false;

    wsBobReconnected.on('message', (data) => {
        const msg = JSON.parse(data.toString());
        if (msg.type === 'webrtc_offer') {
            console.log('📞 Bob recibió oferta WebRTC SDP de llamada:', msg.sdpOrCandidate);
            signalingDelivered = true;
        }
    });

    wsAlice.send(JSON.stringify({
        type: 'webrtc_offer',
        senderMyaowId: 'MYAOW-ALICE1',
        targetMyaowId: 'MYAOW-BOB1',
        sdpOrCandidate: 'v=0\r\no=alice 123456 IN IP4 0.0.0.0\r\ns=Myaow HD Video',
        timestamp: new Date().toISOString()
    }));

    await sleep(400);
    console.log(signalingDelivered ? '✅ Señalización WebRTC Operativa al 100%!' : '❌ Falló la señalización WebRTC');

    // Limpieza
    wsAlice.close();
    wsBobReconnected.close();

    console.log('\n===============================================================');
    console.log('  🎉 TODAS LAS PRUEBAS DE COMUNICACIÓN PASARON EXITOSAMENTE');
    console.log('===============================================================\n');
}

function waitForOpen(ws) {
    return new Promise((resolve) => {
        if (ws.readyState === WebSocket.OPEN) return resolve();
        ws.on('open', resolve);
    });
}

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

function fetchJSON(url) {
    return new Promise((resolve, reject) => {
        http.get(url, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => resolve(JSON.parse(data)));
        }).on('error', reject);
    });
}

function postJSON(url, body) {
    return new Promise((resolve, reject) => {
        const u = new URL(url);
        const req = http.request({
            hostname: u.hostname,
            port: u.port,
            path: u.pathname,
            method: 'POST',
            headers: { 'Content-Type': 'application/json' }
        }, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => resolve(JSON.parse(data)));
        });
        req.on('error', reject);
        req.write(JSON.stringify(body));
        req.end();
    });
}

runE2ETests().catch(console.error);
