begin;
select plan(34);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'mom@example.com'),
  ('00000000-0000-0000-0000-0000000000b2', 'sis@example.com'),
  ('00000000-0000-0000-0000-0000000000c3', 'mallory@example.com'),
  ('00000000-0000-0000-0000-0000000000d4', 'dave@example.com');

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

select public.upsert_category(
  current_setting('test.cat')::uuid, current_setting('test.lib')::uuid,
  'newer', null, '2026-02-01T00:00:00Z'::timestamptz);
select is(
  (select name from public.categories where id = current_setting('test.cat')::uuid),
  'newer', 'newer client_updated_at push is accepted for categories too');

-- dave is a member of a second, unrelated library (library B). This app's
-- real deployment is single-family/single-library (bootstrap_library()
-- refuses to create a second one), but the schema itself places no
-- constraint against a second libraries row existing, so the RPCs must not
-- rely on that deployment assumption for authorization. Insert library B
-- directly (as the test's superuser role) to exercise that case.
reset role;
insert into public.libraries (owner_id) values ('00000000-0000-0000-0000-0000000000d4');
select set_config('test.lib_b', (select id::text from public.libraries
  where owner_id = '00000000-0000-0000-0000-0000000000d4'), true);
insert into public.library_members (library_id, email, user_id, role)
  values (current_setting('test.lib_b')::uuid, 'dave@example.com',
    '00000000-0000-0000-0000-0000000000d4', 'owner');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d4","email":"dave@example.com","role":"authenticated"}', true);
set local role authenticated;
select set_config('test.art_b', gen_random_uuid()::text, true);
select public.upsert_article(
  current_setting('test.art_b')::uuid, current_setting('test.lib_b')::uuid, null, null,
  'daves article', 'mr', null, now(), null, null, '2026-01-01T00:00:00Z'::timestamptz);
select set_config('test.cat_b', gen_random_uuid()::text, true);
select public.upsert_category(
  current_setting('test.cat_b')::uuid, current_setting('test.lib_b')::uuid,
  'daves category', null, '2026-01-01T00:00:00Z'::timestamptz);

-- mom (member of library A only) cannot hijack library B's rows by passing
-- her own library_id alongside an id she doesn't own; security definer RPCs
-- must check the row's EXISTING library_id, not just caller membership
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","email":"mom@example.com","role":"authenticated"}', true);
set local role authenticated;
select public.upsert_article(
  current_setting('test.art_b')::uuid, current_setting('test.lib')::uuid, null, null,
  'hijacked', 'mr', null, now(), null, null, '2026-03-01T00:00:00Z'::timestamptz);
select public.upsert_category(
  current_setting('test.cat_b')::uuid, current_setting('test.lib')::uuid,
  'hijacked', null, '2026-03-01T00:00:00Z'::timestamptz);

-- check with RLS bypassed (superuser) since mom isn't a member of library B
-- and can't see its rows at all, which is itself correct but not what this
-- assertion is testing
reset role;
select is(
  (select library_id from public.articles where id = current_setting('test.art_b')::uuid),
  current_setting('test.lib_b')::uuid, 'cross-library upsert_article cannot reassign another library''s row');
select is(
  (select library_id from public.categories where id = current_setting('test.cat_b')::uuid),
  current_setting('test.lib_b')::uuid, 'cross-library upsert_category cannot reassign another library''s row');

-- category dedup-on-sync: two "devices" independently create a
-- case-insensitively duplicate category name; the second upsert_category
-- must merge into the first instead of inserting a duplicate row (still as
-- mom, library A).
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","email":"mom@example.com","role":"authenticated"}', true);
set local role authenticated;

select set_config('test.cat_dup1', gen_random_uuid()::text, true);
select is(
  public.upsert_category(current_setting('test.cat_dup1')::uuid, current_setting('test.lib')::uuid,
    'Groceries', null, '2026-04-01T00:00:00Z'::timestamptz),
  current_setting('test.cat_dup1')::uuid,
  'fresh category insert returns its own id');

select set_config('test.cat_dup2', gen_random_uuid()::text, true);
select is(
  public.upsert_category(current_setting('test.cat_dup2')::uuid, current_setting('test.lib')::uuid,
    'GROCERIES', null, '2026-04-02T00:00:00Z'::timestamptz),
  current_setting('test.cat_dup1')::uuid,
  'a case-insensitive duplicate name merges into the existing id instead of inserting');

select is(
  (select count(*)::int from public.categories where lower(name) = 'groceries'),
  1, 'no duplicate row was created for the case-insensitive collision');

select is(
  (select count(*)::int from public.categories where id = current_setting('test.cat_dup2')::uuid),
  0, 'the losing id was never inserted');

-- a third "device" independently creates yet another case-insensitive
-- duplicate of the same name, under a third id. upsert_category now dedupes
-- via a single atomic INSERT ... ON CONFLICT (replacing the old
-- SELECT-then-INSERT), so this proves the merge path isn't limited to a
-- one-shot "first collision only" special case -- repeated colliding
-- inserts keep merging into the same original survivor.
select set_config('test.cat_dup3', gen_random_uuid()::text, true);
select is(
  public.upsert_category(current_setting('test.cat_dup3')::uuid, current_setting('test.lib')::uuid,
    'groceries', null, '2026-04-04T00:00:00Z'::timestamptz),
  current_setting('test.cat_dup1')::uuid,
  'a second, later collision from a third id also merges into the original survivor');
select is(
  (select count(*)::int from public.categories where lower(name) = 'groceries'),
  1, 'still only one row after the second colliding insert');

-- same id, colliding (different-case) name pushed again by the same caller:
-- this takes the UPDATE-existing-row branch (the id already exists), not
-- the INSERT ... ON CONFLICT branch, and must not raise 23505 either.
select lives_ok(
  $$select public.upsert_category(current_setting('test.cat_dup1')::uuid, current_setting('test.lib')::uuid,
    'GROCERIES', null, '2026-04-05T00:00:00Z'::timestamptz)$$,
  'same id + colliding-case name from the same caller updates in place without erroring');
select is(
  (select name from public.categories where id = current_setting('test.cat_dup1')::uuid),
  'GROCERIES', 'the in-place update applied the new casing to the survivor row');

-- dedup is scoped to library_id: the same name in a DIFFERENT library (dave,
-- library B) must insert its own row, never merge into library A's
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d4","email":"dave@example.com","role":"authenticated"}', true);
set local role authenticated;
select set_config('test.cat_dup_b', gen_random_uuid()::text, true);
select is(
  public.upsert_category(current_setting('test.cat_dup_b')::uuid, current_setting('test.lib_b')::uuid,
    'Groceries', null, '2026-04-03T00:00:00Z'::timestamptz),
  current_setting('test.cat_dup_b')::uuid,
  'a same-named category in a different library inserts its own row, not a cross-library merge');

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","email":"mom@example.com","role":"authenticated"}', true);
set local role authenticated;

-- articles.created_by is stamped from the caller's auth.uid(), not trusted
-- from the client, and is immutable across updates (still as mom).
select set_config('test.art_cb', gen_random_uuid()::text, true);
select public.upsert_article(
  current_setting('test.art_cb')::uuid, current_setting('test.lib')::uuid, null, null,
  'authored', 'mr', null, now(),
  '00000000-0000-0000-0000-0000000000d4', -- client dishonestly claims dave as author
  null, '2026-05-01T00:00:00Z'::timestamptz);
select is(
  (select created_by from public.articles where id = current_setting('test.art_cb')::uuid),
  '00000000-0000-0000-0000-0000000000a1'::uuid,
  'server stamps created_by from the caller, ignoring the client-supplied value');

select public.upsert_article(
  current_setting('test.art_cb')::uuid, current_setting('test.lib')::uuid, null, null,
  'authored v2', 'mr', null, now(),
  '00000000-0000-0000-0000-0000000000b2', -- client now claims sis as author
  null, '2026-05-02T00:00:00Z'::timestamptz);
select is(
  (select created_by from public.articles where id = current_setting('test.art_cb')::uuid),
  '00000000-0000-0000-0000-0000000000a1'::uuid,
  'updating an article never changes its created_by, regardless of what the client sends');

-- a different member of the same library (sis) updating mom's article also
-- cannot alter created_by, confirming this isn't just a same-caller quirk
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b2","email":"sis@example.com","role":"authenticated"}', true);
set local role authenticated;
select public.upsert_article(
  current_setting('test.art_cb')::uuid, current_setting('test.lib')::uuid, null, null,
  'authored v3 by sis', 'mr', null, now(),
  '00000000-0000-0000-0000-0000000000b2', -- sis claims herself as author
  null, '2026-05-03T00:00:00Z'::timestamptz);
select is(
  (select created_by from public.articles where id = current_setting('test.art_cb')::uuid),
  '00000000-0000-0000-0000-0000000000a1'::uuid,
  'a different member updating the article still cannot change its created_by from the original author');
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","email":"mom@example.com","role":"authenticated"}', true);
set local role authenticated;

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
