-- Test identities and ciphertext-shaped fixtures only. No real user data.
begin;
do $$
declare a text='MYAOW-COLLABA'; b text='MYAOW-COLLABB'; c text='MYAOW-COLLABC'; d text='MYAOW-COLLABD';
 ta text=repeat('a',64); tb text=repeat('b',64); tc text=repeat('c',64); td text=repeat('d',64);
 gid uuid=gen_random_uuid(); iid uuid=gen_random_uuid(); tid uuid=gen_random_uuid(); sid uuid=gen_random_uuid();
 r jsonb; e jsonb; packets jsonb='[]'; p jsonb; body jsonb; recipient text; denied boolean;
begin
 if exists(select 1 from myaow_private.profiles where id in(a,b,c,d)) then raise exception 'Fixture collision'; end if;
 insert into myaow_private.profiles(id,username,display_name,identity_key_hex) values
 (a,'collab_a','A',repeat('1',64)),(b,'collab_b','B',repeat('2',64)),(c,'collab_c','C',repeat('3',64)),(d,'collab_d','D',repeat('4',64));
 insert into myaow_private.sessions(token_hash,owner,expires_at) values
 (encode(extensions.digest(ta,'sha256'),'hex'),a,now()+interval '1 hour'),
 (encode(extensions.digest(tb,'sha256'),'hex'),b,now()+interval '1 hour'),
 (encode(extensions.digest(tc,'sha256'),'hex'),c,now()+interval '1 hour'),
 (encode(extensions.digest(td,'sha256'),'hex'),d,now()+interval '1 hour');
 perform public.myaow_collaboration('groups_create',jsonb_build_object('token',ta,'id',gid,'name','Fixture team'));
 perform public.myaow_collaboration('groups_create',jsonb_build_object('token',ta,'id',gid,'name','Fixture team'));
 r=public.myaow_collaboration('groups_list',jsonb_build_object('token',tb));
 if r->'groups'<>'[]'::jsonb then raise exception 'Group leaked to outsider'; end if;
 begin
  perform public.myaow_collaboration('groups_members',jsonb_build_object('token',tb,'groupId',gid));
  raise exception 'Outsider read members';
 exception when insufficient_privilege then null; end;
 perform public.myaow_collaboration('groups_invite_create',jsonb_build_object('token',ta,'id',iid,'groupId',gid,'recipientId',b));
 begin
  perform public.myaow_collaboration('groups_invite_accept',jsonb_build_object('token',tc,'inviteId',iid));
  raise exception 'Invitation accepted by wrong person';
 exception when insufficient_privilege then null; end;
 perform public.myaow_collaboration('groups_invite_accept',jsonb_build_object('token',tb,'inviteId',iid));
 perform public.myaow_collaboration('groups_invite_accept',jsonb_build_object('token',tb,'inviteId',iid));
 begin
  perform public.myaow_collaboration('groups_invite_create',jsonb_build_object('token',tb,'groupId',gid,'recipientId',c));
  raise exception 'Member issued invitation';
 exception when insufficient_privilege then null; end;
 iid=gen_random_uuid();
 perform public.myaow_collaboration('groups_invite_create',jsonb_build_object('token',ta,'id',iid,'groupId',gid,'recipientId',c));
 perform public.myaow_collaboration('groups_invite_accept',jsonb_build_object('token',tc,'inviteId',iid));
 r=public.myaow_collaboration('groups_members',jsonb_build_object('token',tb,'groupId',gid));
 if jsonb_array_length(r->'members')<>3 then raise exception 'Missing membership'; end if;
 r=public.myaow_collaboration('tasks_create',jsonb_build_object('token',tb,'id',tid,'groupId',gid,'title','Test task','assigneeMyaowId',a,'priority','Importante','dueLabel','Hoy'));
 if r#>>'{task,assignee_myaow_id}'<>a or r#>>'{task,is_completed}'<>'0' then raise exception 'Invalid native task shape'; end if;
 r=public.myaow_collaboration('tasks_list',jsonb_build_object('token',tc,'groupId',gid));
 if jsonb_array_length(r->'tasks')<>1 then raise exception 'Missing task'; end if;
 begin
  perform public.myaow_collaboration('tasks_update',jsonb_build_object('token',tc,'id',tid,'state','done'));
  raise exception 'Unassigned member edited task';
 exception when insufficient_privilege then null; end;
 r=public.myaow_collaboration('tasks_update',jsonb_build_object('token',ta,'id',tid,'state','in_progress','progress',60));
 if r#>>'{task,progress}'<>'60' then raise exception 'Progress not saved'; end if;
 r=public.myaow_collaboration('tasks_update',jsonb_build_object('token',tb,'id',tid,'completed',true));
 if r#>>'{task,progress}'<>'100' or r#>>'{task,completed_by_myaow_id}'<>b then raise exception 'Completion not attributed'; end if;
 begin
  perform public.myaow_collaboration('tasks_create',jsonb_build_object('token',ta,'groupId',gid,'title','Bad assignee','assigneeMyaowId',d));
  raise exception 'Outsider assigned task';
 exception when insufficient_privilege then null; end;
 -- Group policy is enforced on the server, including creators and assignees.
 perform public.myaow_collaboration('groups_info',jsonb_build_object('token',ta,'groupId',gid,'taskPolicy','open'));
 r=public.myaow_collaboration('tasks_update',jsonb_build_object('token',tc,'id',tid,'state','in_progress','progress',37));
 if r#>>'{task,progress}'<>'37' then raise exception 'Open member update failed'; end if;
 begin
  perform public.myaow_collaboration('groups_info',jsonb_build_object('token',tc,'groupId',gid,'taskPolicy','admins'));
  raise exception 'Member changed policy';
 exception when insufficient_privilege then null; end;
 perform public.myaow_collaboration('groups_info',jsonb_build_object('token',ta,'groupId',gid,'taskPolicy','admins'));
 begin
  perform public.myaow_collaboration('tasks_update',jsonb_build_object('token',tb,'id',tid,'completed',true));
  raise exception 'Creator bypassed administrator policy';
 exception when insufficient_privilege then null; end;
 begin
  perform public.myaow_collaboration('tasks_delete',jsonb_build_object('token',tb,'id',tid));
  raise exception 'Creator deleted under administrator policy';
 exception when insufficient_privilege then null; end;
 begin
  perform public.myaow_collaboration('tasks_create',jsonb_build_object('token',tc,'groupId',gid,'title','Forbidden'));
  raise exception 'Member created under administrator policy';
 exception when insufficient_privilege then null; end;
 r=public.myaow_collaboration('tasks_list',jsonb_build_object('token',tb,'groupId',gid));
 if r->>'task_policy'<>'admins' then raise exception 'Missing policy on refresh'; end if;
 perform public.myaow_collaboration('groups_info',jsonb_build_object('token',ta,'groupId',gid,'taskPolicy','assigned'));
 perform public.myaow_collaboration('groups_promote',jsonb_build_object('token',ta,'groupId',gid,'target',b));
 begin
  perform public.myaow_collaboration('groups_promote',jsonb_build_object('token',tb,'groupId',gid,'target',c));
  raise exception 'Admin escalated role';
 exception when insufficient_privilege then null; end;
 perform public.myaow_collaboration('groups_demote',jsonb_build_object('token',ta,'groupId',gid,'target',b));
 -- A scheduled encrypted group message contains one envelope per recipient.
 foreach recipient in array array[b,c] loop
  e=jsonb_build_object('version',2,'messageId',upper(gen_random_uuid()::text),'senderId',a,'recipientId',recipient,'senderPublicKey',repeat('1',64),'groupId',gid,
   'encapsulatedKey',encode(decode(repeat('11',32),'hex'),'base64'),'ciphertext',encode(decode(repeat('22',32),'hex'),'base64'));
  packets=packets||jsonb_build_array(jsonb_build_object('id',e->>'messageId','type','message','senderMyaowId',a,'senderDisplayName','A','recipientMyaowId',recipient,'encryptedPayload',e::text));
 end loop;
 body=jsonb_build_object('token',ta,'id',sid,'due',floor(extract(epoch from now()+interval '1 hour')*1000),'preview',encode(decode(repeat('33',32),'hex'),'base64'),'packets',packets);
 begin
  perform public.myaow_collaboration('schedules_create',body||jsonb_build_object('packets',jsonb_build_array(packets->0)));
  raise exception 'Partial group batch accepted';
 exception when insufficient_privilege then null; end;
 perform public.myaow_collaboration('schedules_create',body);
 perform public.myaow_collaboration('schedules_create',body);
 if (select count(*) from myaow_private.schedules where owner=a)<>1 then raise exception 'Schedule duplicated'; end if;
 begin
  perform public.myaow_collaboration('schedules_create',body||jsonb_build_object('preview',encode(decode(repeat('44',32),'hex'),'base64')));
  raise exception 'Changed schedule reused identifier';
 exception when unique_violation then null; end;
 begin
  perform public.myaow_collaboration('schedules_cancel',jsonb_build_object('token',tb,'id',sid));
  raise exception 'Other account cancelled schedule';
 exception when unique_violation then null; end;
 r=public.myaow_collaboration('schedules_list',jsonb_build_object('token',tb));
 if r->'messages'<>'[]'::jsonb then raise exception 'Scheduled preview leaked'; end if;
 perform public.myaow_collaboration('schedules_cancel',jsonb_build_object('token',ta,'id',sid));
 perform public.myaow_collaboration('schedules_cancel',jsonb_build_object('token',ta,'id',sid));
 perform myaow_private.dispatch_due();
 if exists(select 1 from myaow_private.messages where sender=a) then raise exception 'Cancelled schedule dispatched'; end if;
 sid=gen_random_uuid();body=body||jsonb_build_object('id',sid);
 perform public.myaow_collaboration('schedules_create',body);
 -- Force only our fixture due. Closed app and expired session must not prevent delivery.
 update myaow_private.schedules set due_at=now()-interval '1 second' where owner=a and id=sid;
 update myaow_private.sessions set expires_at=now()-interval '1 second' where owner=a;
 perform myaow_private.dispatch_due();perform myaow_private.dispatch_due();
 if (select state from myaow_private.schedules where owner=a and id=sid)<>'queued' or (select count(*) from myaow_private.messages where sender=a)<>2 then raise exception 'Autonomous delivery failed or duplicated'; end if;
 for p in select value from jsonb_array_elements(packets) loop
  perform public.myaow_backend('acknowledge',jsonb_build_object('token',case when p->>'recipientMyaowId'=b then tb else tc end,'senderId',a,'id',p->>'id'));
 end loop;
 perform myaow_private.dispatch_due();
 if (select state from myaow_private.schedules where owner=a and id=sid)<>'delivered' then raise exception 'Delivery status not advanced'; end if;
 update myaow_private.sessions set expires_at=now()+interval '1 hour' where owner=a;
 -- A full recipient queue must roll back the whole batch, retain the schedule,
 -- and retry later without delivering a partial group message.
 packets='[]'::jsonb;
 foreach recipient in array array[b,c] loop
  e=e||jsonb_build_object('messageId',upper(gen_random_uuid()::text),'recipientId',recipient);
  packets=packets||jsonb_build_array(jsonb_build_object('id',e->>'messageId','type','message','senderMyaowId',a,'senderDisplayName','A','recipientMyaowId',recipient,'encryptedPayload',e::text));
 end loop;
 insert into myaow_private.messages(sender,id,recipient,envelope)
 select d,gen_random_uuid(),c,'{}'::jsonb from generate_series(1,1000);
 sid=gen_random_uuid();body=body||jsonb_build_object('id',sid,'packets',packets);
 perform public.myaow_collaboration('schedules_create',body);
 update myaow_private.schedules set due_at=now()-interval '1 second' where owner=a and id=sid;
 perform myaow_private.dispatch_due();
 if (select state from myaow_private.schedules where owner=a and id=sid)<>'pending'
  or (select count(*) from myaow_private.messages where sender=a)<>2 then raise exception 'Queue overflow caused partial batch'; end if;
 delete from myaow_private.messages where sender=d and messages.recipient=c;
 perform myaow_private.dispatch_due();
 if (select state from myaow_private.schedules where owner=a and id=sid)<>'queued'
  or (select count(*) from myaow_private.messages where sender=a)<>4 then raise exception 'Queue recovery did not retry'; end if;
 -- A new block made after scheduling prevents the entire group dispatch.
 sid=gen_random_uuid();body=body||jsonb_build_object('id',sid);
 perform public.myaow_collaboration('schedules_create',body);
 perform public.myaow_backend('block',jsonb_build_object('token',tb,'target',a));
 update myaow_private.schedules set due_at=now()-interval '1 second' where owner=a and id=sid;
 perform myaow_private.dispatch_due();
 if (select state from myaow_private.schedules where owner=a and id=sid)<>'attention' then raise exception 'Block bypassed by scheduler'; end if;
 delete from myaow_private.blocks where owner=b and target=a;
 -- Membership is checked again at dispatch, not only at creation.
 sid=gen_random_uuid();body=body||jsonb_build_object('id',sid);
 perform public.myaow_collaboration('schedules_create',body);
 perform public.myaow_collaboration('groups_kick',jsonb_build_object('token',ta,'groupId',gid,'target',c));
 update myaow_private.schedules set due_at=now()-interval '1 second' where owner=a and id=sid;
 perform myaow_private.dispatch_due();
 if (select state from myaow_private.schedules where owner=a and id=sid)<>'attention' then raise exception 'Removed member still receives scheduled batch'; end if;
 begin
  perform public.myaow_collaboration('groups_invite_accept',jsonb_build_object('token',tc,'inviteId',iid));
  raise exception 'Removed member reused old invitation';
 exception when insufficient_privilege then null; end;
 begin
  perform public.myaow_collaboration('tasks_list',jsonb_build_object('token',tc,'groupId',gid));
  raise exception 'Removed member read tasks';
 exception when insufficient_privilege then null; end;
 begin
  perform public.myaow_collaboration('groups_leave',jsonb_build_object('token',ta,'groupId',gid));
  raise exception 'Owner left orphaned group';
 exception when insufficient_privilege then null; end;
end $$;
rollback;
select 'PASS: group membership, targeted invitations, role escalation, task ownership/progress, private schedules, idempotency, cancellation, autonomous dispatch after session expiry, delivery receipts, atomic queue overflow/retry, blocks and membership revalidation; fixtures rolled back' as result;
