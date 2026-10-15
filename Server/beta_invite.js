'use strict';
// Run only by the server operator. The code is printed once; only its hash is stored.
require('dotenv').config();
const Database=require('better-sqlite3');
const {BetaAccess}=require('./beta_access');
if(!process.env.MYAOW_DB_PATH)throw Error('MYAOW_DB_PATH is required');
const db=new Database(process.env.MYAOW_DB_PATH,{fileMustExist:true});
db.pragma('busy_timeout = 5000');
try { console.log(new BetaAccess(db).create(Number(process.argv[2] || 7))); } finally { db.close(); }
