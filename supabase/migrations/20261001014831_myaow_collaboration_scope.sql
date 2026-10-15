-- Explicit local block scope for variables that share table-column names.
create or replace function myaow_private.validate_batch(actor text, packets jsonb) returns void
language plpgsql security invoker set search_path='' as $$
<<routing>>
declare packet jsonb; checked jsonb; envelope jsonb; recipients text[]='{}'; ids uuid[]='{}'; group_id uuid; first_item boolean=true; current_group uuid;
begin
 if jsonb_typeof(packets) is distinct from 'array' or jsonb_array_length(packets) not between 1 and 100 or octet_length(packets::text)>4194304 then
  raise exception 'Invalid encrypted batch' using errcode='22023'; end if;
 for packet in select value from jsonb_array_elements(packets) loop
  if jsonb_typeof(packet) is distinct from 'object' or exists(select 1 from jsonb_object_keys(packet) k where k not in ('id','type','senderMyaowId','senderDisplayName','recipientMyaowId','encryptedPayload')) then raise exception 'Invalid packet fields' using errcode='22023'; end if;
  envelope=(packet->>'encryptedPayload')::jsonb;
  checked=myaow_private.validate_envelope(actor,envelope); current_group=(checked->>'groupId')::uuid;
  if packet->>'type' is distinct from 'message' or packet->>'id' is distinct from envelope->>'messageId'
   or packet->>'senderMyaowId' is distinct from actor or packet->>'recipientMyaowId' is distinct from checked->>'recipient'
   or (checked->>'recipient')=any(recipients) or (packet->>'id')::uuid=any(ids) then raise exception 'Invalid packet routing' using errcode='22023'; end if;
  if first_item then group_id=current_group; first_item=false;
  elsif group_id is distinct from current_group then raise exception 'Mixed conversations' using errcode='22023'; end if;
  recipients=array_append(recipients,checked->>'recipient'); ids=array_append(ids,(packet->>'id')::uuid);
 end loop;
 if group_id is null and cardinality(recipients)>1 then raise exception 'Group required' using errcode='22023'; end if;
 if group_id is not null and ((select count(*) from myaow_private.group_members m where m.group_id=routing.group_id and m.member<>actor)<>cardinality(recipients)
  or exists(select 1 from myaow_private.group_members m where m.group_id=routing.group_id and m.member<>actor and not(m.member=any(recipients)))) then
  raise exception 'Group changed' using errcode='42501'; end if;
end $$;

