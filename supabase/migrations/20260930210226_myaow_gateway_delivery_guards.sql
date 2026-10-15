-- Explicit deny documents the service-only boundary; it grants no table access.
do $$ declare t record; begin
 for t in select tablename from pg_tables where schemaname='myaow_private' loop
  execute format('create policy deny_direct_access on myaow_private.%I for all to anon,authenticated using (false) with check (false)',t.tablename);
 end loop;
end $$;

create or replace function public.myaow_backend(action text, payload jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path = '' as $$
#variable_conflict use_variable
declare actor text; profile myaow_private.profiles; cfg myaow_private.settings;
 item myaow_private.messages; challenge myaow_private.challenges;
 envelope jsonb; recipient text; gid uuid; mid uuid; token text; result jsonb; n integer;
begin
 if current_user not in ('service_role','postgres') then raise exception 'Forbidden' using errcode='42501'; end if;
 if action='health' then return jsonb_build_object('status','ok','backend','supabase','phase','identity-and-delivery','registration','closed-until-client-validation'); end if;
 if action='rate_limit' then
  delete from myaow_private.rate_limits where expires_at<now();
  insert into myaow_private.rate_limits(key,hits,expires_at) values(payload->>'key',1,now()+interval '1 minute')
  on conflict(key) do update set hits=myaow_private.rate_limits.hits+1 returning hits into n;
  return jsonb_build_object('allowed',n<=60);
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
  select * into profile from myaow_private.profiles where username=payload->>'username';
  if not found or exists(select 1 from myaow_private.blocks where (owner=actor and target=profile.id) or (owner=profile.id and target=actor)) then
   raise exception 'Contact unavailable' using errcode='P0002';
  end if;
  return jsonb_build_object('myaowId',profile.id,'username',profile.username,'displayName',profile.display_name,'identityKeyHex',profile.identity_key_hex,'isOnline',false);
 end if;
 if action='block' then
  if payload->>'target'=actor then raise exception 'Invalid target'; end if;
  insert into myaow_private.blocks(owner,target) values(actor,payload->>'target') on conflict do nothing;
  return jsonb_build_object('ok',true);
 end if;
 if action='send' then
  perform pg_advisory_xact_lock(hashtextextended(actor,3));
  envelope=payload->'envelope'; mid=(envelope->>'messageId')::uuid; recipient=envelope->>'recipientId';
  gid=nullif(envelope->>'groupId','')::uuid;
  select * into profile from myaow_private.profiles where id=actor;
  if jsonb_typeof(envelope) is distinct from 'object' or envelope->>'version' is distinct from '2'
   or envelope->>'senderId' is distinct from actor or envelope->>'senderPublicKey' is distinct from profile.identity_key_hex
   or recipient is null or recipient=actor or octet_length(envelope::text)>196608
   or not(envelope ?& array['version','messageId','senderId','recipientId','senderPublicKey','encapsulatedKey','ciphertext'])
   or exists(select 1 from jsonb_object_keys(envelope) k where k not in ('version','messageId','senderId','recipientId','senderPublicKey','encapsulatedKey','ciphertext','groupId'))
   or jsonb_typeof(envelope->'encapsulatedKey') is distinct from 'string'
   or jsonb_typeof(envelope->'ciphertext') is distinct from 'string'
   or octet_length(decode(envelope->>'encapsulatedKey','base64'))<>32
   or octet_length(decode(envelope->>'ciphertext','base64'))<16 then raise exception 'Invalid encrypted envelope' using errcode='22023'; end if;
  if exists(select 1 from myaow_private.blocks where (owner=actor and target=recipient) or (owner=recipient and target=actor))
   or (gid is not null and (not exists(select 1 from myaow_private.group_members where group_id=gid and member=actor)
   or not exists(select 1 from myaow_private.group_members where group_id=gid and member=recipient))) then raise exception 'Message unavailable' using errcode='42501'; end if;
  select * into item from myaow_private.messages where sender=actor and id=mid;
  if found then
   if item.envelope<>envelope then raise exception 'Message identifier reused' using errcode='23505'; end if;
   return jsonb_build_object('id',envelope->>'messageId','status',case when item.delivered_at is null then 'queued_on_server' else 'delivered' end);
  end if;
  perform pg_advisory_xact_lock(hashtextextended(recipient,4));
  if (select count(*) from myaow_private.messages where myaow_private.messages.recipient=recipient and delivered_at is null)>=1000
   or (select coalesce(sum(octet_length(m.envelope::text)),0) from myaow_private.messages m where m.recipient=recipient and m.delivered_at is null)>=8388608
   then raise exception 'Recipient queue full' using errcode='54000'; end if;
  insert into myaow_private.messages(sender,id,recipient,group_id,envelope) values(actor,mid,recipient,gid,envelope);
  return jsonb_build_object('id',envelope->>'messageId','status','queued_on_server');
 end if;
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
