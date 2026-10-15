import { createPushWorker, makeAPNsGateway } from './worker.mjs';

const base = Deno.env.get('SUPABASE_URL');
const keys = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') || '{}');
const key = keys.default || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
const rpc = async (action: string, payload: unknown, functionName = "myaow_push") => {
 if (!base || !key) throw new Error('Unavailable');
 const headers: Record<string,string> = {'content-type':'application/json',apikey:key};
 if (!key.startsWith('sb_secret_')) headers.authorization = `Bearer ${key}`;
 const response = await fetch(`${base}/rest/v1/rpc/${functionName}`,{method:'POST',headers,
  body:JSON.stringify({action,payload}),signal:AbortSignal.timeout(10000)});
 if (!response.ok) { await response.body?.cancel(); throw new Error('Unavailable'); }
 return await response.json();
};
// Deno negotiates HTTP/2 through ALPN. Explicitly disallow HTTP/1 for APNs.
const client = Deno.createHttpClient({http1:false,http2:true});
const gateway = makeAPNsGateway({
 enabled:Deno.env.get('MYAOW_APNS_ENABLED')==='true',teamId:Deno.env.get('APNS_TEAM_ID'),keyId:Deno.env.get('APNS_KEY_ID'),
 privateKey:Deno.env.get('APNS_PRIVATE_KEY'),topics:(Deno.env.get('APNS_TOPICS') || '').split(',').filter(Boolean)
},(url: string,init: RequestInit)=>fetch(url,{...init,client}));
Deno.serve(createPushWorker({secret:Deno.env.get('MYAOW_PUSH_WORKER_SECRET'),gateway,rpc,callRpc:(action: string,payload: unknown)=>rpc(action,payload,"myaow_call_push")}));
