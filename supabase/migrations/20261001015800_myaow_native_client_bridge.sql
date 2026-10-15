-- Native client reads and writes retain the same verified session authority.
create index profiles_id_casefold on myaow_private.profiles(lower(id));
create or replace function public.myaow_backend(action text, payload jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path = '' as $$
#variable_conflict use_variable
declare actor text; profile myaow_private.profiles; cfg myaow_private.settings;
 item myaow_private.messages; challenge myaow_private.challenges;
 envelope jsonb; recipient text; gid uuid; mid uuid; token text; result jsonb; n integer;
begin
 if current_user not in ('service_role','postgres') then raise exception 'Forbidden' using errcode='42501'; end if;
 if action='health' then return jsonb_build_object('status','ok','backend','supabase','phase','private-beta-collaboration','registration',(select registration_mode from myaow_private.settings where singleton)); end if;
 if action='rate_limit' then
  delete from myaow_private.rate_limits where expires_at<now();
  insert into myaow_private.rate_limits(key,hits,expires_at) values(payload->>'key',1,now()+interval '1 minute')
  on conflict(key) do update set hits=myaow_private.rate_limits.hits+1 returning hits into n;
  return jsonb_build_object('allowed',n<=60);
 end if;
 if action='username_available' then
  if not coalesce((payload->>'username')~'^[a-z0-9_]{3,30}$',false) then raise exception 'Invalid username' using errcode='22023'; end if;
  return jsonb_build_object('available',not exists(select 1 from myaow_private.profiles where username=payload->>'username'));
 end if;
 if action='register' then
  select * into cfg from myaow_private.settings where singleton for update;
  select * into profile from myaow_private.profiles where id=payload->>'myaowId';
  if found then
   if profile.identity_key_hex=lower(payload->>'identityKeyHex') and profile.username=payload->>'username' then
    return jsonb_build_object('registered',true);
   end if;
   raise exception 'Identity already registered' using errcode='23505';
  end if;
  if cfg.registration_mode<>'invite' then raise exception 'Registration closed' using errcode='42501'; end if;
  if (select count(*) from myaow_private.profiles)>=cfg.account_limit then raise exception 'Beta full' using errcode='42501'; end if;
  perform 1 from myaow_private.invitations where code_hash=encode(extensions.digest(coalesce(payload->>'betaInvite',''),'sha256'),'hex') and used_by is null and expires_at>now() for update;
  if not found then raise exception 'Invitation unavailable' using errcode='42501'; end if;
  insert into myaow_private.profiles(id,username,display_name,identity_key_hex)
  values(payload->>'myaowId',payload->>'username',payload->>'displayName',lower(payload->>'identityKeyHex'));
  update myaow_private.invitations set used_by=payload->>'myaowId',used_at=now()
   where code_hash=encode(extensions.digest(payload->>'betaInvite','sha256'),'hex');
  return jsonb_build_object('registered',true);
 end if;
 if action='challenge_profile' then
  select * into profile from myaow_private.profiles where id=payload->>'myaowId';
  if not found then raise exception 'Authentication failed' using errcode='28000'; end if;
  return jsonb_build_object('identityKeyHex',profile.identity_key_hex);
 end if;
 if action='challenge_store' then
  delete from myaow_private.challenges where expires_at<now();
  perform pg_advisory_xact_lock(hashtextextended(payload->>'myaowId',1));
  if (select count(*) from myaow_private.challenges where owner=payload->>'myaowId')>=5 then raise exception 'Too many challenges' using errcode='54000'; end if;
  insert into myaow_private.challenges(id,owner,proof_hash,expires_at)
   values((payload->>'id')::uuid,payload->>'myaowId',payload->>'proofHash',now()+interval '30 seconds');
  return '{}'::jsonb;
 end if;
 if action='authenticate' then
  delete from myaow_private.challenges where id=(payload->>'id')::uuid returning * into challenge;
  -- Return instead of raising, so a bad proof consumes this challenge.
  if challenge.id is null or challenge.expires_at<=now() or challenge.owner is distinct from payload->>'myaowId'
   or challenge.proof_hash<>encode(extensions.digest(coalesce(payload->>'proof',''),'sha256'),'hex') then
   return jsonb_build_object('error','Authentication failed');
  end if;
  perform pg_advisory_xact_lock(hashtextextended(challenge.owner,2));
  delete from myaow_private.sessions where expires_at<now();
  delete from myaow_private.sessions where token_hash in
   (select token_hash from myaow_private.sessions where owner=challenge.owner order by created_at desc offset 9);
  token=encode(extensions.gen_random_bytes(32),'hex');
  insert into myaow_private.sessions(token_hash,owner,expires_at)
   values(encode(extensions.digest(token,'sha256'),'hex'),challenge.owner,now()+interval '24 hours');
  return jsonb_build_object('sessionId',token,'expiresIn',86400);
 end if;
 select owner into actor from myaow_private.sessions
  where token_hash=encode(extensions.digest(coalesce(payload->>'token',''),'sha256'),'hex') and expires_at>now();
 if actor is null then raise exception 'Authentication required' using errcode='28000'; end if;
 if action='logout' then
  delete from myaow_private.sessions where token_hash=encode(extensions.digest(payload->>'token','sha256'),'hex');
  return jsonb_build_object('ok',true);
 end if;
 if action='profile' then
  select * into profile from myaow_private.profiles where id=actor;
  return jsonb_build_object('myaowId',actor,'username',profile.username,'displayName',profile.display_name,'identityKeyHex',profile.identity_key_hex);
 end if;
 if action='lookup' then
  select * into profile from myaow_private.profiles where username=lower(payload->>'username') or lower(id)=lower(payload->>'username');
  if not found or exists(select 1 from myaow_private.blocks where (owner=actor and target=profile.id) or (owner=profile.id and target=actor)) then
   raise exception 'Contact unavailable' using errcode='P0002';
  end if;
  return jsonb_build_object('myaowId',profile.id,'username',profile.username,'displayName',profile.display_name,'identityKeyHex',profile.identity_key_hex,'isOnline',false);
 end if;
 if action='blocked' then
  return jsonb_build_object('blockedIds',(select coalesce(jsonb_agg(target),'[]') from myaow_private.blocks where owner=actor));
 end if;
 if action='unblock' then
  delete from myaow_private.blocks where owner=actor and target=payload->>'target';
  return jsonb_build_object('ok',true);
 end if;
 if action='sync' then
  if jsonb_typeof(payload->'ids') is distinct from 'array' or jsonb_array_length(payload->'ids')>100 then raise exception 'Invalid receipt request' using errcode='22023'; end if;
  result=public.myaow_backend('pending',payload);
  return result || jsonb_build_object('receipts',(select coalesce(jsonb_agg(jsonb_build_object('id',m.envelope->>'messageId','status',case when m.delivered_at is null then 'queued_on_server' else 'delivered' end)),'[]')
    from myaow_private.messages m where m.sender=actor and m.id in (select value::uuid from jsonb_array_elements_text(payload->'ids'))));
 end if;
 if action='block' then
  if payload->>'target'=actor then raise exception 'Invalid target'; end if;
  insert into myaow_private.blocks(owner,target) values(actor,payload->>'target') on conflict do nothing;
  return jsonb_build_object('ok',true);
 end if;
 if action='send' then return myaow_private.accept_message(actor,payload->'envelope'); end if;
 if action='pending' then
  select coalesce(jsonb_agg(to_jsonb(q)),'[]') into result from (
   select m.sender,m.envelope->>'messageId' as id,m.envelope,m.created_at from myaow_private.messages m where m.recipient=actor and m.delivered_at is null
   and not exists(select 1 from myaow_private.blocks b where (b.owner=actor and b.target=m.sender) or (b.owner=m.sender and b.target=actor))
   and (m.group_id is null or (exists(select 1 from myaow_private.group_members where group_id=m.group_id and member=actor)
    and exists(select 1 from myaow_private.group_members where group_id=m.group_id and member=m.sender)))
   order by m.created_at,m.id limit 50) q;
  return jsonb_build_object('messages',result);
 end if;
 if action='acknowledge' then
  update myaow_private.messages set delivered_at=coalesce(delivered_at,now())
   where myaow_private.messages.recipient=actor and sender=payload->>'senderId' and id=(payload->>'id')::uuid;
  return jsonb_build_object('acknowledged',found);
 end if;
 raise exception 'Unsupported operation' using errcode='22023';
end $$;
revoke all on function public.myaow_backend(text,jsonb) from public,anon,authenticated;
grant execute on function public.myaow_backend(text,jsonb) to service_role;

