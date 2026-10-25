-- Run once in Supabase SQL Editor. Self-service account deletion only.
-- Deletes owned boards (including contributions from others), own contributions
-- elsewhere, public profile, Auth account and its sessions in one transaction.
begin;
create or replace function public.moatteul_delete_my_account(confirmation text)
returns void language plpgsql security definer set search_path = '' as $$
declare caller uuid := auth.uid();
begin
  if caller is null or confirmation is distinct from 'DELETE' then
    raise exception 'Authenticated confirmation required' using errcode='42501';
  end if;
  -- Check live session as well as JWT; an already deleted/revoked session cannot call this.
  if not exists(select 1 from auth.sessions s where s.user_id=caller
      and s.id::text=auth.jwt()->>'session_id') then
    raise exception 'Please sign in again' using errcode='42501';
  end if;
  perform 1 from auth.users u where u.id=caller for update;
  if not found then raise exception 'Account not found'; end if;
  perform 1 from public.boards b where b.owner_id=caller for update;
  delete from public.post_likes l where l.user_id=caller or l.post_id in (
    select p.id from public.posts p join public.board_tabs t on t.id=p.tab_id
      join public.boards b on b.id=t.board_id where p.author_id=caller or b.owner_id=caller);
  delete from public.post_comments c where c.author_id=caller or c.post_id in (
    select p.id from public.posts p join public.board_tabs t on t.id=p.tab_id
      join public.boards b on b.id=t.board_id where p.author_id=caller or b.owner_id=caller);
  delete from public.posts p where p.author_id=caller or p.tab_id in (
    select t.id from public.board_tabs t join public.boards b on b.id=t.board_id where b.owner_id=caller);
  delete from public.board_tabs t where t.board_id in (
    select b.id from public.boards b where b.owner_id=caller);
  delete from public.boards b where b.owner_id=caller;
  delete from public.moatteul_profiles p where p.id=caller;
  delete from auth.users u where u.id=caller;
end;
$$;
revoke all on function public.moatteul_delete_my_account(text) from public, anon;
grant execute on function public.moatteul_delete_my_account(text) to authenticated;
notify pgrst,'reload schema';
commit;
