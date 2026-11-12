-- Sudoku et Chat Doku : grilles solo, une table à un joueur, génération côté client.
-- À coller tel quel dans l'éditeur SQL, après 20261112140000_bac.sql.

create or replace function arcade.doku_kind(p_game text)
returns text
language sql
immutable
as $$
  select case lower(coalesce(p_game, ''))
    when 'sudoku' then 'sudoku'
    when 'chatdoku' then 'chatdoku'
    else null
  end;
$$;

create or replace function arcade.doku_ints(p_arr jsonb, p_len integer, p_min integer, p_max integer)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_row jsonb := '[]'::jsonb;
  v_i integer;
  v_n integer;
begin
  if p_len <= 0 or jsonb_typeof(coalesce(p_arr, '[]'::jsonb)) <> 'array' then
    return null;
  end if;
  if jsonb_array_length(p_arr) <> p_len then
    return null;
  end if;
  for v_i in 0..p_len - 1 loop
    begin
      v_n := (p_arr->>v_i)::integer;
    exception when others then
      return null;
    end;
    if v_n is null or v_n < p_min or v_n > p_max then
      return null;
    end if;
    v_row := v_row || to_jsonb(v_n);
  end loop;
  return v_row;
end;
$$;

create or replace function arcade.doku_solved(p_kind text, p_size integer, p_values jsonb, p_colors jsonb)
returns boolean
language plpgsql
immutable
as $$
declare
  v_len integer := p_size * p_size;
  v_i integer;
  v_j integer;
  v_n integer;
  v_row integer;
  v_col integer;
  v_bw integer;
  v_bh integer;
  v_seen integer[];
  v_cats integer := 0;
  v_a integer;
  v_b integer;
  v_ar integer;
  v_ac integer;
  v_br integer;
  v_bc integer;
begin
  if p_size is null or p_size < 4 or jsonb_typeof(coalesce(p_values, '[]'::jsonb)) <> 'array' then
    return false;
  end if;
  if jsonb_array_length(p_values) <> v_len then
    return false;
  end if;
  if p_kind = 'sudoku' then
    v_bw := case p_size when 9 then 3 when 6 then 3 else 2 end;
    v_bh := case p_size when 9 then 3 when 6 then 2 else 2 end;
    for v_row in 0..p_size - 1 loop
      v_seen := array_fill(0, array[p_size]);
      for v_col in 0..p_size - 1 loop
        v_n := coalesce((p_values->>(v_row * p_size + v_col))::integer, 0);
        if v_n < 1 or v_n > p_size or v_seen[v_n] = 1 then
          return false;
        end if;
        v_seen[v_n] := 1;
      end loop;
    end loop;
    for v_col in 0..p_size - 1 loop
      v_seen := array_fill(0, array[p_size]);
      for v_row in 0..p_size - 1 loop
        v_n := coalesce((p_values->>(v_row * p_size + v_col))::integer, 0);
        if v_n < 1 or v_n > p_size or v_seen[v_n] = 1 then
          return false;
        end if;
        v_seen[v_n] := 1;
      end loop;
    end loop;
    for v_row in 0..(p_size / v_bh) - 1 loop
      for v_col in 0..(p_size / v_bw) - 1 loop
        v_seen := array_fill(0, array[p_size]);
        for v_i in 0..v_bh - 1 loop
          for v_j in 0..v_bw - 1 loop
            v_n := coalesce((p_values->>(((v_row * v_bh + v_i) * p_size) + v_col * v_bw + v_j))::integer, 0);
            if v_n < 1 or v_n > p_size or v_seen[v_n] = 1 then
              return false;
            end if;
            v_seen[v_n] := 1;
          end loop;
        end loop;
      end loop;
    end loop;
    return true;
  end if;
  if p_kind <> 'chatdoku' or jsonb_typeof(coalesce(p_colors, '[]'::jsonb)) <> 'array' then
    return false;
  end if;
  if jsonb_array_length(p_colors) <> v_len then
    return false;
  end if;
  v_seen := array_fill(0, array[p_size * 3]);
  for v_i in 0..v_len - 1 loop
    if coalesce((p_values->>v_i)::integer, 0) = 0 then
      continue;
    end if;
    v_cats := v_cats + 1;
    v_row := v_i / p_size;
    v_col := v_i % p_size;
    v_n := coalesce((p_colors->>v_i)::integer, -1);
    if v_n < 0 or v_n >= p_size then
      return false;
    end if;
    if v_seen[v_row + 1] = 1 or v_seen[p_size + v_col + 1] = 1 or v_seen[p_size * 2 + v_n + 1] = 1 then
      return false;
    end if;
    v_seen[v_row + 1] := 1;
    v_seen[p_size + v_col + 1] := 1;
    v_seen[p_size * 2 + v_n + 1] := 1;
    for v_j in v_i + 1..v_len - 1 loop
      if coalesce((p_values->>v_j)::integer, 0) = 0 then
        continue;
      end if;
      v_ar := v_i / p_size;
      v_ac := v_i % p_size;
      v_br := v_j / p_size;
      v_bc := v_j % p_size;
      if abs(v_ar - v_br) <= 1 and abs(v_ac - v_bc) <= 1 then
        return false;
      end if;
    end loop;
  end loop;
  return v_cats = p_size;
