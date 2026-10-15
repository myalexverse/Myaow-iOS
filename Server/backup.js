'use strict';
const fs=require('node:fs/promises');
const path=require('node:path');
const crypto=require('node:crypto');
const Database=require('better-sqlite3');
async function makeBackup({database,uploads,destination}) {
    // Exclusive destination prevents overwriting an earlier restore point.
    await fs.mkdir(destination,{mode:0o700});
    const db=new Database(database,{readonly:true,fileMustExist:true});
    try {
        await db.backup(path.join(destination,'myaow.db'));
        await fs.cp(uploads,path.join(destination,'uploads'),{recursive:true,errorOnExist:true,force:false});
        const digest=crypto.createHash('sha256').update(await fs.readFile(path.join(destination,'myaow.db'))).digest('hex');
        await fs.writeFile(path.join(destination,'manifest.json'),JSON.stringify({version:1,createdAt:new Date().toISOString(),databaseSHA256:digest}),{mode:0o600});
        return destination;
    } finally { db.close(); }
}
async function verifyBackup(destination) {
    const manifest=JSON.parse(await fs.readFile(path.join(destination,'manifest.json'),'utf8'));
    const dbPath=path.join(destination,'myaow.db');
    if(crypto.createHash('sha256').update(await fs.readFile(dbPath)).digest('hex')!==manifest.databaseSHA256)throw Error('Backup checksum mismatch');
    const db=new Database(dbPath,{readonly:true,fileMustExist:true});
    try {
        if(db.pragma('integrity_check',{simple:true})!=='ok')throw Error('Database integrity check failed');
        if(!(await fs.stat(path.join(destination,'uploads'))).isDirectory())throw Error('Missing uploads');
        return true;
    }finally{db.close();}
}
if(require.main===module) {
    require('dotenv').config();
    const action=process.argv[2], destination=process.argv[3];
    const run=async()=>{
        if(!destination||!['create','verify'].includes(action))throw Error('Usage: node backup.js create|verify /backups/unique-directory');
        if(action==='verify')await verifyBackup(destination);
        else {
            if(!process.env.MYAOW_DB_PATH||!process.env.MYAOW_UPLOADS_DIR)throw Error('Explicit database and uploads paths required');
            await makeBackup({database:process.env.MYAOW_DB_PATH,uploads:process.env.MYAOW_UPLOADS_DIR,destination});
            await verifyBackup(destination);
        }
        console.log('Backup verified');
    };
    run().catch(()=>{console.error('Backup operation failed; do not use this restore point.');process.exitCode=1;});
}
module.exports={makeBackup,verifyBackup};
