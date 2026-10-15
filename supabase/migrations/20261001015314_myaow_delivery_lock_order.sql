-- Avoid inverted group/sender locks across single and batch delivery.
create or replace function myaow_private.accept_message(actor text, envelope jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
#variable_conflict use_variable
declare item myaow_private.messages; recipient text; gid uuid; mid uuid; checked jsonb;
begin
 -- Match batch/scheduler lock order: group membership, sender, recipient.
 checked=myaow_private.validate_envelope(actor,envelope);
 perform pg_advisory_xact_lock(hashtextextended(actor,3));
 recipient=checked->>'recipient'; gid=(checked->>'groupId')::uuid; mid=(envelope->>'messageId')::uuid;
  select * into item from myaow_private.messages where sender=actor and id=mid;
  if found then
   if item.envelope<>envelope then raise exception 'Message identifier reused' using errcode='23505'; end if;
   return jsonb_build_object('id',envelope->>'messageId','status',case when item.delivered_at is null then 'queued_on_server' else 'delivered' end);
  end if;
  perform pg_advisory_xact_lock(hashtextextended(recipient,4));
  if (select count(*) from myaow_private.messages where myaow_private.messages.recipient=recipient and delivered_at is null)>=1000
   or (select coalesce(sum(octet_length(m.envelope::text)),0) from myaow_private.messages m where m.recipient=recipient and m.delivered_at is null)+octet_length(envelope::text)>8388608
   then raise exception 'Recipient queue full' using errcode='54000'; end if;
  insert into myaow_private.messages(sender,id,recipient,group_id,envelope) values(actor,mid,recipient,gid,envelope);
  return jsonb_build_object('id',envelope->>'messageId','status','queued_on_server');
end $$;

