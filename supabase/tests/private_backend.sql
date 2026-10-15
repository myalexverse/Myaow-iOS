begin;
do $$
declare a text='MYAOW-CHECKA'; b text='MYAOW-CHECKB'; c text='MYAOW-CHECKC';
 ta text=repeat('a',64); tb text=repeat('b',64); tc text=repeat('c',64);
 e jsonb; r jsonb; cid uuid=gen_random_uuid(); mid uuid=gen_random_uuid(); gid uuid=gen_random_uuid();
begin
 if exists(select 1 from myaow_private.profiles where id in(a,b,c)) then raise exception 'Fixture collision'; end if;
 insert into myaow_private.profiles(id,username,display_name,identity_key_hex) values
 (a,'fixture_a','Fixture A',repeat('1',64)),(b,'fixture_b','Fixture B',repeat('2',64)),(c,'fixture_c','Fixture C',repeat('3',64));
 insert into myaow_private.sessions(token_hash,owner,expires_at) values
 (encode(extensions.digest(ta,'sha256'),'hex'),a,now()+interval '1 hour'),
 (encode(extensions.digest(tb,'sha256'),'hex'),b,now()+interval '1 hour'),
 (encode(extensions.digest(tc,'sha256'),'hex'),c,now()+interval '1 hour');
 begin
  perform public.myaow_backend('pending',jsonb_build_object('token','wrong'));
  raise exception 'Accepted unauthenticated read';
 exception when invalid_authorization_specification then null; end;
 e=jsonb_build_object('version',2,'messageId',mid,'senderId',a,'recipientId',b,'senderPublicKey',repeat('1',64),
 'encapsulatedKey',encode(decode(repeat('11',32),'hex'),'base64'),'ciphertext',encode(decode(repeat('22',32),'hex'),'base64'));
 begin
  perform public.myaow_backend('send',jsonb_build_object('token',tc,'envelope',e));
  raise exception 'Accepted forged sender';
 exception when invalid_parameter_value then null; end;
 begin
  perform public.myaow_backend('send',jsonb_build_object('token',ta,'envelope',e||'{"ciphertext":null}'::jsonb));
  raise exception 'Accepted null ciphertext';
 exception when invalid_parameter_value then null; end;
 r=public.myaow_backend('send',jsonb_build_object('token',ta,'envelope',e));
 if r->>'status'<>'queued_on_server' then raise exception 'Missing durable acceptance'; end if;
 perform public.myaow_backend('send',jsonb_build_object('token',ta,'envelope',e));
 if (select count(*) from myaow_private.messages where sender=a)<>1 then raise exception 'Duplicate message'; end if;
 begin
  perform public.myaow_backend('send',jsonb_build_object('token',ta,'envelope',e||jsonb_build_object('ciphertext',encode(decode(repeat('33',32),'hex'),'base64'))));
  raise exception 'Allowed identifier reuse';
 exception when unique_violation then null; end;
 r=public.myaow_backend('pending',jsonb_build_object('token',tc));
 if jsonb_array_length(r->'messages')<>0 then raise exception 'Cross-account disclosure'; end if;
 r=public.myaow_backend('pending',jsonb_build_object('token',tb));
 if jsonb_array_length(r->'messages')<>1 then raise exception 'Missing recipient message'; end if;
 r=public.myaow_backend('acknowledge',jsonb_build_object('token',tc,'senderId',a,'id',mid));
 if (r->>'acknowledged')::boolean then raise exception 'Cross-account acknowledgement'; end if;
 perform public.myaow_backend('block',jsonb_build_object('token',tb,'target',a));
 r=public.myaow_backend('pending',jsonb_build_object('token',tb));
 if jsonb_array_length(r->'messages')<>0 then raise exception 'Blocked message replay'; end if;
 begin
  perform public.myaow_backend('send',jsonb_build_object('token',ta,'envelope',e||jsonb_build_object('messageId',gen_random_uuid())));
  raise exception 'Accepted blocked sender';
 exception when insufficient_privilege then null; end;
 delete from myaow_private.blocks where owner=b;
 perform public.myaow_backend('acknowledge',jsonb_build_object('token',tb,'senderId',a,'id',mid));
 r=public.myaow_backend('send',jsonb_build_object('token',ta,'envelope',e));
 if r->>'status'<>'delivered' then raise exception 'Missing delivery tombstone'; end if;
 insert into myaow_private.groups(id,owner,name) values(gid,a,'Fixture');
 insert into myaow_private.group_members(group_id,member,role) values(gid,a,'owner'),(gid,b,'member');
 e=e||jsonb_build_object('messageId',gen_random_uuid(),'groupId',gid);
 perform public.myaow_backend('send',jsonb_build_object('token',ta,'envelope',e));
 delete from myaow_private.group_members where group_id=gid and member=b;
 r=public.myaow_backend('pending',jsonb_build_object('token',tb));
 if jsonb_array_length(r->'messages')<>0 then raise exception 'Removed member can replay'; end if;
 begin
  perform public.myaow_backend('send',jsonb_build_object('token',ta,'envelope',e||jsonb_build_object('messageId',gen_random_uuid())));
  raise exception 'Removed member can receive';
 exception when insufficient_privilege then null; end;
 perform public.myaow_backend('challenge_store',jsonb_build_object('id',cid,'myaowId',a,'proofHash',encode(extensions.digest('test-proof','sha256'),'hex')));
 r=public.myaow_backend('authenticate',jsonb_build_object('id',cid,'myaowId',a,'proof','wrong-proof'));
 if not (r?'error') or exists(select 1 from myaow_private.challenges where id=cid) then raise exception 'Proof attempt not consumed'; end if;
 begin
  insert into myaow_private.profiles(id,username,display_name,identity_key_hex) values('MYAOW-checka','fixture_case','Duplicate case',repeat('4',64));
  raise exception 'Case-ambiguous identity accepted';
 exception when unique_violation then null; end;
 r=public.myaow_backend('username_available',jsonb_build_object('username','fixture_a'));
 if (r->>'available')::boolean then raise exception 'Existing username available'; end if;
 r=public.myaow_backend('lookup',jsonb_build_object('token',ta,'username',lower(b)));
 if r->>'myaowId'<>b then raise exception 'Identity lookup loses case'; end if;
 r=public.myaow_backend('sync',jsonb_build_object('token',ta,'ids',jsonb_build_array(mid)));
 if r#>>'{receipts,0,status}'<>'delivered' then raise exception 'Sender receipt missing'; end if;
 r=public.myaow_backend('sync',jsonb_build_object('token',tc,'ids',jsonb_build_array(mid)));
 if r->'receipts'<>'[]'::jsonb then raise exception 'Foreign receipt leaked'; end if;
 perform public.myaow_backend('block',jsonb_build_object('token',ta,'target',c));
 r=public.myaow_backend('blocked',jsonb_build_object('token',ta));
 if not ((r->'blockedIds')?c) then raise exception 'Block list missing'; end if;
 perform public.myaow_backend('unblock',jsonb_build_object('token',ta,'target',c));
 r=public.myaow_backend('blocked',jsonb_build_object('token',ta));
 if (r->'blockedIds')?c then raise exception 'Unblock failed'; end if;
 perform public.myaow_backend('logout',jsonb_build_object('token',ta));
 begin
  perform public.myaow_backend('profile',jsonb_build_object('token',ta));
  raise exception 'Revoked session works';
 exception when invalid_authorization_specification then null; end;
 -- Registration stays closed to public users; all changes here roll back.
 begin
  perform public.myaow_backend('register','{"myaowId":"MYAOW-NEW00","username":"fixture_new","displayName":"New","identityKeyHex":"4444444444444444444444444444444444444444444444444444444444444444","betaInvite":"fixture"}');
  raise exception 'Registration unexpectedly open';
 exception when insufficient_privilege then null; end;
 update myaow_private.settings set registration_mode='invite';
 insert into myaow_private.invitations(code_hash,expires_at) values(encode(extensions.digest('fixture','sha256'),'hex'),now()+interval '1 hour');
 begin
  perform public.myaow_backend('register','{"myaowId":"MYAOW-NEW00","username":"bad username","displayName":"New","identityKeyHex":"4444444444444444444444444444444444444444444444444444444444444444","betaInvite":"fixture"}');
  raise exception 'Invalid registration accepted';
 exception when check_violation then null; end;
 if exists(select 1 from myaow_private.invitations where used_by is not null) then raise exception 'Failed registration consumed invitation'; end if;
 perform public.myaow_backend('register','{"myaowId":"MYAOW-NEW00","username":"fixture_new","displayName":"New","identityKeyHex":"4444444444444444444444444444444444444444444444444444444444444444","betaInvite":"fixture"}');
 begin
  perform public.myaow_backend('register','{"myaowId":"MYAOW-NEW01","username":"fixture_new1","displayName":"New","identityKeyHex":"4444444444444444444444444444444444444444444444444444444444444444","betaInvite":"fixture"}');
  raise exception 'Invitation reused';
 exception when insufficient_privilege then null; end;
end $$;
rollback;
select 'PASS: identity ownership, invitation atomicity, revocation, encrypted queue, deduplication, recipient isolation, blocks, group membership and proof replay; fixtures rolled back' as result;
