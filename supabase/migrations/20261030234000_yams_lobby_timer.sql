-- Salon, plusieurs manches, ordre de départ et chronomètre.
-- À coller dans l'éditeur SQL du projet Supabase de Mangathèque.

alter table yams.rooms add column if not exists player_cap integer not null default 5;
alter table yams.rooms add column if not exists manche_count integer not null default 1;
alter table yams.rooms add column if not exists current_manche integer not null default 0;
alter table yams.rooms add column if not exists play_mode text not null default 'virtual';
alter table yams.rooms add column if not exists timed boolean not null default false;
alter table yams.rooms add column if not exists hints boolean not null default true;
alter table yams.rooms add column if not exists seat_order integer[] not null default '{}';
alter table yams.rooms add column if not exists skip_count integer not null default 0;
alter table yams.rooms add column if not exists deadline timestamptz;
alter table yams.rooms add column if not exists timer_phase text not null default 'play';
alter table yams.rooms add column if not exists opening integer[] not null default array[0, 0, 0, 0, 0];

update yams.players
set scores = jsonb_build_array(scores)
where jsonb_typeof(scores) = 'object';

update yams.rooms as room
set seat_order = coalesce((
  select array_agg(seat order by seat)
  from yams.players
  where room_code = room.code
), '{}')
where cardinality(seat_order) = 0;

create or replace function yams.empty_book(p_count integer)
returns jsonb
language plpgsql
immutable
as $$
declare
  book jsonb := '[]'::jsonb;
  i integer;
  total integer := greatest(1, least(coalesce(p_count, 1), 5));
begin
  for i in 1..total loop
    book := book || jsonb_build_array(yams.empty_scores());
  end loop;
  return book;
end;
$$;

create or replace function yams.sheet_at(p_scores jsonb, p_manche integer)
returns jsonb
language sql
immutable
as $$
  select case
    when jsonb_typeof(p_scores) = 'array' then coalesce(p_scores -> greatest(p_manche, 0), yams.empty_scores())
    else coalesce(p_scores, yams.empty_scores())
  end;
$$;

create or replace function yams.sheet_open(p_scores jsonb, p_manche integer)
returns boolean
language sql
immutable
as $$
  select exists (
    select 1
    from jsonb_each_text(yams.sheet_at(p_scores, p_manche)) as entry
    where entry.value = ''
  );
$$;

create or replace function yams.room_state(p_code text, p_token text)
returns jsonb
language plpgsql
security definer
set search_path = yams, public
as $$
declare
  room yams.rooms%rowtype;
  you_seat integer := -1;
  players jsonb;
  remaining integer := 0;
begin
  select * into room from yams.rooms where code = upper(p_code);
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Table introuvable.');
  end if;
  select seat into you_seat from yams.players where room_code = room.code and token = p_token;
  if you_seat is null then
    return jsonb_build_object('ok', false, 'error', 'Joueur inconnu sur cette table.');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('name', name, 'scores', scores) order by seat), '[]'::jsonb)
    into players
  from yams.players
  where room_code = room.code;
  if room.deadline is not null then
    remaining := greatest(0, floor(extract(epoch from (room.deadline - now())) * 1000))::integer;
  end if;
  return jsonb_build_object(
    'ok', true,
    'token', p_token,
    'state', jsonb_build_object(
      'code', room.code,
      'revision', room.revision,
      'you', you_seat,
      'turn', room.turn_index,
      'rolls', room.rolls,
      'dice', to_jsonb(room.dice),
      'held', to_jsonb(room.held),
      'phase', room.phase,
      'players', players,
      'playerCap', room.player_cap,
      'mancheCount', room.manche_count,
      'manche', room.current_manche,
      'mode', room.play_mode,
      'timed', room.timed,
      'hints', room.hints,
      'order', to_jsonb(room.seat_order),
      'skips', room.skip_count,
      'timerPhase', room.timer_phase,
      'remainingMs', remaining,
      'opening', to_jsonb(room.opening)
    )
  );
end;
$$;

create or replace function yams.arm_timer(p_code text)
returns void
language plpgsql
security definer
set search_path = yams, public
as $$
begin
  update yams.rooms
  set skip_count = 0,
      timer_phase = 'play',
      deadline = case when timed and phase = 'play' then now() + interval '60 seconds' else null end
  where code = p_code;
