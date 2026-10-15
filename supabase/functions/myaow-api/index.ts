import { createHandler } from './handler.mjs';
import { makeTURNProvider } from './turn.mjs';

const base = Deno.env.get('SUPABASE_URL');
const keys = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') || '{}');
const key = keys.default || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
const rpc = async (action: string, payload: unknown) => {
 if (!base || !key) throw new Error('Configuration unavailable');
 const headers: Record<string,string> = {'content-type':'application/json',apikey:key};
 if (!key.startsWith('sb_secret_')) headers.authorization = `Bearer ${key}`;
 const functionName = action.startsWith('projects_') ? 'myaow_projects' : action.startsWith('calls_') ? 'myaow_calls' : action.startsWith('push_') ? 'myaow_push' : action.startsWith('media_') ? 'myaow_media' : /^(groups_|tasks_|schedules_)/.test(action) || action==='messages_batch' ? 'myaow_collaboration' : 'myaow_backend';
 const response = await fetch(`${base}/rest/v1/rpc/${functionName}`, {
  method:'POST', headers, body:JSON.stringify({action,payload}), signal:AbortSignal.timeout(10000)
 });
 const result = await response.json();
 if (!response.ok) throw {code: result.code};
 return result;
};
const storageRequest = async (path: string, init: RequestInit = {}) => {
 if (!base || !key) throw new Error('Configuration unavailable');
 const headers: Record<string,string> = {apikey:key,...(init.headers as Record<string,string> || {})};
 if (!key.startsWith('sb_secret_')) headers.authorization = `Bearer ${key}`;
 const result = await fetch(`${base}/storage/v1/${path}`,{...init,headers,signal:AbortSignal.timeout(45000)});
 if(!result.ok) { await result.body?.cancel(); throw new Error('Storage unavailable'); }
 return result;
};
const objectPath = (id: string) => {
 if(!/^[a-f0-9-]{36}$/.test(id))throw new Error('Invalid object');
 return `object/myaow-ciphertext/${id}`;
};
Deno.serve(createHandler(rpc,{
 put: async (id: string, bytes: Uint8Array) => {
  const result=await storageRequest(objectPath(id),{method:'POST',headers:{'content-type':'application/octet-stream','x-upsert':'true'},body:bytes});
  await result.body?.cancel();
 },
 get: async (id: string) => {
  const result=await storageRequest(objectPath(id));
  return new Uint8Array(await result.arrayBuffer());
 },
 remove: async (id: string) => {
  objectPath(id);
  const result=await storageRequest('object/myaow-ciphertext',{method:'DELETE',headers:{'content-type':'application/json'},body:JSON.stringify({prefixes:[id]})});
  await result.body?.cancel();
 }
}, makeTURNProvider({cloudflareKeyId:Deno.env.get("TURN_CLOUDFLARE_KEY_ID"),cloudflareToken:Deno.env.get("TURN_CLOUDFLARE_API_TOKEN"),
 urls:Deno.env.get("TURN_URLS"),sharedSecret:Deno.env.get("TURN_SHARED_SECRET")})));
