-- ArticleScreen's "Translate now" button previously showed whenever
-- english_text was null and original_lang <> 'en', conflating two different
-- cases: (a) a translation was genuinely attempted and is pending/failed
-- (quota exhausted, offline, both ML Kit and cloud failed), vs (b) the user
-- explicitly turned the translate toggle off in EditArticleScreen. Nothing
-- persisted which case applied, so the retry button offered to spend cloud-
-- translate quota on an article someone deliberately chose to keep
-- untranslated.
--
-- This is synced (not local-only) because the app is family-shared: a
-- daughter viewing an article her mom declined to translate should see the
-- same "declined" state, not a stray "translate now" prompt just because her
-- device never learned about the decision.
--
-- p_translation_declined defaults to false so every existing positional call
-- to upsert_article (including the ones in supabase/tests/rls_test.sql) keeps
-- working unchanged.

alter table public.articles
  add column translation_declined boolean not null default false;

-- Carried forward unchanged from 20261006000000_articles_created_by_server.sql:
--   * is_member(p_library_id) authorization check
--   * created_by is stamped from auth.uid() on insert only, and p_created_by
--     is otherwise ignored (kept as a parameter for client compatibility)
--   * the cross-library guard on the UPDATE-existing-row path (the row's
--     EXISTING library_id, not just caller membership of p_library_id)
--   * client_updated_at LWW semantics
--
-- Adding p_translation_declined changes the parameter list, so `create or
-- replace` would leave the old 11-arg signature behind as a separate
-- overload instead of replacing it (Postgres keys functions by their
-- argument types). Drop it explicitly first so only the new 12-arg
-- signature exists - avoids ambiguous overload resolution for callers that
-- pass named params without p_translation_declined.
drop function if exists public.upsert_article(
  uuid, uuid, uuid, text, text, text, text, timestamptz, uuid, timestamptz, timestamptz
);

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
  p_client_updated_at timestamptz,
  p_translation_declined boolean default false
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_member(p_library_id) then
    raise exception 'forbidden';
  end if;

  if not exists (select 1 from public.articles where id = p_id) then
    insert into public.articles (
      id, library_id, category_id, image_path, original_text, original_lang,
      english_text, translation_declined, scanned_at, created_by, deleted_at,
      client_updated_at
    ) values (
      p_id, p_library_id, p_category_id, p_image_path, p_original_text, p_original_lang,
      p_english_text, p_translation_declined, p_scanned_at, auth.uid(), p_deleted_at,
      p_client_updated_at
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
    translation_declined = p_translation_declined,
    scanned_at = p_scanned_at,
    deleted_at = p_deleted_at,
    client_updated_at = p_client_updated_at
  where id = p_id
    and library_id = p_library_id
    and (client_updated_at is null or p_client_updated_at >= client_updated_at);
end $$;

revoke all on function public.upsert_article(
  uuid, uuid, uuid, text, text, text, text, timestamptz, uuid, timestamptz, timestamptz, boolean
) from public, anon;
grant execute on function public.upsert_article(
  uuid, uuid, uuid, text, text, text, text, timestamptz, uuid, timestamptz, timestamptz, boolean
) to authenticated;