end;
$$;

create or replace function yams.advance(p_code text)
returns void
language plpgsql
security definer
set search_path = yams, public
as $$
declare
  room yams.rooms%rowtype;
  count_players integer;
  pos integer;
  step integer;
  nxt integer;
  open_on_manche integer;
begin
  select * into room from yams.rooms where code = p_code for update;
  select count(*) into count_players from yams.players where room_code = p_code;
  if count_players = 0 or cardinality(room.seat_order) = 0 then
    update yams.rooms
      set phase = 'done', dice = array[0,0,0,0,0], held = array[false,false,false,false,false], rolls = 0, deadline = null, seen = now(), revision = revision + 1
      where code = p_code;
    return;
  end if;
  select count(*) into open_on_manche
  from yams.players
  where room_code = p_code and yams.sheet_open(scores, room.current_manche);
  if open_on_manche = 0 then
    if room.current_manche + 1 < room.manche_count then
      update yams.rooms
      set current_manche = current_manche + 1,
          turn_index = seat_order[1],
          dice = array[0,0,0,0,0],
          held = array[false,false,false,false,false],
          rolls = 0,
          phase = 'play',
          seen = now(),
          revision = revision + 1
      where code = p_code;
      perform yams.arm_timer(p_code);
      return;
    end if;
    update yams.rooms
      set phase = 'done', dice = array[0,0,0,0,0], held = array[false,false,false,false,false], rolls = 0, deadline = null, seen = now(), revision = revision + 1
      where code = p_code;
    return;
  end if;
  pos := coalesce(array_position(room.seat_order, room.turn_index), 0);
  nxt := room.turn_index;
  for step in 1..cardinality(room.seat_order) loop
    pos := (pos % cardinality(room.seat_order)) + 1;
    nxt := room.seat_order[pos];
    exit when exists (
      select 1 from yams.players
      where room_code = p_code and seat = nxt and yams.sheet_open(scores, room.current_manche)
    );
  end loop;
  update yams.rooms
    set turn_index = nxt,
        dice = array[0,0,0,0,0],
        held = array[false,false,false,false,false],
        rolls = 0,
        phase = 'play',
        seen = now(),
        revision = revision + 1
    where code = p_code;
  perform yams.arm_timer(p_code);
end;
$$;

create or replace function yams.apply_penalty(p_code text)
returns void
language plpgsql
security definer
set search_path = yams, public
as $$
declare
  room yams.rooms%rowtype;
  player yams.players%rowtype;
  sheet jsonb;
  cats text[] := array['as','deux','trois','quatre','cinq','six','brelan','carre','full','petite','grande','yams','chance'];
  prefer text[] := array['yams','grande','full','petite','chance','carre','brelan','six','cinq','quatre','trois','deux','as'];
  cat text;
  chosen text;
  chosen_points integer;
  points integer;
  stored text;
  known boolean;
begin
  select * into room from yams.rooms where code = p_code for update;
  if room.phase <> 'play' then
    return;
  end if;
  select * into player from yams.players where room_code = p_code and seat = room.turn_index;
  if not found then
    return;
  end if;
  sheet := yams.sheet_at(player.scores, room.current_manche);
  known := room.play_mode <> 'physical' and exists (select 1 from unnest(room.dice) as face where face > 0);
  chosen := null;
  chosen_points := null;
  if known then
    foreach cat in array cats loop
      if coalesce(sheet->>cat, '') = '' then
        points := yams.score_category(room.dice, cat);
        if points > 0 and (chosen_points is null or points < chosen_points) then
          chosen := cat;
          chosen_points := points;
        end if;
      end if;
    end loop;
  end if;
  if chosen is null then
    foreach cat in array prefer loop
      if coalesce(sheet->>cat, '') = '' then
        chosen := cat;
        stored := 'x';
        exit;
      end if;
    end loop;
  else
    stored := chosen_points::text;
  end if;
  if chosen is null then
    return;
  end if;
  update yams.players
    set scores = jsonb_set(scores, array[room.current_manche::text, chosen], to_jsonb(stored))
    where room_code = p_code and seat = player.seat;
  perform yams.advance(p_code);
