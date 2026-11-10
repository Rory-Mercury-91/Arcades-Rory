-- Accès aux tables, départ en fin de partie, nettoyage.
-- À coller tel quel dans l'éditeur SQL. Mangathèque n'est pas modifié.
-- Le mot de passe n'est pas choisi dans l'application.

create or replace function yams.purge_old()
returns void
language sql
security definer
set search_path = yams, public
as $$
  delete from yams.rooms
  where seen < now() - interval '12 hours'
     or (phase = 'done' and seen < now() - interval '30 minutes');
$$;

create or replace function arcade.purge_old()
returns void
language sql
security definer
set search_path = arcade, public
as $$
  delete from arcade.rooms as rooms
  where rooms.seen < now() - interval '12 hours'
     or (rooms.phase = 'done' and rooms.seen < now() - interval '30 minutes');
$$;

create table if not exists yams.keeper (
  id integer primary key default 1 check (id = 1),
  secret_hash text not null
);

alter table yams.keeper enable row level security;
revoke all on table yams.keeper from public, anon, authenticated;

create or replace function yams.keeper_ok(p_secret text)
returns boolean
language plpgsql
security definer
set search_path = yams, public, extensions
as $$
declare
  stored text;
begin
  if coalesce(btrim(p_secret), '') = '' then
    return false;
  end if;
  select secret_hash into stored from yams.keeper where id = 1;
  if stored is null then
    raise exception 'L''accès n''est pas encore en place.';
  end if;
  return encode(extensions.digest(convert_to(p_secret, 'UTF8'), 'sha256'), 'hex') = stored;
end;
$$;

create or replace function public.tables_admin_status()
returns jsonb
language plpgsql
security definer
set search_path = yams, public
as $$
begin
  return jsonb_build_object(
    'ok', true,
    'ready', exists (select 1 from yams.keeper where id = 1)
  );
end;
$$;

create or replace function public.tables_admin_setup(p_secret text)
returns jsonb
language plpgsql
security definer
set search_path = yams, public
as $$
begin
  return jsonb_build_object('ok', false, 'error', 'L''accès se règle dans le fichier .env du projet.');
end;
$$;

create or replace function public.tables_admin_list(p_secret text)
returns jsonb
language plpgsql
security definer
set search_path = yams, arcade, public
as $$
declare
  tables jsonb;
begin
  if not yams.keeper_ok(p_secret) then
    return jsonb_build_object('ok', false, 'error', 'Mot de passe refusé.');
  end if;
  perform yams.purge_old();
  perform arcade.purge_old();
  select coalesce(jsonb_agg(item.row order by item.seen desc), '[]'::jsonb)
    into tables
  from (
    select rooms.seen,
      jsonb_build_object(
        'game', 'yams',
        'code', rooms.code,
        'phase', rooms.phase,
        'finished', rooms.phase = 'done',
        'seen', rooms.seen,
        'players', coalesce((
          select jsonb_agg(players.name order by players.seat)
          from yams.players as players
          where players.room_code = rooms.code
        ), '[]'::jsonb)
      ) as row
    from yams.rooms as rooms
    union all
    select rooms.seen,
      jsonb_build_object(
        'game', rooms.game,
        'code', rooms.code,
        'phase', rooms.phase,
        'finished', rooms.phase = 'done',
        'seen', rooms.seen,
        'players', coalesce((
          select jsonb_agg(players.name order by players.seat)
          from arcade.players as players
          where players.room_code = rooms.code and players.bot = false
        ), '[]'::jsonb)
      ) as row
    from arcade.rooms as rooms
    where rooms.game <> 'naval'
  ) as item;
  return jsonb_build_object('ok', true, 'tables', tables);
exception when others then
  return jsonb_build_object('ok', false, 'error', sqlerrm);
end;
$$;

create or replace function public.tables_admin_drop(p_secret text, p_game text, p_code text)
returns jsonb
language plpgsql
security definer
set search_path = yams, arcade, public
as $$
declare
  v_code text := upper(coalesce(p_code, ''));
  v_game text := lower(coalesce(p_game, ''));
  removed integer := 0;
begin
  if not yams.keeper_ok(p_secret) then
    return jsonb_build_object('ok', false, 'error', 'Mot de passe refusé.');
  end if;
  if v_game = 'yams' then
    delete from yams.rooms as rooms where rooms.code = v_code;
    get diagnostics removed = row_count;
  elsif v_game in ('morpion', 'mastermind', 'mines') then
    delete from arcade.rooms as rooms where rooms.code = v_code and rooms.game = v_game;
    get diagnostics removed = row_count;
  else
    return jsonb_build_object('ok', false, 'error', 'Jeu inconnu.');
  end if;
  return jsonb_build_object('ok', true, 'removed', removed);
