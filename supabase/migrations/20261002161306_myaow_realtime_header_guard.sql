create or replace function myaow_private.can_receive_wakeup(channel text) returns boolean
language sql stable security definer set search_path = '' as $$
 select auth.uid() is null and exists (
  select 1 from myaow_private.sessions s
  where s.expires_at > now()
   and (nullif(current_setting('request.headers',true),'')::jsonb->>'x-myaow-session') ~ '^[a-f0-9]{64}$'
   and s.token_hash = encode(extensions.digest(nullif(current_setting('request.headers',true),'')::jsonb->>'x-myaow-session','sha256'),'hex')
   and channel = 'myaow:' || s.token_hash
 );
$$;
