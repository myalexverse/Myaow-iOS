'use strict';
const fs = require('node:fs');
const { betaConfiguration } = require('./beta_configuration');

function main(args = process.argv.slice(2)) {
    let env;
    const deployment = args.length === 2 && args[0] === '--env';
    if (!(deployment || args.length === 0)) {
        console.error('Uso: node check_beta_configuration.js [--env /ruta/.env.beta]');
        return 2;
    }
    if (deployment) {
        try {
            // Parse, never source a shell file; do not merge with the operator's
            // environment, which could silently hide missing deployment values.
            const values = require('dotenv').parse(fs.readFileSync(args[1]));
            env = { ...values, NODE_ENV: 'production', MYAOW_DB_PATH: '/data/myaow.db', MYAOW_UPLOADS_DIR: '/data/uploads',
                APNS_KEY_PATH: values.APNS_KEY_FILE, TURN_SHARED_SECRET_FILE: values.TURN_SECRET_FILE };
        } catch {
            console.error('No se pudo leer el archivo de configuración. No se inició ningún servicio.');
            return 2;
        }
    } else {
        env = process.env;
    }
    const result = betaConfiguration(env, { deployment });
    console.log(JSON.stringify(result, null, 2));
    return result.configured ? 0 : 1;
}
if (require.main === module) process.exitCode = main();
module.exports = { main };