end;
$$;

create or replace function arcade.doku_load(p_game text, p_payload jsonb)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_kind text := arcade.doku_kind(p_game);
  v_size integer := coalesce((p_payload->>'size')::integer, 0);
  v_len integer;
  v_given jsonb;
  v_solution jsonb;
  v_colors jsonb := '[]'::jsonb;
  v_i integer;
begin
  if v_kind is null then
    return jsonb_build_object('error', 'Jeu inconnu.');
  end if;
  if v_kind = 'sudoku' and v_size not in (4, 6, 9) then
    return jsonb_build_object('error', 'Taille inconnue.');
  end if;
  if v_kind = 'chatdoku' and (v_size < 5 or v_size > 9) then
    return jsonb_build_object('error', 'Taille inconnue.');
  end if;
  v_len := v_size * v_size;
  v_given := arcade.doku_ints(p_payload->'given', v_len, 0, case when v_kind = 'chatdoku' then 1 else v_size end);
  v_solution := arcade.doku_ints(p_payload->'solution', v_len, 0, case when v_kind = 'chatdoku' then 1 else v_size end);
  if v_given is null or v_solution is null then
    return jsonb_build_object('error', 'Grille invalide.');
  end if;
  if v_kind = 'chatdoku' then
    v_colors := arcade.doku_ints(p_payload->'colors', v_len, 0, v_size - 1);
    if v_colors is null then
      return jsonb_build_object('error', 'Couleurs invalides.');
    end if;
  end if;
  for v_i in 0..v_len - 1 loop
    if coalesce((v_given->>v_i)::integer, 0) <> 0 and (v_given->>v_i) is distinct from (v_solution->>v_i) then
      return jsonb_build_object('error', 'Les indices ne correspondent pas.');
    end if;
  end loop;
  if not arcade.doku_solved(v_kind, v_size, v_solution, v_colors) then
    return jsonb_build_object('error', 'La solution n''est pas valide.');
  end if;
  return jsonb_build_object(
    'error', '',
    'board', jsonb_build_object(
      'size', v_size,
      'given', v_given,
      'values', v_given,
      'colors', v_colors,
      'stamp', md5(v_given::text || v_solution::text)
    ),
    'secret', jsonb_build_object('solution', v_solution)
  );
end;
$$;

create or replace function arcade.doku_act(
  p_game text,
  p_board jsonb,
  p_secret jsonb,
  p_action text,
  p_payload jsonb
)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_kind text := arcade.doku_kind(p_game);
  v_board jsonb := coalesce(p_board, '{}'::jsonb);
  v_secret jsonb := coalesce(p_secret, '{}'::jsonb);
  v_loaded jsonb;
  v_size integer := coalesce((v_board->>'size')::integer, 0);
  v_index integer;
  v_value integer;
  v_i integer;
  v_len integer;