end;
$$;

create or replace function yams.tick(p_code text)
returns void
language plpgsql
security definer
set search_path = yams, public
as $$
declare
  room yams.rooms%rowtype;
begin
  select * into room from yams.rooms where code = upper(coalesce(p_code, '')) for update;
  if not found or room.phase <> 'play' or not room.timed then
    return;
  end if;
  if room.deadline is null then
    perform yams.arm_timer(room.code);
    update yams.rooms set revision = revision + 1 where code = room.code;
    return;
  end if;
  if room.deadline > now() then
    return;
  end if;
  if room.timer_phase = 'confirm' then
    perform yams.apply_penalty(room.code);
    return;
  end if;
  update yams.rooms
    set timer_phase = 'confirm', deadline = now() + interval '15 seconds', revision = revision + 1, seen = now()
    where code = room.code;
end;
$$;

create or replace function yams.opening_order(p_code text, p_winner integer)
returns integer[]
language plpgsql
stable
as $$
declare
  ordered integer[];
  pos integer;
  total integer;
  result integer[] := '{}';
  i integer;
begin
  select array_agg(seat order by lower(translate(
    name,
    'àâäéèêëïîôùûüçÀÂÄÉÈÊËÏÎÔÙÛÜÇ',
    'aaaeeeeiioouuucaaaeeeeiioouuuc'
  )), seat)
    into ordered
  from yams.players
  where room_code = p_code;
  total := coalesce(cardinality(ordered), 0);
  if total = 0 then
    return result;
  end if;
  pos := coalesce(array_position(ordered, p_winner), 1);
  for i in 0..total - 1 loop
    result := result || ordered[((pos - 1 + i) % total) + 1];
  end loop;
  return result;
end;
$$;

drop function if exists public.yams_create_room(text);

create or replace function public.yams_create_room(
  p_name text,
  p_players integer,
  p_manches integer,
  p_mode text,
  p_timed boolean,
  p_hints boolean
)
returns jsonb
language plpgsql
security definer
set search_path = yams, public
as $$
declare
  alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  new_code text;
  new_token text;
  tries integer := 0;
  cap integer := greatest(1, least(coalesce(p_players, 1), 5));
  manches integer := greatest(1, least(coalesce(p_manches, 1), 5));
  mode text := case when p_mode = 'physical' then 'physical' else 'virtual' end;
begin
  perform yams.purge_old();
  loop
    tries := tries + 1;
    new_code := '';
    for i in 1..4 loop
      new_code := new_code || substr(alphabet, 1 + floor(random() * length(alphabet))::integer, 1);
    end loop;
    exit when not exists (select 1 from yams.rooms where code = new_code);
    if tries > 20 then
      return jsonb_build_object('ok', false, 'error', 'Impossible de créer la table.');
    end if;
  end loop;
  new_token := md5(random()::text || clock_timestamp()::text);
  insert into yams.rooms (code, phase, player_cap, manche_count, play_mode, timed, hints)
  values (new_code, 'lobby', cap, manches, mode, coalesce(p_timed, false), coalesce(p_hints, true));
  insert into yams.players (room_code, seat, name, token, scores)
  values (new_code, 0, left(coalesce(nullif(btrim(p_name), ''), 'Joueur 1'), 24), new_token, yams.empty_book(manches));
  return yams.room_state(new_code, new_token);
end;
$$;

create or replace function public.yams_join_room(p_code text, p_name text, p_token text)
returns jsonb
language plpgsql
security definer
set search_path = yams, public
as $$
declare
  room yams.rooms%rowtype;
  existing integer;
  known_token text;
  seat_count integer;
  new_token text;
