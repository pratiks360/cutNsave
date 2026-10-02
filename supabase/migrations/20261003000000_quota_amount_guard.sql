-- atomic monthly cap. Limits = Google free tier.
-- Guard against non-positive `amount`: without this, a member with a valid
-- JWT could call consume_quota directly with a negative amount to reset or
-- inflate the quota counter, defeating the free-tier cap.
create or replace function public.consume_quota(lib uuid, kind text, amount int) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  m date := date_trunc('month', now())::date;
  ocr_limit int := 1000;
  translate_limit int := 500000;
begin
  if amount <= 0 then
    raise exception 'amount must be positive';
  end if;
  if not public.is_member(lib) then
    raise exception 'forbidden';
  end if;
  insert into public.quota_usage (library_id, month) values (lib, m) on conflict do nothing;
  if kind = 'ocr' then
    update public.quota_usage set ocr_calls = ocr_calls + amount
      where library_id = lib and month = m and ocr_calls + amount <= ocr_limit;
  elsif kind = 'translate' then
    update public.quota_usage set translate_chars = translate_chars + amount
      where library_id = lib and month = m and translate_chars + amount <= translate_limit;
  else
    raise exception 'bad kind';
  end if;
  return found;
end $$;
