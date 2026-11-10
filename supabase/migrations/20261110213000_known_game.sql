-- Une seule liste des jeux du salon arcade.
-- À coller tel quel dans l'éditeur SQL.

create or replace function arcade.known_game(p_game text)
returns boolean
language sql
immutable
as $$
  select lower(coalesce(p_game, '')) in ('morpion', 'mastermind', 'mines');
$$;

revoke all on function arcade.known_game(text) from public, anon, authenticated;

create or replace function arcade.reset_room(p_code text)
returns void
language plpgsql
security definer
set search_path = arcade, public
as $$
#variable_conflict use_column
declare
  v_room arcade.rooms%rowtype;
  v_humans integer;
  v_seated integer;
  v_bot boolean;
  v_board jsonb;
  v_secret jsonb := '{}'::jsonb;
begin
  select rooms.* into v_room from arcade.rooms as rooms where rooms.code = p_code;
  v_bot := coalesce((v_room.config->>'bot')::boolean, false);
  v_humans := coalesce((v_room.config->>'humans')::integer, case when v_bot then 1 else 2 end);
  select count(*) into v_seated from arcade.players as players where players.room_code = p_code and players.bot = false;
  v_board := arcade.fresh_board(v_room.game, v_bot);
  if v_room.game = 'mastermind' and v_bot then
    v_secret := jsonb_build_object('code', v_board->'secret');
    v_board := '{"guesses":[]}'::jsonb;
  elsif v_room.game = 'mines' then
    v_secret := '{"mines":[]}'::jsonb;
  end if;
  update arcade.rooms as rooms
  set board = v_board,
      secret = v_secret,
      winner = null,
      turn_seat = 0,
      phase = case
        when v_seated < v_humans then 'lobby'
        when arcade.known_game(rooms.game) and not v_bot then 'lobby'
        else 'play'
      end
  where rooms.code = p_code;
end;
$$;

create or replace function arcade.apply_action(p_code text, p_seat integer, p_action text, p_payload jsonb)
returns text
language plpgsql
security definer
set search_path = arcade, public
as $$
#variable_conflict use_column
declare
  v_room arcade.rooms%rowtype;
  v_index integer;
  v_mark text;
  v_found text;
  v_guess jsonb;
  v_score jsonb;
  v_opened jsonb;
  v_size integer;
  v_ships jsonb;
  v_shots jsonb;
  v_hit boolean;
  v_alive integer;
  v_flags jsonb;