create or replace function public.myaow_collaboration(action text,payload jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path='' as $$
<<collaboration>>
declare actor text; gid uuid; role_name text; g myaow_private.groups; inv myaow_private.group_invitations;
 t myaow_private.tasks; s myaow_private.schedules; result jsonb; recipient text; task_id uuid; invitation_id uuid;
 packet jsonb; due timestamptz; new_state text; new_progress integer; item record;
begin
 if current_user not in ('service_role','postgres') then raise exception 'Forbidden' using errcode='42501'; end if;
 select owner into actor from myaow_private.sessions where token_hash=encode(extensions.digest(coalesce(payload->>'token',''),'sha256'),'hex') and expires_at>now();
 if actor is null then raise exception 'Authentication required' using errcode='28000'; end if;
 if action='groups_create' then
  perform pg_advisory_xact_lock(hashtextextended(actor,10));
  gid=coalesce((payload->>'id')::uuid,gen_random_uuid());
  select * into g from myaow_private.groups where id=gid;
  if found then
   if g.owner<>actor or g.name is distinct from payload->>'name' or g.category is distinct from coalesce(payload->>'category','Trabajo') then raise exception 'Group ID reused' using errcode='23505'; end if;
   return jsonb_build_object('groupId',gid);
  end if;
  if (select count(*) from myaow_private.groups where owner=actor)>=20 then raise exception 'Group limit' using errcode='54000'; end if;
  insert into myaow_private.groups(id,owner,name,category) values(gid,actor,payload->>'name',coalesce(payload->>'category','Trabajo'));
  insert into myaow_private.group_members(group_id,member,role) values(gid,actor,'owner');
  return jsonb_build_object('groupId',gid);
 end if;
 if action='groups_list' then
  select coalesce(jsonb_agg(to_jsonb(q)),'[]') into result from (
   select grp.id,grp.name,grp.category,grp.description,grp.owner as created_by,grp.created_at,
    (select count(*) from myaow_private.group_members n where n.group_id=grp.id) as "memberCount"
   from myaow_private.groups grp join myaow_private.group_members m on m.group_id=grp.id where m.member=actor order by grp.created_at limit 100) q;
  return jsonb_build_object('groups',result);
 end if;
 if action='groups_invite_accept' then
  -- Lock the group first for a consistent lock order with kick/leave/invite.
  select group_id into gid from myaow_private.group_invitations where id=(payload->>'inviteId')::uuid;
  perform 1 from myaow_private.groups where id=gid for update;
  select * into inv from myaow_private.group_invitations where id=(payload->>'inviteId')::uuid for update;
  if not found or inv.recipient is distinct from actor then raise exception 'Invitation unavailable' using errcode='42501'; end if;
  if inv.state='accepted' and exists(select 1 from myaow_private.group_members where group_id=gid and member=actor) then return jsonb_build_object('groupId',gid); end if;
  if inv.state<>'pending' or inv.expires_at<=now()
   or not exists(select 1 from myaow_private.group_members where group_id=gid and member=inv.inviter and role in ('owner','admin'))
   or exists(select 1 from myaow_private.blocks where (owner=actor and target=inv.inviter) or (owner=inv.inviter and target=actor)) then raise exception 'Invitation unavailable' using errcode='42501'; end if;
  if (select count(*) from myaow_private.group_members where group_id=gid)>=30 then raise exception 'Group full' using errcode='54000'; end if;
  insert into myaow_private.group_members(group_id,member,role) values(gid,actor,'member') on conflict do nothing;
  update myaow_private.group_invitations set state='accepted' where id=inv.id;
  return jsonb_build_object('groupId',gid);
 end if;
 if action in ('schedules_create','schedules_list','schedules_cancel','messages_batch') then
  perform pg_advisory_xact_lock(hashtextextended(actor,11));
  if action='schedules_list' then
   select coalesce(jsonb_agg(to_jsonb(q)),'[]') into result from (
    select id,extract(epoch from due_at)*1000 as due,encrypted_preview as preview,state from myaow_private.schedules
    where owner=actor and state<>'cancelled' order by due_at desc limit 200) q;
   return jsonb_build_object('messages',result);
  elsif action='schedules_cancel' then
   select * into s from myaow_private.schedules where owner=actor and id=(payload->>'id')::uuid for update;
   if not found or s.state not in ('pending','attention','cancelled') then raise exception 'Already queued or unavailable' using errcode='23505'; end if;
   update myaow_private.schedules set state='cancelled' where owner=actor and id=s.id;
   return jsonb_build_object('success',true);
  elsif action='schedules_create' then
   due=to_timestamp((payload->>'due')::double precision/1000);
   select * into s from myaow_private.schedules where owner=actor and id=(payload->>'id')::uuid;
   if found then
    if s.due_at is distinct from due or s.packets is distinct from payload->'packets' or s.encrypted_preview is distinct from payload->>'preview' then raise exception 'Schedule ID reused' using errcode='23505'; end if;
    return jsonb_build_object('id',s.id,'due',extract(epoch from s.due_at)*1000,'preview',s.encrypted_preview,'state',s.state);
   end if;
   if due is null or due<=now() or due>now()+interval '30 days' or not isfinite(due)
    or payload->>'preview' is null or length(payload->>'preview') not between 32 and 200000
    or not((payload->>'preview')~'^[A-Za-z0-9+/]+={0,2}$') or octet_length(decode(payload->>'preview','base64'))<28 then raise exception 'Invalid schedule' using errcode='22023'; end if;
   if (select count(*) from myaow_private.schedules where owner=actor and state in ('pending','attention'))>=100 then raise exception 'Schedule limit' using errcode='54000'; end if;
   perform myaow_private.validate_batch(actor,payload->'packets');
   insert into myaow_private.schedules(owner,id,due_at,encrypted_preview,packets) values(actor,(payload->>'id')::uuid,due,payload->>'preview',payload->'packets') returning * into s;
   return jsonb_build_object('id',s.id,'due',extract(epoch from s.due_at)*1000,'preview',s.encrypted_preview,'state',s.state);
  else
   perform myaow_private.validate_batch(actor,payload->'packets');
   for packet in select value from jsonb_array_elements(payload->'packets') order by value->>'recipientMyaowId' loop
    perform myaow_private.accept_message(actor,(packet->>'encryptedPayload')::jsonb);
   end loop;
   return jsonb_build_object('status','queued','messages',(select jsonb_agg(value->>'id') from jsonb_array_elements(payload->'packets')));
  end if;
 end if;
 -- All following operations require membership, including reads. Never trust
 -- a creator/requester identifier supplied in the request body.
 if action in ('tasks_update','tasks_delete') then
  select group_id into gid from myaow_private.tasks where id=(payload->>'id')::uuid;
 else gid=(payload->>'groupId')::uuid; end if;
 select * into g from myaow_private.groups where id=gid for update;
 select role into role_name from myaow_private.group_members where group_id=gid and member=actor;
 if g.id is null or role_name is null then raise exception 'Group unavailable' using errcode='42501'; end if;
 if action='groups_members' then
  select coalesce(jsonb_agg(jsonb_build_object('myaow_id',p.id,'display_name',p.display_name,'role',case when m.role='owner' then 'admin' else m.role end)),'[]') into result
   from myaow_private.group_members m join myaow_private.profiles p on p.id=m.member where m.group_id=gid;
  return jsonb_build_object('members',result);
 elsif action='groups_invite_create' then
  if role_name not in ('owner','admin') then raise exception 'Administrator required' using errcode='42501'; end if;
  recipient=payload->>'recipientId'; invitation_id=coalesce((payload->>'id')::uuid,gen_random_uuid());
  if recipient=actor or recipient is null or not exists(select 1 from myaow_private.profiles where id=recipient)
   or exists(select 1 from myaow_private.blocks where (owner=actor and target=recipient) or (owner=recipient and target=actor)) then raise exception 'Contact unavailable' using errcode='42501'; end if;
  select * into inv from myaow_private.group_invitations where id=invitation_id;
  if found then
   if inv.group_id<>gid or inv.inviter<>actor or inv.recipient<>recipient then raise exception 'Invitation ID reused' using errcode='23505'; end if;
  else
   if (select count(*) from myaow_private.group_invitations where group_id=gid and state='pending' and expires_at>now())>=100 then raise exception 'Invitation limit' using errcode='54000'; end if;
   insert into myaow_private.group_invitations(id,group_id,inviter,recipient,expires_at) values(invitation_id,gid,actor,recipient,now()+interval '7 days');
  end if;
  return jsonb_build_object('inviteId',invitation_id,'groupId',gid);
 elsif action='groups_info' then
  if role_name not in ('owner','admin') then raise exception 'Administrator required' using errcode='42501'; end if;
  update myaow_private.groups set name=coalesce(payload->>'name',name),description=coalesce(payload->>'description',description) where id=gid;
 elsif action in ('groups_kick','groups_leave','groups_promote','groups_demote') then
  recipient=case when action='groups_leave' then actor else payload->>'target' end;
  if recipient is null or recipient=g.owner then raise exception 'Owner cannot be removed' using errcode='42501'; end if;
  if action<>'groups_leave' and (role_name not in ('owner','admin') or (role_name='admin' and exists(select 1 from myaow_private.group_members where group_id=gid and member=recipient and role<>'member'))) then raise exception 'Administrator required' using errcode='42501'; end if;
  if action in ('groups_promote','groups_demote') then
   if role_name<>'owner' then raise exception 'Owner required' using errcode='42501'; end if;
   update myaow_private.group_members set role=case when action='groups_promote' then 'admin' else 'member' end where group_id=gid and member=recipient;
  else
   delete from myaow_private.group_members where group_id=gid and member=recipient;
   update myaow_private.group_invitations set state='cancelled' where group_id=gid and state in ('pending','accepted') and (group_invitations.recipient=collaboration.recipient or inviter=collaboration.recipient);
   update myaow_private.tasks set assignee=null,updated_at=now() where group_id=gid and assignee=recipient;
  end if;
 elsif action='tasks_list' then
  select coalesce(jsonb_agg(myaow_private.task_json(q)),'[]') into result from (select * from myaow_private.tasks where group_id=gid order by created_at desc limit 500) q;
  return jsonb_build_object('tasks',result);
 elsif action='tasks_create' then
  task_id=coalesce((payload->>'id')::uuid,gen_random_uuid()); recipient=nullif(payload->>'assigneeMyaowId','');
  if recipient is not null and not exists(select 1 from myaow_private.group_members where group_id=gid and member=recipient) then raise exception 'Assignee not in group' using errcode='42501'; end if;
  select * into t from myaow_private.tasks where id=task_id;
  if found then
   if t.group_id<>gid or t.creator<>actor or t.title is distinct from payload->>'title' or t.assignee is distinct from recipient then raise exception 'Task ID reused' using errcode='23505'; end if;
  else
   if (select count(*) from myaow_private.tasks where group_id=gid)>=500 then raise exception 'Task limit' using errcode='54000'; end if;
   insert into myaow_private.tasks(id,group_id,creator,assignee,title,due_label,priority)
   values(task_id,gid,actor,recipient,payload->>'title',coalesce(payload->>'dueLabel','Pronto'),coalesce(payload->>'priority','normal')) returning * into t;
  end if;
  return jsonb_build_object('success',true,'task',myaow_private.task_json(t));
 elsif action in ('tasks_update','tasks_delete') then
  select * into t from myaow_private.tasks where id=(payload->>'id')::uuid for update;
  if not found or (role_name not in ('owner','admin') and actor<>t.creator and (action='tasks_delete' or actor is distinct from t.assignee)) then raise exception 'Task unavailable' using errcode='42501'; end if;
  if action='tasks_delete' then delete from myaow_private.tasks where id=t.id;
  else
   new_state=coalesce(payload->>'state',case when payload?'completed' then case when (payload->>'completed')::boolean then 'done' else 'pending' end else t.state end);
   new_progress=case when new_state='done' then 100 when new_state='pending' then 0 else coalesce((payload->>'progress')::integer,t.progress) end;
   update myaow_private.tasks set state=new_state,progress=new_progress,updated_at=now(),
    completed_by=case when new_state='done' then actor else null end, completed_at=case when new_state='done' then now() else null end where id=t.id returning * into t;
   return jsonb_build_object('success',true,'task',myaow_private.task_json(t));
  end if;
 else raise exception 'Unsupported operation' using errcode='22023'; end if;
 return jsonb_build_object('success',true);
end $$;

