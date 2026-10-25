-- Run once in Supabase SQL Editor before using nicknames.
-- Public profiles expose only user ID and nickname, never email.
begin;
create table if not exists public.moatteul_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text check (nickname is null or (nickname=btrim(nickname) and char_length(nickname) between 2 and 20))
);
alter table public.moatteul_profiles enable row level security;
revoke all on public.moatteul_profiles from anon, authenticated;
grant select on public.moatteul_profiles to anon, authenticated;
drop policy if exists nicknames_read on public.moatteul_profiles;
create policy nicknames_read on public.moatteul_profiles for select to anon, authenticated using (true);

create or replace function public.moatteul_sync_nickname()
returns trigger language plpgsql security definer set search_path = '' as $$
declare display_name text;
begin
  display_name := nullif(btrim(new.raw_user_meta_data->>'nickname'),'');
  if display_name is not null and char_length(display_name) not between 2 and 20 then
    raise exception 'Nickname must contain 2 to 20 characters';
  end if;
  insert into public.moatteul_profiles(id,nickname) values(new.id,display_name)
  on conflict(id) do update set nickname=excluded.nickname;
  return new;
end;
$$;
revoke all on function public.moatteul_sync_nickname() from public, anon, authenticated;
drop trigger if exists moatteul_nickname_sync on auth.users;
create trigger moatteul_nickname_sync after insert or update of raw_user_meta_data on auth.users
for each row execute function public.moatteul_sync_nickname();

insert into public.moatteul_profiles(id,nickname)
select id,case when char_length(btrim(raw_user_meta_data->>'nickname')) between 2 and 20
  then btrim(raw_user_meta_data->>'nickname') else null end
from auth.users
on conflict(id) do update set nickname=excluded.nickname;
notify pgrst,'reload schema';
commit;
