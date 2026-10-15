-- Short-lived authenticated signaling; media never passes through Postgres.
create table myaow_private.call_contacts (
 owner text not null references myaow_private.profiles(id) on delete cascade,
 peer text not null references myaow_private.profiles(id) on delete cascade,
 primary key(owner,peer), check(owner<>peer)
);
create index call_contacts_peer on myaow_private.call_contacts(peer);
create table myaow_private.call_sessions (
 id uuid primary key,
 caller text not null references myaow_private.profiles(id) on delete cascade,
 callee text not null references myaow_private.profiles(id) on delete cascade,
 state text not null check(state in ('ringing','accepted','ended')),
 expires_at timestamptz not null, created_at timestamptz not null default now(), check(caller<>callee)
);
create index call_sessions_caller on myaow_private.call_sessions(caller,expires_at) where state<>'ended';
create index call_sessions_callee on myaow_private.call_sessions(callee,expires_at) where state<>'ended';
create index call_sessions_expiry on myaow_private.call_sessions(expires_at);
create table myaow_private.call_signals (
 id uuid primary key, call_id uuid not null references myaow_private.call_sessions(id) on delete cascade,
 sender text not null references myaow_private.profiles(id) on delete cascade,
 recipient text not null references myaow_private.profiles(id) on delete cascade,
 signal_type text not null, packet jsonb not null, expires_at timestamptz not null,
 sequence bigint generated always as identity,
 check(octet_length(packet::text)<=60000)
);
create index call_signals_recipient on myaow_private.call_signals(recipient,sequence);
create index call_signals_call on myaow_private.call_signals(call_id);
create index call_signals_sender on myaow_private.call_signals(sender);
create index call_signals_expiry on myaow_private.call_signals(expires_at);
do $$ declare tab text; begin
 foreach tab in array array['call_contacts','call_sessions','call_signals'] loop
  execute format('alter table myaow_private.%I enable row level security',tab);
  execute format('revoke all on myaow_private.%I from public,anon,authenticated',tab);
  execute format('grant select,insert,update,delete on myaow_private.%I to service_role',tab);
 end loop;
end $$;
grant usage on sequence myaow_private.call_signals_sequence_seq to service_role;

create function myaow_private.calls_allowed(a text,b text) returns boolean
language sql stable security invoker set search_path='' as $$
 select exists(select 1 from myaow_private.call_contacts where owner=a and peer=b)
 and exists(select 1 from myaow_private.call_contacts where owner=b and peer=a)
 and not exists(select 1 from myaow_private.blocks where (owner=a and target=b) or (owner=b and target=a));
$$;
revoke all on function myaow_private.calls_allowed(text,text) from public,anon,authenticated;
grant execute on function myaow_private.calls_allowed(text,text) to service_role;

