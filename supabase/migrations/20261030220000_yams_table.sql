-- Table de Yams isolée. Mangathèque ne lit pas ce schéma.
-- Aucune clé étrangère vers les tables manga, animé ou auth.
-- Les téléphones passent par les fonctions publiques, en HTTPS.

create schema if not exists yams;

revoke all on schema yams from public, anon, authenticated;

create table if not exists yams.rooms (
  code text primary key,
  revision integer not null default 1,
  seen timestamptz not null default now(),
  turn_index integer not null default 0,
  rolls integer not null default 0,
  dice integer[] not null default array[0, 0, 0, 0, 0],
  held boolean[] not null default array[false, false, false, false, false],
  phase text not null default 'play'
);

create table if not exists yams.players (
  room_code text not null references yams.rooms (code) on delete cascade,
  seat integer not null check (seat >= 0 and seat < 5),
  name text not null,
  token text not null unique,
  scores jsonb not null,
  primary key (room_code, seat)
);

alter table yams.rooms enable row level security;
alter table yams.players enable row level security;

create or replace function yams.empty_scores()
returns jsonb
language sql
immutable
as $$
  select '{"as":"","deux":"","trois":"","quatre":"","cinq":"","six":"","brelan":"","carre":"","full":"","petite":"","grande":"","yams":"","chance":""}'::jsonb;
$$;

create or replace function yams.score_category(p_dice integer[], p_cat text)
returns integer
language plpgsql
immutable
as $$
declare
  face integer;
  counts integer[] := array[0, 0, 0, 0, 0, 0, 0];
  total integer := 0;
  present integer[] := '{}';
  start_face integer;
  offset_face integer;
  ok boolean;
begin
  if p_dice is null then
    return 0;
  end if;
  foreach face in array p_dice loop
    if face between 1 and 6 then
      counts[face + 1] := counts[face + 1] + 1;
      total := total + face;
      if not face = any (present) then
        present := present || face;
      end if;
    end if;
  end loop;

  if p_cat = 'as' then return counts[2] * 1; end if;
  if p_cat = 'deux' then return counts[3] * 2; end if;
  if p_cat = 'trois' then return counts[4] * 3; end if;
  if p_cat = 'quatre' then return counts[5] * 4; end if;
  if p_cat = 'cinq' then return counts[6] * 5; end if;
  if p_cat = 'six' then return counts[7] * 6; end if;
  if p_cat = 'brelan' then
    if 3 <= any (counts) or 4 <= any (counts) or 5 <= any (counts) then return total; end if;
    return 0;
  end if;
  if p_cat = 'carre' then
    if 4 <= any (counts) or 5 <= any (counts) then return total; end if;
    return 0;
  end if;
  if p_cat = 'full' then
    if 3 = any (counts) and 2 = any (counts) then return 25; end if;
    return 0;
  end if;
  if p_cat in ('petite', 'grande') then
    for start_face in 1..(case when p_cat = 'petite' then 3 else 2 end) loop
      ok := true;
      for offset_face in 0..(case when p_cat = 'petite' then 3 else 4 end) loop
        if not (start_face + offset_face) = any (present) then
          ok := false;
        end if;
      end loop;
      if ok then
        return case when p_cat = 'petite' then 30 else 40 end;
      end if;
    end loop;
    return 0;
  end if;
  if p_cat = 'yams' then
    if 5 = any (counts) then return 50; end if;
    return 0;
  end if;
  if p_cat = 'chance' then
    return least(30, total);
  end if;
  return 0;
end;
$$;

create or replace function yams.manual_value(p_cat text, p_raw text, p_bar boolean)
returns text
language plpgsql
immutable
as $$
declare
  points integer;
  limit_points integer;
begin
  if p_bar or p_raw = 'x' then
    return 'x';
  end if;
  begin
    points := p_raw::integer;
  exception when others then
    return null;
  end;
  if p_cat = 'full' then return case when points = 25 then '25' else null end; end if;
  if p_cat = 'petite' then return case when points = 30 then '30' else null end; end if;
  if p_cat = 'grande' then return case when points = 40 then '40' else null end; end if;
  if p_cat = 'yams' then return case when points = 50 then '50' else null end; end if;
  limit_points := case p_cat
    when 'as' then 5
    when 'deux' then 10
    when 'trois' then 15
    when 'quatre' then 20
    when 'cinq' then 25
    when 'six' then 30
    when 'brelan' then 30
    when 'carre' then 30
    when 'chance' then 30
    else null
  end;
  if limit_points is null or points < 0 or points > limit_points then
    return null;
  end if;
  return points::text;
end;
$$;

create or replace function yams.purge_old()
returns void
language sql
security definer
set search_path = yams, public
as $$
  delete from yams.rooms where seen < now() - interval '12 hours';
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
      'players', players
    )
  );
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
  nxt integer;
  step integer;
  open_count integer;
