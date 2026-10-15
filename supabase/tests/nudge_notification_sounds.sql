-- Isolated synthetic fixtures. No global queue claim, network request or committed data.
begin;
set local lock_timeout='2s';
set local statement_timeout='15s';
do $$
declare a text='MYAOW-NUDGE-QAA'; b text='MYAOW-NUDGE-QAB'; device uuid=gen_random_uuid();
 mid uuid; sound text; envelope jsonb; job myaow_private.push_jobs; result jsonb;
begin
 if exists(select 1 from myaow_private.profiles where id in(a,b)) then raise exception 'Fixture collision'; end if;
 if not (select push_enabled from myaow_private.settings where singleton) then raise exception 'Push disabled; test requires delivery enabled'; end if;
 insert into myaow_private.profiles(id,username,display_name,identity_key_hex) values
 (a,'nudge_qa_a','A',repeat('1',64)),(b,'nudge_qa_b','B',repeat('2',64));
 insert into myaow_private.push_devices(owner,installation,environment,alert_token,bundle_id)
 values(b,device,'sandbox',encode(extensions.gen_random_bytes(32),'hex'),'com.ScendLabs.Myaow');
 foreach sound in array array['classic','electric','cosmic','melodic','claw','lazy','kiss','giggle','party','question','sleepy','echo','mentada','admiration',null] loop
  mid=gen_random_uuid();
  envelope=jsonb_build_object('version',2,'messageId',mid,'senderId',a,'recipientId',b,'senderPublicKey',repeat('1',64),
   'encapsulatedKey',encode(decode(repeat('11',32),'hex'),'base64'),'ciphertext',encode(decode(repeat('22',32),'hex'),'base64'));
  if sound is not null then envelope=envelope||jsonb_build_object('notificationSound',sound); end if;
  perform myaow_private.accept_message(a,envelope);
  perform myaow_private.accept_message(a,envelope);
  if (select count(*) from myaow_private.push_jobs where sender=a and message_id=mid)<>1 then raise exception 'Push duplicate or missing'; end if;
  update myaow_private.push_jobs set lease=gen_random_uuid(),lease_until=now()+interval '1 minute'
   where sender=a and message_id=mid returning * into job;
  result=public.myaow_push('push_validate',jsonb_build_object('id',job.id,'lease',job.lease));
  if result->>'valid' is distinct from 'true' or result->>'notificationSound' is distinct from sound then raise exception 'Sound not forwarded'; end if;
  if result ?| array['sender','text','envelope','ciphertext'] then raise exception 'Content leaked'; end if;
 end loop;
 foreach sound in array array['../../private','default','mentada.wav',''] loop
  begin
   perform myaow_private.accept_message(a,envelope||jsonb_build_object('messageId',gen_random_uuid(),'notificationSound',sound));
   raise exception 'Unknown sound accepted';
  exception when sqlstate '22023' then null; end;
 end loop;
 if has_function_privilege('anon','public.myaow_push(text,jsonb)','EXECUTE') or has_function_privilege('authenticated','public.myaow_push(text,jsonb)','EXECUTE') then raise exception 'Push RPC exposed'; end if;
end $$;
rollback;
select 'PASS: 14 sounds, legacy fallback, idempotence, private content and invalid sound rejection; no APNs request' as result;