create function public.myaow_calls(action text,payload jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
#variable_conflict use_variable
declare actor text; peer text; cid uuid; mid uuid; kind text; expiry timestamptz; envelope jsonb; clean jsonb;
 prior myaow_private.call_signals; current_call myaow_private.call_sessions; result jsonb; hits integer; lock_id text;
begin
 if current_user not in ('service_role','postgres') then raise exception 'Forbidden' using errcode='42501'; end if;
 select owner into actor from myaow_private.sessions where token_hash=encode(extensions.digest(coalesce(payload->>'token',''),'sha256'),'hex') and expires_at>now();
 if actor is null then raise exception 'Authentication required' using errcode='28000'; end if;
 if action='calls_contacts' then
  if jsonb_typeof(payload->'callers') is distinct from 'array' or jsonb_array_length(payload->'callers')>1000
   or exists(select 1 from jsonb_array_elements(payload->'callers') v where jsonb_typeof(v)<>'string') then raise exception 'Invalid contacts' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended(actor,21));
  delete from myaow_private.call_contacts where owner=actor and peer not in(select jsonb_array_elements_text(payload->'callers'));
  insert into myaow_private.call_contacts(owner,peer)
   select actor,p.id from myaow_private.profiles p where p.id<>actor and p.id in(select jsonb_array_elements_text(payload->'callers')) on conflict do nothing;
  return jsonb_build_object('saved',true);
 elsif action='calls_ice' then
  -- Separate hourly budget, tied to the verified account rather than an expiring session.
  delete from myaow_private.rate_limits where key='ice:'||actor and expires_at<=now();
  insert into myaow_private.rate_limits(key,hits,expires_at) values('ice:'||actor,1,now()+interval '1 hour')
   on conflict(key) do update set hits=myaow_private.rate_limits.hits+1 returning rate_limits.hits into hits;
  if hits>40 then raise exception 'Calling budget reached' using errcode='54000'; end if;
  return jsonb_build_object('owner',actor);
 elsif action='calls_pending' then
  update myaow_private.call_sessions set expires_at=least(created_at+interval '3 hours',now()+interval '90 seconds')
   where id=nullif(payload->>'activeCallId','')::uuid and state='accepted' and expires_at>now()
    and actor in(caller,callee) and myaow_private.calls_allowed(caller,callee);
  select coalesce(jsonb_agg(packet order by sequence),'[]') into result from (
   select s.packet,s.sequence from myaow_private.call_signals s join myaow_private.call_sessions c on c.id=s.call_id
   where s.recipient=actor and s.expires_at>now() and c.expires_at>now()
    and (c.state<>'ended' or s.signal_type='call_hangup') and myaow_private.calls_allowed(s.sender,actor)
   order by s.sequence limit 300) q;
  return jsonb_build_object('signals',result);
 elsif action<>'calls_signal' then raise exception 'Unknown action' using errcode='22023'; end if;
 cid=(payload->>'callId')::uuid; mid=(payload->'packet'->>'id')::uuid; kind=payload->>'signalType';
 expiry=to_timestamp((payload->>'expiresAt')::double precision);
 if cid is null or mid is null or kind is null or kind not in ('call_offer','call_answer','call_hangup','webrtc_offer','webrtc_answer','webrtc_ice_candidate')
  or expiry is null or not isfinite(expiry) or expiry<=now() or expiry>now()+interval '95 seconds' then raise exception 'Invalid signal' using errcode='22023'; end if;
 envelope=(payload->'packet'->>'encryptedPayload')::jsonb;
 peer=myaow_private.validate_envelope(actor,envelope)->>'recipient';
 if (envelope->>'messageId')::uuid is distinct from mid or nullif(envelope->>'groupId','') is not null
  or peer is distinct from payload->'packet'->>'recipientMyaowId' then raise exception 'Invalid packet' using errcode='22023'; end if;
 clean=jsonb_build_object('type','call_signal','id',payload->'packet'->>'id','callId',payload->>'callId','signalType',kind,
  'expiresAt',payload->'expiresAt','senderMyaowId',actor,'recipientMyaowId',peer,'encryptedPayload',payload->'packet'->>'encryptedPayload');
 if octet_length(clean::text)>(case when kind='call_offer' then 4000 else 60000 end) then raise exception 'Signal too large' using errcode='22023'; end if;
 -- Ordered locks prevent simultaneous A->B and B->A offers from creating two calls.
 for lock_id in select unnest(array[actor,peer]) order by 1 loop perform pg_advisory_xact_lock(hashtextextended(lock_id,22)); end loop;
 if not myaow_private.calls_allowed(actor,peer) then raise exception 'Contact unavailable' using errcode='42501'; end if;
 select * into prior from myaow_private.call_signals where id=mid;
 if found then
  if prior.packet is distinct from clean then raise exception 'Signal ID reused' using errcode='23505'; end if;
  return jsonb_build_object('accepted',true,'duplicate',true);
 end if;
 select * into current_call from myaow_private.call_sessions where id=cid for update;
 if kind='call_offer' then
  if current_call.id is not null or exists(select 1 from myaow_private.call_sessions where state<>'ended' and expires_at>now()
   and (caller in(actor,peer) or callee in(actor,peer))) then raise exception 'Call unavailable' using errcode='23505'; end if;
  if (select count(*) from myaow_private.call_sessions where caller=actor and created_at>now()-interval '1 hour')>=30 then raise exception 'Call limit' using errcode='54000'; end if;
  insert into myaow_private.call_sessions(id,caller,callee,state,expires_at) values(cid,actor,peer,'ringing',least(expiry,now()+interval '45 seconds'));
 else
  if current_call.id is null or current_call.state='ended' or current_call.expires_at<=now()
   or not ((current_call.caller=actor and current_call.callee=peer) or (current_call.caller=peer and current_call.callee=actor)) then raise exception 'Call unavailable' using errcode='42501'; end if;
  if kind='call_answer' then
   if current_call.callee<>actor or current_call.state<>'ringing' then raise exception 'Invalid answer' using errcode='42501'; end if;
   update myaow_private.call_sessions set state='accepted',expires_at=now()+interval '90 seconds' where id=cid;
  elsif kind='call_hangup' then
   update myaow_private.call_sessions set state='ended',expires_at=now()+interval '95 seconds' where id=cid;
  elsif current_call.state<>'accepted' or (kind='webrtc_offer' and current_call.caller<>actor) or (kind='webrtc_answer' and current_call.callee<>actor) then
   raise exception 'Call not accepted' using errcode='42501';
  end if;
 end if;
 if (select count(*) from myaow_private.call_signals where call_id=cid)>=300 then raise exception 'Signal limit' using errcode='54000'; end if;
 insert into myaow_private.call_signals(id,call_id,sender,recipient,signal_type,packet,expires_at) values(mid,cid,actor,peer,kind,clean,expiry);
 perform myaow_private.wake_owner(peer);
 return jsonb_build_object('accepted',true);
end $$;
revoke all on function public.myaow_calls(text,jsonb) from public,anon,authenticated;
grant execute on function public.myaow_calls(text,jsonb) to service_role;
select cron.schedule('myaow-prune-calls','*/5 * * * *',
 $$delete from myaow_private.call_signals where expires_at<=now(); delete from myaow_private.call_sessions where expires_at<now()-interval '1 hour';$$);
