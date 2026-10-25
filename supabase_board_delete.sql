-- Run once in Supabase SQL Editor to enable atomic, owner-only board deletion.
begin;
create or replace function public.moatteul_delete_board(target_board_id text)
returns void language plpgsql security definer set search_path = '' as $$
declare board_owner uuid;
begin
  if auth.uid() is null then raise exception 'Login required' using errcode='42501'; end if;
  select b.owner_id into board_owner from public.boards b
    where b.id::text=target_board_id for update;
  if not found then raise exception 'Board not found' using errcode='P0002'; end if;
  if board_owner is distinct from auth.uid() then
    raise exception 'Only the owner can delete this board' using errcode='42501';
  end if;
  delete from public.post_likes l using public.posts p, public.board_tabs t
    where l.post_id=p.id and p.tab_id=t.id and t.board_id::text=target_board_id;
  delete from public.post_comments c using public.posts p, public.board_tabs t
    where c.post_id=p.id and p.tab_id=t.id and t.board_id::text=target_board_id;
  delete from public.posts p using public.board_tabs t
    where p.tab_id=t.id and t.board_id::text=target_board_id;
  delete from public.board_tabs t where t.board_id::text=target_board_id;
  delete from public.boards b where b.id::text=target_board_id;
end;
$$;
revoke all on function public.moatteul_delete_board(text) from public, anon;
grant execute on function public.moatteul_delete_board(text) to authenticated;
notify pgrst,'reload schema';
commit;
