-- Wake-up hints only: no plaintext, envelopes, profile identifiers or attachment URLs.
-- Myaow uses its own revocable X25519 sessions, not Supabase Auth users.
create function myaow_private.can_receive_wakeup(channel text) returns boolean
language sql stable security definer set search_path = '' as $$
 select auth.uid() is null and exists (
  select 1 from myaow_private.sessions s
  where s.expires_at > now()
   and (current_setting('request.headers',true)::jsonb->>'x-myaow-session') ~ '^[a-f0-9]{64}$'
   and s.token_hash = encode(extensions.digest(current_setting('request.headers',true)::jsonb->>'x-myaow-session','sha256'),'hex')
   and channel = 'myaow:' || s.token_hash
 );
$$;
revoke all on function myaow_private.can_receive_wakeup(text) from public, authenticated;
grant usage on schema myaow_private to anon;
grant execute on function myaow_private.can_receive_wakeup(text) to anon;
-- Schema USAGE does not grant SELECT on any of the private tables.
create policy myaow_session_receive_wakeup on realtime.messages for select to anon
 using (extension='broadcast' and myaow_private.can_receive_wakeup(realtime.topic()));

create function myaow_private.wake_owner(target text) returns void
language plpgsql security invoker set search_path='' as $$
declare session_row record;
begin
 for session_row in select token_hash from myaow_private.sessions where owner=target and expires_at>now() loop
  begin
   perform realtime.send('{}'::jsonb,'wake','myaow:'||session_row.token_hash,true);
  exception when others then
   -- Realtime availability must never roll back a durable message. HTTP reconciliation remains active.
   raise log 'Myaow wakeup unavailable';
  end;
 end loop;
end;
$$;
revoke all on function myaow_private.wake_owner(text) from public,anon,authenticated;
grant execute on function myaow_private.wake_owner(text) to service_role;

create function myaow_private.wake_messages() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 if TG_OP='INSERT' then perform myaow_private.wake_owner(new.recipient);
 elsif new.delivered_at is distinct from old.delivered_at then perform myaow_private.wake_owner(new.sender);
 end if;
 return null;
end;
$$;
revoke all on function myaow_private.wake_messages() from public,anon,authenticated;
grant execute on function myaow_private.wake_messages() to service_role;
create trigger myaow_message_wakeup after insert or update of delivered_at on myaow_private.messages
 for each row execute function myaow_private.wake_messages();

create function myaow_private.wake_collaboration() returns trigger
language plpgsql security invoker set search_path='' as $$
declare item jsonb; gid uuid; member_row record;
begin
 item=case when TG_OP='DELETE' then to_jsonb(old) else to_jsonb(new) end;
 if TG_TABLE_NAME='schedules' then perform myaow_private.wake_owner(item->>'owner'); return null; end if;
 gid=case when TG_TABLE_NAME='groups' then (item->>'id')::uuid else (item->>'group_id')::uuid end;
 for member_row in select member from myaow_private.group_members where group_id=gid loop
  perform myaow_private.wake_owner(member_row.member);
 end loop;
 if TG_TABLE_NAME='group_members' then perform myaow_private.wake_owner(item->>'member'); end if;
 return null;
end;
$$;
revoke all on function myaow_private.wake_collaboration() from public,anon,authenticated;
grant execute on function myaow_private.wake_collaboration() to service_role;
create trigger myaow_tasks_wakeup after insert or update or delete on myaow_private.tasks
 for each row execute function myaow_private.wake_collaboration();
create trigger myaow_members_wakeup after insert or update or delete on myaow_private.group_members
 for each row execute function myaow_private.wake_collaboration();
create trigger myaow_groups_wakeup after update on myaow_private.groups
 for each row execute function myaow_private.wake_collaboration();
create trigger myaow_schedules_wakeup after insert or update on myaow_private.schedules
 for each row execute function myaow_private.wake_collaboration();
