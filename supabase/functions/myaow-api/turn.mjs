import {createHmac} from 'node:crypto';

// Provider secrets stay in Supabase. Devices receive expiring relay-only credentials.
export function makeTURNProvider(config, send=fetch, now=()=>Date.now()) {
 const ttl=4*3600;
 return async owner=>{
  if(config.cloudflareKeyId && config.cloudflareToken) {
   if(!/^[a-zA-Z0-9_-]{16,128}$/.test(config.cloudflareKeyId))throw Error('TURN unavailable');
   const response=await send(`https://rtc.live.cloudflare.com/v1/turn/keys/${config.cloudflareKeyId}/credentials/generate-ice-servers`,{
    method:'POST',redirect:'error',signal:AbortSignal.timeout(8000),headers:{authorization:`Bearer ${config.cloudflareToken}`,'content-type':'application/json'},body:JSON.stringify({ttl})
   });
   if(!response.ok){await response.body?.cancel();throw Error('TURN unavailable');}
   const data=await response.json();
   const iceServers=(Array.isArray(data.iceServers)?data.iceServers:[]).flatMap(server=>{
    const urls=(Array.isArray(server.urls)?server.urls:[server.urls]).filter(url=>typeof url==='string' && /^turns?:turn\.cloudflare\.com:(3478|443|80|5349)(\?transport=(udp|tcp))?$/.test(url));
    return urls.length && typeof server.username==='string' && server.username && typeof server.credential==='string' && server.credential ? [{urls,username:server.username,credential:server.credential}] : [];
   });
   if(!iceServers.length)throw Error('TURN unavailable');
   return {iceServers,expiresAt:Math.floor(now()/1000)+ttl,iceTransportPolicy:'relay'};
  }
  const urls=(config.urls || '').split(',').map(x=>x.trim()).filter(Boolean),secret=config.sharedSecret || '';
  if(!urls.length || secret.length<32 || urls.some(x=>!/^turns?:[a-zA-Z0-9.\-]+:\d+(\?transport=(udp|tcp))?$/.test(x)))throw Error('TURN unavailable');
  const expiresAt=Math.floor(now()/1000)+ttl;
  const username=expiresAt+':'+createHmac('sha256',secret).update(owner).digest('hex').slice(0,24);
  return {iceServers:[{urls,username,credential:createHmac('sha1',secret).update(username).digest('base64')}],expiresAt,iceTransportPolicy:'relay'};
 };
}