begin
  if v_kind is null then
    return jsonb_build_object('error', 'Jeu inconnu.');
  end if;
  if p_action in ('deal', 'again') then
    v_loaded := arcade.doku_load(p_game, coalesce(p_payload, '{}'::jsonb));
    if coalesce(v_loaded->>'error', '') <> '' then
      return v_loaded;
    end if;
    return jsonb_build_object(
      'error', '',
      'board', v_loaded->'board',
      'secret', v_loaded->'secret',
      'phase', 'play',
      'winner', null
    );
  end if;
  if v_size <= 0 or coalesce(v_board->'given', '[]'::jsonb) = '[]'::jsonb then
    return jsonb_build_object('error', 'La grille n''est pas prête.');
  end if;
  v_len := v_size * v_size;
  if arcade.doku_solved(v_kind, v_size, v_board->'values', v_board->'colors') then
    return jsonb_build_object('error', '', 'board', v_board, 'secret', v_secret, 'phase', 'done', 'winner', 0);
  end if;
  if p_action = 'place' then
    v_index := (p_payload->>'i')::integer;
    v_value := (p_payload->>'v')::integer;
    if v_index is null or v_index < 0 or v_index >= v_len then
      return jsonb_build_object('error', 'Case invalide.');
    end if;
    if coalesce((v_board->'given'->>v_index)::integer, 0) <> 0 then
      return jsonb_build_object('error', 'Cette case est déjà donnée.');
    end if;
    if v_kind = 'chatdoku' then
      if v_value not in (0, 1) then
        return jsonb_build_object('error', 'Valeur inconnue.');
      end if;
    elsif v_value is null or v_value < 0 or v_value > v_size then
      return jsonb_build_object('error', 'Chiffre inconnu.');
    end if;
    v_board := jsonb_set(v_board, array['values', v_index::text], to_jsonb(v_value));
  elsif p_action = 'hint' then
    for v_i in 0..v_len - 1 loop
      if coalesce((v_board->'values'->>v_i)::integer, 0) is distinct from coalesce((v_secret->'solution'->>v_i)::integer, 0) then
        v_board := jsonb_set(v_board, array['values', v_i::text], to_jsonb(coalesce((v_secret->'solution'->>v_i)::integer, 0)));
        exit;
      end if;
    end loop;
  else
    return jsonb_build_object('error', 'Coup inconnu.');
  end if;
  if arcade.doku_solved(v_kind, v_size, v_board->'values', v_board->'colors') then
    return jsonb_build_object(
      'error', '',
      'board', v_board,
      'secret', v_secret,
      'phase', 'done',
      'winner', 0
    );
  end if;
  return jsonb_build_object(
    'error', '',
    'board', v_board,
    'secret', v_secret,
    'phase', 'play',
    'winner', null
  );
end;
$$;

create or replace function arcade.known_game(p_game text)
returns boolean
language sql
immutable
as $$
  select lower(coalesce(p_game, '')) in ('morpion', 'mastermind', 'mines', 'triomino', 'bac', 'sudoku', 'chatdoku');
$$;

create or replace function arcade.fresh_board(p_game text, p_bot boolean)
returns jsonb
language plpgsql
as $$
declare
  code integer[] := '{}';
  idx integer;
begin
  if p_game = 'morpion' then
    return '{"cells":["","","","","","","","",""]}'::jsonb;
  elsif p_game = 'mastermind' then
    if p_bot then
      for idx in 1..4 loop
        code := code || (floor(random() * 6))::integer;
      end loop;
      return jsonb_build_object('guesses', '[]'::jsonb, 'secret', to_jsonb(code));
    end if;
    return '{"guesses":[]}'::jsonb;
  elsif p_game = 'mines' then
    return '{"revealed":{},"eliminated":[],"flags":[]}'::jsonb;
  elsif p_game = 'triomino' then
    return '{"placed":[],"scores":[],"draws":0}'::jsonb;
  elsif p_game = 'bac' then
    return '{"letter":"","round":0,"rounds":5,"used":[],"scores":[],"submitted":[],"voted":[],"step":"write"}'::jsonb;
  elsif arcade.doku_kind(p_game) is not null then
    return '{"size":0,"given":[],"values":[],"colors":[],"stamp":""}'::jsonb;
  end if;
  return '{}'::jsonb;
