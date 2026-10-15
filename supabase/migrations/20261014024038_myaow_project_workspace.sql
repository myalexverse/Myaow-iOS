-- Additive project workspace. All data stays behind the authenticated gateway.
alter table myaow_private.tasks
 add constraint tasks_due_finite check(due_at is null or isfinite(due_at)),
 add column completed_due_at timestamptz,
 add column due_timezone text not null default 'UTC' check(length(due_timezone) between 1 and 80),
 add column is_key boolean not null default false,
 add column cadence text not null default 'once' check(cadence in ('once','daily','weekly'));
create index tasks_group_due on myaow_private.tasks(group_id,due_at) where state<>'done';
create or replace function myaow_private.task_json(t myaow_private.tasks) returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('id',t.id,'group_id',t.group_id,'title',t.title,'assignee_myaow_id',t.assignee,
 'assignee_name',(select display_name from myaow_private.profiles where id=t.assignee),'due_label',t.due_label,'priority',t.priority,'due_at',t.due_at,'completed_due_at',t.completed_due_at,'due_timezone',t.due_timezone,'is_key',t.is_key,'cadence',t.cadence,
 'is_completed',case when t.state='done' then 1 else 0 end,'state',t.state,'progress',t.progress,
 'completed_by_myaow_id',t.completed_by,'completed_by_name',(select display_name from myaow_private.profiles where id=t.completed_by),
 'completed_at',t.completed_at,'created_by_myaow_id',t.creator,'created_at',t.created_at,'updated_at',t.updated_at);
