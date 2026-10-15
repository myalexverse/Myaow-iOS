import test from 'node:test';
import assert from 'node:assert/strict';
import {createHandler,digest} from '../supabase/functions/myaow-api/handler.mjs';
const token='a'.repeat(64),id='12345678-1234-1234-1234-123456789012';
const bytes=new Uint8Array(64).fill(9);
function fixture(){
 const calls=[];let stored;
 const rpc=async(action,payload)=>{calls.push([action,payload]);if(action==='rate_limit')return{allowed:true};if(payload.token!==token)throw{code:'28000'};return{id,bytes:64,sha256:digest(bytes),ready:true};};
 const storage={put:async(i,b)=>{stored=b;},get:async()=>stored??bytes,remove:async()=>{stored=undefined;}};
 return{handler:createHandler(rpc,storage),calls,get stored(){return stored;}};
}
function request(path,body=bytes,auth=token,type='application/octet-stream'){
 return new Request('https://test/functions/v1/myaow-api'+path,{method:'POST',headers:{'content-type':type,...(auth?{authorization:'Bearer '+auth}:{})},body});
}
test('media authenticates before Storage, validates ciphertext length/hash and commits only exact bytes',async()=>{
 const f=fixture();assert.equal((await f.handler(request('/media/upload/'+id,bytes,null))).status,401);assert.equal(f.stored,undefined);
 assert.equal((await f.handler(request('/media/upload/'+id,new Uint8Array(65)))).status,413);
 assert.equal((await f.handler(request('/media/upload/'+id,new Uint8Array(64)))).status,400);assert.equal(f.stored,undefined);
 assert.equal((await f.handler(request('/media/upload/'+id))).status,200);assert.deepEqual(f.stored,bytes);
 assert.equal(f.calls.filter(([a])=>a==='media_commit').length,1);
});
test('private downloads authenticate, do not cache, and never expose storage keys or plaintext',async()=>{
 const f=fixture();const response=await f.handler(request('/media/download',JSON.stringify({id,token:'forged'}),token,'application/json'));
 assert.equal(response.status,200);assert.equal(response.headers.get('cache-control'),'no-store');assert.deepEqual(new Uint8Array(await response.arrayBuffer()),bytes);
 assert.equal(f.calls.find(([a])=>a==='media_download')[1].token,token);
});
test('Storage failure never commits a phantom attachment and hides provider errors',async()=>{
 let committed=false;const handler=createHandler(async(a)=>{if(a==='rate_limit')return{allowed:true};if(a==='media_commit')committed=true;return{id,bytes:64,sha256:digest(bytes)};},{put:async()=>{throw new Error('provider private details');}});
 const response=await handler(request('/media/upload/'+id));assert.equal(response.status,503);assert.equal(committed,false);assert.ok(!(await response.text()).includes('provider'));
});
