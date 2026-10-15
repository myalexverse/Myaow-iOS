'use strict';
const { betaConfiguration } = require('./beta_configuration');
const result = betaConfiguration(process.env);
if (!result.configured) {
    console.error(JSON.stringify({ error: 'BetaConfigurationIncomplete', checks: result.checks.filter(check => !check.ready) }));
    process.exitCode = 1;
} else {
    require('./server');
}