begin
  select * into room from yams.rooms where code = p_code for update;
  select count(*) into count_players from yams.players where room_code = p_code;
  select count(*) into open_count
  from yams.players
  where room_code = p_code
    and exists (
      select 1 from jsonb_each_text(scores) as entry where entry.value = ''
    );
  if count_players = 0 or open_count = 0 then
    update yams.rooms
      set phase = 'done', dice = array[0,0,0,0,0], held = array[false,false,false,false,false], rolls = 0, seen = now(), revision = revision + 1
      where code = p_code;
    return;
  end if;
  nxt := room.turn_index;
  for step in 1..count_players loop
    nxt := (nxt + 1) % count_players;
    if exists (
      select 1 from yams.players
      where room_code = p_code and seat = nxt
        and exists (select 1 from jsonb_each_text(scores) as entry where entry.value = '')
    ) then
      exit;
    end if;
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
end;
$$;

create or replace function public.yams_create_room(p_name text)
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
  insert into yams.rooms (code) values (new_code);
  insert into yams.players (room_code, seat, name, token, scores)
  values (new_code, 0, left(coalesce(nullif(btrim(p_name), ''), 'Joueur 1'), 24), new_token, yams.empty_scores());
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
  select count(*) into seat_count from yams.players where room_code = room.code;
  if seat_count >= 5 then
    return jsonb_build_object('ok', false, 'error', 'La table est complète (5 joueurs).');
  end if;
  new_token := md5(random()::text || clock_timestamp()::text || seat_count::text);
  insert into yams.players (room_code, seat, name, token, scores)
  values (
    room.code,
    seat_count,
    left(coalesce(nullif(btrim(p_name), ''), 'Joueur ' || (seat_count + 1)), 24),
    new_token,
    yams.empty_scores()
  );
  update yams.rooms set revision = revision + 1, seen = now() where code = room.code;
  return yams.room_state(room.code, new_token);
end;
$$;

create or replace function public.yams_state(p_code text, p_token text)
returns jsonb
language plpgsql
security definer
set search_path = yams, public
as $$
declare
  result jsonb;
begin
  perform yams.purge_old();
  result := yams.room_state(upper(coalesce(p_code, '')), coalesce(p_token, ''));
  if (result->>'ok')::boolean then
    update yams.rooms set seen = now() where code = upper(p_code);
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
begin
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
  update yams.rooms
    set dice = next_dice, held = hold, rolls = rolls + 1, seen = now(), revision = revision + 1
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
  points integer;
  stored text;
begin
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
  if not coalesce(p_manual, false) and room.rolls < 1 then
    return jsonb_build_object('ok', false, 'error', 'Lance les dés avant de marquer.');
  end if;
  if p_cat not in ('as','deux','trois','quatre','cinq','six','brelan','carre','full','petite','grande','yams','chance') then
    return jsonb_build_object('ok', false, 'error', 'Case inconnue.');
  end if;
  if coalesce(player.scores->>p_cat, '') <> '' then
    return jsonb_build_object('ok', false, 'error', 'Cette case est déjà jouée.');
  end if;
  if coalesce(p_manual, false) then
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
    set scores = jsonb_set(scores, array[p_cat], to_jsonb(stored))
    where room_code = room.code and seat = player.seat;
  perform yams.advance(room.code);
  return yams.room_state(room.code, p_token);
end;
$$;

create or replace function public.yams_rename(p_code text, p_token text, p_name text)
returns jsonb
language plpgsql
security definer
set search_path = yams, public
as $$
declare
  room yams.rooms%rowtype;
  player yams.players%rowtype;
  next_name text;
begin
  select * into room from yams.rooms where code = upper(coalesce(p_code, '')) for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Table introuvable.');
  end if;
  select * into player from yams.players where room_code = room.code and token = coalesce(p_token, '');
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Joueur inconnu sur cette table.');
  end if;
  next_name := left(coalesce(nullif(btrim(p_name), ''), 'Joueur ' || (player.seat + 1)), 24);
  update yams.players set name = next_name where room_code = room.code and seat = player.seat;
  update yams.rooms set revision = revision + 1, seen = now() where code = room.code;
  return yams.room_state(room.code, p_token);
end;
$$;

revoke all on function public.yams_create_room(text) from public;
revoke all on function public.yams_rename(text, text, text) from public;
revoke all on function public.yams_join_room(text, text, text) from public;
revoke all on function public.yams_state(text, text) from public;
revoke all on function public.yams_roll(text, text, boolean[]) from public;
revoke all on function public.yams_score(text, text, text, boolean, text, boolean) from public;

grant execute on function public.yams_create_room(text) to anon, authenticated;
grant execute on function public.yams_rename(text, text, text) to anon, authenticated;
grant execute on function public.yams_join_room(text, text, text) to anon, authenticated;
grant execute on function public.yams_state(text, text) to anon, authenticated;
grant execute on function public.yams_roll(text, text, boolean[]) to anon, authenticated;
grant execute on function public.yams_score(text, text, text, boolean, text, boolean) to anon, authenticated;
