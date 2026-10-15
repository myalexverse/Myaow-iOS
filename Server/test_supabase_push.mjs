import {test} from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync,verify,randomUUID} from 'node:crypto';
import {makeAPNsGateway,createPushWorker} from '../supabase/functions/myaow-push/worker.mjs';
import {createHandler} from '../supabase/functions/myaow-api/handler.mjs';

const pair=generateKeyPairSync('ec',{namedCurve:'prime256v1'});
const config={enabled:true,teamId:'ABCDEFGHIJ',keyId:'1234567890',privateKey:pair.privateKey.export({format:'pem',type:'pkcs8'}),topics:['com.ScendLabs.Myaow']};
const device={id:randomUUID(),token:'a'.repeat(64),topic:'com.ScendLabs.Myaow',environment:'sandbox',expiration:1900000000};
const secret='test-worker-secret-'.repeat(4);
const req=(token=secret)=>new Request('https://unit.invalid',{method:'POST',headers:{'x-myaow-worker':token}});

test('APNs signs valid ES256, uses the correct environment and only sends a generic payload',async()=>{
 let captured;
 const gateway=makeAPNsGateway(config,async(url,options)=>{captured={url,options};return new Response(null,{status:200});});
 assert.equal(gateway.configured(),true);
 assert.equal(await gateway.send(device),'accepted');
 assert.ok(captured.url.startsWith('https://api.sandbox.push.apple.com/3/device/'));
 assert.equal(captured.options.redirect,'error');
 const jwt=captured.options.headers.authorization.slice(7), parts=jwt.split('.');
 assert.equal(verify('sha256',Buffer.from(parts[0]+'.'+parts[1]),{key:pair.publicKey,dsaEncoding:'ieee-p1363'},Buffer.from(parts[2],'base64url')),true);
 assert.equal(captured.options.headers['apns-collapse-id'],device.id);
 assert.equal(captured.options.headers['apns-push-type'],'alert');
 assert.deepEqual(JSON.parse(captured.options.body),{aps:{alert:{title:'Myaow',body:'Tienes un mensaje nuevo.'},sound:'myaow-classic.wav'}});
});
test('APNs failures distinguish invalid tokens, transient errors and permanent rejection',async()=>{
 for(const [status,reason,expected] of [[410,'Unregistered','invalid'],[400,'BadDeviceToken','invalid'],[429,'TooManyRequests','retry'],[503,'ServiceUnavailable','retry'],[403,'ExpiredProviderToken','retry'],[400,'BadTopic','failed']]) {
  const gateway=makeAPNsGateway(config,async()=>new Response(JSON.stringify({reason}),{status}));
  assert.equal(await gateway.send(device),expected);
 }
 assert.equal(await makeAPNsGateway(config,async()=>{throw Error('network');}).send(device),'retry');
});
test('APNs configuration and device allowlists fail closed before any network call',async()=>{
 const never=()=>{assert.fail('Unexpected network');};
 assert.equal(makeAPNsGateway({...config,privateKey:'invalid'},never).configured(),false);
 assert.equal(makeAPNsGateway({...config,enabled:false},never).configured(),false);
 assert.equal(await makeAPNsGateway(config,never).send({...device,topic:'other.app'}),'failed');
 assert.equal(await makeAPNsGateway(config,never).send({...device,token:'../foreign'}),'failed');
});
test('APNs accepts escaped PEM secrets but rejects other elliptic curves',()=>{
 const never=()=>{assert.fail('Unexpected network');};
 assert.equal(makeAPNsGateway({...config,privateKey:config.privateKey.replaceAll('\n','\\n')},never).configured(),true);
 const other=generateKeyPairSync('ec',{namedCurve:'secp384r1'});
 assert.equal(makeAPNsGateway({...config,privateKey:other.privateKey.export({format:'pem',type:'pkcs8'})},never).configured(),false);
});
test('worker rejects missing/wrong/unicode credentials and does not claim jobs while disabled',async()=>{
 const never=()=>{assert.fail('Unexpected RPC');};
 const worker=createPushWorker({secret,gateway:{configured:()=>false},rpc:never});
 for(const value of ['', 'x'.repeat(secret.length), 'é'.repeat(secret.length)])assert.equal((await worker(req(value))).status,401);
 assert.equal((await worker(req())).status,503);
 assert.equal((await createPushWorker({secret:undefined,gateway:{configured:()=>true},rpc:never})(req(''))).status,401);
});
test('worker revalidates before sending, persists results and leaves interrupted work leased for retry',async()=>{
 const events=[];
 const worker=createPushWorker({secret,gateway:{configured:()=>true,send:async()=>{events.push('send');return 'accepted';}},rpc:async(action,payload)=>{
  events.push(action);
  if(action==='push_claim')return [{id:'one',lease:'lease-1'},{id:'two',lease:'lease-2'}];
  if(action==='push_validate')return {valid:payload.id==='one',...device};
  assert.equal(payload.outcome,'accepted');return {saved:true};
 }});
 assert.deepEqual(await (await worker(req())).json(),{processed:1});
 assert.equal(events.filter(x=>x==='send').length,1);
 assert.ok(events.indexOf('push_validate')<events.indexOf('send'));
 const interrupted=createPushWorker({secret,gateway:{configured:()=>true},rpc:async(action)=>{if(action==='push_claim')return [{id:'one',lease:'lease'}];throw Error('offline');}});
 assert.deepEqual(await (await interrupted(req())).json(),{processed:0});
});
test('client gateway permits only device registration, never claiming or completing jobs',async()=>{
 const calls=[];
 const handler=createHandler(async(action,payload)=>{calls.push({action,payload});return action==='rate_limit'?{allowed:true}:{registered:true,deliveryEnabled:false};});
 const request=(path,body={})=>new Request('https://unit.invalid/myaow-api'+path,{method:'POST',headers:{'content-type':'application/json',authorization:'Bearer '+'a'.repeat(64)},body:JSON.stringify(body)});
 assert.equal((await handler(request('/push/device',{installation:'id',environment:'sandbox',owner:'victim',token:'forged'}))).status,200);
 assert.equal(calls.at(-1).action,'push_register');assert.equal(calls.at(-1).payload.owner,undefined);assert.equal(calls.at(-1).payload.token,'a'.repeat(64));
 for(const path of ['/push/claim','/push/finish','/push/validate'])assert.equal((await handler(request(path))).status,404);
});
test('VoIP sends only an unexpired encrypted offer, using the VoIP topic and no chat alert',async()=>{
 let captured;
 const gateway=makeAPNsGateway(config,async(url,options)=>{captured={url,options};return new Response(null,{status:200});});
 const payload={type:'call_signal',signalType:'call_offer',id:randomUUID(),callId:randomUUID(),expiresAt:Date.now()/1000+40,senderMyaowId:'MYAOW-A',recipientMyaowId:'MYAOW-B',encryptedPayload:'encrypted-only',untrustedText:'must not send'};
 assert.equal(await gateway.send({...device,kind:'voip',payload}),'accepted');
 assert.equal(captured.options.headers['apns-topic'],'com.ScendLabs.Myaow.voip');
 assert.equal(captured.options.headers['apns-push-type'],'voip');
 const body=JSON.parse(captured.options.body);assert.deepEqual(body.aps,{});assert.equal(body.untrustedText,undefined);
 const never=makeAPNsGateway(config,async()=>assert.fail('Unexpected APNs send'));
 assert.equal(await never.send({...device,kind:'voip',payload:{...payload,signalType:'webrtc_offer'}}),'failed');
 assert.equal(await never.send({...device,kind:'voip',payload:{...payload,expiresAt:0}}),'failed');
 assert.equal(await never.send({...device,kind:'voip',payload:{...payload,encryptedPayload:'x'.repeat(6000)}}),'failed');
});
test('worker prioritizes the separate call queue and revalidates its lease',async()=>{
 const events=[];
 const worker=createPushWorker({secret,gateway:{configured:()=>true,send:async d=>{events.push(d.kind);return 'accepted';}},
 rpc:async action=>{events.push('alert:'+action);return [];},
 callRpc:async(action,job)=>{events.push(action);if(action==='push_claim')return [{id:'call',lease:'lease'}];if(action==='push_validate')return {valid:true,kind:'voip'};assert.equal(job.outcome,'accepted');return {};}});
 assert.deepEqual(await (await worker(req())).json(),{processed:1});
 assert.ok(events.indexOf('push_validate')<events.indexOf('voip'));assert.ok(events.indexOf('voip')<events.indexOf('alert:push_claim'));
});

