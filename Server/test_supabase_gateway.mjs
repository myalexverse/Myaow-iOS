import {test} from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {makeChallenge,digest,createHandler} from '../supabase/functions/myaow-api/handler.mjs';

export function proofFor(challenge,id,pair) {
 const hex=Buffer.from(pair.publicKey.export({format:'jwk'}).x,'base64url').toString('hex');
 const server=crypto.createPublicKey({format:'jwk',key:{kty:'OKP',crv:'X25519',x:Buffer.from(challenge.serverPublicKeyHex,'hex').toString('base64url')}});
 const context=Buffer.from(['MYAOW-AUTH-V2',id,challenge.nonce,challenge.serverPublicKeyHex,hex].join('\0'));
 const secret=crypto.diffieHellman({privateKey:pair.privateKey,publicKey:server});
 const key=crypto.hkdfSync('sha256',secret,Buffer.from(challenge.nonce),context,32);
 return crypto.createHmac('sha256',key).update(context).digest('hex');
}
const request=(path,body={},token)=>new Request('https://unit.invalid/functions/v1/myaow-api'+path,{method:'POST',headers:{'content-type':'application/json',...(token?{authorization:'Bearer '+token}:{})},body:JSON.stringify(body)});

test('Supabase gateway preserves existing X25519 authentication and rejects low-order keys',()=>{
 const pair=crypto.generateKeyPairSync('x25519');
 const hex=Buffer.from(pair.publicKey.export({format:'jwk'}).x,'base64url').toString('hex');
 const c=makeChallenge('MYAOW-TESTA',hex);
 assert.equal(digest(proofFor(c,'MYAOW-TESTA',pair)),c.proofHash);
 assert.notEqual(digest(proofFor(c,'MYAOW-TESTB',pair)),c.proofHash);
 assert.throws(()=>makeChallenge('MYAOW-TESTA','00'.repeat(32)));
 const globalBuffer=globalThis.Buffer;
 try {
  globalThis.Buffer=undefined; // Deno does not provide Node's global Buffer.
  assert.equal(makeChallenge('MYAOW-TESTA',hex).proofHash.length,64);
 } finally { globalThis.Buffer=globalBuffer; }
});
test('gateway rejects unauthenticated data access and ignores forged body tokens or actor IDs',async()=>{
 const calls=[];
 const handler=createHandler(async(action,payload)=>{calls.push({action,payload});return action==='rate_limit'?{allowed:true}:{ok:true};});
 assert.equal((await handler(request('/messages/pending',{token:'b'.repeat(64)}))).status,401);
 assert.equal(calls.length,0);
 const res=await handler(request('/messages/pending',{token:'b'.repeat(64),actor:'VICTIM'},'a'.repeat(64)));
 assert.equal(res.status,200);
 assert.deepEqual(calls.at(-1),{action:'pending',payload:{token:'a'.repeat(64)}});
});
test('public challenge never returns stored proof hash and failed proof returns unauthorized',async()=>{
 const pair=crypto.generateKeyPairSync('x25519');let stored;
 const handler=createHandler(async(action,payload)=>{
  if(action==='rate_limit')return {allowed:true};
  if(action==='challenge_profile')return {identityKeyHex:Buffer.from(pair.publicKey.export({format:'jwk'}).x,'base64url').toString('hex')};
  if(action==='challenge_store'){stored=payload;return {};}
  return {error:'Authentication failed'};
 });
 const c=await (await handler(request('/auth/challenge',{myaowId:'MYAOW-TESTA'}))).json();
 assert.equal(c.proofHash,undefined);assert.equal(digest(proofFor(c,'MYAOW-TESTA',pair)),stored.proofHash);
 assert.equal((await handler(request('/auth/proof',{id:c.id,myaowId:'MYAOW-TESTA',proof:'0'.repeat(64)}))).status,401);
});
test('gateway bounds request size, handles rate limits and never returns raw database errors',async()=>{
 const handler=createHandler(async()=>{throw {code:'XX000',message:'secret database content'};});
 const failure=await handler(request('/profile',{},'a'.repeat(64)));assert.equal(failure.status,503);
 assert.equal((await failure.text()).includes('secret'),false);
 assert.equal((await handler(request('/register',{large:'x'.repeat(220001)}))).status,413);
 const limited=createHandler(async()=>({allowed:false}));
 assert.equal((await limited(request('/register',{}))).status,429);
});
test('collaboration routes take authority from the session, not request fields',async()=>{
 const calls=[];
 const handler=createHandler(async(action,payload)=>{calls.push({action,payload});return action==='rate_limit'?{allowed:true}:{ok:true};});
 for(const [path,action,body] of [
  ['/groups/create','groups_create',{id:'group',name:'Team'}],
  ['/groups/accept','groups_invite_accept',{inviteId:'invite'}],
  ['/tasks/update','tasks_update',{id:'task',state:'in_progress',progress:50}],
  ['/schedules/cancel','schedules_cancel',{id:'schedule'}],
 ]) {
  assert.equal((await handler(request(path,body))).status,401);
  assert.equal((await handler(request(path,{...body,token:'b'.repeat(64),actor:'VICTIM',owner:'VICTIM'},'a'.repeat(64)))).status,200);
  assert.equal(calls.at(-1).action,action);
  assert.equal(calls.at(-1).payload.token,'a'.repeat(64));
  assert.equal(calls.at(-1).payload.actor,undefined);
  assert.equal(calls.at(-1).payload.owner,undefined);
 }
 const large={packets:[{encryptedPayload:'x'.repeat(250000)}]};
 assert.equal((await handler(request('/messages/batch',large,'a'.repeat(64)))).status,200);
 assert.equal((await handler(request('/messages/send',large,'a'.repeat(64)))).status,413);
 assert.equal((await handler(request('/schedules/create',{preview:'x'.repeat(4500001)},'a'.repeat(64)))).status,413);
 assert.equal((await handler(request('/dispatch_due',{},'a'.repeat(64)))).status,404);
});

