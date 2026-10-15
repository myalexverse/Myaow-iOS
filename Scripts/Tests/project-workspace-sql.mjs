const { PGlite } = await import(process.env.MYAOW_PGLITE_MODULE || '/private/tmp/myaow-project-sql/node_modules/@electric-sql/pglite/dist/index.js');
import fs from 'node:fs';
const root=process.cwd();
const db=new PGlite();
try {
await db.exec(`create role anon; create role authenticated; create role service_role bypassrls; create schema extensions; grant usage on schema extensions to service_role;
create function extensions.digest(text,text) returns bytea language sql immutable as 'select sha256(convert_to($1,''UTF8''))';`);
for(const name of ['20260930205323_myaow_private_backend.sql','20261001013659_myaow_collaboration_scheduler.sql','20261001014742_myaow_collaboration_runtime_guards.sql','20261001014831_myaow_collaboration_scope.sql','20261001015314_myaow_delivery_lock_order.sql','20261009010000_myaow_group_task_policy.sql','20261014024038_myaow_project_workspace.sql']){
 let sql=fs.readFileSync(root+'/supabase/migrations/'+name,'utf8').split('create extension if not exists pg_cron')[0];
 await db.exec(sql); console.log('Applied '+name);
}
await db.exec(fs.readFileSync(root+'/supabase/tests/collaboration.sql','utf8'));
console.log('PASS existing collaboration regression checks');
await db.exec(fs.readFileSync(root+'/supabase/tests/project_workspace.sql','utf8'));
console.log('PASS project workspace database checks');
}catch(e){ console.error('FAILED',e.message,e.detail||'',e.where||''); process.exitCode=1; }
finally{await db.close()}