begin
  select rooms.* into v_room from arcade.rooms as rooms where rooms.code = p_code for update;
  if p_action = 'again' then
    if p_seat <> 0 then
      return 'Seul le créateur relance la partie.';
    end if;
    perform arcade.reset_room(p_code);
    return null;
  end if;
  if p_action = 'start' then
    if p_seat <> 0 then
      return 'Seul le créateur lance la partie.';
    end if;
    if v_room.phase <> 'lobby' then
      return 'La partie est déjà lancée.';
    end if;
    if not arcade.known_game(v_room.game) then
      return 'Coup inconnu.';
    end if;
    select count(*) into v_alive
    from arcade.players as players
    where players.room_code = p_code and players.bot = false;
    if v_alive < coalesce((v_room.config->>'humans')::integer, 2) then
      return 'En attente des autres joueurs.';
    end if;
    if v_room.game = 'morpion' then
      v_room.phase := 'play';
      v_room.turn_seat := case when coalesce(v_room.config->>'mark', 'X') = 'O' then 1 else 0 end;
    elsif v_room.game = 'mastermind' then
      v_room.phase := 'code';
      v_room.turn_seat := coalesce((v_room.config->>'maker')::integer, 0);
    else
      v_room.phase := 'play';
      v_room.turn_seat := 0;
    end if;
  elsif v_room.phase in ('lobby', 'done') then
    return 'La partie n''attend pas de coup.';
  elsif v_room.game = 'morpion' and p_action = 'play' then
    if v_room.phase <> 'play' or v_room.turn_seat <> p_seat then
      return 'Ce n''est pas ton tour.';
    end if;
    v_index := (p_payload->>'i')::integer;
    if v_index is null or v_index < 0 or v_index > 8 then
      return 'Case invalide.';
    end if;
    if coalesce(v_room.board->'cells'->>v_index, '') <> '' then
      return 'Case déjà prise.';
    end if;
    v_mark := case
      when coalesce(v_room.config->>'mark', 'X') = 'O' then case when p_seat = 0 then 'O' else 'X' end
      else case when p_seat = 0 then 'X' else 'O' end
    end;
    v_room.board := jsonb_set(v_room.board, array['cells', v_index::text], to_jsonb(v_mark));
    v_found := arcade.morpion_winner(v_room.board->'cells');
    if v_found = 'X' then
      v_room.phase := 'done';
      v_room.winner := case when coalesce(v_room.config->>'mark', 'X') = 'O' then 1 else 0 end;
    elsif v_found = 'O' then
      v_room.phase := 'done';
      v_room.winner := case when coalesce(v_room.config->>'mark', 'X') = 'O' then 0 else 1 end;
    elsif v_found = 'draw' then
      v_room.phase := 'done';
      v_room.winner := -1;
    else
      v_room.turn_seat := 1 - p_seat;
    end if;
  elsif v_room.game = 'mastermind' and p_action = 'secret' then
    if v_room.phase <> 'code' or p_seat <> coalesce((v_room.config->>'maker')::integer, 0) then
      return 'Ce n''est pas le moment de poser le code.';
    end if;
    v_guess := p_payload->'code';
    if jsonb_typeof(v_guess) <> 'array' or jsonb_array_length(v_guess) <> 4 then
      return 'Le code doit avoir quatre couleurs.';
    end if;
    if exists (
      select 1 from jsonb_array_elements(v_guess) as peg(value)
      where (peg.value #>> '{}') !~ '^[0-5]$'
    ) then
      return 'Couleur inconnue.';
    end if;
    v_room.secret := jsonb_build_object('code', v_guess);
    v_room.phase := 'play';
    v_room.turn_seat := 1 - coalesce((v_room.config->>'maker')::integer, 0);
  elsif v_room.game = 'mastermind' and p_action = 'guess' then
    if v_room.phase <> 'play' or v_room.turn_seat <> p_seat then
      return 'Ce n''est pas ton tour.';
    end if;
    v_guess := p_payload->'code';
    if jsonb_typeof(v_guess) <> 'array' or jsonb_array_length(v_guess) <> 4 then
      return 'Choisis quatre couleurs.';
    end if;
    v_score := arcade.mm_score(v_room.secret->'code', v_guess);
    v_room.board := jsonb_set(
      v_room.board,
      '{guesses}',
      coalesce(v_room.board->'guesses', '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
        'code', v_guess,
        'black', v_score->'black',
        'white', v_score->'white'
      ))
    );
    if (v_score->>'black')::integer = 4 then
      v_room.phase := 'done';
      v_room.winner := p_seat;
      v_room.board := jsonb_set(v_room.board, '{solved}', 'true'::jsonb);
    elsif jsonb_array_length(v_room.board->'guesses') >= greatest(4, least(12, coalesce((v_room.config->>'tries')::integer, 8))) then
      v_room.phase := 'done';
      v_room.winner := case when coalesce((v_room.config->>'bot')::boolean, false) then null else coalesce((v_room.config->>'maker')::integer, 0) end;
    end if;
  elsif v_room.game = 'mines' and p_action = 'flag' then
    if v_room.phase <> 'play' or v_room.turn_seat <> p_seat then
      return 'Ce n''est pas ton tour.';
    end if;
    v_index := (p_payload->>'i')::integer;
    v_size := coalesce((v_room.config->>'size')::integer, 9);
    if v_index is null or v_index < 0 or v_index >= v_size * v_size then
      return 'Case invalide.';
    end if;
    if coalesce(v_room.board->'revealed', '{}'::jsonb) ? v_index::text then
      return 'Case déjà ouverte.';
    end if;
    v_flags := coalesce(v_room.board->'flags', '[]'::jsonb);
    if v_flags @> to_jsonb(v_index) then
      select coalesce(jsonb_agg(item.value), '[]'::jsonb) into v_flags
      from jsonb_array_elements(v_flags) as item(value)
      where item.value <> to_jsonb(v_index);
    else
      v_flags := v_flags || jsonb_build_array(v_index);
    end if;
    v_room.board := jsonb_set(v_room.board, '{flags}', v_flags);
  elsif v_room.game = 'mines' and p_action = 'open' then
    if v_room.phase <> 'play' or v_room.turn_seat <> p_seat then
      return 'Ce n''est pas ton tour.';
    end if;
    if coalesce(v_room.board->'eliminated', '[]'::jsonb) @> to_jsonb(p_seat) then
      return 'Tu es éliminé.';
    end if;
    v_index := (p_payload->>'i')::integer;
    v_size := coalesce((v_room.config->>'size')::integer, 9);
    if v_index is null or v_index < 0 or v_index >= v_size * v_size then
      return 'Case invalide.';
    end if;
    if coalesce(v_room.board->'flags', '[]'::jsonb) @> to_jsonb(v_index) then
      return 'Enlève la croix avant d''ouvrir.';
    end if;
    v_opened := arcade.mines_open(v_room.board, v_room.secret, v_size, v_index);
    if coalesce((v_opened->>'ignored')::boolean, false) then
      return null;
    end if;
    v_room.board := v_opened->'board';
    v_room.secret := v_opened->'secret';
    update arcade.rooms as rooms
    set board = v_room.board, secret = v_room.secret
    where rooms.code = p_code;
    if coalesce((v_opened->>'hit')::boolean, false) then
      v_room.board := jsonb_set(
        v_room.board,
        '{eliminated}',
        coalesce(v_room.board->'eliminated', '[]'::jsonb) || jsonb_build_array(p_seat)
      );
      update arcade.rooms as rooms set board = v_room.board where rooms.code = p_code;
      select count(*) into v_alive from unnest(arcade.alive_seats(p_code)) as seat(idx);
      if v_alive <= 1 then
        v_room.phase := 'done';
        v_room.winner := null;
        if v_alive = 1 then
          select seat.idx into v_room.winner from unnest(arcade.alive_seats(p_code)) as seat(idx) limit 1;
        else
          v_room.winner := -2;
        end if;
      else
        v_room.turn_seat := arcade.next_alive(p_code, p_seat);
      end if;
    elsif arcade.mines_clear(v_room.board, v_room.secret, v_size) then
      v_room.phase := 'done';
      v_room.winner := null;
    else
      v_room.turn_seat := arcade.next_alive(p_code, p_seat);
    end if;
  else
    return 'Coup inconnu.';
  end if;

  update arcade.rooms as rooms
  set board = v_room.board,
      secret = v_room.secret,
      phase = v_room.phase,
      turn_seat = v_room.turn_seat,
      winner = v_room.winner
  where rooms.code = p_code;
  return null;
