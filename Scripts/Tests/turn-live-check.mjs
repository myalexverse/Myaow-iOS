// Controlled live check: temporary test identity, no messages or calls to users.
// No provider secret is accepted, read, saved or logged by this script.
import {generateKeyPairSync,createPrivateKey,createPublicKey,diffieHellman,hkdfSync,createHmac,createHash,randomBytes} from 'node:crypto';
import {readFileSync,writeFileSync,unlinkSync} from 'node:fs';
import {createSocket} from 'node:dgram';
import tls from 'node:tls';
import assert from 'node:assert/strict';

const base='https://your-project-ref.supabase.co/functions/v1/myaow-api';
const [mode,file]=process.argv.slice(2);
if(!file?.startsWith('/private/tmp/'))throw Error('Use a private temporary state file');
if(mode==='prepare'){
 const pair=generateKeyPairSync('x25519'), suffix=randomBytes(8).toString('hex');
 const state={id:'MYAOW-TURNCHECK-'+suffix,username:'turncheck_'+suffix,privateKey:pair.privateKey.export({format:'jwk'}),publicHex:Buffer.from(pair.publicKey.export({format:'jwk'}).x,'base64url').toString('hex')};
 writeFileSync(file,JSON.stringify(state),{mode:0o600,flag:'wx'});
 console.log(JSON.stringify({id:state.id,username:state.username,publicHex:state.publicHex}));
}else if(mode==='check'){
 const state=JSON.parse(readFileSync(file,'utf8'));
 let session;
 async function post(path,data={},token){
  return fetch(base+path,{method:'POST',redirect:'error',signal:AbortSignal.timeout(15000),headers:{'content-type':'application/json',...(token?{authorization:'Bearer '+token}:{})},body:JSON.stringify(data)});
 }
 try {
  assert.equal((await post('/webrtc/ice-servers')).status,401);
  assert.equal((await post('/webrtc/ice-servers',{},'0'.repeat(64))).status,401);
  const challengeResponse=await post('/auth/challenge',{myaowId:state.id});
  assert.equal(challengeResponse.status,200);
  const c=await challengeResponse.json();
  const context=Buffer.from(['MYAOW-AUTH-V2',state.id,c.nonce,c.serverPublicKeyHex,state.publicHex].join('\0'));
  const shared=diffieHellman({privateKey:createPrivateKey({format:'jwk',key:state.privateKey}),publicKey:createPublicKey({format:'jwk',key:{kty:'OKP',crv:'X25519',x:Buffer.from(c.serverPublicKeyHex,'hex').toString('base64url')}})});
  const proof=createHmac('sha256',hkdfSync('sha256',shared,Buffer.from(c.nonce),context,32)).update(context).digest('hex');
  const auth=await post('/auth/proof',{myaowId:state.id,id:c.id,proof});
  assert.equal(auth.status,200);session=(await auth.json()).sessionId;
  assert.match(session,/^[a-f0-9]{64}$/);
  const response=await post('/webrtc/ice-servers',{},session);
  assert.equal(response.status,200,'Authenticated TURN endpoint must succeed');
  assert.equal(response.headers.get('cache-control'),'no-store');
  const ice=await response.json();
  assert.equal(ice.iceTransportPolicy,'relay');
  const ttl=ice.expiresAt-Math.floor(Date.now()/1000);
  assert.ok(ttl>0 && ttl<=14400);
  assert.deepEqual(Object.keys(ice).sort(),['expiresAt','iceServers','iceTransportPolicy']);
  assert.ok(ice.iceServers.length>0);
  for(const s of ice.iceServers){
   assert.deepEqual(Object.keys(s).sort(),['credential','urls','username']);
   assert.ok(typeof s.username==='string' && typeof s.credential==='string');
   assert.ok(s.urls.every(u=>/^turns?:turn\.cloudflare\.com:(3478|443|80|5349)(\?transport=(udp|tcp))?$/.test(u)));
  }
  console.log('PASS: authentication, no-store, relay-only, expiring credentials, response field allowlist');
  for(const transport of ['udp','tls']){
   const expected=transport==='udp'?'turn:turn.cloudflare.com:3478?transport=udp':'turns:turn.cloudflare.com:5349?transport=tcp';
   const server=ice.iceServers.find(s=>s.urls.includes(expected));
   assert.ok(server,'Required TURN transport missing');
   await allocation(server,transport);
   console.log('PASS: TURN '+transport+' allocation authenticated and released');
  }
 }finally{
  if(session){const r=await post('/logout',{},session);assert.equal(r.status,200);assert.equal((await post('/webrtc/ice-servers',{},session)).status,401);console.log('PASS: test session revoked');}
  unlinkSync(file);
 }
}else throw Error('Use prepare or check');

