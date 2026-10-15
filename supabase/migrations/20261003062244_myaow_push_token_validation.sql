-- PostgreSQL repetition bounds stop at 255; validate length separately.
create or replace function public.myaow_push(action text,payload jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
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
    'expiration',floor(extract(epoch from j.expires_at))) into result from myaow_private.push_devices d where d.owner=j.owner and d.installation=j.installation;
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
end $$;
