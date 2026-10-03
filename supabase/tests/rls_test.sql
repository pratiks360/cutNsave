begin;
select plan(19);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'mom@example.com'),
  ('00000000-0000-0000-0000-0000000000b2', 'sis@example.com'),
  ('00000000-0000-0000-0000-0000000000c3', 'mallory@example.com');

-- mom signs in first: gets a new library with 5 default categories
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","email":"mom@example.com","role":"authenticated"}', true);
set local role authenticated;
select isnt(public.bootstrap_library(), null, 'first user gets a library');
select is((select count(*)::int from public.categories), 5, 'default categories seeded');

-- mom allow-lists sis and stores an article
insert into public.library_members (library_id, email, role)
  select id, 'sis@example.com', 'member' from public.libraries;
insert into public.articles (id, library_id, original_lang, scanned_at)
  select gen_random_uuid(), id, 'mr', now() from public.libraries;
select is((select count(*)::int from public.articles), 1, 'owner sees article');

reset role;
select set_config('test.lib', (select id::text from public.libraries limit 1), true);

-- sis joins via allow-list
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b2","email":"sis@example.com","role":"authenticated"}', true);
set local role authenticated;
select isnt(public.bootstrap_library(), null, 'allow-listed email joins existing library');
select is((select count(*)::int from public.articles), 1, 'member sees articles');

-- mallory is a stranger
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c3","email":"mallory@example.com","role":"authenticated"}', true);
set local role authenticated;
select is(public.bootstrap_library(), null, 'stranger gets no library');
select is((select count(*)::int from public.articles), 0, 'stranger sees no articles');
select throws_ok(
  $$insert into public.articles (id, library_id, original_lang, scanned_at)
    values (gen_random_uuid(), current_setting('test.lib')::uuid, 'mr', now())$$,
  '42501', null, 'stranger cannot insert article');
select throws_ok(
  $$select public.consume_quota(current_setting('test.lib')::uuid, 'ocr', 1)$$,
  'P0001', 'forbidden', 'stranger cannot consume quota');

-- quota cap: 999 used, one more allowed, then refused
reset role;
insert into public.quota_usage (library_id, month, ocr_calls)
  values (current_setting('test.lib')::uuid, date_trunc('month', now())::date, 999);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","email":"mom@example.com","role":"authenticated"}', true);
set local role authenticated;
select is(public.consume_quota(current_setting('test.lib')::uuid, 'ocr', 1), true, 'last free OCR call allowed');
select is(public.consume_quota(current_setting('test.lib')::uuid, 'ocr', 1), false, 'call beyond cap refused');

-- negative/zero amounts must be rejected, not accepted as a way to reset/inflate the counter
select throws_ok(
  $$select public.consume_quota(current_setting('test.lib')::uuid, 'ocr', -5)$$,
  'P0001', 'amount must be positive', 'negative amount is rejected');
select throws_ok(
  $$select public.consume_quota(current_setting('test.lib')::uuid, 'ocr', 0)$$,
  'P0001', 'amount must be positive', 'zero amount is rejected');

-- client-timestamp last-write-wins guard on upsert_article/upsert_category
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","email":"mom@example.com","role":"authenticated"}', true);
set local role authenticated;

select set_config('test.art', gen_random_uuid()::text, true);
select public.upsert_article(
  current_setting('test.art')::uuid, current_setting('test.lib')::uuid, null, null,
  'first version', 'mr', null, now(), null, null, '2026-01-01T00:00:00Z'::timestamptz);
select is(
  (select original_text from public.articles where id = current_setting('test.art')::uuid),
  'first version', 'fresh insert via upsert_article succeeds');

-- stale push (older client_updated_at) must NOT change stored fields
select public.upsert_article(
  current_setting('test.art')::uuid, current_setting('test.lib')::uuid, null, null,
  'stale version', 'mr', null, now(), null, null, '2025-12-31T00:00:00Z'::timestamptz);
select is(
  (select original_text from public.articles where id = current_setting('test.art')::uuid),
  'first version', 'stale client_updated_at push is rejected by the LWW guard');

-- newer push (newer client_updated_at) DOES update stored fields
select public.upsert_article(
  current_setting('test.art')::uuid, current_setting('test.lib')::uuid, null, null,
  'newer version', 'mr', null, now(), null, null, '2026-02-01T00:00:00Z'::timestamptz);
select is(
  (select original_text from public.articles where id = current_setting('test.art')::uuid),
  'newer version', 'newer client_updated_at push is accepted by the LWW guard');

-- same category coverage for upsert_category
select set_config('test.cat', gen_random_uuid()::text, true);
select public.upsert_category(
  current_setting('test.cat')::uuid, current_setting('test.lib')::uuid,
  'first', null, '2026-01-01T00:00:00Z'::timestamptz);
select public.upsert_category(
  current_setting('test.cat')::uuid, current_setting('test.lib')::uuid,
  'stale', null, '2025-12-31T00:00:00Z'::timestamptz);
select is(
  (select name from public.categories where id = current_setting('test.cat')::uuid),
  'first', 'upsert_category rejects a stale client_updated_at push too');

-- non-member rejected by both RPCs
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c3","email":"mallory@example.com","role":"authenticated"}', true);
set local role authenticated;
select throws_ok(
  $$select public.upsert_article(gen_random_uuid(), current_setting('test.lib')::uuid, null, null,
    'x', 'mr', null, now(), null, null, now())$$,
  'P0001', 'forbidden', 'stranger cannot call upsert_article');
select throws_ok(
  $$select public.upsert_category(gen_random_uuid(), current_setting('test.lib')::uuid,
    'x', null, now())$$,
  'P0001', 'forbidden', 'stranger cannot call upsert_category');

select * from finish();
rollback;
