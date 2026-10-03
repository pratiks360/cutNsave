create extension if not exists pgcrypto;

create table public.libraries (
  id uuid primary key default gen_random_uuid(),
  name text not null default 'Family',
  owner_id uuid not null references auth.users (id),
  created_at timestamptz not null default now()
);

create table public.library_members (
  library_id uuid not null references public.libraries (id) on delete cascade,
  email text not null check (email = lower(email)),
  user_id uuid references auth.users (id),
  role text not null default 'member' check (role in ('owner', 'member')),
  primary key (library_id, email)
);

create table public.categories (
  id uuid primary key,
  library_id uuid not null references public.libraries (id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.articles (
  id uuid primary key,
  library_id uuid not null references public.libraries (id) on delete cascade,
  category_id uuid references public.categories (id),
  image_path text,
  original_text text not null default '',
  original_lang text not null check (original_lang in ('mr', 'hi', 'en')),
  english_text text,
  scanned_at timestamptz not null,
  created_by uuid references auth.users (id),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index articles_library_updated on public.articles (library_id, updated_at);
create index categories_library_updated on public.categories (library_id, updated_at);

create table public.quota_usage (
  library_id uuid not null references public.libraries (id) on delete cascade,
  month date not null,
  ocr_calls int not null default 0,
  translate_chars int not null default 0,
  primary key (library_id, month)
);

-- server decides updated_at (sync cursor)
create or replace function public.set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;
create trigger categories_updated before insert or update on public.categories
  for each row execute function public.set_updated_at();
create trigger articles_updated before insert or update on public.articles
  for each row execute function public.set_updated_at();

-- membership helpers (security definer so RLS policies can call them)
create or replace function public.is_member(lib uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.library_members where library_id = lib and user_id = auth.uid()
  );
$$;
create or replace function public.is_owner(lib uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.library_members
    where library_id = lib and user_id = auth.uid() and role = 'owner'
  );
$$;

alter table public.libraries enable row level security;
alter table public.library_members enable row level security;
alter table public.categories enable row level security;
alter table public.articles enable row level security;
alter table public.quota_usage enable row level security;

create policy libraries_select on public.libraries for select to authenticated
  using (public.is_member(id));
create policy members_select on public.library_members for select to authenticated
  using (public.is_member(library_id));
create policy members_insert on public.library_members for insert to authenticated
  with check (public.is_owner(library_id) and role = 'member' and email = lower(email));
create policy members_delete on public.library_members for delete to authenticated
  using (public.is_owner(library_id) and role <> 'owner');
create policy categories_all on public.categories for all to authenticated
  using (public.is_member(library_id)) with check (public.is_member(library_id));
create policy articles_all on public.articles for all to authenticated
  using (public.is_member(library_id)) with check (public.is_member(library_id));
create policy quota_select on public.quota_usage for select to authenticated
  using (public.is_member(library_id));

-- first sign-in: link allow-listed email, or create the very first library
create or replace function public.bootstrap_library() returns uuid
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  mail text := lower(auth.jwt() ->> 'email');
  lib uuid;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;
  update public.library_members set user_id = uid where email = mail and user_id is null;
  select library_id into lib from public.library_members where user_id = uid limit 1;
  if lib is not null then
    return lib;
  end if;
  if exists (select 1 from public.libraries) then
    return null;
  end if;
  insert into public.libraries (owner_id) values (uid) returning id into lib;
  insert into public.library_members (library_id, email, user_id, role)
    values (lib, mail, uid, 'owner');
  insert into public.categories (id, library_id, name)
    select gen_random_uuid(), lib, n
    from unnest(array['पाककृती / Recipes', 'आरोग्य / Health', 'गोष्टी / Stories',
                      'कविता / Poems', 'इतर / Other']) as n;
  return lib;
end $$;

-- atomic monthly cap. Limits = Google free tier.
create or replace function public.consume_quota(lib uuid, kind text, amount int) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  m date := date_trunc('month', now())::date;
  ocr_limit int := 1000;
  translate_limit int := 500000;
begin
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

create or replace function public.get_quota(lib uuid)
returns table (month date, ocr_used int, ocr_limit int, translate_used int, translate_limit int)
language plpgsql security definer set search_path = public as $$
declare
  m date := date_trunc('month', now())::date;
begin
  if not public.is_member(lib) then
    raise exception 'forbidden';
  end if;
  return query
    select m,
           coalesce((select q.ocr_calls from public.quota_usage q where q.library_id = lib and q.month = m), 0),
           1000,
           coalesce((select q.translate_chars from public.quota_usage q where q.library_id = lib and q.month = m), 0),
           500000;
end $$;

revoke all on function public.bootstrap_library() from public, anon;
revoke all on function public.consume_quota(uuid, text, int) from public, anon;
revoke all on function public.get_quota(uuid) from public, anon;
grant execute on function public.bootstrap_library() to authenticated;
grant execute on function public.consume_quota(uuid, text, int) to authenticated;
grant execute on function public.get_quota(uuid) to authenticated;

-- storage: private bucket, path prefix = library id
insert into storage.buckets (id, name, public) values ('articles', 'articles', false)
  on conflict (id) do nothing;
create policy articles_objects_rw on storage.objects for all to authenticated
  using (bucket_id = 'articles' and public.is_member(((storage.foldername(name))[1])::uuid))
  with check (bucket_id = 'articles' and public.is_member(((storage.foldername(name))[1])::uuid));
