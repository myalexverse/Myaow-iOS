-- Myaow private beta. Identity keys stay on devices, including offline Radio.
create schema myaow_private;
revoke all on schema myaow_private from public, anon, authenticated;
grant usage on schema myaow_private to service_role;
alter default privileges in schema myaow_private revoke all on tables from public, anon, authenticated;
alter default privileges in schema myaow_private revoke execute on functions from public, anon, authenticated;

create table myaow_private.settings (
 singleton boolean primary key default true check(singleton),
 registration_mode text not null default 'closed' check(registration_mode in ('closed','invite')),
 account_limit integer not null default 30 check(account_limit between 1 and 30)
);
insert into myaow_private.settings(singleton) values(true);
create table myaow_private.profiles (
 id text primary key check(id ~ '^MYAOW-[A-Za-z0-9-]{4,64}$'),
 username text not null unique check(username ~ '^[a-z0-9_]{3,30}$'),
 display_name text not null check(length(display_name) between 1 and 80),
 identity_key_hex text not null check(identity_key_hex ~ '^[a-f0-9]{64}$'),
 created_at timestamptz not null default now()
);
create table myaow_private.invitations (
 code_hash text primary key check(code_hash ~ '^[a-f0-9]{64}$'),
 expires_at timestamptz not null, used_by text unique references myaow_private.profiles(id), used_at timestamptz
);
create table myaow_private.challenges (
 id uuid primary key, owner text not null references myaow_private.profiles(id) on delete cascade,
 proof_hash text not null check(proof_hash ~ '^[a-f0-9]{64}$'), expires_at timestamptz not null
);
create index challenges_owner on myaow_private.challenges(owner);
create index challenges_expiry on myaow_private.challenges(expires_at);
create table myaow_private.sessions (
 token_hash text primary key check(token_hash ~ '^[a-f0-9]{64}$'),
 owner text not null references myaow_private.profiles(id) on delete cascade,
 expires_at timestamptz not null, created_at timestamptz not null default now()
);
create index sessions_owner on myaow_private.sessions(owner);
create index sessions_expiry on myaow_private.sessions(expires_at);
create table myaow_private.blocks (
 owner text not null references myaow_private.profiles(id) on delete cascade,
 target text not null references myaow_private.profiles(id) on delete cascade,
 primary key(owner,target), check(owner<>target)
);
create index blocks_target on myaow_private.blocks(target);
create table myaow_private.groups (
 id uuid primary key, owner text not null references myaow_private.profiles(id),
 name text not null check(length(name) between 1 and 80), created_at timestamptz not null default now()
);
create index groups_owner on myaow_private.groups(owner);
create table myaow_private.group_members (
 group_id uuid not null references myaow_private.groups(id) on delete cascade,
 member text not null references myaow_private.profiles(id) on delete cascade,
 role text not null check(role in ('owner','admin','member')), primary key(group_id,member)
);
create index group_members_member on myaow_private.group_members(member);
create table myaow_private.group_invitations (
 id uuid primary key, group_id uuid not null references myaow_private.groups(id) on delete cascade,
 inviter text not null references myaow_private.profiles(id), recipient text not null references myaow_private.profiles(id),
 expires_at timestamptz not null, state text not null default 'pending' check(state in ('pending','accepted','declined','cancelled'))
);
create index group_invitations_group on myaow_private.group_invitations(group_id);
create index group_invitations_recipient on myaow_private.group_invitations(recipient,state);
create index group_invitations_inviter on myaow_private.group_invitations(inviter);
create table myaow_private.tasks (
 id uuid primary key, group_id uuid not null references myaow_private.groups(id) on delete cascade,
 creator text not null references myaow_private.profiles(id), assignee text references myaow_private.profiles(id),
 title text not null check(length(title) between 1 and 240),
 state text not null default 'pending' check(state in ('pending','in_progress','done')),
 progress integer not null default 0 check(progress between 0 and 100),
 due_at timestamptz, updated_at timestamptz not null default now()
);
create index tasks_group on myaow_private.tasks(group_id,updated_at);
create index tasks_creator on myaow_private.tasks(creator);
create index tasks_assignee on myaow_private.tasks(assignee);
create table myaow_private.messages (
 sender text not null references myaow_private.profiles(id), id uuid not null,
 recipient text not null references myaow_private.profiles(id),
 group_id uuid references myaow_private.groups(id), envelope jsonb not null,
 created_at timestamptz not null default now(), delivered_at timestamptz,
 primary key(sender,id), check(sender<>recipient), check(octet_length(envelope::text)<=196608)
);
create index messages_pending on myaow_private.messages(recipient,created_at,id) where delivered_at is null;
create index messages_recipient on myaow_private.messages(recipient);
create index messages_group on myaow_private.messages(group_id);
create table myaow_private.schedules (
 owner text not null references myaow_private.profiles(id), id uuid not null,
 due_at timestamptz not null, encrypted_preview text not null, packets jsonb not null,
 state text not null default 'pending' check(state in ('pending','queued','delivered','cancelled','attention')),
 primary key(owner,id), check(jsonb_typeof(packets)='array'), check(octet_length(packets::text)<=4194304)
);
create index schedules_due on myaow_private.schedules(due_at) where state='pending';
create table myaow_private.push_devices (
 owner text not null references myaow_private.profiles(id) on delete cascade, installation uuid not null,
 environment text not null check(environment in ('sandbox','production')),
 alert_token text, voip_token text, allowed_callers text[] not null default '{}',
 updated_at timestamptz not null default now(), primary key(owner,installation)
);
create table myaow_private.push_jobs (
 id uuid primary key default gen_random_uuid(), owner text not null references myaow_private.profiles(id),
 sender text not null, message_id uuid not null,
 kind text not null check(kind in ('alert','voip')), payload jsonb not null,
 state text not null default 'pending' check(state in ('pending','accepted_by_apns','cancelled','failed')),
 attempts integer not null default 0, due_at timestamptz not null default now(), expires_at timestamptz not null,
 foreign key(sender,message_id) references myaow_private.messages(sender,id) on delete cascade,
 unique(owner,sender,message_id,kind)
);
create index push_jobs_sender_message on myaow_private.push_jobs(sender,message_id);
create index push_jobs_owner on myaow_private.push_jobs(owner);
create index push_jobs_due on myaow_private.push_jobs(due_at) where state='pending';
create table myaow_private.rate_limits (key text primary key, hits integer not null, expires_at timestamptz not null);

