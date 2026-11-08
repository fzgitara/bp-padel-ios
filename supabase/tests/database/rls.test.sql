begin;
select plan(29);

-- Fixtures (run as the postgres superuser, so RLS does not apply here)
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'owner@example.com'),
  ('00000000-0000-0000-0000-00000000000b', 'scorer@example.com'),
  ('00000000-0000-0000-0000-00000000000c', 'outsider@example.com');

select is(
  (select display_name from public.profiles where id = '00000000-0000-0000-0000-00000000000a'),
  'owner',
  'signup creates a profile named after the email'
);

-- Counts rows touched by a statement, running with the caller's role so RLS applies
create function public.test_affected(statement text) returns int
language plpgsql as $$
declare
  affected int;
begin
  execute statement;
  get diagnostics affected = row_count;
  return affected;
end;
$$;
grant execute on function public.test_affected(text) to authenticated;

-- Owner creates a tournament, a player, a participant and a match
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000a"}', true);
set local role authenticated;

insert into public.tournaments (id, owner_id, name, format)
values ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'Friday', 'americano');

select is(
  (select role from public.tournament_members where tournament_id = '10000000-0000-0000-0000-000000000001'),
  'owner',
  'creating a tournament makes the creator its owner member'
);

insert into public.players (id, owner_id, name)
values ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'Andi');

select lives_ok(
  $$insert into public.tournament_participants (tournament_id, player_id)
    values ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001')$$,
  'owner adds own player as participant'
);

select lives_ok(
  $$insert into public.matches (id, tournament_id, round, team1, team2)
    values ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 1,
            array['20000000-0000-0000-0000-000000000001']::uuid[], array[gen_random_uuid()])$$,
  'owner creates a match'
);

select is(length(public.create_invite('10000000-0000-0000-0000-000000000001')), 8, 'create_invite returns an 8 character code');

-- Keep the code for later steps (postgres reads it back)
reset role;
create temp table invite_code as
  select code from public.tournament_invites where tournament_id = '10000000-0000-0000-0000-000000000001';
grant select on invite_code to authenticated;

-- Outsider: sees nothing, cannot write
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000c"}', true);
set local role authenticated;

select is((select count(*)::int from public.tournaments), 0, 'outsider cannot see the tournament');
select is((select count(*)::int from public.matches), 0, 'outsider cannot see matches');
select is((select count(*)::int from public.players), 0, 'outsider cannot see the owner players');
select is(
  (select count(*)::int from public.profiles where id = '00000000-0000-0000-0000-00000000000a'),
  0,
  'outsider cannot see the owner profile'
);
select throws_ok(
  $$insert into public.tournaments (owner_id, name, format)
    values ('00000000-0000-0000-0000-00000000000a', 'Stolen', 'americano')$$,
  '42501',
  'new row violates row-level security policy for table "tournaments"',
  'outsider cannot create a tournament owned by someone else'
);
select is(
  public.test_affected($$update public.matches set score1 = 99$$),
  0,
  'outsider cannot update matches'
);
select throws_ok(
  $$select public.join_tournament('NOPE0000')$$,
  'P0001',
  'invite_not_found',
  'unknown code is rejected'
);
select throws_ok(
  $$select public.create_invite('10000000-0000-0000-0000-000000000001')$$,
  '42501',
  'not_owner',
  'outsider cannot create an invite'
);

-- Scorer joins with the code (lowercase and padded, to prove it is normalised)
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000b"}', true);

select is(
  public.join_tournament(' ' || lower((select code from invite_code)) || ' '),
  '10000000-0000-0000-0000-000000000001'::uuid,
  'scorer joins with a valid code'
);
select is(
  (select role from public.tournament_members where user_id = '00000000-0000-0000-0000-00000000000b'),
  'scorer',
  'joined user is a scorer'
);
select is((select count(*)::int from public.tournaments), 1, 'scorer sees the tournament');
select is((select count(*)::int from public.players), 1, 'scorer sees players used in the tournament');
select is(
  (select count(*)::int from public.profiles where id = '00000000-0000-0000-0000-00000000000a'),
  1,
  'scorer sees the owner profile'
);
select is(
  public.test_affected($$update public.matches set score1 = 21, score2 = 10, status = 'completed'$$),
  1,
  'scorer can update a match'
);
select is(
  public.test_affected($$update public.tournaments set name = 'Hacked'$$),
  0,
  'scorer cannot update the tournament'
);
select throws_ok(
  $$insert into public.matches (tournament_id, round, team1, team2)
    values ('10000000-0000-0000-0000-000000000001', 2, array[gen_random_uuid()], array[gen_random_uuid()])$$,
  '42501',
  'new row violates row-level security policy for table "matches"',
  'scorer cannot create matches'
);
select is(
  public.test_affected($$delete from public.matches$$),
  0,
  'scorer cannot delete matches'
);
select throws_ok(
  $$select public.create_invite('10000000-0000-0000-0000-000000000001')$$,
  '42501',
  'not_owner',
  'scorer cannot create an invite'
);

-- Owner joining their own tournament keeps the owner role; invites can be expired and revoked
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000a"}', true);
select public.join_tournament((select code from invite_code));
select is(
  (select role from public.tournament_members where user_id = '00000000-0000-0000-0000-00000000000a'),
  'owner',
  'joining again never downgrades the owner'
);

reset role;
insert into public.tournament_invites (code, tournament_id, created_by, expires_at, revoked) values
  ('EXPIRED1', '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', now() - interval '1 minute', false),
  ('REVOKED1', '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', now() + interval '1 day', true);

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000c"}', true);
set local role authenticated;
select throws_ok($$select public.join_tournament('EXPIRED1')$$, 'P0001', 'invite_expired', 'expired code is rejected');
select throws_ok($$select public.join_tournament('REVOKED1')$$, 'P0001', 'invite_revoked', 'revoked code is rejected');

-- Leaving: a scorer can leave, the owner row cannot be deleted
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000a"}', true);
select is(
  public.test_affected($$delete from public.tournament_members where role = 'owner'$$),
  0,
  'the owner member row cannot be deleted'
);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000b"}', true);
select is(
  public.test_affected($$delete from public.tournament_members where user_id = '00000000-0000-0000-0000-00000000000b'$$),
  1,
  'a scorer can leave the tournament'
);

-- Deleting the owner account removes their tournaments
reset role;
delete from auth.users where id = '00000000-0000-0000-0000-00000000000a';
select is((select count(*)::int from public.tournaments), 0, 'deleting the owner account deletes their tournaments');

select * from finish();
rollback;
