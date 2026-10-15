-- Synthetic records in a transaction; no Apple request and no persistent data.
begin;
do $$
declare a text='MYAOW-PUSH-TESTA'; b text='MYAOW-PUSH-TESTB'; ta text=repeat('a',64); tb text=repeat('b',64);
 d1 uuid=gen_random_uuid(); d2 uuid=gen_random_uuid(); mid uuid; envelope jsonb; jobs jsonb; j jsonb; result jsonb;
begin
 if exists(select 1 from myaow_private.profiles where id in(a,b)) then raise exception 'Fixture collision'; end if;
 if has_function_privilege('anon','public.myaow_push(text,jsonb)','EXECUTE') or has_function_privilege('authenticated','public.myaow_push(text,jsonb)','EXECUTE') then raise exception 'RPC publicly exposed'; end if;
 insert into myaow_private.profiles(id,username,display_name,identity_key_hex) values(a,'push_fixture_a','A',repeat('1',64)),(b,'push_fixture_b','B',repeat('2',64));
 insert into myaow_private.sessions(token_hash,owner,expires_at) values(encode(extensions.digest(ta,'sha256'),'hex'),a,now()+interval '1 hour'),(encode(extensions.digest(tb,'sha256'),'hex'),b,now()+interval '1 hour');
 begin perform public.myaow_push('push_register','{}');raise exception 'Unauthenticated registration';exception when sqlstate '28000' then null;end;
 begin perform public.myaow_push('push_register',jsonb_build_object('token',tb,'installation',d1,'environment','sandbox','bundleId','foreign.app','alertToken',repeat('d',64)));raise exception 'Foreign topic accepted';exception when sqlstate '22023' then null;end;
 perform public.myaow_push('push_register',jsonb_build_object('token',tb,'installation',d1,'environment','sandbox','bundleId','com.ScendLabs.Myaow','alertToken',repeat('d',64),'owner',a));
 perform public.myaow_push('push_register',jsonb_build_object('token',tb,'installation',d2,'environment','sandbox','bundleId','com.ScendLabs.Myaow','alertToken',repeat('e',64)));
 if (select count(*) from myaow_private.push_devices where owner=b)<>2 or exists(select 1 from myaow_private.push_devices where owner=a) then raise exception 'Device owner forged';end if;
 update myaow_private.settings set push_enabled=true where singleton;
 mid=gen_random_uuid();
 envelope=jsonb_build_object('version',2,'messageId',mid,'senderId',a,'recipientId',b,'senderPublicKey',repeat('1',64),
  'encapsulatedKey',encode(decode(repeat('11',32),'hex'),'base64'),'ciphertext',encode(decode(repeat('22',32),'hex'),'base64'));
 perform myaow_private.accept_message(a,envelope); perform myaow_private.accept_message(a,envelope);
 if (select count(*) from myaow_private.push_jobs where sender=a)<>2 then raise exception 'Missing or duplicate device jobs';end if;
 jobs=public.myaow_push('push_claim','{}');
 if jsonb_array_length(jobs)<>2 or public.myaow_push('push_claim','{}')<>'[]'::jsonb then raise exception 'Lease did not exclude concurrent worker';end if;
 j=jobs->0;
 result=public.myaow_push('push_validate',j);if result->>'valid'<>'true' or result?'sender' or result?'envelope' then raise exception 'Unsafe job';end if;
 perform public.myaow_push('push_finish',j||jsonb_build_object('outcome','accepted'));
 if exists(select 1 from myaow_private.messages where sender=a and delivered_at is not null) then raise exception 'APNs acceptance falsely counted as delivery';end if;
 j=jobs->1;perform public.myaow_push('push_finish',j||jsonb_build_object('outcome','retry'));
 if not exists(select 1 from myaow_private.push_jobs where id=(j->>'id')::uuid and state='pending' and due_at>now() and attempts=1) then raise exception 'Retry not retained';end if;
 if public.myaow_push('push_finish',j||jsonb_build_object('outcome','accepted'))->>'valid'<>'false' then raise exception 'Stale lease accepted';end if;
 update myaow_private.push_jobs set due_at=now()-interval '1 second' where sender=a and state='pending';
 j=public.myaow_push('push_claim','{}')->0;
 insert into myaow_private.blocks(owner,target)values(b,a);
 if public.myaow_push('push_validate',j)->>'valid'<>'false' then raise exception 'Block after claim ignored';end if;
 delete from myaow_private.blocks where owner=b and target=a;
 mid=gen_random_uuid();envelope=envelope||jsonb_build_object('messageId',mid);
 perform myaow_private.accept_message(a,envelope);
 jobs=public.myaow_push('push_claim','{}');j=jobs->0;
 perform public.myaow_push('push_finish',j||jsonb_build_object('outcome','invalid'));
 if not exists(select 1 from myaow_private.push_devices d join myaow_private.push_jobs q on q.owner=d.owner and q.installation=d.installation where q.id=(j->>'id')::uuid and d.alert_token is null and q.state='failed') then raise exception 'Invalid device token retained';end if;
 perform public.myaow_backend('acknowledge',jsonb_build_object('token',tb,'senderId',a,'id',mid));
 if exists(select 1 from myaow_private.push_jobs where sender=a and message_id=mid and state='pending') then raise exception 'Receipt failed to cancel pending alert';end if;
 perform public.myaow_backend('logout',jsonb_build_object('token',tb));
 if exists(select 1 from myaow_private.push_devices where owner=b) then raise exception 'Logout left device registered';end if;
end $$;
rollback;
select 'PASS: authenticated registration, device isolation, topic allowlist, per-device deduplication, leases, retry, stale-worker rejection, block revalidation, invalid-token removal, receipt cancellation and logout cleanup; no APNs request' as result;