-- Private tables are not exposed through the Data API. RLS additionally denies
-- ordinary JWT roles; only the Edge Function's server credential may use RPCs.
do $$ declare t record; begin
 for t in select tablename from pg_tables where schemaname='myaow_private' loop
  execute format('alter table myaow_private.%I enable row level security',t.tablename);
  execute format('revoke all on myaow_private.%I from public,anon,authenticated',t.tablename);
  execute format('grant select,insert,update,delete on myaow_private.%I to service_role',t.tablename);
 end loop;
end $$;

create function public.myaow_backend(action text, payload jsonb default '{}') returns jsonb
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
   return jsonb_build_object('id',mid,'status',case when item.delivered_at is null then 'queued_on_server' else 'delivered' end);
  end if;
  perform pg_advisory_xact_lock(hashtextextended(recipient,4));
  if (select count(*) from myaow_private.messages where myaow_private.messages.recipient=recipient and delivered_at is null)>=1000
   or (select coalesce(sum(octet_length(m.envelope::text)),0) from myaow_private.messages m where m.recipient=recipient and m.delivered_at is null)>=8388608
   then raise exception 'Recipient queue full' using errcode='54000'; end if;
  insert into myaow_private.messages(sender,id,recipient,group_id,envelope) values(actor,mid,recipient,gid,envelope);
  return jsonb_build_object('id',mid,'status','queued_on_server');
 end if;
 if action='pending' then
  select coalesce(jsonb_agg(to_jsonb(q)),'[]') into result from (
   select m.sender,m.id,m.envelope,m.created_at from myaow_private.messages m where m.recipient=actor and m.delivered_at is null
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
