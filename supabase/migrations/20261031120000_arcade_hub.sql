-- Hub de jeux, isolé de Mangathèque et du schéma yams.
-- À coller tel quel dans l'éditeur SQL.

create schema if not exists arcade;
revoke all on schema arcade from public, anon, authenticated;

create table if not exists arcade.rooms (
  code text primary key,
  game text not null,
  phase text not null,
  config jsonb not null default '{}'::jsonb,
  board jsonb not null default '{}'::jsonb,
  secret jsonb not null default '{}'::jsonb,
  turn_seat integer not null default 0,
  winner integer,
  revision integer not null default 1,
  seen timestamptz not null default now()
);

create table if not exists arcade.players (
  room_code text not null references arcade.rooms (code) on delete cascade,
  seat integer not null,
  name text not null,
  token text not null,
  bot boolean not null default false,
  primary key (room_code, seat)
);

alter table arcade.rooms enable row level security;
alter table arcade.players enable row level security;

create or replace function arcade.mine_count(p_size integer)
returns integer
language sql
immutable
as $$
  select case when p_size <= 9 then 10 when p_size = 12 then 22 else 40 end;
$$;

create or replace function arcade.neighbors(p_size integer, p_index integer)
returns integer[]
language sql
immutable
as $$
  select coalesce(array_agg(cell.idx), '{}'::integer[])
  from (
    select (pos.row_n + delta.dr) * p_size + (pos.col_n + delta.dc) as idx
    from (select p_index / p_size as row_n, p_index % p_size as col_n) as pos
    cross join (values (-1,-1),(-1,0),(-1,1),(0,-1),(0,1),(1,-1),(1,0),(1,1)) as delta(dr, dc)
    where (pos.row_n + delta.dr) between 0 and p_size - 1
      and (pos.col_n + delta.dc) between 0 and p_size - 1
  ) as cell;
$$;

create or replace function arcade.is_mine(p_secret jsonb, p_index integer)
returns boolean
language sql
immutable
as $$
  select coalesce(p_secret->'mines', '[]'::jsonb) @> to_jsonb(p_index);
$$;

create or replace function arcade.morpion_winner(p_cells jsonb)
returns text
language plpgsql
immutable
as $$
declare
  line record;
  mark text;
  filled integer := 0;
  idx integer;
begin
  for line in
    select * from (values
      (0,1,2),(3,4,5),(6,7,8),(0,3,6),(1,4,7),(2,5,8),(0,4,8),(2,4,6)
    ) as lines(a, b, c)
  loop
    mark := coalesce(p_cells->>line.a, '');
    if mark <> '' and mark = coalesce(p_cells->>line.b, '') and mark = coalesce(p_cells->>line.c, '') then
      return mark;
    end if;
  end loop;
  for idx in 0..8 loop
    if coalesce(p_cells->>idx, '') <> '' then
      filled := filled + 1;
    end if;
  end loop;
  if filled = 9 then
    return 'draw';
  end if;
  return '';
end;
$$;

create or replace function arcade.morpion_value(p_cells jsonb, p_mark text)
returns integer
language plpgsql
as $$
declare
  found text;
  idx integer;
  next_cells jsonb;
  child text;
  value integer;
  best integer;
begin
  found := arcade.morpion_winner(p_cells);
  if found = 'X' then return 1; end if;
  if found = 'O' then return -1; end if;
  if found = 'draw' then return 0; end if;
  best := case when p_mark = 'X' then -2 else 2 end;
  child := case when p_mark = 'X' then 'O' else 'X' end;
  for idx in 0..8 loop
    if coalesce(p_cells->>idx, '') <> '' then
      continue;
    end if;
    next_cells := jsonb_set(p_cells, array[idx::text], to_jsonb(p_mark));
    value := arcade.morpion_value(next_cells, child);
    if p_mark = 'X' and value > best then best := value; end if;
    if p_mark = 'O' and value < best then best := value; end if;
  end loop;
  return best;
end;
$$;

create or replace function arcade.morpion_best(p_cells jsonb, p_mark text)
returns integer
language plpgsql
as $$
declare
  idx integer;
  next_cells jsonb;
  child text;
  value integer;
  best integer;
  chosen integer := -1;
