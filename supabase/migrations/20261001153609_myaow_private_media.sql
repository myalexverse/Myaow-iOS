-- Only encrypted bytes enter Storage. Names, types and keys stay in HPKE messages.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('myaow-ciphertext','myaow-ciphertext',false,10485788,array['application/octet-stream']);
create table myaow_private.media (
 id uuid primary key, owner text not null references myaow_private.profiles(id),
 recipient text references myaow_private.profiles(id), group_id uuid references myaow_private.groups(id),
 byte_count integer not null check(byte_count between 29 and 10485788),
 sha256 text not null check(sha256 ~ '^[a-f0-9]{64}$'),
 ready boolean not null default false, created_at timestamptz not null default now(),
 check ((recipient is null) <> (group_id is null))
);
create index media_owner on myaow_private.media(owner);
create index media_recipient on myaow_private.media(recipient);
create index media_group on myaow_private.media(group_id);
create table myaow_private.media_readers (
 media_id uuid not null references myaow_private.media(id) on delete cascade,
 reader text not null references myaow_private.profiles(id), primary key(media_id,reader)
);
create index media_readers_reader on myaow_private.media_readers(reader);
alter table myaow_private.media enable row level security;
alter table myaow_private.media_readers enable row level security;
revoke all on myaow_private.media,myaow_private.media_readers from public,anon,authenticated;
grant select,insert,update,delete on myaow_private.media,myaow_private.media_readers to service_role;
create policy media_no_direct_access on myaow_private.media for all to anon,authenticated using(false) with check(false);
create policy media_readers_no_direct_access on myaow_private.media_readers for all to anon,authenticated using(false) with check(false);

create function public.myaow_media(action text,payload jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path='' as $$
#variable_conflict use_variable
declare actor text; item myaow_private.media; mid uuid; target text; gid uuid; bytes integer;
begin
 if current_user not in ('service_role','postgres') then raise exception 'Forbidden' using errcode='42501'; end if;
 select owner into actor from myaow_private.sessions where token_hash=encode(extensions.digest(coalesce(payload->>'token',''),'sha256'),'hex') and expires_at>now();
 if actor is null then raise exception 'Authentication required' using errcode='28000'; end if;
 mid=(payload->>'id')::uuid;
 if mid is null then raise exception 'Invalid id' using errcode='22023'; end if;
 if action='media_prepare' then
  target=nullif(payload->>'recipient',''); gid=nullif(payload->>'groupId','')::uuid; bytes=(payload->>'bytes')::integer;
  if bytes is null or bytes<29 or bytes>10485788 or not coalesce((payload->>'sha256')~'^[a-f0-9]{64}$',false) or ((target is null) = (gid is null)) then raise exception 'Invalid attachment' using errcode='22023'; end if;
  -- Serialize reservations across accounts: the closed pilot has a hard 200 MiB budget.
  perform pg_advisory_xact_lock(hashtextextended('myaow-media-budget',0));
  select * into item from myaow_private.media where id=mid;
  if found then
   if item.owner<>actor or item.recipient is distinct from target or item.group_id is distinct from gid or item.byte_count<>bytes or item.sha256<>payload->>'sha256' then raise exception 'Attachment conflict' using errcode='23505'; end if;
   return jsonb_build_object('id',item.id,'ready',item.ready);
  end if;
  if target is not null and (target=actor or not exists(select 1 from myaow_private.profiles p where p.id=target) or exists(select 1 from myaow_private.blocks b where (b.owner=actor and b.target=target) or (b.owner=target and b.target=actor))) then raise exception 'Contact unavailable' using errcode='42501'; end if;
  if gid is not null and not exists(select 1 from myaow_private.group_members where group_id=gid and member=actor) then raise exception 'Group unavailable' using errcode='42501'; end if;
  if (select coalesce(sum(byte_count),0) from myaow_private.media)>=209715200-bytes or (select coalesce(sum(byte_count),0) from myaow_private.media where owner=actor)>=41943040-bytes then raise exception 'Storage quota' using errcode='54000'; end if;
  insert into myaow_private.media(id,owner,recipient,group_id,byte_count,sha256) values(mid,actor,target,gid,bytes,payload->>'sha256');
  if target is not null then insert into myaow_private.media_readers values(mid,target);
  else insert into myaow_private.media_readers select mid,m.member from myaow_private.group_members m where m.group_id=gid and m.member<>actor and not exists(select 1 from myaow_private.blocks b where (b.owner=actor and b.target=m.member) or (b.owner=m.member and b.target=actor)); end if;
  return jsonb_build_object('id',mid,'ready',false);
 end if;
 select * into item from myaow_private.media where id=mid;
 if not found then raise exception 'Not found' using errcode='P0002'; end if;
 if action in ('media_upload','media_commit','media_delete','media_remove') then
  if item.owner<>actor then raise exception 'Forbidden' using errcode='42501'; end if;
  if action='media_commit' then update myaow_private.media set ready=true where id=mid; end if;
  if action='media_remove' then delete from myaow_private.media where id=mid; end if;
 elsif action='media_download' then
  if not item.ready then raise exception 'Not ready' using errcode='P0002'; end if;
  if actor<>item.owner and (not exists(select 1 from myaow_private.media_readers where media_id=mid and reader=actor)
   or exists(select 1 from myaow_private.blocks b where (b.owner=actor and b.target=item.owner) or (b.owner=item.owner and b.target=actor))
   or (item.group_id is not null and (not exists(select 1 from myaow_private.group_members where group_id=item.group_id and member=actor) or not exists(select 1 from myaow_private.group_members where group_id=item.group_id and member=item.owner)))) then raise exception 'Forbidden' using errcode='42501'; end if;
 else raise exception 'Unknown operation' using errcode='22023'; end if;
 return jsonb_build_object('id',item.id,'bytes',item.byte_count,'sha256',item.sha256,'ready',item.ready);
end $$;
revoke all on function public.myaow_media(text,jsonb) from public,anon,authenticated;
grant execute on function public.myaow_media(text,jsonb) to service_role;
