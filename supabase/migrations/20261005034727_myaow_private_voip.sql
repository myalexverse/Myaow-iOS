-- VoIP has a separate enable switch and short TTL. No chat-content or public call endpoint.
alter table myaow_private.settings add column call_push_enabled boolean not null default false;
create table myaow_private.call_push_jobs (
 id uuid primary key default gen_random_uuid(), signal_id uuid not null references myaow_private.call_signals(id) on delete cascade,
 owner text not null, installation uuid not null, token_hash text not null,
 state text not null default 'pending' check(state in ('pending','accepted_by_apns','cancelled','failed')),
 attempts integer not null default 0, due_at timestamptz not null default now(),
 lease uuid, lease_until timestamptz,
 foreign key(owner,installation) references myaow_private.push_devices(owner,installation) on delete cascade,
 unique(signal_id,installation)
);
create index call_push_device on myaow_private.call_push_jobs(owner,installation);
create index call_push_due on myaow_private.call_push_jobs(due_at) where state='pending';
alter table myaow_private.call_push_jobs enable row level security;
revoke all on myaow_private.call_push_jobs from public,anon,authenticated;
grant select,insert,update,delete on myaow_private.call_push_jobs to service_role;

create function myaow_private.call_push_eligible(j myaow_private.call_push_jobs) returns boolean
language sql stable security invoker set search_path='' as $$
 select exists(select 1 from myaow_private.call_signals s join myaow_private.call_sessions c on c.id=s.call_id
  join myaow_private.push_devices d on d.owner=j.owner and d.installation=j.installation
  where s.id=j.signal_id and s.signal_type='call_offer' and s.recipient=j.owner and s.expires_at>now()
   and c.state='ringing' and c.expires_at>now() and d.updated_at>now()-interval '90 days'
   and d.environment='production' and d.bundle_id='com.ScendLabs.Myaow'
   and encode(extensions.digest(d.voip_token,'sha256'),'hex')=j.token_hash
   and myaow_private.calls_allowed(s.sender,s.recipient));
$$;

create or replace function myaow_private.invoke_push_worker() returns void
language plpgsql security invoker set search_path='' as $$
declare secret text;
begin
 if not ((select push_enabled from myaow_private.settings where singleton) and exists(select 1 from myaow_private.push_jobs where state='pending' and due_at<=now() and (lease_until is null or lease_until<=now())))
  and not ((select call_push_enabled from myaow_private.settings where singleton) and exists(select 1 from myaow_private.call_push_jobs where state='pending' and due_at<=now() and (lease_until is null or lease_until<=now()))) then return; end if;
 select decrypted_secret into secret from vault.decrypted_secrets where name='myaow_push_worker_secret';
 if secret is null or length(secret)<32 then return; end if;
 perform net.http_post(url:='https://your-project-ref.supabase.co/functions/v1/myaow-push',
  headers:=jsonb_build_object('Content-Type','application/json','x-myaow-worker',secret),body:='{}'::jsonb,timeout_milliseconds:=25000);
end $$;

-- Restricted trigger invokes only the fixed internal worker, never a user URL.
create function myaow_private.enqueue_call_push() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.signal_type<>'call_offer' or not (select call_push_enabled from myaow_private.settings where singleton) then return null; end if;
 insert into myaow_private.call_push_jobs(signal_id,owner,installation,token_hash)
  select new.id,new.recipient,d.installation,encode(extensions.digest(d.voip_token,'sha256'),'hex')
  from myaow_private.push_devices d where d.owner=new.recipient and d.voip_token is not null
   and d.environment='production' and d.bundle_id='com.ScendLabs.Myaow' and d.updated_at>now()-interval '90 days'
  on conflict do nothing;
 begin perform myaow_private.invoke_push_worker(); exception when others then
  raise log 'Myaow immediate call wake unavailable'; -- Scheduled worker is the recovery path.
 end;
 return null;
end $$;
create trigger myaow_enqueue_call_push after insert on myaow_private.call_signals for each row execute function myaow_private.enqueue_call_push();

create function public.myaow_call_push(action text,payload jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
#variable_conflict use_variable
declare j myaow_private.call_push_jobs; result jsonb='[]'; outcome text;
begin
 if current_user not in ('service_role','postgres') then raise exception 'Forbidden' using errcode='42501'; end if;
 if action='push_claim' then
  if not (select call_push_enabled from myaow_private.settings where singleton) then return '[]'; end if;
  update myaow_private.call_push_jobs q set state='cancelled',lease=null,lease_until=null
   where q.state='pending' and (q.attempts>=3 or not myaow_private.call_push_eligible(q));
  for j in select * from myaow_private.call_push_jobs where state='pending' and due_at<=now() and (lease_until is null or lease_until<=now())
   order by due_at,id limit 10 for update skip locked loop
   update myaow_private.call_push_jobs set lease=gen_random_uuid(),lease_until=now()+interval '12 seconds',attempts=attempts+1 where id=j.id returning * into j;
   result=result||jsonb_build_array(jsonb_build_object('id',j.id,'lease',j.lease));
  end loop;
  return result;
 elsif action in ('push_validate','push_finish') then
  select * into j from myaow_private.call_push_jobs where id=(payload->>'id')::uuid and lease=(payload->>'lease')::uuid and lease_until>now() and state='pending' for update;
  if not found then return jsonb_build_object('valid',false); end if;
  if not (select call_push_enabled from myaow_private.settings where singleton) or not myaow_private.call_push_eligible(j) then
   update myaow_private.call_push_jobs set state='cancelled',lease=null,lease_until=null where id=j.id;
   return jsonb_build_object('valid',false);
  end if;
  if action='push_validate' then
   select jsonb_build_object('valid',true,'id',j.id,'kind','voip','token',d.voip_token,'environment',d.environment,
    'topic',d.bundle_id,'expiration',floor(extract(epoch from least(s.expires_at,c.expires_at))),'payload',s.packet)
    into result from myaow_private.push_devices d join myaow_private.call_signals s on s.id=j.signal_id
    join myaow_private.call_sessions c on c.id=s.call_id where d.owner=j.owner and d.installation=j.installation;
   return result;
  end if;
  outcome=payload->>'outcome';
  if outcome is null or outcome not in ('accepted','retry','invalid','failed') then raise exception 'Invalid outcome' using errcode='22023'; end if;
  update myaow_private.call_push_jobs set state=case when outcome='accepted' then 'accepted_by_apns' when outcome in ('invalid','failed') or attempts>=3 then 'failed' else 'pending' end,
   due_at=now()+interval '2 seconds',lease=null,lease_until=null where id=j.id;
  if outcome='invalid' then update myaow_private.push_devices set voip_token=null where owner=j.owner and installation=j.installation and encode(extensions.digest(voip_token,'sha256'),'hex')=j.token_hash; end if;
  return jsonb_build_object('saved',true);
 end if;
 raise exception 'Unknown action' using errcode='22023';
end $$;
revoke all on function public.myaow_call_push(text,jsonb),myaow_private.call_push_eligible(myaow_private.call_push_jobs),myaow_private.enqueue_call_push() from public,anon,authenticated;
grant execute on function public.myaow_call_push(text,jsonb),myaow_private.call_push_eligible(myaow_private.call_push_jobs) to service_role;
