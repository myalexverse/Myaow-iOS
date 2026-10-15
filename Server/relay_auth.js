const crypto = require('node:crypto');

const PROTOCOL = 'myaow-x25519-hkdf-sha256-v2';
const validPublicKey = value => typeof value === 'string' && /^[0-9a-f]{64}$/i.test(value);
function transcript(id, nonce, serverPublicKeyHex, clientPublicKeyHex) {
    return Buffer.from(['MYAOW-AUTH-V2', id, nonce, serverPublicKeyHex, clientPublicKeyHex.toLowerCase()].join('\0'), 'utf8');
}
function createChallenge(myaowId, clientPublicKeyHex) {
    if (!validPublicKey(clientPublicKeyHex)) throw new Error('Invalid identity key');
    const clientKey = crypto.createPublicKey({ format: 'jwk', key: { kty: 'OKP', crv: 'X25519', x: Buffer.from(clientPublicKeyHex, 'hex').toString('base64url') } });
    const pair = crypto.generateKeyPairSync('x25519');
    const serverPublicKeyHex = Buffer.from(pair.publicKey.export({ format: 'jwk' }).x, 'base64url').toString('hex');
    const nonce = crypto.randomBytes(32).toString('hex');
    const context = transcript(myaowId, nonce, serverPublicKeyHex, clientPublicKeyHex);
    const secret = crypto.diffieHellman({ privateKey: pair.privateKey, publicKey: clientKey });
    const key = crypto.hkdfSync('sha256', secret, Buffer.from(nonce, 'utf8'), context, 32);
    const expectedProof = crypto.createHmac('sha256', key).update(context).digest();
    return { myaowId, nonce, serverPublicKeyHex, expectedProof, expiresAt: Date.now() + 30000, protocol: PROTOCOL };
}
function verifyProof(challenge, myaowId, proof) {
    if (!challenge || challenge.expiresAt < Date.now() || challenge.myaowId !== myaowId || !validPublicKey(proof)) return false;
    return crypto.timingSafeEqual(challenge.expectedProof, Buffer.from(proof, 'hex'));
}
module.exports = { PROTOCOL, validPublicKey, createChallenge, verifyProof };