function attr(type,value){const b=Buffer.alloc(4+Math.ceil(value.length/4)*4);b.writeUInt16BE(type);b.writeUInt16BE(value.length,2);value.copy(b,4);return b;}
function packet(type,attributes,key){
 const id=randomBytes(12),body=Buffer.concat(attributes),h=Buffer.alloc(20);
 h.writeUInt16BE(type);h.writeUInt16BE(body.length+(key?24:0),2);h.writeUInt32BE(0x2112a442,4);id.copy(h,8);
 const before=Buffer.concat([h,body]);return key?Buffer.concat([before,attr(8,createHmac('sha1',key).update(before).digest())]):before;
}
function attributes(data){
 assert.ok(data.length>=20 && data.readUInt32BE(4)===0x2112a442);
 const result=new Map();for(let i=20;i+4<=data.length;){const n=data.readUInt16BE(i+2);assert.ok(i+4+n<=data.length);result.set(data.readUInt16BE(i),data.subarray(i+4,i+4+n));i+=4+Math.ceil(n/4)*4;}return result;
}
async function allocation(server,transport){
 const socket=transport==='udp'?createSocket('udp4'):tls.connect({host:'turn.cloudflare.com',port:5349,servername:'turn.cloudflare.com',rejectUnauthorized:true});
 const opened=transport==='udp'?new Promise((resolve,reject)=>{socket.once('error',reject);socket.connect(3478,'turn.cloudflare.com',resolve);}):new Promise((resolve,reject)=>{socket.once('error',reject);socket.once('secureConnect',resolve);socket.setTimeout(10000,()=>socket.destroy(Error('TURN TLS timeout')));});
 try{
  await opened;
  function exchange(request){return new Promise((resolve,reject)=>{
   let buffered=Buffer.alloc(0);const event=transport==='udp'?'message':'data';
   const timer=setTimeout(()=>finish(Error('TURN response timeout')),10000);
   function finish(error,value){clearTimeout(timer);socket.removeListener(event,onData);socket.removeListener('error',onError);error?reject(error):resolve(value);}
   function onError(){finish(Error('TURN transport failed'));}
   function onData(chunk){buffered=Buffer.concat([buffered,chunk]);if(buffered.length<20)return;const n=20+buffered.readUInt16BE(2);if(buffered.length<n)return;const frame=buffered.subarray(0,n);if(!frame.subarray(8,20).equals(request.subarray(8,20))){buffered=buffered.subarray(n);return;}finish(null,frame);}
   socket.on(event,onData);socket.once('error',onError);
   transport==='udp'?socket.send(request):socket.write(request);
  });}
  const initial=await exchange(packet(3,[attr(0x19,Buffer.from([17,0,0,0]))]));
  const challenge=attributes(initial);assert.equal(initial.readUInt16BE(0),0x113);
  assert.ok(challenge.has(0x14)&&challenge.has(0x15));
  const realm=challenge.get(0x14),nonce=challenge.get(0x15);
  const key=createHash('md5').update(server.username+':'+realm.toString()+':'+server.credential).digest();
  const auth=[attr(6,Buffer.from(server.username)),attr(0x14,realm),attr(0x15,nonce)];
  const lifetime=Buffer.alloc(4);lifetime.writeUInt32BE(60);
  const result=await exchange(packet(3,[attr(0x19,Buffer.from([17,0,0,0])),attr(0xd,lifetime),...auth],key));
  assert.equal(result.readUInt16BE(0),0x103,'TURN allocation refused');assert.ok(attributes(result).has(0x16));
  const released=await exchange(packet(4,[attr(0xd,Buffer.alloc(4)),...auth],key));
  assert.equal(released.readUInt16BE(0),0x104);assert.equal(attributes(released).get(0xd)?.readUInt32BE(0),0);
 }finally{transport==='udp'?socket.close():socket.destroy();}
}
