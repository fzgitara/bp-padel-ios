-- Core tables for BP Padel.

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '',
  created_at timestamptz not null default now()
);

create table public.tournaments (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  name text not null,
  total_courts int not null default 1 check (total_courts >= 1),
  status text not null default 'setup' check (status in ('setup', 'active', 'completed')),
  format text not null check (format in ('americano', 'mexicano')),
  points_mode text not null default 'default' check (points_mode in ('total21', 'default')),
  partner_mode text not null default 'rotating' check (partner_mode in ('fixed', 'rotating')),
  teams jsonb not null default '[]',
  created_at timestamptz not null default now()
);

create table public.tournament_members (
  tournament_id uuid not null references public.tournaments (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role text not null check (role in ('owner', 'scorer')),
  primary key (tournament_id, user_id)
);

create table public.tournament_invites (
  code text primary key,
  tournament_id uuid not null references public.tournaments (id) on delete cascade,
  created_by uuid not null references public.profiles (id) on delete cascade,
  expires_at timestamptz not null default now() + interval '7 days',
  revoked boolean not null default false
);

create table public.players (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  name text not null
);

create table public.tournament_participants (
  tournament_id uuid not null references public.tournaments (id) on delete cascade,
  player_id uuid not null references public.players (id) on delete cascade,
  active boolean not null default true,
  primary key (tournament_id, player_id)
);

create table public.matches (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments (id) on delete cascade,
  round int not null,
  team1 uuid[] not null,
  team2 uuid[] not null,
  score1 int,
  score2 int,
  status text not null default 'pending' check (status in ('pending', 'completed')),
  live_sets1 int,
  live_sets2 int,
  live_game1 int,
  live_game2 int
);

create index matches_tournament_round_idx on public.matches (tournament_id, round);
create index tournament_members_user_idx on public.tournament_members (user_id);
create index players_owner_idx on public.players (owner_id);

-- A profile row is created for every new auth user.
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', split_part(new.email, '@', 1), '')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- The creator becomes the owner member of a new tournament.
create function public.handle_new_tournament() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.tournament_members (tournament_id, user_id, role)
  values (new.id, new.owner_id, 'owner');
  return new;
end;
$$;

create trigger on_tournament_created
  after insert on public.tournaments
  for each row execute function public.handle_new_tournament();

revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.handle_new_tournament() from public, anon, authenticated;

-- Live score changes are pushed to subscribed clients.
alter publication supabase_realtime add table public.matches;
