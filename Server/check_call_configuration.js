'use strict';
// Read-only. Prints booleans only; never prints credentials, tokens or certificate contents.
require('dotenv').config();
const {callConfigurationChecks}=require('./beta_configuration');
const checks=callConfigurationChecks(process.env);
console.log(JSON.stringify({checks,configured:checks.every(x=>x.ready),note:'Configuration presence does not verify APNs delivery, DNS, certificates, firewall or media connectivity.'},null,2));
process.exitCode=checks.every(x=>x.ready)?0:1;