end;
$$;

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
        when arcade.doku_kind(rooms.game) is not null then 'play'
        when arcade.known_game(rooms.game) and not v_bot then 'lobby'
        else 'play'
      end
  where rooms.code = p_code;
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
  v_rounds integer := 5;
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
  v_opened jsonb;
begin
  if not arcade.known_game(v_game) then
    return jsonb_build_object('ok', false, 'error', 'Jeu inconnu.');
  end if;
  if v_game = 'triomino' then
    v_bot := false;
    v_humans := greatest(2, least(5, coalesce((v_config->>'humans')::integer, 2)));
  elsif v_game = 'bac' then
    v_bot := false;
    v_humans := greatest(2, least(5, coalesce((v_config->>'humans')::integer, 2)));
    v_rounds := greatest(3, least(8, coalesce((v_config->>'rounds')::integer, 5)));
  elsif arcade.doku_kind(v_game) is not null then
    v_bot := false;
    v_humans := 1;
    v_size := coalesce((v_config->>'size')::integer, case when v_game = 'chatdoku' then 7 else 9 end);
    if v_game = 'sudoku' and v_size not in (4, 6, 9) then
      v_size := 9;
    end if;
    if v_game = 'chatdoku' then
      v_size := greatest(5, least(9, v_size));
    end if;
  elsif v_game = 'mines' then
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
  if v_game = 'triomino' then
    v_config := v_config || jsonb_build_object('aid', case when coalesce(p_config->>'aid', 'guide') = 'free' then 'free' else 'guide' end);
  end if;
  if v_game = 'bac' then
    v_config := v_config || jsonb_build_object('rounds', v_rounds);
  end if;
  if arcade.doku_kind(v_game) is not null then
    v_config := v_config || jsonb_build_object(
      'level', case when coalesce(p_config->>'level', 'easy') in ('medium', 'hard') then p_config->>'level' else 'easy' end
    );
  end if;
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
  elsif arcade.doku_kind(v_game) is not null then
    v_phase := 'play';
    v_secret := '{}'::jsonb;
    if coalesce(p_config->'given', '[]'::jsonb) <> '[]'::jsonb then
      v_opened := arcade.doku_load(v_game, p_config);
      if coalesce(v_opened->>'error', '') = '' then
        v_board := v_opened->'board';
        v_secret := v_opened->'secret';
      end if;
    end if;
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
  v_trio jsonb;
  v_bac jsonb;
  v_doku jsonb;
