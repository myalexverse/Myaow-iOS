create or replace function myaow_private.invoke_push_worker() returns void
language plpgsql security invoker set search_path='' as $$
declare secret text;
begin
 if not (select push_enabled from myaow_private.settings where singleton) then return; end if;
 if not exists(select 1 from myaow_private.push_jobs where state='pending' and due_at<=now() and (lease_until is null or lease_until<=now())) then return; end if;
 select decrypted_secret into secret from vault.decrypted_secrets where name='myaow_push_worker_secret';
 if secret is null or length(secret)<32 then return; end if;
 perform net.http_post(url:='https://your-project-ref.supabase.co/functions/v1/myaow-push',
  headers:=jsonb_build_object('Content-Type','application/json','x-myaow-worker',secret),body:='{}'::jsonb,timeout_milliseconds:=25000);
end $$;
select cron.schedule('myaow-push-dispatch','5 seconds','select myaow_private.invoke_push_worker()');
