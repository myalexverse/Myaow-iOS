import { createHash, createPublicKey, generateKeyPairSync, diffieHellman, hkdfSync, createHmac, randomBytes, randomUUID } from 'node:crypto';
import { Buffer } from 'node:buffer';

export const protocol = 'myaow-x25519-hkdf-sha256-v2';
export const digest = value => createHash('sha256').update(value).digest('hex');
export function makeChallenge(id, publicHex) {
  if (!/^[a-f0-9]{64}$/i.test(publicHex)) throw new Error('Invalid identity');
  const publicKey = createPublicKey({format:'jwk', key:{kty:'OKP',crv:'X25519',x:Buffer.from(publicHex,'hex').toString('base64url')}});
  const pair = generateKeyPairSync('x25519');
  const serverPublicKeyHex = Buffer.from(pair.publicKey.export({format:'jwk'}).x,'base64url').toString('hex');
  const nonce = randomBytes(32).toString('hex');
  const context = Buffer.from(['MYAOW-AUTH-V2',id,nonce,serverPublicKeyHex,publicHex.toLowerCase()].join('\0'));
  const shared = diffieHellman({privateKey:pair.privateKey, publicKey});
  const key = hkdfSync('sha256',shared,Buffer.from(nonce),context,32);
  const proof = createHmac('sha256',key).update(context).digest('hex');
  return {id:randomUUID(),nonce,serverPublicKeyHex,protocol,proofHash:digest(proof)};
}

class HTTPError extends Error { constructor(status, message) { super(message); this.status=status; } }
const response = (data,status=200) => new Response(JSON.stringify(data), {status,headers:{'content-type':'application/json','cache-control':'no-store','x-content-type-options':'nosniff'}});
async function body(req, limit=220000) {
  if (!(req.headers.get('content-type') || '').toLowerCase().startsWith('application/json')) throw new HTTPError(415,'JSON required');
  if (!req.body) throw new HTTPError(400,'Invalid request');
  const reader=req.body.getReader(); const chunks=[]; let length=0;
  while (true) {
    const {done,value}=await reader.read(); if(done)break;
    length+=value.length;
    if(length>limit){await reader.cancel();throw new HTTPError(413,'Request too large');}
    chunks.push(value);
  }
  const bytes=new Uint8Array(length); let offset=0;
  for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
  let value;try{value=JSON.parse(new TextDecoder().decode(bytes));}catch{throw new HTTPError(400,'Invalid JSON');}
  if(!value || Array.isArray(value) || typeof value!=='object')throw new HTTPError(400,'Invalid request');
  return value;
}

