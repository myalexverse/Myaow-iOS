-- Exposes only an allowlisted sound ID for maullido push delivery. No chat text.
set local lock_timeout='2s';
set local statement_timeout='15s';
CREATE OR REPLACE FUNCTION myaow_private.validate_envelope(actor text, envelope jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
#variable_conflict use_variable
declare profile myaow_private.profiles; mid uuid; recipient text; gid uuid;
begin
  mid=(envelope->>'messageId')::uuid; recipient=envelope->>'recipientId';
  gid=nullif(envelope->>'groupId','')::uuid;
  if gid is not null then perform 1 from myaow_private.groups where id=gid for share; end if;
  select * into profile from myaow_private.profiles where id=actor;
  if jsonb_typeof(envelope) is distinct from 'object' or envelope->>'version' is distinct from '2'
   or envelope->>'senderId' is distinct from actor or envelope->>'senderPublicKey' is distinct from profile.identity_key_hex
   or recipient is null or recipient=actor or octet_length(envelope::text)>196608
   or not(envelope ?& array['version','messageId','senderId','recipientId','senderPublicKey','encapsulatedKey','ciphertext'])
   or exists(select 1 from jsonb_object_keys(envelope) k where k not in ('version','messageId','senderId','recipientId','senderPublicKey','encapsulatedKey','ciphertext','groupId','notificationSound'))
   or (envelope ? 'notificationSound' and (jsonb_typeof(envelope->'notificationSound') is distinct from 'string' or envelope->>'notificationSound' not in ('classic','electric','cosmic','melodic','claw','lazy','kiss','giggle','party','question','sleepy','echo','mentada','admiration')))
   or jsonb_typeof(envelope->'encapsulatedKey') is distinct from 'string'
   or jsonb_typeof(envelope->'ciphertext') is distinct from 'string'
   or octet_length(decode(envelope->>'encapsulatedKey','base64'))<>32
   or octet_length(decode(envelope->>'ciphertext','base64'))<16 then raise exception 'Invalid encrypted envelope' using errcode='22023'; end if;
  if exists(select 1 from myaow_private.blocks where (owner=actor and target=recipient) or (owner=recipient and target=actor))
   or (gid is not null and (not exists(select 1 from myaow_private.group_members where group_id=gid and member=actor)
   or not exists(select 1 from myaow_private.group_members where group_id=gid and member=recipient))) then raise exception 'Message unavailable' using errcode='42501'; end if;
  return jsonb_build_object('recipient',recipient,'groupId',gid);
end $function$;

CREATE OR REPLACE FUNCTION myaow_private.enqueue_push()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
 if TG_OP='UPDATE' then
  if new.delivered_at is not null then update myaow_private.push_jobs set state='cancelled',lease=null,lease_until=null where sender=new.sender and message_id=new.id and state='pending'; end if;
 elsif (select push_enabled from myaow_private.settings where singleton) then
  insert into myaow_private.push_jobs(owner,sender,message_id,kind,payload,expires_at,installation,token_hash)
  select new.recipient,new.sender,new.id,'alert',case when new.envelope->>'notificationSound' in ('classic','electric','cosmic','melodic','claw','lazy','kiss','giggle','party','question','sleepy','echo','mentada','admiration') then jsonb_build_object('notificationSound',new.envelope->>'notificationSound') else '{}'::jsonb end,now()+interval '24 hours',d.installation,encode(extensions.digest(d.alert_token,'sha256'),'hex')
  from myaow_private.push_devices d where d.owner=new.recipient and d.alert_token is not null and d.updated_at>now()-interval '90 days'
  on conflict do nothing;
 end if;
 return null;
end $function$;

CREATE OR REPLACE FUNCTION public.myaow_push(action text, payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
#variable_conflict use_variable
declare actor text; sh text; iid uuid; env text; topic text; alert text; voice text; j myaow_private.push_jobs; result jsonb='[]'; outcome text;
begin
 if action='push_register' then
  sh=encode(extensions.digest(coalesce(payload->>'token',''),'sha256'),'hex');
  select owner into actor from myaow_private.sessions where token_hash=sh and expires_at>now();
  if actor is null then raise exception 'Authentication required' using errcode='28000'; end if;
  iid=(payload->>'installation')::uuid; env=payload->>'environment'; topic=payload->>'bundleId';
  alert=lower(nullif(payload->>'alertToken','')); voice=lower(nullif(payload->>'voipToken',''));
  if iid is null or env is null or env not in ('sandbox','production') or topic is null or topic not in ('com.ScendLabs.Myaow','com.ScendLabs.Myaow.SupabasePilot')
   or (alert is not null and (length(alert) not between 32 and 512 or alert !~ '^[a-f0-9]+$')) or (voice is not null and (length(voice) not between 32 and 512 or voice !~ '^[a-f0-9]+$')) then raise exception 'Invalid device' using errcode='22023'; end if;
  -- Bound registration and serialize same-token ownership transfers between accounts.
  perform pg_advisory_xact_lock(hashtextextended('push-register',14));
  if alert is null and voice is null then
   delete from myaow_private.push_devices where owner=actor and installation=iid;
  else
   delete from myaow_private.push_devices where bundle_id=topic and environment=env and (owner<>actor or installation<>iid)
    and ((alert is not null and alert_token=alert) or (voice is not null and voip_token=voice));
   if not exists(select 1 from myaow_private.push_devices where owner=actor and installation=iid)
    and (select count(*) from myaow_private.push_devices where owner=actor)>=5 then raise exception 'Device limit' using errcode='54000'; end if;
   insert into myaow_private.push_devices(owner,installation,environment,alert_token,voip_token,bundle_id,session_hash)
   values(actor,iid,env,alert,voice,topic,sh)
   on conflict(owner,installation) do update set environment=excluded.environment,alert_token=excluded.alert_token,voip_token=excluded.voip_token,
    bundle_id=excluded.bundle_id,session_hash=excluded.session_hash,updated_at=now();
  end if;
  return jsonb_build_object('registered',true,'deliveryEnabled',(select push_enabled from myaow_private.settings where singleton));
 end if;
 -- Worker actions have no public API route and EXECUTE is restricted to service_role.
 if action='push_claim' then
  if not (select push_enabled from myaow_private.settings where singleton) then return '[]'; end if;
  update myaow_private.push_jobs q set state='cancelled',lease=null,lease_until=null
   where q.state='pending' and (q.attempts>=8 or not myaow_private.push_eligible(q));
  for j in select * from myaow_private.push_jobs where state='pending' and due_at<=now() and (lease_until is null or lease_until<=now())
   order by due_at,id limit 10 for update skip locked loop
   update myaow_private.push_jobs set lease=gen_random_uuid(),lease_until=now()+interval '2 minutes',attempts=attempts+1 where id=j.id returning * into j;
   result=result||jsonb_build_array(jsonb_build_object('id',j.id,'lease',j.lease));
  end loop;
  return result;
 elsif action in ('push_validate','push_finish') then
  select * into j from myaow_private.push_jobs where id=(payload->>'id')::uuid and lease=(payload->>'lease')::uuid and lease_until>now() and state='pending' for update;
  if not found then return jsonb_build_object('valid',false); end if;
  if not (select push_enabled from myaow_private.settings where singleton) or not myaow_private.push_eligible(j) then
   update myaow_private.push_jobs set state='cancelled',lease=null,lease_until=null where id=j.id;
   return jsonb_build_object('valid',false);
  end if;
  if action='push_validate' then
   select jsonb_build_object('valid',true,'id',j.id,'token',d.alert_token,'environment',d.environment,'topic',d.bundle_id,
    'notificationSound',j.payload->>'notificationSound','expiration',floor(extract(epoch from j.expires_at))) into result from myaow_private.push_devices d where d.owner=j.owner and d.installation=j.installation;
   return result;
  end if;
  outcome=payload->>'outcome';
  if outcome is null or outcome not in ('accepted','retry','invalid','failed') then raise exception 'Invalid result' using errcode='22023'; end if;
  update myaow_private.push_jobs set state=case when outcome='accepted' then 'accepted_by_apns' when outcome in ('invalid','failed') or attempts>=8 then 'failed' else 'pending' end,
   due_at=now()+make_interval(secs=>least(3600,5*power(2,attempts))::integer),lease=null,lease_until=null where id=j.id;
  if outcome='invalid' then update myaow_private.push_devices set alert_token=null where owner=j.owner and installation=j.installation and encode(extensions.digest(alert_token,'sha256'),'hex')=j.token_hash; end if;
  return jsonb_build_object('saved',true);
 end if;
 raise exception 'Unknown action' using errcode='22023';
end $function$;
