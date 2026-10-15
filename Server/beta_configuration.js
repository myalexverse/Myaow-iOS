'use strict';
const fs = require('node:fs');
const crypto = require('node:crypto');
const net = require('node:net');
const path = require('node:path');
const { iceConfiguration } = require('./ice_configuration');

// This checks local configuration only. It never contacts Apple, DNS or TURN,
// and its output contains fixed labels rather than environment/file contents.
function publicHostname(value) {
    return typeof value === 'string' && value.length <= 253 && !net.isIP(value)
        && value.split('.').length >= 2
        && value.split('.').every(label => /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/i.test(label))
        && !/(^|\.)(localhost|local|internal|test|invalid|example)(\.|$)/i.test(value)
        && !/(^|\.)example\.(com|net|org)$/i.test(value);
}

function callConfigurationChecks(env) {
    const checks = [];
    const add = (id, ready, fix) => checks.push({ id, ready: Boolean(ready), fix });
    add('apns_identifiers', /^[A-Z0-9]{10}$/.test(env.APNS_TEAM_ID || '')
        && /^[A-Z0-9]{10}$/.test(env.APNS_KEY_ID || ''), 'Configurar Team ID y Key ID válidos de Apple.');
    add('apns_topic', env.APNS_TOPIC === 'com.ScendLabs.Myaow', 'Usar el identificador de la app firmada: com.ScendLabs.Myaow.');
    let keyReady = false;
    try {
        const key = crypto.createPrivateKey(fs.readFileSync(env.APNS_KEY_PATH));
        const payload = Buffer.from('myaow-local-key-validation');
        keyReady = key.asymmetricKeyType === 'ec' && key.asymmetricKeyDetails?.namedCurve === 'prime256v1'
            && crypto.verify('sha256', payload, crypto.createPublicKey(key), crypto.sign('sha256', payload, key));
    } catch { /* Do not expose a path, PEM or error details. */ }
    add('apns_signing_key', keyReady, 'Montar una clave privada Apple .p8 legible y válida (EC P-256).');
    let turnReady = false;
    try {
        const urls = iceConfiguration('local-configuration-check', env).iceServers[0].urls;
        const secret = env.TURN_SHARED_SECRET_FILE ? fs.readFileSync(env.TURN_SHARED_SECRET_FILE, 'utf8').trim() : env.TURN_SHARED_SECRET;
        turnReady = !/replace|example|secreto_aleatorio/i.test(secret)
            && urls.every(url => {
                const match = /^(turns?):([^:]+):(\d+)(?:\?transport=(udp|tcp))?$/.exec(url);
                return match && publicHostname(match[2]) && Number(match[3]) >= 1 && Number(match[3]) <= 65535
                    && !(match[1] === 'turns' && match[4] === 'udp');
            });
    } catch { /* Credential generation failures become a fixed status. */ }
    add('turn_credentials', turnReady, 'Configurar dominios y puertos TURN reales y un secreto aleatorio de al menos 32 caracteres.');
    add('turn_tls', (env.TURN_URLS || '').split(',').some(url => /^turns:[^:]+:\d+(?:\?transport=tcp)?$/.test(url.trim())),
        'Incluir un endpoint TURN con TLS para redes restrictivas.');
    return checks;
}

function betaConfiguration(env, { deployment = false } = {}) {
    const checks = callConfigurationChecks(env);
    const add = (id, ready, fix) => checks.push({ id, ready: Boolean(ready), fix });
    add('production', env.NODE_ENV === 'production', 'Ejecutar la beta con NODE_ENV=production.');
    add('registration', ['invite', 'closed'].includes(env.BETA_REGISTRATION_MODE), 'Restringir altas a invitaciones o cerrar nuevos registros.');
    add('account_limit', /^\d+$/.test(env.BETA_MAX_USERS || '') && Number(env.BETA_MAX_USERS) >= 1 && Number(env.BETA_MAX_USERS) <= 30,
        'Definir BETA_MAX_USERS entre 1 y 30 para este piloto.');
    add('persistent_paths', [env.MYAOW_DB_PATH, env.MYAOW_UPLOADS_DIR].every(value => typeof value === 'string'
        && path.isAbsolute(value) && (value === '/data' || value.startsWith('/data/')) && !value.split('/').includes('..')),
        'Guardar base de datos y archivos en el volumen persistente /data.');
    if (deployment) {
        add('api_domain', publicHostname(env.API_DOMAIN), 'Configurar un subdominio público propio para la API.');
        const email = (env.ACME_EMAIL || '').split('@');
        add('certificate_email', email.length === 2 && /^[^\s@]+$/.test(email[0]) && publicHostname(email[1]),
            'Definir el correo operativo para los certificados HTTPS.');
        add('caddy_version', /^caddy:(?:\d+\.\d+\.\d+(?:-[a-z0-9.-]+)?)(?:@sha256:[a-f0-9]{64})?$/.test(env.CADDY_IMAGE || '')
            || /^caddy@sha256:[a-f0-9]{64}$/.test(env.CADDY_IMAGE || ''),
            'Fijar una versión completa o digest de Caddy validado al desplegar.');
        add('secret_files', [env.APNS_KEY_PATH, env.TURN_SHARED_SECRET_FILE].every(value => typeof value === 'string' && path.isAbsolute(value)),
            'Indicar rutas absolutas de los dos archivos de secretos fuera del repositorio.');
    }
    return { configured: checks.every(check => check.ready), checks,
        note: 'Solo valida configuración local. No acredita autorización de Apple, DNS, certificados, firewall, respaldos externos ni entrega o llamadas reales.' };
}

module.exports = { betaConfiguration, callConfigurationChecks };
