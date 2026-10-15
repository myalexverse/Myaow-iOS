begin;
do $$
declare a text='MYAOW-PLAN-A'; b text='MYAOW-PLAN-B'; c text='MYAOW-PLAN-C';
 ta text=repeat('a',64); tb text=repeat('b',64); tc text=repeat('c',64);
 gid uuid=gen_random_uuid(); tid uuid=gen_random_uuid(); iid uuid=gen_random_uuid(); other_gid uuid=gen_random_uuid();
 r jsonb; original jsonb; plan jsonb; due timestamptz='2026-11-05T18:30:00-06:00';
begin
 insert into myaow_private.profiles(id,username,display_name,identity_key_hex) values
 (a,'project_a','A',repeat('1',64)),(b,'project_b','B',repeat('2',64)),(c,'project_c','C',repeat('3',64));
 insert into myaow_private.sessions(token_hash,owner,expires_at) values
 (encode(extensions.digest(ta,'sha256'),'hex'),a,now()+interval '1 hour'),
 (encode(extensions.digest(tb,'sha256'),'hex'),b,now()+interval '1 hour'),
 (encode(extensions.digest(tc,'sha256'),'hex'),c,now()+interval '1 hour');
 perform public.myaow_collaboration('groups_create',jsonb_build_object('token',ta,'id',gid,'name','Project fixture'));
 insert into myaow_private.group_members values(gid,b,'member');
 perform public.myaow_collaboration('groups_create',jsonb_build_object('token',tc,'id',other_gid,'name','Other group'));
 plan=jsonb_build_object('token',ta,'groupId',gid,'objective','Ship a tested beta','startsAt','2026-10-01T12:00:00Z','endsAt','2026-12-01T12:00:00Z','reviewAt','2026-11-01T12:00:00Z','timezone','America/Mexico_City','status','active','version',0);
 r=public.myaow_projects('projects_save',plan);
 if r#>>'{project,version}'<>'1' then raise exception 'Version missing'; end if;
 begin perform public.myaow_projects('projects_save',plan); raise exception 'Stale overwrite allowed'; exception when unique_violation then null; end;
 begin perform public.myaow_projects('projects_save',plan||jsonb_build_object('token',tb,'version',1)); raise exception 'Member edited project'; exception when insufficient_privilege then null; end;
 begin perform public.myaow_projects('projects_get',jsonb_build_object('token',tc,'groupId',gid)); raise exception 'Outsider read project'; exception when insufficient_privilege then null; end;
 begin perform public.myaow_projects('projects_save',plan||jsonb_build_object('version',1,'endsAt','2026-09-01T12:00:00Z')); raise exception 'Bad dates accepted'; exception when check_violation then null; end;
 begin perform public.myaow_projects('projects_save',plan||jsonb_build_object('version',1,'timezone','bad/zone')); raise exception 'Bad zone accepted'; exception when invalid_parameter_value then null; end;
 r=public.myaow_collaboration('tasks_create',jsonb_build_object('token',ta,'groupId',gid,'id',tid,'title','Key delivery','assigneeMyaowId',b,'dueAt',due,'dueTimezone','America/Mexico_City','isKey',true,'cadence','weekly'));
 if (r#>>'{task,due_at}')::timestamptz<>due or r#>>'{task,is_key}'<>'true' then raise exception 'Deadline lost'; end if;
 begin perform public.myaow_projects('projects_save',plan||jsonb_build_object('version',1,'status','completed')); raise exception 'Closed unfinished project'; exception when unique_violation then null; end;
 r=public.myaow_collaboration('tasks_update',jsonb_build_object('token',ta,'id',tid,'assigneeMyaowId',a));
 if r#>>'{task,assignee_myaow_id}'<>a then raise exception 'Reassignment not saved'; end if;
 begin perform public.myaow_collaboration('tasks_update',jsonb_build_object('token',ta,'id',tid,'assigneeMyaowId',c)); raise exception 'Outsider assignment accepted'; exception when insufficient_privilege then null; end;
 perform public.myaow_collaboration('tasks_update',jsonb_build_object('token',ta,'id',tid,'assigneeMyaowId',b));
 original=public.myaow_collaboration('tasks_update',jsonb_build_object('token',tb,'id',tid,'completed',true));
 r=public.myaow_collaboration('tasks_update',jsonb_build_object('token',ta,'id',tid,'isKey',false,'dueAt',due+interval '1 hour'));
 if (r#>>'{task,completed_due_at}')::timestamptz<>due then raise exception 'Achievement deadline changed after completion'; end if;
 if r#>>'{task,completed_at}'<>original#>>'{task,completed_at}' or r#>>'{task,completed_by_myaow_id}'<>b then raise exception 'Metadata edit changed completion'; end if;
 begin perform public.myaow_collaboration('tasks_update',jsonb_build_object('token',tc,'id',tid,'isKey',true)); raise exception 'Outsider edited task'; exception when insufficient_privilege then null; end;
 r=public.myaow_projects('projects_propose',jsonb_build_object('token',tb,'groupId',gid,'id',iid,'title','Test with teammates'));
 r=public.myaow_projects('projects_propose',jsonb_build_object('token',tb,'groupId',gid,'id',iid,'title','Test with teammates'));
 if jsonb_array_length(r->'proposals')<>1 then raise exception 'Retry duplicated idea'; end if;
 begin perform public.myaow_projects('projects_vote',jsonb_build_object('token',tc,'groupId',other_gid,'id',iid,'voted',true)); raise exception 'Cross group vote'; exception when insufficient_privilege then null; end;
 r=public.myaow_projects('projects_vote',jsonb_build_object('token',tb,'groupId',gid,'id',iid,'voted',true));
 r=public.myaow_projects('projects_vote',jsonb_build_object('token',tb,'groupId',gid,'id',iid,'voted',true));
 if r#>>'{proposals,0,votes}'<>'1' then raise exception 'Duplicate vote'; end if;
 r=public.myaow_projects('projects_vote',jsonb_build_object('token',tb,'groupId',gid,'id',iid,'voted',false));
 if r#>>'{proposals,0,votes}'<>'0' then raise exception 'Vote not withdrawn'; end if;
 begin perform public.myaow_projects('projects_accept',jsonb_build_object('token',tb,'groupId',gid,'id',iid)); raise exception 'Member approved idea'; exception when insufficient_privilege then null; end;
 r=public.myaow_projects('projects_accept',jsonb_build_object('token',ta,'groupId',gid,'id',iid));
 original=r;
 r=public.myaow_projects('projects_accept',jsonb_build_object('token',ta,'groupId',gid,'id',iid));
 if r#>>'{proposals,0,task_id}' is null or r#>>'{proposals,0,task_id}'<>original#>>'{proposals,0,task_id}' or (select count(*) from myaow_private.tasks where group_id=gid)<>2 then raise exception 'Approval not atomic/idempotent'; end if;
 begin perform public.myaow_projects('projects_vote',jsonb_build_object('token',tb,'groupId',gid,'id',iid,'voted',true)); raise exception 'Closed vote accepted'; exception when unique_violation then null; end;
 iid=gen_random_uuid();
 perform public.myaow_projects('projects_propose',jsonb_build_object('token',tb,'groupId',gid,'id',iid,'title','Second idea'));
 perform public.myaow_projects('projects_vote',jsonb_build_object('token',tb,'groupId',gid,'id',iid,'voted',true));
 perform public.myaow_collaboration('groups_kick',jsonb_build_object('token',ta,'groupId',gid,'target',b));
 if exists(select 1 from myaow_private.project_votes where member=b) then raise exception 'Former member vote retained'; end if;
 begin perform public.myaow_projects('projects_get',jsonb_build_object('token',tb,'groupId',gid)); raise exception 'Removed member read project'; exception when insufficient_privilege then null; end;
 if has_function_privilege('anon','public.myaow_projects(text,jsonb)','execute') or has_function_privilege('authenticated','public.myaow_projects(text,jsonb)','execute') then raise exception 'Public RPC exposed'; end if;
 -- Close after all deliveries, then reopen through a new task.
 update myaow_private.tasks set state='done',progress=100 where group_id=gid;
 perform public.myaow_projects('projects_save',plan||jsonb_build_object('version',1,'status','completed'));
 perform public.myaow_collaboration('tasks_create',jsonb_build_object('token',ta,'groupId',gid,'title','New delivery'));
 if (select status from myaow_private.projects where group_id=gid)<>'active' then raise exception 'New delivery did not reopen project'; end if;
 -- Same RPC under the restricted gateway database role, not just the owner.
 execute 'set local role service_role';
 r=public.myaow_projects('projects_get',jsonb_build_object('token',ta,'groupId',gid));
 if r#>>'{project,status}'<>'active' then raise exception 'Gateway role cannot read project'; end if;
 execute 'reset role';
end $$;
rollback;