exception when others then
  return jsonb_build_object('ok', false, 'error', sqlerrm);
end;
$$;

create or replace function public.tables_admin_sweep(p_secret text)
returns jsonb
language plpgsql
security definer
set search_path = yams, arcade, public
as $$
declare
  removed integer := 0;
  batch integer := 0;
begin
  if not yams.keeper_ok(p_secret) then
    return jsonb_build_object('ok', false, 'error', 'Mot de passe refusé.');
  end if;
  delete from yams.rooms as rooms where rooms.phase = 'done';
  get diagnostics batch = row_count;
  removed := removed + batch;
  delete from arcade.rooms as rooms where rooms.phase = 'done';
  get diagnostics batch = row_count;
  removed := removed + batch;
  delete from arcade.rooms as rooms where rooms.game = 'naval';
  get diagnostics batch = row_count;
  removed := removed + batch;
  return jsonb_build_object('ok', true, 'removed', removed);
exception when others then
  return jsonb_build_object('ok', false, 'error', sqlerrm);
end;
$$;

create or replace function public.yams_leave(p_code text, p_token text)
returns jsonb
language plpgsql
security definer
set search_path = yams, public
as $$
#variable_conflict use_column
declare
  v_code text := upper(coalesce(p_code, ''));
  room yams.rooms%rowtype;
begin
  select rooms.* into room from yams.rooms as rooms where rooms.code = v_code;
  if not found then
    return jsonb_build_object('ok', true);
  end if;
  if room.phase <> 'done' then
    return jsonb_build_object('ok', false, 'error', 'La partie est encore en cours.');
  end if;
  delete from yams.players as players
  where players.room_code = v_code and players.token = coalesce(p_token, '');
  if not exists (select 1 from yams.players as players where players.room_code = v_code) then
    delete from yams.rooms as rooms where rooms.code = v_code;
  end if;
  return jsonb_build_object('ok', true);
exception when others then
  return jsonb_build_object('ok', false, 'error', sqlerrm);
end;
$$;

create or replace function public.arcade_leave(p_code text, p_token text)
returns jsonb
language plpgsql
security definer
set search_path = arcade, public
as $$
#variable_conflict use_column
declare
  v_code text := upper(coalesce(p_code, ''));
  v_phase text;
begin
  select rooms.phase into v_phase from arcade.rooms as rooms where rooms.code = v_code;
  if v_phase is null then
    return jsonb_build_object('ok', true);
  end if;
  if v_phase <> 'done' then
    return jsonb_build_object('ok', false, 'error', 'La partie est encore en cours.');
  end if;
  delete from arcade.players as players
  where players.room_code = v_code and players.token = coalesce(p_token, '') and players.bot = false;
  if not exists (
    select 1 from arcade.players as players
    where players.room_code = v_code and players.bot = false
  ) then
    delete from arcade.rooms as rooms where rooms.code = v_code;
  end if;
  return jsonb_build_object('ok', true);
exception when others then
  return jsonb_build_object('ok', false, 'error', sqlerrm);
end;
$$;

create or replace function public.arcade_state(p_code text, p_token text)
returns jsonb
language plpgsql
security definer
set search_path = arcade, public
as $$
#variable_conflict use_column
declare
  v_code text := upper(coalesce(p_code, ''));
begin
  perform arcade.purge_old();
  update arcade.rooms as rooms set seen = now() where rooms.code = v_code;
  return arcade.public_state(v_code, p_token);
exception when others then
  return jsonb_build_object('ok', false, 'error', sqlerrm);
end;
$$;

create or replace function public.arcade_create(p_game text, p_name text, p_config jsonb)
returns jsonb
language plpgsql
security definer
set search_path = arcade, public
as $$
#variable_conflict use_column
declare
  v_game text := lower(coalesce(p_game, ''));
  v_name text := left(coalesce(nullif(trim(p_name), ''), 'Joueur'), 24);
  v_config jsonb := coalesce(p_config, '{}'::jsonb);
  v_bot boolean := coalesce((v_config->>'bot')::boolean, false);
  v_humans integer;
  v_size integer := 9;
  v_code text := '';
  v_token text := md5(random()::text || clock_timestamp()::text);
  v_board jsonb;
  v_secret jsonb := '{}'::jsonb;
  v_phase text;
  v_alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_try integer;
  v_step integer;
  v_mark text;
  v_maker integer;
  v_tries integer;
