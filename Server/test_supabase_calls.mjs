import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHandler} from '../supabase/functions/myaow-api/handler.mjs';
import {makeTURNProvider} from '../supabase/functions/myaow-api/turn.mjs';
const req=(path,body={},token='a'.repeat(64))=>new Request('https://unit.invalid/myaow-api'+path,{method:'POST',headers:{'content-type':'application/json',...(token?{authorization:'Bearer '+token}:{})},body:JSON.stringify(body)});
test('TURN requires an authenticated RPC budget before accessing provider secrets',async()=>{
 let calls=0;
 const rpc=async action=>{if(action==='rate_limit')return {allowed:true};throw {code:'28000'};};
 const h=createHandler(rpc,undefined,async()=>{calls++;});
 assert.equal((await h(req('/webrtc/ice-servers',{},''))).status,401);
 assert.equal((await h(req('/webrtc/ice-servers'))).status,401);
 assert.equal(calls,0);
});
test('TURN credentials expire and omit direct/STUN and unexpected hosts',async()=>{
 let captured;
 const provider=makeTURNProvider({cloudflareKeyId:'k'.repeat(32),cloudflareToken:'server-only-secret'},async(url,options)=>{
  captured={url,options};return Response.json({iceServers:[{urls:['stun:stun.cloudflare.com:3478']},{urls:['turn:turn.cloudflare.com:3478?transport=udp','turns:turn.cloudflare.com:443?transport=tcp','turn:evil.invalid:3478'],username:'ephemeral',credential:'ephemeral-secret'}]});
 },()=>1900000000000);
 const result=await provider('MYAOW-ONE');
 assert.equal(result.iceTransportPolicy,'relay');assert.equal(result.expiresAt,1900014400);
 assert.equal(result.iceServers.length,1);assert.equal(result.iceServers[0].urls.length,2);
 assert.ok(captured.url.endsWith('/credentials/generate-ice-servers'));assert.equal(captured.options.redirect,'error');
 assert.equal(JSON.stringify(result).includes('server-only-secret'),false);
 assert.equal(captured.options.body,JSON.stringify({ttl:14400}));
 await assert.rejects(makeTURNProvider({})('MYAOW-ONE'));
 await assert.rejects(makeTURNProvider({cloudflareKeyId:'k'.repeat(32),cloudflareToken:'secret'},async()=>Response.json({iceServers:[]}))('MYAOW-ONE'));
});
test('Coturn alternative uses pseudonymous expiring usernames and never reveals shared secret',async()=>{
 const result=await makeTURNProvider({urls:'turn:turn.example.com:3478?transport=udp',sharedSecret:'test-secret'.repeat(5)},undefined,()=>1900000000000)('MYAOW-ONE');
 assert.equal(result.expiresAt,1900014400);assert.equal(result.iceServers[0].username.includes('MYAOW'),false);
 assert.ok(result.iceServers[0].credential.length>20);
});
test('call gateway ignores forged actor and token fields; synchronization includes expiring call signals',async()=>{
 const calls=[];const packet={id:'test'};
 const h=createHandler(async(action,payload)=>{calls.push({action,payload});if(action==='rate_limit')return {allowed:true};if(action==='sync')return {messages:[],receipts:[]};if(action==='calls_pending')return {signals:[packet]};return {accepted:true};});
 assert.equal((await h(req('/calls/signal',{owner:'victim',token:'forged',signalType:'call_offer',packet}))).status,200);
 assert.equal(calls.at(-1).action,'calls_signal');assert.equal(calls.at(-1).payload.owner,undefined);assert.equal(calls.at(-1).payload.token,'a'.repeat(64));
 const result=await (await h(req('/messages/sync',{ids:[]}))).json();assert.deepEqual(result.callSignals,[packet]);
 for(const path of ['/calls/push_claim','/calls/dispatch'])assert.equal((await h(req(path))).status,404);
});

test('chat saturation cannot starve negotiation, ICE, sync or hangup; every lane remains bounded',async()=>{
 const buckets=new Map(); const h=createHandler(async(action,payload)=>{
  if(action==='rate_limit'){const count=(buckets.get(payload.key)||0)+1;buckets.set(payload.key,count);return {allowed:count<=60};}
  if(action==='sync')return {messages:[],receipts:[]};
  if(action==='calls_pending')return {signals:[]};
  return {accepted:true};
 });
 for(let i=0;i<60;i++)assert.equal((await h(req('/groups/list'))).status,200);
 assert.equal((await h(req('/groups/list'))).status,429);
 for(let i=0;i<60;i++)assert.equal((await h(req('/messages/sync'))).status,200);
 assert.equal((await h(req('/messages/sync'))).status,429);
 for(let i=0;i<60;i++)assert.equal((await h(req('/calls/signal',{signalType:'webrtc_ice_candidate'}))).status,200);
 assert.equal((await h(req('/calls/signal',{signalType:'webrtc_ice_candidate'}))).status,429);
 assert.equal((await h(req('/calls/signal',{signalType:'call_answer'}))).status,200);
 assert.equal((await h(req('/calls/signal',{signalType:'call_hangup'}))).status,200);
 assert.equal((await h(req('/messages/acknowledge'))).status,200);
 assert.equal(buckets.size,6);
 // Caller fields and arbitrary routes cannot mint unbounded rate lanes.
 assert.equal((await h(req('/made-up-path',{lane:'free'}))).status,429);
 assert.equal(buckets.size,6);
});