begin
  perform yams.purge_old();
  select * into room from yams.rooms where code = upper(coalesce(p_code, ''));
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Table introuvable.');
  end if;
  select seat, token into existing, known_token
  from yams.players
  where room_code = room.code and token = coalesce(p_token, '');
  if existing is not null then
    return yams.room_state(room.code, known_token);
  end if;
  if nullif(btrim(p_name), '') is not null then
    select seat, token into existing, known_token
    from yams.players
    where room_code = room.code
      and lower(btrim(name)) = lower(btrim(p_name))
    order by seat
    limit 1;
    if existing is not null then
      return yams.room_state(room.code, known_token);
    end if;
  end if;
  if room.phase <> 'lobby' then
    return jsonb_build_object('ok', false, 'error', 'La partie a déjà commencé.');
  end if;
  select count(*) into seat_count from yams.players where room_code = room.code;
  if seat_count >= room.player_cap then
    return jsonb_build_object('ok', false, 'error', 'La table est complète.');
  end if;
  new_token := md5(random()::text || clock_timestamp()::text || seat_count::text);
  insert into yams.players (room_code, seat, name, token, scores)
  values (
    room.code,
    seat_count,
    left(coalesce(nullif(btrim(p_name), ''), 'Joueur ' || (seat_count + 1)), 24),
    new_token,
    yams.empty_book(room.manche_count)
  );
  update yams.rooms set revision = revision + 1, seen = now() where code = room.code;
  return yams.room_state(room.code, new_token);
end;
$$;

create or replace function public.yams_start(p_code text, p_token text)
returns jsonb
language plpgsql
security definer
set search_path = yams, public
as $$
#variable_conflict use_column
declare
  room yams.rooms%rowtype;
  you_seat integer;
  dice_row integer[] := array[0, 0, 0, 0, 0];
  v_seat integer;
  attempt integer;
  top integer;
  ties integer;
  winner integer;
  v_code text;
begin
  perform yams.purge_old();
  select rooms.* into room from yams.rooms as rooms where rooms.code = upper(coalesce(p_code, '')) for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Table introuvable.');
  end if;
  select players.seat into you_seat from yams.players as players where players.room_code = room.code and players.token = coalesce(p_token, '');
  if you_seat is null then
    return jsonb_build_object('ok', false, 'error', 'Joueur inconnu sur cette table.');
  end if;
  if you_seat <> 0 then
    return jsonb_build_object('ok', false, 'error', 'Seul l''hôte lance la partie.');
  end if;
  if room.phase <> 'lobby' then
    return jsonb_build_object('ok', false, 'error', 'La partie a déjà commencé.');
  end if;
  v_code := room.code;
  for v_seat in select players.seat from yams.players as players where players.room_code = v_code order by players.seat loop
    dice_row[v_seat + 1] := 1 + floor(random() * 6)::integer;
  end loop;
  for attempt in 1..12 loop
    top := 0;
    ties := 0;
    winner := null;
    for v_seat in select players.seat from yams.players as players where players.room_code = v_code order by players.seat loop
      if dice_row[v_seat + 1] > top then
        top := dice_row[v_seat + 1];
        ties := 1;
        winner := v_seat;
      elsif dice_row[v_seat + 1] = top then
        ties := ties + 1;
      end if;
    end loop;
    exit when ties <= 1;
    for v_seat in select players.seat from yams.players as players where players.room_code = v_code order by players.seat loop
      if dice_row[v_seat + 1] = top then
        dice_row[v_seat + 1] := 1 + floor(random() * 6)::integer;
      end if;
    end loop;
  end loop;
  if winner is null then
    select players.seat into winner from yams.players as players where players.room_code = v_code order by players.seat limit 1;
  end if;
  update yams.rooms as rooms
    set phase = 'play',
        opening = dice_row,
        seat_order = yams.opening_order(v_code, winner),
        turn_index = winner,
        current_manche = 0,
        rolls = 0,
        dice = array[0,0,0,0,0],
        held = array[false,false,false,false,false],
        seen = now(),
        revision = rooms.revision + 1
    where rooms.code = v_code;
  perform yams.arm_timer(v_code);
  return yams.room_state(v_code, p_token);
exception
  when others then
    return jsonb_build_object('ok', false, 'error', sqlerrm);
end;
$$;

create or replace function public.yams_presence(p_code text, p_token text, p_yes boolean)
returns jsonb
language plpgsql
security definer
set search_path = yams, public
as $$
declare
  room yams.rooms%rowtype;
  you_seat integer;