$$;
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
  insert into myaow_private.groups(id,owner,name,category,task_policy) values(gid,actor,payload->>'name',coalesce(payload->>'category','Trabajo'),coalesce(payload->>'taskPolicy','assigned'));
  insert into myaow_private.group_members(group_id,member,role) values(gid,actor,'owner');
  return jsonb_build_object('groupId',gid);
 end if;
 if action='groups_list' then
  select coalesce(jsonb_agg(to_jsonb(q)),'[]') into result from (
   select grp.id,grp.name,grp.category,grp.description,grp.task_policy,grp.owner as created_by,grp.created_at,
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
  update myaow_private.groups set name=coalesce(payload->>'name',name),description=coalesce(payload->>'description',description),task_policy=coalesce(payload->>'taskPolicy',task_policy) where id=gid;
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
  return jsonb_build_object('tasks',result,'task_policy',g.task_policy);
 elsif action='tasks_create' then
  if g.task_policy='admins' and role_name not in ('owner','admin') then raise exception 'Administrator required' using errcode='42501'; end if;
  if payload?'dueTimezone' and not exists(select 1 from pg_catalog.pg_timezone_names where name=payload->>'dueTimezone') then raise exception 'Invalid timezone' using errcode='22023'; end if;
  task_id=coalesce((payload->>'id')::uuid,gen_random_uuid()); recipient=nullif(payload->>'assigneeMyaowId','');
  if recipient is not null and not exists(select 1 from myaow_private.group_members where group_id=gid and member=recipient) then raise exception 'Assignee not in group' using errcode='42501'; end if;
  select * into t from myaow_private.tasks where id=task_id;
  if found then
   if t.group_id<>gid or t.creator<>actor or t.title is distinct from payload->>'title' or t.assignee is distinct from recipient or t.due_at is distinct from (payload->>'dueAt')::timestamptz or t.is_key is distinct from coalesce((payload->>'isKey')::boolean,false) or t.cadence is distinct from coalesce(payload->>'cadence','once') or t.due_timezone is distinct from coalesce(payload->>'dueTimezone','UTC') or t.priority is distinct from coalesce(payload->>'priority','normal') or t.due_label is distinct from coalesce(payload->>'dueLabel','Pronto') then raise exception 'Task ID reused' using errcode='23505'; end if;
  else
   if (select count(*) from myaow_private.tasks where group_id=gid)>=500 then raise exception 'Task limit' using errcode='54000'; end if;
   insert into myaow_private.tasks(id,group_id,creator,assignee,title,due_label,priority,due_at,due_timezone,is_key,cadence)
   values(task_id,gid,actor,recipient,payload->>'title',coalesce(payload->>'dueLabel','Pronto'),coalesce(payload->>'priority','normal'),(payload->>'dueAt')::timestamptz,coalesce(payload->>'dueTimezone','UTC'),coalesce((payload->>'isKey')::boolean,false),coalesce(payload->>'cadence','once')) returning * into t;
  end if;
  return jsonb_build_object('success',true,'task',myaow_private.task_json(t));
 elsif action in ('tasks_update','tasks_delete') then
  select * into t from myaow_private.tasks where id=(payload->>'id')::uuid for update;
  if not found or (role_name not in ('owner','admin') and (g.task_policy='admins' or (action='tasks_delete' and actor<>t.creator) or (action='tasks_update' and g.task_policy='assigned' and actor<>t.creator and actor is distinct from t.assignee))) then raise exception 'Task unavailable' using errcode='42501'; end if;
  if payload?'dueTimezone' and not exists(select 1 from pg_catalog.pg_timezone_names where name=payload->>'dueTimezone') then raise exception 'Invalid timezone' using errcode='22023'; end if;
  if payload?'assigneeMyaowId' and nullif(payload->>'assigneeMyaowId','') is not null and not exists(select 1 from myaow_private.group_members where group_id=gid and member=payload->>'assigneeMyaowId') then raise exception 'Assignee not in group' using errcode='42501'; end if;
  if action='tasks_delete' then delete from myaow_private.tasks where id=t.id;
  else
   new_state=coalesce(payload->>'state',case when payload?'completed' then case when (payload->>'completed')::boolean then 'done' else 'pending' end else t.state end);
   new_progress=case when new_state='done' then 100 when new_state='pending' then 0 else coalesce((payload->>'progress')::integer,t.progress) end;
   update myaow_private.tasks set state=new_state,progress=new_progress,updated_at=now(),
    assignee=case when payload?'assigneeMyaowId' then nullif(payload->>'assigneeMyaowId','') else assignee end,
    due_at=case when payload?'dueAt' then (payload->>'dueAt')::timestamptz else due_at end,
    due_label=case when payload?'dueAt' then 'Pronto' else due_label end,
    due_timezone=coalesce(payload->>'dueTimezone',due_timezone),
    is_key=coalesce((payload->>'isKey')::boolean,is_key),cadence=coalesce(payload->>'cadence',cadence),
    completed_due_at=case when new_state='done' then case when t.completed_at is null then t.due_at else t.completed_due_at end else null end,
    completed_by=case when new_state='done' then coalesce(t.completed_by,actor) else null end, completed_at=case when new_state='done' then coalesce(t.completed_at,now()) else null end where id=t.id returning * into t;
   return jsonb_build_object('success',true,'task',myaow_private.task_json(t));
  end if;
 else raise exception 'Unsupported operation' using errcode='22023'; end if;
 return jsonb_build_object('success',true);
end $$;


create table myaow_private.projects (
 group_id uuid primary key references myaow_private.groups(id) on delete cascade,
 objective text not null check(length(trim(objective)) between 1 and 1200),
 starts_at timestamptz not null check(isfinite(starts_at)),
 ends_at timestamptz not null check(isfinite(ends_at) and ends_at>starts_at),
 review_at timestamptz check(review_at is null or (isfinite(review_at) and review_at>=starts_at and review_at<=ends_at)),
 timezone text not null check(length(timezone) between 1 and 80),
 status text not null default 'active' check(status in ('active','paused','completed')),
 version integer not null default 1,
 updated_at timestamptz not null default now()
);
create table myaow_private.project_proposals (
 id uuid primary key, group_id uuid not null references myaow_private.groups(id) on delete cascade,
 author text not null references myaow_private.profiles(id),
 title text not null check(length(trim(title)) between 1 and 240),
 created_at timestamptz not null default now(),
 task_id uuid references myaow_private.tasks(id) on delete set null,
 accepted boolean not null default false,
 unique(id,group_id)
);
create index proposals_group_created on myaow_private.project_proposals(group_id,created_at);
create index proposals_author on myaow_private.project_proposals(author);
create index proposals_task on myaow_private.project_proposals(task_id) where task_id is not null;
create table myaow_private.project_votes (
 proposal_id uuid not null, group_id uuid not null, member text not null,
 primary key(proposal_id,member),
 foreign key(proposal_id,group_id) references myaow_private.project_proposals(id,group_id) on delete cascade,
 foreign key(group_id,member) references myaow_private.group_members(group_id,member) on delete cascade
);
create index votes_member on myaow_private.project_votes(group_id,member);
alter table myaow_private.projects enable row level security;
alter table myaow_private.project_proposals enable row level security;
alter table myaow_private.project_votes enable row level security;
revoke all on myaow_private.projects,myaow_private.project_proposals,myaow_private.project_votes from public,anon,authenticated;
grant select,insert,update,delete on myaow_private.projects,myaow_private.project_proposals,myaow_private.project_votes to service_role;

create function public.myaow_projects(action text,payload jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare actor text; gid uuid=(payload->>'groupId')::uuid; role_name text; result jsonb;
 project_row myaow_private.projects; idea myaow_private.project_proposals; desired_proposal_id uuid; created_task_id uuid;
begin
 if current_user not in ('service_role','postgres') then raise exception 'Forbidden' using errcode='42501'; end if;
 select owner into actor from myaow_private.sessions where token_hash=encode(extensions.digest(coalesce(payload->>'token',''),'sha256'),'hex') and expires_at>now();
 if actor is null then raise exception 'Authentication required' using errcode='28000'; end if;
 -- Same lock order as group kick/leave and task writes. Revocation wins before any new write.
 perform 1 from myaow_private.groups where id=gid for update;
 select role into role_name from myaow_private.group_members where group_id=gid and member=actor;
 if role_name is null then raise exception 'Group unavailable' using errcode='42501'; end if;
 if action='projects_save' then
  if role_name not in ('owner','admin') then raise exception 'Administrator required' using errcode='42501'; end if;
  if not exists(select 1 from pg_catalog.pg_timezone_names where name=payload->>'timezone') then raise exception 'Invalid timezone' using errcode='22023'; end if;
  if payload->>'status'='completed' and exists(select 1 from myaow_private.tasks where group_id=gid and state<>'done') then raise exception 'Pending tasks remain' using errcode='23505'; end if;
  select * into project_row from myaow_private.projects where group_id=gid;
  if coalesce(project_row.version,0)<>coalesce((payload->>'version')::integer,-1) then raise exception 'Project changed' using errcode='23505'; end if;
  insert into myaow_private.projects(group_id,objective,starts_at,ends_at,review_at,timezone,status)
   values(gid,payload->>'objective',(payload->>'startsAt')::timestamptz,(payload->>'endsAt')::timestamptz,(payload->>'reviewAt')::timestamptz,payload->>'timezone',payload->>'status')
  on conflict(group_id) do update set objective=excluded.objective,starts_at=excluded.starts_at,ends_at=excluded.ends_at,
   review_at=excluded.review_at,timezone=excluded.timezone,status=excluded.status,version=projects.version+1,updated_at=now();
 elsif action='projects_propose' then
  desired_proposal_id=(payload->>'id')::uuid;
  select * into idea from myaow_private.project_proposals where id=desired_proposal_id;
  if found then
   if idea.group_id<>gid or idea.author<>actor or idea.title is distinct from payload->>'title' then raise exception 'Proposal ID reused' using errcode='23505'; end if;
  else
   if (select count(*) from myaow_private.project_proposals where group_id=gid)>=200 then raise exception 'Proposal limit' using errcode='54000'; end if;
   insert into myaow_private.project_proposals(id,group_id,author,title) values(desired_proposal_id,gid,actor,payload->>'title');
  end if;
 elsif action in ('projects_vote','projects_accept') then
  select * into idea from myaow_private.project_proposals where id=(payload->>'id')::uuid and group_id=gid for update;
  if not found then raise exception 'Proposal unavailable' using errcode='42501'; end if;
  if action='projects_vote' then
   if idea.accepted then raise exception 'Voting closed' using errcode='23505'; end if;
   if (payload->>'voted')::boolean then
    insert into myaow_private.project_votes values(idea.id,gid,actor) on conflict do nothing;
   else delete from myaow_private.project_votes where proposal_id=idea.id and member=actor; end if;
  else
   if role_name not in ('owner','admin') then raise exception 'Administrator required' using errcode='42501'; end if;
   if not idea.accepted then
    created_task_id=gen_random_uuid();
    perform public.myaow_collaboration('tasks_create',jsonb_build_object('token',payload->>'token','groupId',gid,'id',created_task_id,'title',idea.title));
    update myaow_private.project_proposals set accepted=true,task_id=created_task_id where id=idea.id;
   end if;
  end if;
 elsif action<>'projects_get' then raise exception 'Unsupported operation' using errcode='22023'; end if;
 select coalesce(jsonb_agg(to_jsonb(q)),'[]') into result from (
  select i.id,i.title,i.author,p.display_name as author_name,i.accepted,i.task_id,
   (select count(*) from myaow_private.project_votes v where v.proposal_id=i.id) as votes,
   exists(select 1 from myaow_private.project_votes v where v.proposal_id=i.id and v.member=actor) as voted
  from myaow_private.project_proposals i join myaow_private.profiles p on p.id=i.author
  where i.group_id=gid order by i.accepted,i.created_at desc limit 200) q;
 return jsonb_build_object('project',(select to_jsonb(p) from myaow_private.projects p where p.group_id=gid),'proposals',result);
end $$;
revoke all on function public.myaow_projects(text,jsonb) from public,anon,authenticated;
grant execute on function public.myaow_projects(text,jsonb) to service_role;

-- A reopened task/new delivery reopens a previously completed project.
create function myaow_private.reopen_project_for_task() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 update myaow_private.projects set status='active',version=version+1,updated_at=now()
 where group_id=new.group_id and status='completed';
 return new;
end $$;
revoke all on function myaow_private.reopen_project_for_task() from public,anon,authenticated;
grant execute on function myaow_private.reopen_project_for_task() to service_role;
create trigger reopen_project_after_task after insert or update of state on myaow_private.tasks
for each row when (new.state<>'done') execute function myaow_private.reopen_project_for_task();
