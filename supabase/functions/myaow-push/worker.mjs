import { createPrivateKey, sign, timingSafeEqual } from 'node:crypto';
import { Buffer } from 'node:buffer';

// Only a catalog ID is exposed for nudge alerts, never the encrypted conversation.
// Older clients missing a newly bundled sound fall back to the system default.
const soundIDs = new Set(['classic','electric','cosmic','melodic','claw','lazy','kiss','giggle','party','question','sleepy','echo','mentada','admiration']);
const notification = sound => ({aps:{alert:{title:'Myaow',body:'Tienes un mensaje nuevo.'},sound:`myaow-${soundIDs.has(sound)?sound:'classic'}.wav`}});
export function makeAPNsGateway(config, send = fetch) {
 let cached, issued=0, key;
 const ready = () => config.enabled === true && /^[A-Z0-9]{10}$/.test(config.teamId || '') && /^[A-Z0-9]{10}$/.test(config.keyId || '') && !!config.privateKey;
 const jwt = () => {
  const now=Math.floor(Date.now()/1000);
  if(cached && now>=issued && now-issued<3000)return cached;
  key ||= createPrivateKey(config.privateKey.replaceAll('\\n','\n'));
  // Supabase's Deno runtime can name the same NIST P-256 curve "p256".
  // Keep validation strict while accepting the two runtime names.
  if(key.asymmetricKeyType!=='ec' || !['prime256v1','p256'].includes(key.asymmetricKeyDetails?.namedCurve))throw new Error('Invalid signing key');
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const input=encode({alg:'ES256',kid:config.keyId})+'.'+encode({iss:config.teamId,iat:now});
  cached=input+'.'+sign('sha256',Buffer.from(input),{key,dsaEncoding:'ieee-p1363'}).toString('base64url'); issued=now;
  return cached;
 };
 return {
  configured() { if(!ready())return false; try { jwt();return true; }catch{return false;} },
  async send(device) {
   if(!ready())return 'retry';
   if(!/^[a-f0-9]{32,512}$/.test(device.token || '') || !['sandbox','production'].includes(device.environment) || !config.topics?.includes(device.topic))return 'failed';
   const voip=device.kind==='voip';
   let body=notification(device.notificationSound);
   if(voip) {
    const p=device.payload;
    if(!p || p.type!=='call_signal' || p.signalType!=='call_offer' || typeof p.encryptedPayload!=='string' ||
      !/^[a-f0-9-]{36}$/i.test(p.callId || '') || !/^[a-f0-9-]{36}$/i.test(p.id || '') ||
      typeof p.expiresAt!=='number' || p.expiresAt<=Date.now()/1000 || p.expiresAt>Date.now()/1000+95)return 'failed';
    body={aps:{},type:'call_signal',id:p.id,callId:p.callId,signalType:'call_offer',expiresAt:p.expiresAt,
      senderMyaowId:p.senderMyaowId,recipientMyaowId:p.recipientMyaowId,encryptedPayload:p.encryptedPayload};
    if(Buffer.byteLength(JSON.stringify(body))>5120)return 'failed';
   } else if(device.kind && device.kind!=='alert')return 'failed';
   try {
    const host=device.environment==='production'?'api.push.apple.com':'api.sandbox.push.apple.com';
    const response=await send(`https://${host}/3/device/${device.token}`,{method:'POST',redirect:'error',signal:AbortSignal.timeout(8000),headers:{
     authorization:`bearer ${jwt()}`,'content-type':'application/json','apns-topic':device.topic+(voip?'.voip':''),'apns-push-type':voip?'voip':'alert','apns-priority':'10',
     'apns-id':device.id,'apns-collapse-id':device.id,'apns-expiration':String(device.expiration)
    },body:JSON.stringify(body)});
    if(response.status===200){await response.body?.cancel();return 'accepted';}
    const error=await response.json().catch(()=>({}));
    if(response.status===410 || ['BadDeviceToken','DeviceTokenNotForTopic'].includes(error.reason))return 'invalid';
    if(['ExpiredProviderToken','InvalidProviderToken'].includes(error.reason)){cached=null;return 'retry';}
    return response.status===429 || response.status>=500 ? 'retry' : 'failed';
   }catch{return 'retry';}
  }
 };
}

export function createPushWorker({secret,gateway,rpc,callRpc}) {
 const reply=(data,status=200)=>Response.json(data,{status,headers:{'cache-control':'no-store'}});
 return async request => {
  const supplied=request.headers.get('x-myaow-worker') || '';
  const expected=Buffer.from(secret || ''), actual=Buffer.from(supplied);
  if(expected.length<32 || actual.length!==expected.length || !timingSafeEqual(actual,expected))return reply({error:'Unauthorized'},401);
  if(request.method!=='POST')return reply({error:'Method not allowed'},405);
  if(!gateway.configured())return reply({error:'Push is not configured'},503);
  let processed=0;
  try {
   for(const queue of [callRpc,rpc].filter(Boolean)) {
   const jobs=await queue('push_claim',{});
   for(let offset=0;offset<jobs.length;offset+=5) {
    await Promise.all(jobs.slice(offset,offset+5).map(async job=>{
     try {
      const device=await queue('push_validate',job);
      if(!device.valid)return;
      const outcome=await gateway.send(device);
      await queue('push_finish',{...job,outcome}); processed++;
     }catch{ /* The lease expires; a later invocation can retry without losing the job. */ }
    }));
   }
   }
   return reply({processed});
  }catch{return reply({error:'Temporarily unavailable'},503);}
 };
}