begin
  perform yams.tick(upper(coalesce(p_code, '')));
  select * into room from yams.rooms where code = upper(coalesce(p_code, '')) for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Table introuvable.');
  end if;
  select seat into you_seat from yams.players where room_code = room.code and token = coalesce(p_token, '');
  if you_seat is null then
    return jsonb_build_object('ok', false, 'error', 'Joueur inconnu sur cette table.');
  end if;
  if room.phase <> 'play' or you_seat <> room.turn_index or room.timer_phase <> 'confirm' then
    return yams.room_state(room.code, p_token);
  end if;
  if coalesce(p_yes, false) and room.skip_count < 3 then
    update yams.rooms
      set skip_count = skip_count + 1,
          timer_phase = 'play',
          deadline = now() + interval '60 seconds',
          revision = revision + 1,
          seen = now()
      where code = room.code;
  else
    perform yams.apply_penalty(room.code);
  end if;
  return yams.room_state(room.code, p_token);
end;
$$;

create or replace function public.yams_state(p_code text, p_token text)
returns jsonb
language plpgsql
security definer
set search_path = yams, public
as $$
#variable_conflict use_column
declare
  result jsonb;
  v_code text := upper(coalesce(p_code, ''));
begin
  perform yams.purge_old();
  perform yams.tick(v_code);
  result := yams.room_state(v_code, coalesce(p_token, ''));
  if (result->>'ok')::boolean then
    update yams.rooms as rooms set seen = now() where rooms.code = v_code;
  end if;
  return result;
end;
$$;

create or replace function public.yams_roll(p_code text, p_token text, p_hold boolean[])
returns jsonb
language plpgsql
security definer
set search_path = yams, public
as $$
declare
  room yams.rooms%rowtype;
  you_seat integer;
  hold boolean[] := array[false, false, false, false, false];
  next_dice integer[] := array[0, 0, 0, 0, 0];
  i integer;
  next_rolls integer;
begin
  perform yams.tick(upper(coalesce(p_code, '')));
  select * into room from yams.rooms where code = upper(coalesce(p_code, '')) for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Table introuvable.');
  end if;
  select seat into you_seat from yams.players where room_code = room.code and token = coalesce(p_token, '');
  if you_seat is null then
    return jsonb_build_object('ok', false, 'error', 'Joueur inconnu sur cette table.');
  end if;
  if room.phase <> 'play' or you_seat <> room.turn_index then
    return jsonb_build_object('ok', false, 'error', 'Ce n''est pas ton tour.');
  end if;
  if room.timer_phase = 'confirm' then
    return jsonb_build_object('ok', false, 'error', 'Réponds d''abord à la fenêtre.');
  end if;
  if room.play_mode = 'physical' then
    return jsonb_build_object('ok', false, 'error', 'Cette partie se joue avec des dés physiques.');
  end if;
  if room.rolls >= 3 then
    return jsonb_build_object('ok', false, 'error', 'Les trois lancers sont utilisés.');
  end if;
  if room.rolls > 0 and p_hold is not null then
    for i in 1..5 loop
      hold[i] := coalesce(p_hold[i], false) and room.dice[i] <> 0;
    end loop;
  end if;
  for i in 1..5 loop
    if hold[i] then
      next_dice[i] := room.dice[i];
    else
      next_dice[i] := 1 + floor(random() * 6)::integer;
    end if;
  end loop;
  next_rolls := room.rolls + 1;
  update yams.rooms
    set dice = next_dice,
        held = hold,
        rolls = next_rolls,
        seen = now(),
        revision = revision + 1,
        skip_count = case when timed and next_rolls < 3 then 0 else skip_count end,
        timer_phase = case when timed and next_rolls < 3 then 'play' else timer_phase end,
        deadline = case when timed and next_rolls < 3 then now() + interval '60 seconds' else deadline end
    where code = room.code;
  return yams.room_state(room.code, p_token);
end;
$$;

create or replace function public.yams_score(
  p_code text,
  p_token text,
  p_cat text,
  p_manual boolean,
  p_value text,
  p_bar boolean
)
returns jsonb
language plpgsql
security definer
set search_path = yams, public
as $$
declare
  room yams.rooms%rowtype;
  player yams.players%rowtype;
  sheet jsonb;
  points integer;
  stored text;