begin
  best := case when p_mark = 'X' then -2 else 2 end;
  child := case when p_mark = 'X' then 'O' else 'X' end;
  for idx in 0..8 loop
    if coalesce(p_cells->>idx, '') <> '' then
      continue;
    end if;
    next_cells := jsonb_set(p_cells, array[idx::text], to_jsonb(p_mark));
    value := arcade.morpion_value(next_cells, child);
    if chosen < 0 or (p_mark = 'X' and value > best) or (p_mark = 'O' and value < best) then
      best := value;
      chosen := idx;
    end if;
  end loop;
  return chosen;
end;
$$;

create or replace function arcade.mm_score(p_secret jsonb, p_guess jsonb)
returns jsonb
language plpgsql
immutable
as $$
declare
  secret integer[] := '{}';
  guess integer[] := '{}';
  elem jsonb;
  black integer := 0;
  white integer := 0;
  idx integer;
  at integer;
begin
  for elem in select value from jsonb_array_elements(p_secret) loop
    secret := secret || (elem #>> '{}')::integer;
  end loop;
  for elem in select value from jsonb_array_elements(p_guess) loop
    guess := guess || (elem #>> '{}')::integer;
  end loop;
  for idx in 1..4 loop
    if guess[idx] = secret[idx] then
      black := black + 1;
      secret[idx] := -1;
      guess[idx] := -2;
    end if;
  end loop;
  for idx in 1..4 loop
    if guess[idx] < 0 then
      continue;
    end if;
    at := array_position(secret, guess[idx]);
    if at is not null then
      white := white + 1;
      secret[at] := -1;
    end if;
  end loop;
  return jsonb_build_object('black', black, 'white', white);
end;
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
  end if;
  return '{}'::jsonb;
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
  v_self jsonb;
  v_ready jsonb;
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
      'secret', case
        when v_room.phase = 'done' then v_room.secret->'code'
        when coalesce((v_room.config->>'bot')::boolean, false) then null
        when v_seat = coalesce((v_room.config->>'maker')::integer, 0) and v_room.phase in ('code', 'play') then v_room.secret->'code'
        else null
      end
    );
  elsif v_room.game = 'mines' then
    v_view := jsonb_build_object(
      'size', coalesce((v_room.config->>'size')::integer, 9),
      'revealed', coalesce(v_room.board->'revealed', '{}'::jsonb),
      'eliminated', coalesce(v_room.board->'eliminated', '[]'::jsonb),
      'flags', coalesce(v_room.board->'flags', '[]'::jsonb),
      'mines', case when v_room.phase = 'done' then v_room.secret->'mines' else '[]'::jsonb end
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

create or replace function arcade.touch(p_code text)
returns void
language sql
security definer
set search_path = arcade, public
as $$
  update arcade.rooms as rooms
  set revision = rooms.revision + 1, seen = now()
  where rooms.code = p_code;
$$;

create or replace function arcade.mines_place(p_size integer, p_safe integer)
returns jsonb
language sql
volatile
as $$
  select coalesce(jsonb_agg(picked.idx), '[]'::jsonb)
  from (
    select series.idx
    from generate_series(0, p_size * p_size - 1) as series(idx)
    where series.idx <> p_safe
    order by random()
    limit arcade.mine_count(p_size)
  ) as picked;
$$;

create or replace function arcade.mines_open(p_board jsonb, p_secret jsonb, p_size integer, p_index integer)
returns jsonb
language plpgsql
as $$
declare
  revealed jsonb := coalesce(p_board->'revealed', '{}'::jsonb);
  mines jsonb := coalesce(p_secret->'mines', '[]'::jsonb);
  secret jsonb := p_secret;
  queue integer[] := array[p_index];
  cursor integer;
  around integer;
  neighbor integer;
  hit boolean := false;
begin
  if revealed ? p_index::text or coalesce(p_board->'flags', '[]'::jsonb) @> to_jsonb(p_index) then
    return jsonb_build_object('board', p_board, 'secret', p_secret, 'hit', false, 'ignored', true);
  end if;
  if jsonb_array_length(mines) = 0 then
    mines := arcade.mines_place(p_size, p_index);
    secret := jsonb_build_object('mines', mines);
  end if;
  if mines @> to_jsonb(p_index) then
    revealed := revealed || jsonb_build_object(p_index::text, -1);
    return jsonb_build_object(
      'board', jsonb_set(p_board, '{revealed}', revealed),
      'secret', secret,
      'hit', true,
      'ignored', false
    );
  end if;
  while coalesce(array_length(queue, 1), 0) > 0 loop
    cursor := queue[1];
    queue := queue[2:coalesce(array_length(queue, 1), 1)];
    if revealed ? cursor::text then
      continue;
    end if;
    if mines @> to_jsonb(cursor) then
      continue;
    end if;
    select count(*)::integer into around
    from unnest(arcade.neighbors(p_size, cursor)) as near(idx)
    where mines @> to_jsonb(near.idx);
    revealed := revealed || jsonb_build_object(cursor::text, around);
    if around = 0 then
      foreach neighbor in array arcade.neighbors(p_size, cursor) loop
        if not (revealed ? neighbor::text)
          and not (mines @> to_jsonb(neighbor))
          and not (coalesce(p_board->'flags', '[]'::jsonb) @> to_jsonb(neighbor)) then
          queue := queue || neighbor;
        end if;
      end loop;
    end if;
  end loop;
  return jsonb_build_object(
    'board', jsonb_set(p_board, '{revealed}', revealed),
    'secret', secret,
    'hit', hit,
    'ignored', false
  );
end;
$$;

create or replace function arcade.mines_clear(p_board jsonb, p_secret jsonb, p_size integer)
returns boolean
language plpgsql
immutable
as $$
declare
  total integer := p_size * p_size;
  mines integer;
  shown integer;
begin
  mines := jsonb_array_length(coalesce(p_secret->'mines', '[]'::jsonb));
  shown := (select count(*) from jsonb_object_keys(coalesce(p_board->'revealed', '{}'::jsonb)))::integer;
  return mines > 0 and shown >= total - mines;
end;
$$;

create or replace function arcade.alive_seats(p_code text)
returns integer[]
language sql
stable
as $$
  select coalesce(array_agg(players.seat order by players.seat), '{}'::integer[])
  from arcade.players as players
  join arcade.rooms as rooms on rooms.code = players.room_code
  where players.room_code = p_code
    and not (coalesce(rooms.board->'eliminated', '[]'::jsonb) @> to_jsonb(players.seat));
$$;

create or replace function arcade.next_alive(p_code text, p_seat integer)
returns integer
language plpgsql
stable
as $$
declare
  seats integer[] := arcade.alive_seats(p_code);
  chosen integer;
begin
  if coalesce(array_length(seats, 1), 0) = 0 then
    return p_seat;
  end if;
  select seat.idx into chosen
  from unnest(seats) as seat(idx)
  where seat.idx > p_seat
  order by seat.idx
  limit 1;
  if chosen is null then
    return seats[1];
  end if;
  return chosen;
end;
$$;

create or replace function arcade.mines_bot_pick(p_board jsonb, p_size integer)
returns integer
language plpgsql
volatile
as $$
declare
  revealed jsonb := coalesce(p_board->'revealed', '{}'::jsonb);
  safe integer[] := '{}';
  danger integer[] := '{}';
  pool integer[] := '{}';
  idx integer;
  near integer;
  hidden integer;
  bombs integer;
  number integer;
begin
  for idx in 0..p_size * p_size - 1 loop
    if not (revealed ? idx::text) then
      continue;
    end if;
    number := (revealed->>idx::text)::integer;
    if number < 0 then
      continue;
    end if;
    hidden := 0;
    bombs := 0;
    foreach near in array arcade.neighbors(p_size, idx) loop
      if not (revealed ? near::text) then
        hidden := hidden + 1;
      elsif (revealed->>near::text)::integer < 0 then
        bombs := bombs + 1;
      end if;
    end loop;
    if hidden = 0 then
      continue;
    end if;
    foreach near in array arcade.neighbors(p_size, idx) loop
      if revealed ? near::text then
        continue;
      end if;
      if number = bombs then
        safe := safe || near;
      end if;
      if number - bombs = hidden then
        danger := danger || near;
      end if;
    end loop;
  end loop;
  if coalesce(array_length(safe, 1), 0) > 0 then
    return safe[1];
  end if;
  for idx in 0..p_size * p_size - 1 loop
    if not (revealed ? idx::text) and not (idx = any(danger)) then
      pool := pool || idx;
    end if;
  end loop;
  if coalesce(array_length(pool, 1), 0) = 0 then
    for idx in 0..p_size * p_size - 1 loop
      if not (revealed ? idx::text) then
        pool := pool || idx;
      end if;
    end loop;
  end if;
  if coalesce(array_length(pool, 1), 0) = 0 then
    return -1;
  end if;
  return pool[1 + (floor(random() * array_length(pool, 1)))::integer];
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
        when rooms.game in ('morpion', 'mastermind', 'mines') and not v_bot then 'lobby'
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
    if v_room.game not in ('morpion', 'mastermind', 'mines') then
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

create or replace function arcade.run_bots(p_code text)
returns void
language plpgsql
security definer
set search_path = arcade, public
as $$
#variable_conflict use_column
declare
  v_room arcade.rooms%rowtype;
  v_bot boolean;
  v_index integer;
  v_guard integer := 0;
begin
  loop
    v_guard := v_guard + 1;
    if v_guard > 4 then
      return;
    end if;
    select rooms.* into v_room from arcade.rooms as rooms where rooms.code = p_code;
    if v_room.phase <> 'play' then
      return;
    end if;
    select players.bot into v_bot
    from arcade.players as players
    where players.room_code = p_code and players.seat = v_room.turn_seat;
    if not coalesce(v_bot, false) then
      return;
    end if;
    if v_room.game = 'morpion' then
      v_index := arcade.morpion_best(v_room.board->'cells', case
        when coalesce(v_room.config->>'mark', 'X') = 'O' then case when v_room.turn_seat = 0 then 'O' else 'X' end
        else case when v_room.turn_seat = 0 then 'X' else 'O' end
      end);
      perform arcade.apply_action(p_code, v_room.turn_seat, 'play', jsonb_build_object('i', v_index));
    elsif v_room.game = 'mines' then
      v_index := arcade.mines_bot_pick(v_room.board, coalesce((v_room.config->>'size')::integer, 9));
      if v_index < 0 then
        return;
      end if;
      perform arcade.apply_action(p_code, v_room.turn_seat, 'open', jsonb_build_object('i', v_index));
    else
      return;
    end if;
  end loop;
end;
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
          when rooms.game in ('morpion', 'mastermind', 'mines') then 'lobby'
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

create or replace function public.arcade_act(p_code text, p_token text, p_action text, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = arcade, public
as $$
#variable_conflict use_column
declare
  v_code text := upper(coalesce(p_code, ''));
  v_seat integer;
  v_bot boolean;
  v_error text;
begin
  select players.seat, players.bot into v_seat, v_bot
  from arcade.players as players
  where players.room_code = v_code and players.token = coalesce(p_token, '');
  if v_seat is null then
    return jsonb_build_object('ok', false, 'error', 'Joueur inconnu sur cette table.');
  end if;
  if v_bot and p_action <> 'again' then
    return jsonb_build_object('ok', false, 'error', 'Coup refusé.');
  end if;
  v_error := arcade.apply_action(v_code, v_seat, coalesce(p_action, ''), coalesce(p_payload, '{}'::jsonb));
  if v_error is not null then
    return jsonb_build_object('ok', false, 'error', v_error);
  end if;
  perform arcade.run_bots(v_code);
  perform arcade.touch(v_code);
  return arcade.public_state(v_code, p_token);
exception when others then
  return jsonb_build_object('ok', false, 'error', sqlerrm);
end;
$$;

revoke all on all tables in schema arcade from public, anon, authenticated;
revoke all on schema arcade from public, anon, authenticated;
grant execute on function public.arcade_create(text, text, jsonb) to anon, authenticated;
grant execute on function public.arcade_join(text, text, text) to anon, authenticated;
grant execute on function public.arcade_state(text, text) to anon, authenticated;
grant execute on function public.arcade_act(text, text, text, jsonb) to anon, authenticated;
