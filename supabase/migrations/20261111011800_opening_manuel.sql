-- Chacun lance son dé de départ. À coller tel quel dans l'éditeur SQL.

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
  v_code text;
  seats integer[];
  players_here integer;
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
  select coalesce(array_agg(players.seat order by players.seat), '{}'), count(*)::integer
    into seats, players_here
  from yams.players as players
  where players.room_code = v_code;
  if players_here <= 1 then
    update yams.rooms as rooms
      set phase = 'play',
          opening = array[0, 0, 0, 0, 0],
          seat_order = seats,
          turn_index = coalesce(seats[1], 0),
          current_manche = 0,
          rolls = 0,
          dice = array[0, 0, 0, 0, 0],
          held = array[false, false, false, false, false],
          seen = now(),
          revision = rooms.revision + 1
      where rooms.code = v_code;
    perform yams.arm_timer(v_code);
    return yams.room_state(v_code, p_token);
  end if;
  update yams.rooms as rooms
    set phase = 'opening',
        opening = array[0, 0, 0, 0, 0],
        seat_order = seats,
        turn_index = seats[1],
        current_manche = 0,
        rolls = 0,
        dice = array[0, 0, 0, 0, 0],
        held = array[false, false, false, false, false],
        deadline = null,
        seen = now(),
        revision = rooms.revision + 1
    where rooms.code = v_code;
  return yams.room_state(v_code, p_token);
exception
  when others then
    return jsonb_build_object('ok', false, 'error', sqlerrm);
end;
$$;

create or replace function public.yams_opening_roll(p_code text, p_token text)
returns jsonb
language plpgsql
security definer
set search_path = yams, public
as $$
#variable_conflict use_column
declare
  room yams.rooms%rowtype;
  you_seat integer;
  faces integer[];
  face integer;
  ord integer[];
  pos integer;
  step integer;
  candidate integer;
  nxt integer;
  v_seat integer;
  pending boolean := false;
  top integer := 0;
  ties integer := 0;
  winner integer;
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
  if room.phase <> 'opening' or you_seat <> room.turn_index then
    return jsonb_build_object('ok', false, 'error', 'Ce n''est pas ton tour.');
  end if;
  faces := room.opening;
  if faces is null or cardinality(faces) < 5 then
    faces := array[0, 0, 0, 0, 0];
  end if;
  if coalesce(faces[you_seat + 1], 0) <> 0 then
    return jsonb_build_object('ok', false, 'error', 'Tu as déjà lancé.');
  end if;
  face := 1 + floor(random() * 6)::integer;
  faces[you_seat + 1] := face;
  ord := room.seat_order;
  if ord is null or cardinality(ord) = 0 then
    select coalesce(array_agg(players.seat order by players.seat), '{}')
      into ord
    from yams.players as players
    where players.room_code = room.code;
  end if;
  for v_seat in select players.seat from yams.players as players where players.room_code = room.code loop
    if coalesce(faces[v_seat + 1], 0) = 0 then
      pending := true;
    end if;
  end loop;
  if pending then
    pos := coalesce(array_position(ord, you_seat), 1);
    nxt := you_seat;
    for step in 1..cardinality(ord) loop
      candidate := ord[((pos - 1 + step) % cardinality(ord)) + 1];
      if coalesce(faces[candidate + 1], 0) = 0 then
        nxt := candidate;
        exit;
      end if;
    end loop;
    update yams.rooms as rooms
      set opening = faces,
          turn_index = nxt,
          seen = now(),
          revision = rooms.revision + 1
      where rooms.code = room.code;
    return yams.room_state(room.code, p_token);
  end if;
  for v_seat in select players.seat from yams.players as players where players.room_code = room.code order by players.seat loop
    if faces[v_seat + 1] > top then
      top := faces[v_seat + 1];
      ties := 1;
      winner := v_seat;
    elsif faces[v_seat + 1] = top then
      ties := ties + 1;
    end if;
  end loop;
  if ties > 1 then
    for v_seat in select players.seat from yams.players as players where players.room_code = room.code loop
      if faces[v_seat + 1] = top then
        faces[v_seat + 1] := 0;
      end if;
    end loop;
    nxt := null;
    foreach candidate in array ord loop
      if coalesce(faces[candidate + 1], 0) = 0 then
        nxt := candidate;
        exit;
      end if;
    end loop;
    update yams.rooms as rooms
      set opening = faces,
          turn_index = coalesce(nxt, you_seat),
          seen = now(),
          revision = rooms.revision + 1
      where rooms.code = room.code;
    return yams.room_state(room.code, p_token);
  end if;
  update yams.rooms as rooms
    set phase = 'play',
        opening = faces,
        seat_order = yams.opening_order(room.code, winner),
        turn_index = winner,
        rolls = 0,
        dice = array[0, 0, 0, 0, 0],
        held = array[false, false, false, false, false],
        seen = now(),
        revision = rooms.revision + 1
    where rooms.code = room.code;
  perform yams.arm_timer(room.code);
  return yams.room_state(room.code, p_token);
exception
  when others then
    return jsonb_build_object('ok', false, 'error', sqlerrm);
end;
$$;

revoke all on function public.yams_opening_roll(text, text) from public;
grant execute on function public.yams_opening_roll(text, text) to anon, authenticated;