begin
  perform yams.tick(upper(coalesce(p_code, '')));
  select * into room from yams.rooms where code = upper(coalesce(p_code, '')) for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Table introuvable.');
  end if;
  select * into player from yams.players where room_code = room.code and token = coalesce(p_token, '');
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Joueur inconnu sur cette table.');
  end if;
  if room.phase <> 'play' or player.seat <> room.turn_index then
    return jsonb_build_object('ok', false, 'error', 'Ce n''est pas ton tour.');
  end if;
  if room.timer_phase = 'confirm' then
    return jsonb_build_object('ok', false, 'error', 'Réponds d''abord à la fenêtre.');
  end if;
  if not coalesce(p_manual, false) and room.play_mode <> 'physical' and room.rolls < 1 then
    return jsonb_build_object('ok', false, 'error', 'Lance les dés avant de marquer.');
  end if;
  if p_cat not in ('as','deux','trois','quatre','cinq','six','brelan','carre','full','petite','grande','yams','chance') then
    return jsonb_build_object('ok', false, 'error', 'Case inconnue.');
  end if;
  sheet := yams.sheet_at(player.scores, room.current_manche);
  if coalesce(sheet->>p_cat, '') <> '' then
    return jsonb_build_object('ok', false, 'error', 'Cette case est déjà jouée.');
  end if;
  if coalesce(p_manual, false) or room.play_mode = 'physical' then
    stored := yams.manual_value(p_cat, p_value, coalesce(p_bar, false));
    if stored is null then
      return jsonb_build_object('ok', false, 'error', 'Score impossible pour cette case.');
    end if;
  else
    points := yams.score_category(room.dice, p_cat);
    if coalesce(p_bar, false) or (p_cat in ('full','petite','grande','yams') and points = 0) then
      stored := 'x';
    else
      stored := points::text;
    end if;
  end if;
  update yams.players
    set scores = jsonb_set(scores, array[room.current_manche::text, p_cat], to_jsonb(stored))
    where room_code = room.code and seat = player.seat;
  perform yams.advance(room.code);
  return yams.room_state(room.code, p_token);
end;
$$;

create or replace function public.yams_add_manche(p_code text, p_token text)
returns jsonb
language plpgsql
security definer
set search_path = yams, public
as $$
#variable_conflict use_column
declare
  room yams.rooms%rowtype;
  you_seat integer;
begin
  select rooms.* into room from yams.rooms as rooms where rooms.code = upper(coalesce(p_code, '')) for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Table introuvable.');
  end if;
  select players.seat into you_seat from yams.players as players where players.room_code = room.code and players.token = coalesce(p_token, '');
  if you_seat is null then
    return jsonb_build_object('ok', false, 'error', 'Joueur inconnu sur cette table.');
  end if;
  if room.phase = 'lobby' then
    return jsonb_build_object('ok', false, 'error', 'Lance d''abord la partie.');
  end if;
  if room.manche_count >= 5 then
    return jsonb_build_object('ok', false, 'error', 'Cinq manches maximum.');
  end if;
  update yams.players as players
    set scores = players.scores || jsonb_build_array(yams.empty_scores())
    where players.room_code = room.code;
  update yams.rooms as rooms
    set manche_count = rooms.manche_count + 1,
        current_manche = rooms.manche_count,
        dice = array[0,0,0,0,0],
        held = array[false,false,false,false,false],
        rolls = 0,
        phase = 'play',
        seen = now(),
        revision = rooms.revision + 1
    where rooms.code = room.code;
  perform yams.arm_timer(room.code);
  return yams.room_state(room.code, p_token);
end;
$$;

revoke all on function public.yams_create_room(text, integer, integer, text, boolean, boolean) from public;
revoke all on function public.yams_add_manche(text, text) from public;
revoke all on function public.yams_start(text, text) from public;
revoke all on function public.yams_presence(text, text, boolean) from public;
grant execute on function public.yams_create_room(text, integer, integer, text, boolean, boolean) to anon, authenticated;
grant execute on function public.yams_start(text, text) to anon, authenticated;
grant execute on function public.yams_add_manche(text, text) to anon, authenticated;
grant execute on function public.yams_presence(text, text, boolean) to anon, authenticated;
