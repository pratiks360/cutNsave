-- True last-write-wins sync, keyed by the CLIENT's edit timestamp rather than
-- "whichever push happened to land on the server last". Without this, a
-- device that went offline before an edit landed elsewhere can come back
-- online and unconditionally overwrite a newer edit (or "undelete" a row)
-- with its own stale copy, because a plain upsert only cares that a write
-- happened, not whether the incoming data is actually newer.
--
-- client_updated_at records when the edit was made on the device. The
-- upsert_article/upsert_category RPCs below accept it and only apply an
-- UPDATE to an existing row when the incoming client_updated_at is >= the
-- stored one (>= so a client re-pushing its own just-synced row, e.g. via
-- the markClean/retry path, isn't rejected as "not newer than itself"). A
-- genuinely new row is always inserted. The existing set_updated_at trigger
-- is untouched: it only fires on rows that actually get inserted/updated, so
-- a push the RPC decides to skip correctly leaves updated_at (the pull
-- cursor field) unchanged too.

alter table public.articles add column client_updated_at timestamptz;
alter table public.categories add column client_updated_at timestamptz;

update public.articles set client_updated_at = updated_at where client_updated_at is null;
update public.categories set client_updated_at = updated_at where client_updated_at is null;

create or replace function public.upsert_article(
  p_id uuid,
  p_library_id uuid,
  p_category_id uuid,
  p_image_path text,
  p_original_text text,
  p_original_lang text,
  p_english_text text,
  p_scanned_at timestamptz,
  p_created_by uuid,
  p_deleted_at timestamptz,
  p_client_updated_at timestamptz
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_member(p_library_id) then
    raise exception 'forbidden';
  end if;

  if not exists (select 1 from public.articles where id = p_id) then
    insert into public.articles (
      id, library_id, category_id, image_path, original_text, original_lang,
      english_text, scanned_at, created_by, deleted_at, client_updated_at
    ) values (
      p_id, p_library_id, p_category_id, p_image_path, p_original_text, p_original_lang,
      p_english_text, p_scanned_at, p_created_by, p_deleted_at, p_client_updated_at
    );
    return;
  end if;

  update public.articles set
    library_id = p_library_id,
    category_id = p_category_id,
    image_path = p_image_path,
    original_text = p_original_text,
    original_lang = p_original_lang,
    english_text = p_english_text,
    scanned_at = p_scanned_at,
    created_by = p_created_by,
    deleted_at = p_deleted_at,
    client_updated_at = p_client_updated_at
  where id = p_id
    and (client_updated_at is null or p_client_updated_at >= client_updated_at);
end $$;

create or replace function public.upsert_category(
  p_id uuid,
  p_library_id uuid,
  p_name text,
  p_deleted_at timestamptz,
  p_client_updated_at timestamptz
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_member(p_library_id) then
    raise exception 'forbidden';
  end if;

  if not exists (select 1 from public.categories where id = p_id) then
    insert into public.categories (id, library_id, name, deleted_at, client_updated_at)
    values (p_id, p_library_id, p_name, p_deleted_at, p_client_updated_at);
    return;
  end if;

  update public.categories set
    library_id = p_library_id,
    name = p_name,
    deleted_at = p_deleted_at,
    client_updated_at = p_client_updated_at
  where id = p_id
    and (client_updated_at is null or p_client_updated_at >= client_updated_at);
end $$;

revoke all on function public.upsert_article(
  uuid, uuid, uuid, text, text, text, text, timestamptz, uuid, timestamptz, timestamptz
) from public, anon;
revoke all on function public.upsert_category(
  uuid, uuid, text, timestamptz, timestamptz
) from public, anon;
grant execute on function public.upsert_article(
  uuid, uuid, uuid, text, text, text, text, timestamptz, uuid, timestamptz, timestamptz
) to authenticated;
grant execute on function public.upsert_category(
  uuid, uuid, text, timestamptz, timestamptz
) to authenticated;
