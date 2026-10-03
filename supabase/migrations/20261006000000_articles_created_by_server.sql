-- articles.created_by was accepted verbatim from the client, and even
-- overwritten on every *update* to whatever the caller currently sends - so
-- any library member could impersonate another member as an article's
-- author, or silently rewrite an existing article's authorship when editing
-- it. Low risk in a single shared-family deployment, but easy to tighten:
-- the server now stamps created_by from auth.uid() when a row is first
-- inserted, and never touches it again on update (authorship doesn't change
-- just because the text was edited). p_created_by is kept as a parameter for
-- API compatibility with the existing Flutter client (RemoteStore still
-- sends the local value) but is now ignored by the function.
--
-- The cross-library guard from 20261004000000_client_lww.sql (the update's
-- `and library_id = p_library_id` check against the row's EXISTING
-- library_id) is preserved unchanged.

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
      p_english_text, p_scanned_at, auth.uid(), p_deleted_at, p_client_updated_at
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
    deleted_at = p_deleted_at,
    client_updated_at = p_client_updated_at
  where id = p_id
    and library_id = p_library_id
    and (client_updated_at is null or p_client_updated_at >= client_updated_at);
end $$;

revoke all on function public.upsert_article(
  uuid, uuid, uuid, text, text, text, text, timestamptz, uuid, timestamptz, timestamptz
) from public, anon;
grant execute on function public.upsert_article(
  uuid, uuid, uuid, text, text, text, text, timestamptz, uuid, timestamptz, timestamptz
) to authenticated;