begin
  select rooms.* into v_room from arcade.rooms as rooms where rooms.code = p_code for update;
  if p_action = 'again' then
    if p_seat <> 0 then
      return 'Seul le créateur relance la partie.';
    end if;
    if arcade.doku_kind(v_room.game) is null then
      perform arcade.reset_room(p_code);
      return null;
    end if;
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
    elsif v_room.game = 'triomino' then
      v_trio := arcade.trio_deal(coalesce((v_room.config->>'humans')::integer, 2));
      v_room.board := v_trio->'board';
      v_room.secret := v_trio->'secret';
      v_room.phase := coalesce(v_trio->>'phase', 'deal');
      v_room.turn_seat := coalesce((v_trio->>'turn')::integer, 0);
      v_room.winner := null;
    elsif v_room.game = 'bac' then
      v_bac := arcade.bac_open(coalesce((v_room.config->>'humans')::integer, 2), coalesce((v_room.config->>'rounds')::integer, 5));
      v_room.board := v_bac->'board';
      v_room.secret := v_bac->'secret';
      v_room.phase := 'play';
      v_room.turn_seat := 0;
      v_room.winner := null;
    elsif arcade.doku_kind(v_room.game) is not null then
      v_room.phase := 'play';
      v_room.turn_seat := 0;
      v_room.winner := null;
    else
      v_room.phase := 'play';
      v_room.turn_seat := 0;
    end if;
  elsif v_room.phase in ('lobby', 'done') and not (arcade.doku_kind(v_room.game) is not null and p_action in ('deal', 'again')) then
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
    if coalesce((v_room.config->>'bot')::boolean, false) then
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
        v_room.winner := null;
      end if;
    else
      v_room.board := jsonb_set(v_room.board, '{pending}', jsonb_build_object('code', v_guess));
      v_room.phase := 'mark';
      v_room.turn_seat := coalesce((v_room.config->>'maker')::integer, 0);
    end if;
  elsif v_room.game = 'mastermind' and p_action = 'mark' then
    if coalesce((v_room.config->>'bot')::boolean, false) then
      return 'Coup inconnu.';
    end if;
    if v_room.phase <> 'mark' or p_seat <> coalesce((v_room.config->>'maker')::integer, 0) then
      return 'Ce n''est pas le moment de placer les indices.';
    end if;
    v_guess := v_room.board->'pending'->'code';
    if v_guess is null or jsonb_typeof(v_guess) <> 'array' then
      return 'Aucune proposition à noter.';
    end if;
    v_score := arcade.mm_score(v_room.secret->'code', v_guess);
    if coalesce((p_payload->>'black')::integer, -1) <> (v_score->>'black')::integer
       or coalesce((p_payload->>'white')::integer, -1) <> (v_score->>'white')::integer then
      return 'Ces indices ne correspondent pas au code.';
    end if;
    v_room.board := jsonb_set(
      v_room.board,
      '{guesses}',
      coalesce(v_room.board->'guesses', '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
        'code', v_guess,
        'black', v_score->'black',
        'white', v_score->'white'
      ))
    );
    v_room.board := v_room.board - 'pending';
    if (v_score->>'black')::integer = 4 then
      v_room.phase := 'done';
      v_room.winner := 1 - coalesce((v_room.config->>'maker')::integer, 0);
      v_room.board := jsonb_set(v_room.board, '{solved}', 'true'::jsonb);
    elsif jsonb_array_length(v_room.board->'guesses') >= greatest(4, least(12, coalesce((v_room.config->>'tries')::integer, 8))) then
      v_room.phase := 'done';
      v_room.winner := coalesce((v_room.config->>'maker')::integer, 0);
    else
      v_room.phase := 'play';
      v_room.turn_seat := 1 - coalesce((v_room.config->>'maker')::integer, 0);
    end if;
  elsif v_room.game = 'triomino' and p_action = 'pick' then
    if v_room.phase <> 'deal' then
      return 'La donne est terminée.';
    end if;
    if v_room.turn_seat <> p_seat then
      return 'Ce n''est pas ton tour.';
    end if;
    v_trio := arcade.trio_pick(v_room.board, v_room.secret, p_seat, coalesce((v_room.config->>'humans')::integer, 2), coalesce(p_payload, '{}'::jsonb));
    if coalesce(v_trio->>'error', '') <> '' then
      return v_trio->>'error';
    end if;
    v_room.board := v_trio->'board';
    v_room.secret := v_trio->'secret';
    v_room.phase := v_trio->>'phase';
    v_room.turn_seat := coalesce((v_trio->>'turn')::integer, v_room.turn_seat);
    v_room.winner := (v_trio->>'winner')::integer;
  elsif v_room.game = 'triomino' and p_action in ('play', 'draw', 'pass') then
    if v_room.phase <> 'play' or v_room.turn_seat <> p_seat then
      return 'Ce n''est pas ton tour.';
    end if;
    v_trio := arcade.trio_act(v_room.board, v_room.secret, p_seat, coalesce((v_room.config->>'humans')::integer, 2), p_action, coalesce(p_payload, '{}'::jsonb), coalesce(v_room.config->>'aid', 'guide') = 'free');
    if coalesce(v_trio->>'error', '') <> '' then
      return v_trio->>'error';
    end if;
    v_room.board := v_trio->'board';
    v_room.secret := v_trio->'secret';
    v_room.phase := v_trio->>'phase';
    v_room.turn_seat := coalesce((v_trio->>'turn')::integer, v_room.turn_seat);
    v_room.winner := (v_trio->>'winner')::integer;
  elsif arcade.doku_kind(v_room.game) is not null and p_action in ('deal', 'place', 'hint', 'again') then
    if v_room.phase not in ('play', 'done') then
      return 'La partie n''attend pas de coup.';
    end if;
    v_doku := arcade.doku_act(v_room.game, v_room.board, v_room.secret, p_action, coalesce(p_payload, '{}'::jsonb));
    if coalesce(v_doku->>'error', '') <> '' then
      return v_doku->>'error';
    end if;
    v_room.board := v_doku->'board';
    v_room.secret := v_doku->'secret';
    v_room.phase := coalesce(v_doku->>'phase', v_room.phase);
    v_room.winner := case when v_doku->'winner' is null then null else (v_doku->>'winner')::integer end;
  elsif v_room.game = 'bac' and p_action in ('draft', 'submit', 'stop', 'vote', 'next', 'tick') then
    if v_room.phase not in ('play', 'vote', 'show') then
      return 'La partie n''attend pas de coup.';
    end if;
    v_bac := arcade.bac_act(
      v_room.board,
      v_room.secret,
      p_seat,
      coalesce((v_room.config->>'humans')::integer, 2),
      coalesce((v_room.config->>'rounds')::integer, 5),
      p_action,
      coalesce(p_payload, '{}'::jsonb)
    );
    if coalesce(v_bac->>'error', '') <> '' then
      return v_bac->>'error';
    end if;
    v_room.board := v_bac->'board';
    v_room.secret := v_bac->'secret';
    v_room.phase := coalesce(v_bac->>'phase', v_room.phase);
    v_room.turn_seat := coalesce((v_bac->>'turn')::integer, v_room.turn_seat);
    v_room.winner := case when v_bac->'winner' is null then null else (v_bac->>'winner')::integer end;
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