begin
  if v_game not in ('morpion', 'mastermind', 'mines') then
    return jsonb_build_object('ok', false, 'error', 'Jeu inconnu.');
  end if;
  if v_game = 'mines' then
    v_size := coalesce((v_config->>'size')::integer, 9);
    if v_size not in (8, 9, 12, 16) then
      v_size := 9;
    end if;
    v_humans := case when v_bot then 1 else greatest(2, least(4, coalesce((v_config->>'humans')::integer, 2))) end;
  else
    v_humans := case when v_bot then 1 else 2 end;
  end if;
  v_mark := case when upper(coalesce(v_config->>'mark', 'X')) = 'O' then 'O' else 'X' end;
  v_maker := case when lower(coalesce(v_config->>'role', 'maker')) = 'breaker' then 1 else 0 end;
  v_tries := coalesce((v_config->>'tries')::integer, 8);
  if v_tries < 4 then v_tries := 4; end if;
  if v_tries > 12 then v_tries := 12; end if;
  v_config := jsonb_build_object('bot', v_bot, 'humans', v_humans, 'size', v_size, 'mark', v_mark, 'maker', v_maker, 'tries', v_tries);
  perform arcade.purge_old();
  for v_try in 1..20 loop
    v_code := '';
    for v_step in 1..4 loop
      v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::integer, 1);
    end loop;
    exit when not exists (select 1 from arcade.rooms as rooms where rooms.code = v_code);
  end loop;
  v_board := arcade.fresh_board(v_game, v_bot);
  if v_game = 'mastermind' and v_bot then
    v_secret := jsonb_build_object('code', v_board->'secret');
    v_board := '{"guesses":[]}'::jsonb;
    v_phase := 'play';
  elsif v_game = 'mines' then
    v_secret := '{"mines":[]}'::jsonb;
    v_phase := case when v_humans = 1 then 'play' else 'lobby' end;
  elsif v_game = 'mastermind' then
    v_phase := 'lobby';
  else
    v_phase := case when v_bot then 'play' else 'lobby' end;
  end if;
  insert into arcade.rooms as rooms (code, game, phase, config, board, secret)
  values (v_code, v_game, v_phase, v_config, v_board, v_secret);
  insert into arcade.players as players (room_code, seat, name, token, bot)
  values (v_code, 0, v_name, v_token, false);
  if v_bot then
    insert into arcade.players as players (room_code, seat, name, token, bot)
    values (v_code, 1, 'Ordi', md5(random()::text || clock_timestamp()::text), true);
  end if;
  return arcade.public_state(v_code, v_token);
exception when others then
  return jsonb_build_object('ok', false, 'error', sqlerrm);
end;
$$;

delete from arcade.rooms as rooms where rooms.game = 'naval';

drop function if exists arcade.bot_shot(jsonb, jsonb, text);
drop function if exists arcade.naval_sunk(jsonb, jsonb);
drop function if exists arcade.naval_fleet();
drop function if exists arcade.naval_valid(jsonb);

revoke all on function yams.keeper_ok(text) from public, anon, authenticated;
revoke all on function public.tables_admin_status() from public;
revoke all on function public.tables_admin_setup(text) from public;
revoke all on function public.tables_admin_list(text) from public;
revoke all on function public.tables_admin_drop(text, text, text) from public;
revoke all on function public.tables_admin_sweep(text) from public;
revoke all on function public.yams_leave(text, text) from public;
revoke all on function public.arcade_leave(text, text) from public;
revoke all on function public.arcade_state(text, text) from public;
revoke all on function public.arcade_create(text, text, jsonb) from public;

grant execute on function public.tables_admin_status() to anon, authenticated;
grant execute on function public.tables_admin_list(text) to anon, authenticated;
grant execute on function public.tables_admin_drop(text, text, text) to anon, authenticated;
grant execute on function public.tables_admin_sweep(text) to anon, authenticated;
grant execute on function public.yams_leave(text, text) to anon, authenticated;
grant execute on function public.arcade_leave(text, text) to anon, authenticated;
grant execute on function public.arcade_state(text, text) to anon, authenticated;
grant execute on function public.arcade_create(text, text, jsonb) to anon, authenticated;