test('alert ignores untrusted message text and sound overrides; VoIP stays separate',async()=>{
 let payload;
 const gateway=makeAPNsGateway(config,async(_,options)=>{payload=JSON.parse(options.body);return new Response(null,{status:200});});
 assert.equal(await gateway.send({...device,payload:{sound:'../../private',text:'private conversation',sender:'private contact'}}),'accepted');
 assert.deepEqual(payload,{aps:{alert:{title:'Myaow',body:'Tienes un mensaje nuevo.'},sound:'myaow-classic.wav'}});
});

test('allowlisted maullidos choose bundled APNs sounds without leaking message content',async()=>{
 let payload;
 const gateway=makeAPNsGateway(config,async(_,options)=>{payload=JSON.parse(options.body);return new Response(null,{status:200});});
 for(const sound of ['classic','electric','cosmic','melodic','claw','lazy','kiss','giggle','party','question','sleepy','echo','mentada','admiration']) {
  assert.equal(await gateway.send({...device,notificationSound:sound,payload:{text:'private'}}),'accepted');
  assert.deepEqual(payload,{aps:{alert:{title:'Myaow',body:'Tienes un mensaje nuevo.'},sound:`myaow-${sound}.wav`}});
 }
 for(const invalid of ['../../private','default','mentada.wav',null,{},'']) {
  await gateway.send({...device,notificationSound:invalid});
  assert.equal(payload.aps.sound,'myaow-classic.wav');
 }
});
