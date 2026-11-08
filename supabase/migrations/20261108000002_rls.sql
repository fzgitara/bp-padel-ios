-- Row level security, helper functions and invite RPCs.

create function public.is_member(tid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.tournament_members
    where tournament_id = tid and user_id = auth.uid()
  );
$$;

create function public.is_owner(tid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.tournament_members
    where tournament_id = tid and user_id = auth.uid() and role = 'owner'
  );
$$;

create function public.shares_tournament_with(other uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.tournament_members mine
    join public.tournament_members theirs on theirs.tournament_id = mine.tournament_id
    where mine.user_id = auth.uid() and theirs.user_id = other
  );
$$;

revoke execute on function public.is_member(uuid), public.is_owner(uuid), public.shares_tournament_with(uuid)
  from public, anon;
grant execute on function public.is_member(uuid), public.is_owner(uuid), public.shares_tournament_with(uuid)
  to authenticated;

alter table public.profiles enable row level security;
alter table public.tournaments enable row level security;
alter table public.tournament_members enable row level security;
alter table public.tournament_invites enable row level security;
alter table public.players enable row level security;
alter table public.tournament_participants enable row level security;
alter table public.matches enable row level security;

-- profiles
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or public.shares_tournament_with(id));
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- tournaments
create policy tournaments_select on public.tournaments for select to authenticated
  using (public.is_member(id));
create policy tournaments_insert on public.tournaments for insert to authenticated
  with check (owner_id = auth.uid());
create policy tournaments_update on public.tournaments for update to authenticated
  using (public.is_owner(id)) with check (public.is_owner(id));
create policy tournaments_delete on public.tournaments for delete to authenticated
  using (public.is_owner(id));

-- tournament_members: rows are created by triggers and join_tournament only.
-- The owner can remove scorers; a scorer can remove themselves. The owner row is never deletable.
create policy members_select on public.tournament_members for select to authenticated
  using (public.is_member(tournament_id));
create policy members_delete on public.tournament_members for delete to authenticated
  using (role = 'scorer' and (public.is_owner(tournament_id) or user_id = auth.uid()));

-- tournament_invites: owners read and revoke; creating goes through create_invite().
create policy invites_select on public.tournament_invites for select to authenticated
  using (public.is_owner(tournament_id));
create policy invites_update on public.tournament_invites for update to authenticated
  using (public.is_owner(tournament_id)) with check (public.is_owner(tournament_id));

-- players
create policy players_select on public.players for select to authenticated
  using (
    owner_id = auth.uid()
    or exists (
      select 1 from public.tournament_participants tp
      where tp.player_id = players.id and public.is_member(tp.tournament_id)
    )
  );
create policy players_insert on public.players for insert to authenticated
  with check (owner_id = auth.uid());
create policy players_update on public.players for update to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy players_delete on public.players for delete to authenticated
  using (owner_id = auth.uid());

-- tournament_participants
create policy participants_select on public.tournament_participants for select to authenticated
  using (public.is_member(tournament_id));
create policy participants_insert on public.tournament_participants for insert to authenticated
  with check (
    public.is_owner(tournament_id)
    and exists (select 1 from public.players p where p.id = player_id and p.owner_id = auth.uid())
  );
create policy participants_update on public.tournament_participants for update to authenticated
  using (public.is_owner(tournament_id)) with check (public.is_owner(tournament_id));
create policy participants_delete on public.tournament_participants for delete to authenticated
  using (public.is_owner(tournament_id));

-- matches: owner and scorers read and update (scores, teams); only the owner creates and deletes.
create policy matches_select on public.matches for select to authenticated
  using (public.is_member(tournament_id));
create policy matches_insert on public.matches for insert to authenticated
  with check (public.is_owner(tournament_id));
create policy matches_update on public.matches for update to authenticated
  using (public.is_member(tournament_id)) with check (public.is_member(tournament_id));
create policy matches_delete on public.matches for delete to authenticated
  using (public.is_owner(tournament_id));

-- Owner creates an invite code (8 characters, no look-alike letters or digits).
create function public.create_invite(tid uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  random_bytes bytea;
  new_code text;
  i int;
begin
  if not public.is_owner(tid) then
    raise exception 'not_owner' using errcode = '42501';
  end if;

  loop
    random_bytes := extensions.gen_random_bytes(8);
    new_code := '';
    for i in 0..7 loop
      new_code := new_code || substr(alphabet, (get_byte(random_bytes, i) % 32) + 1, 1);
    end loop;

    begin
      insert into public.tournament_invites (code, tournament_id, created_by)
      values (new_code, tid, auth.uid());
      return new_code;
    exception when unique_violation then
      null;
    end;
  end loop;
end;
$$;

-- Joining with a code makes the caller a scorer. Safe to call again; never changes an existing role.
create function public.join_tournament(invite_code text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  invite public.tournament_invites;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into invite from public.tournament_invites where code = upper(trim(invite_code));
  if not found then
    raise exception 'invite_not_found';
  end if;
  if invite.revoked then
    raise exception 'invite_revoked';
  end if;
  if invite.expires_at <= now() then
    raise exception 'invite_expired';
  end if;

  insert into public.tournament_members (tournament_id, user_id, role)
  values (invite.tournament_id, auth.uid(), 'scorer')
  on conflict do nothing;

  return invite.tournament_id;
end;
$$;

revoke execute on function public.create_invite(uuid), public.join_tournament(text) from public, anon;
grant execute on function public.create_invite(uuid), public.join_tournament(text) to authenticated;