test('group task policy crosses the gateway for creation and updates',async()=>{
 const calls=[];
 const h=createHandler(async(action,payload)=>{ calls.push({action,payload}); return action==='rate_limit'?{allowed:true}:{success:true}; });
 for(const path of ['/groups/create','/groups/info']) {
  assert.equal((await h(request(path,{name:'Team',groupId:'a',taskPolicy:'admins'},'a'.repeat(64)))).status,200);
  assert.equal(calls.at(-1).payload.taskPolicy,'admins');
 }
});

test('project and task planning routes preserve exact dates and exclude forged actors',async()=>{
 const calls=[]; const token='a'.repeat(64);
 const handler=createHandler(async(action,payload)=>{calls.push({action,payload});return action==='rate_limit'?{allowed:true}:{ok:true};});
 for(const [path,action,body] of [
  ['/tasks/create-planned','tasks_create',{id:'planned',groupId:'group',title:'Key task',dueAt:'2026-11-06T00:30:00Z',dueTimezone:'America/Mexico_City',isKey:true,cadence:'weekly'}],
  ['/tasks/plan','tasks_update',{id:'planned',dueAt:null,isKey:false,cadence:'once'}],
  ['/projects/save','projects_save',{groupId:'group',objective:'Objective',startsAt:'2026-10-01T12:00:00Z',endsAt:'2026-12-01T12:00:00Z',reviewAt:null,timezone:'UTC',version:0,status:'active'}],
  ['/projects/vote','projects_vote',{groupId:'group',id:'idea',voted:true}],
  ['/projects/accept','projects_accept',{groupId:'group',id:'idea'}]
 ]) {
  assert.equal((await handler(request(path,{...body,actor:'forged',author:'forged',token:'b'.repeat(64)},token))).status,200);
  const last=calls.at(-1); assert.equal(last.action,action); assert.equal(last.payload.token,token);
  assert.equal(last.payload.actor,undefined); assert.equal(last.payload.author,undefined);
  for(const [key,value] of Object.entries(body)) assert.deepEqual(last.payload[key],value);
 }
 assert.equal((await handler(request('/projects/get',{groupId:'group'}))).status,401);
});
