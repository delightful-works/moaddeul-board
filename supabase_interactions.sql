-- Run in the Supabase SQL Editor only if the interaction tables are missing.
-- Existing tables and policies are left unchanged.
begin;
do $migration$
declare post_id_type text;
begin
  select format_type(a.atttypid,a.atttypmod) into post_id_type
  from pg_attribute a where a.attrelid='public.posts'::regclass
    and a.attname='id' and not a.attisdropped;
  if post_id_type is null then raise exception 'public.posts.id is required'; end if;

  if to_regclass('public.post_likes') is null then
    execute format('create table public.post_likes (
      post_id %s not null references public.posts(id) on delete cascade,
      user_id uuid not null references auth.users(id) on delete cascade,
      created_at timestamptz not null default now(),
      primary key(post_id,user_id))',post_id_type);
    alter table public.post_likes enable row level security;
    grant select on public.post_likes to anon, authenticated;
    grant insert, delete on public.post_likes to authenticated;
    create policy likes_read on public.post_likes for select to anon, authenticated
      using (exists(select 1 from public.posts p where p.id=post_id));
    create policy likes_add on public.post_likes for insert to authenticated
      with check (user_id=(select auth.uid()) and exists(select 1 from public.posts p where p.id=post_id));
    create policy likes_remove on public.post_likes for delete to authenticated
      using (user_id=(select auth.uid()));
  end if;

  if to_regclass('public.post_comments') is null then
    execute format('create table public.post_comments (
      id uuid primary key default gen_random_uuid(),
      post_id %s not null references public.posts(id) on delete cascade,
      author_id uuid not null references auth.users(id) on delete cascade,
      body text not null check(length(btrim(body))>0),
      created_at timestamptz not null default now())',post_id_type);
    create index post_comments_post_created_idx on public.post_comments(post_id,created_at);
    alter table public.post_comments enable row level security;
    grant select on public.post_comments to anon, authenticated;
    grant insert on public.post_comments to authenticated;
    create policy comments_read on public.post_comments for select to anon, authenticated
      using (exists(select 1 from public.posts p where p.id=post_id));
    create policy comments_add on public.post_comments for insert to authenticated
      with check (author_id=(select auth.uid()) and exists(select 1 from public.posts p where p.id=post_id));
  end if;
end
$migration$;
notify pgrst,'reload schema';
commit;