end;
$$;

create or replace function public.arcade_join(p_code text, p_name text, p_token text)
returns jsonb
language plpgsql
security definer
set search_path = arcade, public
as $$
#variable_conflict use_column
declare
  v_code text := upper(coalesce(p_code, ''));
  v_name text := left(coalesce(nullif(trim(p_name), ''), 'Joueur'), 24);
  v_room arcade.rooms%rowtype;
  v_seat integer;
  v_token text;
  v_humans integer;
  v_seated integer;
begin
  select rooms.* into v_room from arcade.rooms as rooms where rooms.code = v_code;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Table introuvable.');
  end if;
  if coalesce(p_token, '') <> '' then
    select players.seat, players.token into v_seat, v_token
    from arcade.players as players
    where players.room_code = v_code and players.token = p_token and players.bot = false;
    if v_token is not null then
      return arcade.public_state(v_code, v_token);
    end if;
  end if;
  select players.seat, players.token into v_seat, v_token
  from arcade.players as players
  where players.room_code = v_code and players.bot = false and lower(players.name) = lower(v_name)
  order by players.seat
  limit 1;
  if v_token is not null then
    return arcade.public_state(v_code, v_token);
  end if;
  if v_room.phase <> 'lobby' then
    return jsonb_build_object('ok', false, 'error', 'La partie a déjà commencé.');
  end if;
  v_humans := coalesce((v_room.config->>'humans')::integer, 2);
  select count(*) into v_seated from arcade.players as players where players.room_code = v_code and players.bot = false;
  if v_seated >= v_humans then
    return jsonb_build_object('ok', false, 'error', 'La table est complète.');
  end if;
  v_seat := v_seated;
  v_token := md5(random()::text || clock_timestamp()::text);
  insert into arcade.players as players (room_code, seat, name, token, bot)
  values (v_code, v_seat, v_name, v_token, false);
  if v_seated + 1 >= v_humans then
    update arcade.rooms as rooms
    set phase = case
          when arcade.known_game(rooms.game) then 'lobby'
          else 'play'
        end,
        turn_seat = 0,
        seen = now(),
        revision = rooms.revision + 1
    where rooms.code = v_code;
  else
    perform arcade.touch(v_code);
  end if;
  return arcade.public_state(v_code, v_token);
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
  elsif arcade.known_game(v_game) then
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
  if not arcade.known_game(v_game) then
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
