-- Lancement seul, et manche supplementaire. A coller tel quel dans l'editeur SQL.

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

revoke all on function public.yams_state(text, text) from public;
grant execute on function public.yams_state(text, text) to anon, authenticated;

revoke all on function public.yams_start(text, text) from public;
revoke all on function public.yams_add_manche(text, text) from public;
grant execute on function public.yams_start(text, text) to anon, authenticated;
grant execute on function public.yams_add_manche(text, text) to anon, authenticated;