create or replace function arcade.public_state(p_code text, p_token text)
returns jsonb
language plpgsql
security definer
set search_path = arcade, public
as $$
#variable_conflict use_column
declare
  v_room arcade.rooms%rowtype;
  v_seat integer := -1;
  v_names jsonb;
  v_view jsonb;
  v_bac jsonb;
begin
  select rooms.* into v_room from arcade.rooms as rooms where rooms.code = upper(coalesce(p_code, ''));
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Table introuvable.');
  end if;
  select players.seat into v_seat
  from arcade.players as players
  where players.room_code = v_room.code and players.token = coalesce(p_token, '');
  if v_seat is null then
    return jsonb_build_object('ok', false, 'error', 'Joueur inconnu sur cette table.');
  end if;
  if v_room.game = 'bac' and v_room.phase = 'play' then
    v_bac := arcade.bac_act(v_room.board, v_room.secret, v_seat, coalesce((v_room.config->>'humans')::integer, 2), coalesce((v_room.config->>'rounds')::integer, 5), 'tick', '{}'::jsonb);
    if coalesce(v_bac->>'error', '') = '' and v_bac->'board' is not null and (v_bac->>'phase' is distinct from v_room.phase or v_bac->'board' <> v_room.board) then
      v_room.board := v_bac->'board';
      v_room.secret := v_bac->'secret';
      v_room.phase := coalesce(v_bac->>'phase', v_room.phase);
      update arcade.rooms as rooms
      set board = v_room.board,
          secret = v_room.secret,
          phase = v_room.phase
      where rooms.code = v_room.code;
    end if;
  end if;
  select coalesce(jsonb_agg(players.name order by players.seat), '[]'::jsonb)
    into v_names
  from arcade.players as players
  where players.room_code = v_room.code;
  if v_room.game = 'morpion' then
    v_view := jsonb_build_object(
      'cells', v_room.board->'cells',
      'marks', jsonb_build_array(
        case when coalesce(v_room.config->>'mark', 'X') = 'O' then 'O' else 'X' end,
        case when coalesce(v_room.config->>'mark', 'X') = 'O' then 'X' else 'O' end
      )
    );
  elsif v_room.game = 'mastermind' then
    v_view := jsonb_build_object(
      'guesses', coalesce(v_room.board->'guesses', '[]'::jsonb),
      'solved', coalesce((v_room.board->>'solved')::boolean, false),
      'pending', v_room.board->'pending',
      'secret', case
        when v_room.phase = 'done' then v_room.secret->'code'
        when coalesce((v_room.config->>'bot')::boolean, false) then null
        when v_seat = coalesce((v_room.config->>'maker')::integer, 0) and v_room.phase in ('code', 'play', 'mark') then v_room.secret->'code'
        else null
      end
    );
  elsif v_room.game = 'triomino' then
    v_view := jsonb_build_object(
      'placed', coalesce(v_room.board->'placed', '[]'::jsonb),
      'scores', coalesce(v_room.board->'scores', '[]'::jsonb),
      'draws', coalesce((v_room.board->>'draws')::integer, 0),
      'pile', jsonb_array_length(coalesce(v_room.secret->'pile', '[]'::jsonb)),
      'deal', coalesce(v_room.board->>'deal', ''),
      'need', coalesce((v_room.board->>'need')::integer, 0),
      'hand', coalesce(v_room.secret->'hands'->v_seat, '[]'::jsonb),
      'counts', (
        select coalesce(jsonb_agg(jsonb_array_length(hands.value) order by hands.ord), '[]'::jsonb)
        from jsonb_array_elements(coalesce(v_room.secret->'hands', '[]'::jsonb)) with ordinality as hands(value, ord)
      ),
      'last', v_room.board->'last',
      'must', case when v_seat = v_room.turn_seat then v_room.board->'must' else null end,
      'rest', case when v_room.phase = 'done' then v_room.secret->'hands' else null end
    );
  elsif v_room.game = 'mines' then
    v_view := jsonb_build_object(
      'size', coalesce((v_room.config->>'size')::integer, 9),
      'revealed', coalesce(v_room.board->'revealed', '{}'::jsonb),
      'eliminated', coalesce(v_room.board->'eliminated', '[]'::jsonb),
      'flags', coalesce(v_room.board->'flags', '[]'::jsonb),
      'mines', case when v_room.phase = 'done' then v_room.secret->'mines' else '[]'::jsonb end
    );
  elsif arcade.doku_kind(v_room.game) is not null then
    v_view := jsonb_build_object(
      'size', coalesce((v_room.board->>'size')::integer, coalesce((v_room.config->>'size')::integer, 9)),
      'given', coalesce(v_room.board->'given', '[]'::jsonb),
      'values', coalesce(v_room.board->'values', '[]'::jsonb),
      'colors', v_room.board->'colors',
      'stamp', v_room.board->>'stamp'
    );
  elsif v_room.game = 'bac' then
    v_view := jsonb_build_object(
      'letter', coalesce(v_room.board->>'letter', ''),
      'round', coalesce((v_room.board->>'round')::integer, 1),
      'rounds', coalesce((v_room.board->>'rounds')::integer, 5),
      'scores', coalesce(v_room.board->'scores', '[]'::jsonb),
      'gained', coalesce(v_room.board->'gained', '[]'::jsonb),
      'submitted', coalesce(v_room.board->'submitted', '[]'::jsonb),
      'voted', coalesce(v_room.board->'voted', '[]'::jsonb),
      'stopAt', (v_room.board->>'stopAt')::bigint,
      'step', coalesce(v_room.board->>'step', 'write'),
      'marks', case when v_room.phase in ('show', 'done') then v_room.board->'marks' else null end,
      'mine', coalesce(v_room.secret->'answers'->v_seat, arcade.bac_row()),
      'answers', case
        when v_room.phase in ('vote', 'show', 'done') then coalesce(v_room.secret->'answers', '[]'::jsonb)
        else null
      end,
      'ballot', coalesce(v_room.secret->'ballots'->v_seat, '{}'::jsonb)
    );
  else
    v_view := '{}'::jsonb;
  end if;
  return jsonb_build_object(
    'ok', true,
    'token', p_token,
    'state', jsonb_build_object(
      'code', v_room.code,
      'game', v_room.game,
      'phase', v_room.phase,
      'you', v_seat,
      'turn', v_room.turn_seat,
      'winner', v_room.winner,
      'names', v_names,
      'config', v_room.config,
      'view', v_view
    )
  );
end;
$$;

