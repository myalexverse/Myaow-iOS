// Test-only stdio bridge to the REAL Edge handler. The RPC below is an in-memory
// substitute, not PostgreSQL and not a proof of deployed database behavior.
// No listener, network connection, environment secrets or production accounts.
import {createInterface} from 'node:readline';
import {randomBytes, timingSafeEqual} from 'node:crypto';
import {createHandler, digest} from '../../supabase/functions/myaow-api/handler.mjs';

const profiles = new Map(), challenges = new Map(), sessions = new Map();
let now = 0;
const fail = code => { throw {code}; };
const handler = createHandler(async (action, p) => {
  if (action === 'rate_limit') return {allowed: true};
  if (action === 'username_available') return {available: ![...profiles.values()].some(x => x.username === p.username)};
  if (action === 'register') {
    const previous = profiles.get(p.myaowId);
    if (previous) {
      if (previous.identityKeyHex === p.identityKeyHex && previous.username === p.username) return {registered: true};
      fail('23505');
    }
    if (p.betaInvite !== 'TEST-ONLY-INVITATION') fail('42501');
    if ([...profiles.values()].some(x => x.username === p.username)) fail('23505');
    profiles.set(p.myaowId, {myaowId:p.myaowId, username:p.username, displayName:p.displayName, identityKeyHex:p.identityKeyHex});
    return {registered:true};
  }
  if (action === 'challenge_profile') return profiles.get(p.myaowId) ?? fail('P0002');
  if (action === 'challenge_store') { challenges.set(p.id, {...p, expires: now + 90}); return {}; }
  if (action === 'authenticate') {
    const c = challenges.get(p.id);
    challenges.delete(p.id);
    if (!c || c.myaowId !== p.myaowId || c.expires <= now ||
        !timingSafeEqual(Buffer.from(c.proofHash,'hex'), Buffer.from(digest(p.proof),'hex'))) return {error:'Authentication failed'};
    const token = randomBytes(32).toString('hex');
    sessions.set(digest(token), {owner:c.myaowId, expires:now+86400});
    return {sessionId:token, expiresIn:86400};
  }
  const session = sessions.get(digest(p.token ?? ''));
  if (!session || session.expires <= now) fail('28000');
  if (action === 'profile') return profiles.get(session.owner);
  if (action === 'logout') { sessions.delete(digest(p.token)); return {ok:true}; }
  if (action === 'lookup') return [...profiles.values()].find(x => x.username === p.username.toLowerCase() || x.myaowId.toLowerCase() === p.username.toLowerCase()) ?? fail('P0002');
  fail('22023');
});

for await (const line of createInterface({input:process.stdin, crlfDelay:Infinity})) {
  try {
    const input = JSON.parse(line);
    if (input.advanceSeconds !== undefined) { now += input.advanceSeconds; process.stdout.write('{}\n'); continue; }
    const req = new Request('https://test.invalid/functions/v1/myaow-api/' + input.route, {
      method:'POST', headers:{'content-type':'application/json', ...(input.token ? {authorization:'Bearer '+input.token} : {})},
      body:input.body
    });
    const response = await handler(req);
    process.stdout.write(JSON.stringify({status:response.status, body:await response.text()})+'\n');
  } catch { process.stdout.write(JSON.stringify({status:500, body:'{}'})+'\n'); }
}
