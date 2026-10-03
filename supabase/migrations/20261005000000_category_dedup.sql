-- Repository.createCategory only dedupes locally (case-insensitive, within
-- one device's own SQLite). Two devices that are both offline when a family
-- member types the same category name (e.g. "Recipes" / "recipes ") each
-- generate their own id for it, and both ids independently sync up as
-- "insert new category" once they're back online, leaving two rows for what
-- the user experiences as one category.
--
-- This adds a case-insensitive uniqueness guarantee for live (non-deleted)
-- category names within a library, and teaches upsert_category to dedupe on
-- sync: when an insert's name collides (case-insensitively) with an
-- existing, different, non-deleted category in the same library, it merges
-- into that existing row instead of inserting a duplicate, and returns the
-- *surviving* row's id so the client can remap. Before this, upsert_category
-- returned void; it now returns uuid, so it must be dropped and recreated
-- (Postgres does not allow CREATE OR REPLACE to change a function's return
-- type).
--
-- This only guards category CREATION races. A pre-existing duplicate pair
-- already synced before this migration is not retroactively merged; that's
-- an acceptable one-time manual cleanup rather than something worth a risky
-- automatic merge migration.

create unique index if not exists categories_library_name_unique
  on public.categories (library_id, lower(name))
  where deleted_at is null;

drop function if exists public.upsert_category(uuid, uuid, text, timestamptz, timestamptz);

create function public.upsert_category(
  p_id uuid,
  p_library_id uuid,
  p_name text,
  p_deleted_at timestamptz,
  p_client_updated_at timestamptz
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  existing_id uuid;
begin
  if not public.is_member(p_library_id) then
    raise exception 'forbidden';
  end if;

  if not exists (select 1 from public.categories where id = p_id) then
    -- Dedup-on-sync: a live category with this name already exists under a
    -- different id in this library, e.g. created independently by another
    -- offline device. Merge into it rather than inserting a duplicate.
    select id into existing_id from public.categories
      where library_id = p_library_id and lower(name) = lower(p_name)
        and deleted_at is null and id <> p_id
      limit 1;
    if existing_id is not null then
      update public.categories set client_updated_at = p_client_updated_at
        where id = existing_id
          and (client_updated_at is null or p_client_updated_at >= client_updated_at);
      return existing_id;
    end if;

    insert into public.categories (id, library_id, name, deleted_at, client_updated_at)
    values (p_id, p_library_id, p_name, p_deleted_at, p_client_updated_at);
    return p_id;
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

revoke all on function public.upsert_category(
  uuid, uuid, text, timestamptz, timestamptz
) from public, anon;
grant execute on function public.upsert_category(
  uuid, uuid, text, timestamptz, timestamptz
) to authenticated;
