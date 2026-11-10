-- À coller dans l'éditeur SQL du projet Supabase de Mangathèque.
-- Corrige le nom après coup, et permet de retrouver sa place avec le même nom.

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

revoke all on function public.yams_join_room(text, text, text) from public;
revoke all on function public.yams_rename(text, text, text) from public;
grant execute on function public.yams_join_room(text, text, text) to anon, authenticated;
grant execute on function public.yams_rename(text, text, text) to anon, authenticated;
