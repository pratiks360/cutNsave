-- 20261005000000_category_dedup.sql deduped colliding category names with a
-- SELECT-then-INSERT: look for an existing live row with the same
-- library_id + lower(name), and if none is found, INSERT a new one. Under
-- genuinely concurrent pushes of the same new name from two devices (two
-- overlapping transactions, both committing after the other's SELECT ran),
-- both SELECTs can miss each other's uncommitted insert and both proceed to
-- INSERT, so the second hits categories_library_name_unique as a raw 23505
-- unique-violation instead of merging gracefully. The client's trySync()
-- catches it generically, so this wasn't a visible crash, but it defeated
-- the whole point of the dedup-on-sync feature under real concurrency.
--
-- This replaces the SELECT-then-INSERT with a single atomic
-- INSERT ... ON CONFLICT (library_id, lower(name)) WHERE deleted_at is null
-- DO UPDATE, so the dedup decision and the write happen as one statement
-- under the row's own index lock: there is no window where two concurrent
-- callers can both decide "no existing row" and both insert.
--
-- Carried forward unchanged from prior migrations (each CREATE OR REPLACE
-- fully replaces the previous body, so these must be re-asserted here):
--   * is_member(p_library_id) authorization check
--     (20261005000000_category_dedup.sql)
--   * the cross-library guard on the UPDATE-existing-row path: the WHERE
--     clause checks the row's EXISTING library_id, not just that the caller
--     is a member of the incoming p_library_id
--     (20261004000000_client_lww.sql)
--   * client_updated_at LWW semantics: an incoming push only wins if its
--     client_updated_at is >= the stored value (or the stored value is
--     null) (20261004000000_client_lww.sql)
--
-- The ON CONFLICT merge path only ever touches client_updated_at on the
-- surviving row, exactly like the SELECT-then-INSERT it replaces -- it does
-- not overwrite the survivor's name or deleted_at from the losing insert's
-- values, so a same-named push never "undeletes" or renames the survivor.
--
-- The DO UPDATE has its own WHERE guard (not just a CASE inside SET) so
-- that a stale colliding push -- one whose client_updated_at loses the LWW
-- comparison -- causes Postgres to skip the UPDATE entirely rather than
-- writing the same value back. Writing back an unchanged value would still
-- fire the categories_updated trigger and bump updated_at, which is the
-- sync pull cursor: per the invariant 20261004000000_client_lww.sql
-- established, a push the RPC decides not to apply must leave updated_at
-- untouched, or every other device re-pulls a row that didn't actually
-- change. When the WHERE guard skips the write, RETURNING produces no row,
-- so the id is looked up separately in that branch.
--
-- The merge's conflict target is (library_id, lower(name)), i.e. it is
-- scoped to the SAME library_id being inserted into, and p_library_id was
-- already authorized via is_member() above. So this cannot be used to merge
-- into, or leak identifiers from, another library's category -- the
-- existing "dedup is scoped to library_id" test still covers this.

create or replace function public.upsert_category(
  p_id uuid,
  p_library_id uuid,
  p_name text,
  p_deleted_at timestamptz,
  p_client_updated_at timestamptz
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  result_id uuid;
begin
  if not public.is_member(p_library_id) then
    raise exception 'forbidden';
  end if;

  if not exists (select 1 from public.categories where id = p_id) then
    -- Atomic dedup-on-sync: insert the new row, but if it collides
    -- case-insensitively with an existing live category in the same
    -- library, merge into that survivor instead. Doing this as a single
    -- INSERT ... ON CONFLICT closes the race that a separate SELECT-then-
    -- INSERT leaves open between two concurrent transactions.
    insert into public.categories (id, library_id, name, deleted_at, client_updated_at)
    values (p_id, p_library_id, p_name, p_deleted_at, p_client_updated_at)
    on conflict (library_id, lower(name)) where deleted_at is null
    do update set
      client_updated_at = excluded.client_updated_at
    where public.categories.client_updated_at is null
      or excluded.client_updated_at >= public.categories.client_updated_at
    returning id into result_id;

    if result_id is null then
      -- the WHERE guard above made Postgres skip the UPDATE (a stale
      -- colliding push loses to LWW), so RETURNING produced no row and
      -- the trigger-driven updated_at bump correctly never fired. The
      -- survivor's id is still the one the unique index matched on.
      select id into result_id from public.categories
        where library_id = p_library_id and lower(name) = lower(p_name) and deleted_at is null;
    end if;

    return result_id;
  end if;

  update public.categories set
    library_id = p_library_id,
    name = p_name,
    deleted_at = p_deleted_at,
    client_updated_at = p_client_updated_at
  where id = p_id
    and library_id = p_library_id
    and (client_updated_at is null or p_client_updated_at >= client_updated_at);
  return p_id;
end $$;