// All account/data actions authenticate with the existing Myaow identity proof
// and a revocable server session. Supabase's privileged key stays in this worker.
export function createHandler(rpc, storage, turn) {
 return async req => {
  try {
   const pathname=new URL(req.url).pathname;
   const path=pathname.replace(/^\/myaow-api(?=\/|$)/,'').replace(/^\/functions\/v1\/myaow-api(?=\/|$)/,'') || '/';
   if(req.method==='GET' && path==='/health')return response(await rpc('health',{}));
   if(req.method!=='POST')throw new HTTPError(405,'Method not allowed');
   const data=path.startsWith('/media/')?null:await body(req,['/schedules/create','/messages/batch'].includes(path)?4500000:220000);
   const token=req.headers.get('authorization')?.match(/^Bearer ([a-f0-9]{64})$/)?.[1];
   const open=['/register','/auth/challenge','/auth/proof','/directory/check-username'];
   if(!open.includes(path) && !token)throw new HTTPError(401,'Authentication required');
   // Persisted rate bucket bounds beta workload across function restarts. Global
   // public admission limits are intentionally conservative for this closed pilot.
   // Fixed lanes: chat traffic must not starve ICE, answering or hangup.
   // Each lane retains the persisted 60/min limit; call account/hour and
   // membership limits still run in the authenticated calls RPC.
   const lane = path==='/messages/sync' || path==='/messages/pending' ? 'sync'
     : path==='/messages/acknowledge' ? 'receipts'
     : path==='/calls/signal' && data.signalType==='webrtc_ice_candidate' ? 'ice-signals'
     : path==='/calls/signal' && data.signalType==='call_hangup' ? 'hangup'
     : path==='/calls/signal' || path==='/calls/contacts' || path==='/webrtc/ice-servers' ? 'calls'
     : 'general';
   const rateKey=open.includes(path)?'public:'+path:'session:'+digest(token)+':'+lane;
   if(!(await rpc('rate_limit',{key:rateKey})).allowed)throw new HTTPError(429,'Try again later');
   if(path.startsWith('/media/')) {
    if(!storage) throw new HTTPError(503,'Storage unavailable');
    if(path.startsWith('/media/upload/')) {
     const id=path.slice('/media/upload/'.length);
     if(!/^[a-f0-9-]{36}$/.test(id))throw new HTTPError(400,'Invalid attachment');
     const item=await rpc('media_upload',{id,token});
     if(req.headers.get('content-type')!=='application/octet-stream')throw new HTTPError(415,'Encrypted bytes required');
     const reader=req.body?.getReader(); if(!reader)throw new HTTPError(400,'Missing attachment');
     const chunks=[];let length=0;
     while(true){const {value,done}=await reader.read();if(done)break;length+=value.length;
      if(length>item.bytes || length>10485788){await reader.cancel();throw new HTTPError(413,'Attachment too large');}chunks.push(value);}
     const bytes=new Uint8Array(length);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
     if(length!==item.bytes || digest(bytes)!==item.sha256)throw new HTTPError(400,'Attachment mismatch');
     // A retry may replace only identical ciphertext, validated against the reservation.
     await storage.put(id,bytes);
     await rpc('media_commit',{id,token});
     return response({id});
    }
    const data=await body(req,2048);
    if(path==='/media/prepare')return response(await rpc('media_prepare',{id:data.id,recipient:data.recipient,groupId:data.groupId,bytes:data.bytes,sha256:data.sha256,token}));
    if(path==='/media/download') {
     const item=await rpc('media_download',{id:data.id,token});
     const bytes=await storage.get(item.id);
     if(bytes.length!==item.bytes || digest(bytes)!==item.sha256)throw new HTTPError(503,'Attachment unavailable');
     return new Response(bytes,{headers:{'content-type':'application/octet-stream','cache-control':'no-store','x-content-type-options':'nosniff'}});
    }
    if(path==='/media/delete') {
     const item=await rpc('media_delete',{id:data.id,token});
     await storage.remove(item.id);
     await rpc('media_remove',{id:item.id,token});
     return response({deleted:true});
    }
    throw new HTTPError(404,'Not found');
   }
   if(path==='/directory/check-username') return response(await rpc('username_available',{username:data.username}));
   if(path==='/register') {
    if(typeof data.myaowId!=='string' || typeof data.username!=='string' || typeof data.displayName!=='string'
      || typeof data.identityKeyHex!=='string' || typeof data.betaInvite!=='string')throw new HTTPError(400,'Invalid registration');
    // Reject invalid/low-order X25519 identities before storing a profile.
    makeChallenge(data.myaowId,data.identityKeyHex);
    return response(await rpc('register',{myaowId:data.myaowId,username:data.username,displayName:data.displayName,
      identityKeyHex:data.identityKeyHex.toLowerCase(),betaInvite:data.betaInvite}));
   }
   if(path==='/auth/challenge') {
    if(!/^MYAOW-[A-Za-z0-9-]{4,64}$/.test(data.myaowId || ''))throw new HTTPError(400,'Invalid identity');
    const profile=await rpc('challenge_profile',{myaowId:data.myaowId});
    const challenge=makeChallenge(data.myaowId,profile.identityKeyHex);
    await rpc('challenge_store',{id:challenge.id,myaowId:data.myaowId,proofHash:challenge.proofHash});
    const {proofHash,...publicChallenge}=challenge;
    return response(publicChallenge);
   }
   if(path==='/auth/proof') {
    if(!/^[a-f0-9-]{36}$/i.test(data.id || '') || !/^[a-f0-9]{64}$/.test(data.proof || '') || typeof data.myaowId!=='string')throw new HTTPError(400,'Invalid proof');
    const result=await rpc('authenticate',{id:data.id,myaowId:data.myaowId,proof:data.proof});
    return response(result,result.error?401:200);
   }
   if(path==='/webrtc/ice-servers') {
    const {owner}=await rpc('calls_ice',{token});
    if(!turn)throw new HTTPError(503,'Calling relay is not configured');
    return response(await turn(owner));
   }
   if(path==='/messages/sync') {
    const result=await rpc('sync',{ids:data.ids,token});
    const calls=await rpc('calls_pending',{token,activeCallId:data.activeCallId});
    return response({...result,callSignals:calls.signals});
   }
   if(path==='/push/device' && Array.isArray(data.callers)) await rpc('calls_contacts',{callers:data.callers,token});
   const actions={
    '/calls/signal':['calls_signal',{callId:data.callId,signalType:data.signalType,expiresAt:data.expiresAt,packet:data.packet}],
    '/calls/contacts':['calls_contacts',{callers:data.callers}],
    '/push/device':['push_register',{installation:data.installation,environment:data.environment,bundleId:data.bundleId,alertToken:data.alertToken,voipToken:data.voipToken}],
    '/profile':['profile',{}],'/logout':['logout',{}],'/directory/lookup':['lookup',{username:data.username}],
    '/contacts/block':['block',{target:data.target}], '/contacts/unblock':['unblock',{target:data.target}],
    '/contacts/blocked':['blocked',{}], '/messages/sync':['sync',{ids:data.ids}], '/messages/send':['send',{envelope:data.envelope}],
    '/messages/pending':['pending',{}],'/messages/acknowledge':['acknowledge',{senderId:data.senderId,id:data.id}],
    '/messages/batch':['messages_batch',{packets:data.packets}],
    '/groups/create':['groups_create',{id:data.id,name:data.name,category:data.category,taskPolicy:data.taskPolicy}],
    '/groups/list':['groups_list',{}], '/groups/members':['groups_members',{groupId:data.groupId}],
    '/groups/invite':['groups_invite_create',{id:data.id,groupId:data.groupId,recipientId:data.recipientId}],
    '/groups/accept':['groups_invite_accept',{inviteId:data.inviteId}],
    '/groups/info':['groups_info',{groupId:data.groupId,name:data.name,description:data.description,taskPolicy:data.taskPolicy}],
    '/groups/leave':['groups_leave',{groupId:data.groupId}],
    '/groups/kick':['groups_kick',{groupId:data.groupId,target:data.target}],
    '/groups/promote':['groups_promote',{groupId:data.groupId,target:data.target}],
    '/groups/demote':['groups_demote',{groupId:data.groupId,target:data.target}],
    '/tasks/list':['tasks_list',{groupId:data.groupId}],
    '/tasks/create':['tasks_create',{id:data.id,groupId:data.groupId,title:data.title,assigneeMyaowId:data.assigneeMyaowId,dueLabel:data.dueLabel,priority:data.priority}],
    '/tasks/create-planned':['tasks_create',{id:data.id,groupId:data.groupId,title:data.title,assigneeMyaowId:data.assigneeMyaowId,dueLabel:data.dueLabel,priority:data.priority,dueAt:data.dueAt,dueTimezone:data.dueTimezone,isKey:data.isKey,cadence:data.cadence}],
    '/tasks/plan':['tasks_update',{id:data.id,dueAt:data.dueAt,dueTimezone:data.dueTimezone,isKey:data.isKey,cadence:data.cadence,assigneeMyaowId:data.assigneeMyaowId}],
    '/projects/get':['projects_get',{groupId:data.groupId}],
    '/projects/save':['projects_save',{groupId:data.groupId,objective:data.objective,startsAt:data.startsAt,endsAt:data.endsAt,reviewAt:data.reviewAt,timezone:data.timezone,status:data.status,version:data.version}],
    '/projects/propose':['projects_propose',{groupId:data.groupId,id:data.id,title:data.title}],
    '/projects/vote':['projects_vote',{groupId:data.groupId,id:data.id,voted:data.voted}],
    '/projects/accept':['projects_accept',{groupId:data.groupId,id:data.id}],
    '/tasks/update':['tasks_update',{id:data.id,completed:data.completed,state:data.state,progress:data.progress}],
    '/tasks/delete':['tasks_delete',{id:data.id}],
    '/schedules/create':['schedules_create',{id:data.id,due:data.due,preview:data.preview,packets:data.packets}],
    '/schedules/list':['schedules_list',{}], '/schedules/cancel':['schedules_cancel',{id:data.id}]
   };
   if(!actions[path])throw new HTTPError(404,'Not found');
   const [action,fields]=actions[path];
   return response(await rpc(action,{...fields,token}));
  } catch(error) {
   if(error instanceof HTTPError)return response({error:error.message},error.status);
   const code=error?.code;
   const status=code==='28000'?401:code==='42501'?403:code==='P0002'?404:code==='23505'?409:code==='54000'?429:
     typeof code==='string'&&(code.startsWith('22')||code.startsWith('23'))?400:503;
   return response({error:status===503?'Service temporarily unavailable':status===401?'Authentication required':status===403?'Operation not allowed':'Request rejected'},status);
  }
 };
}
