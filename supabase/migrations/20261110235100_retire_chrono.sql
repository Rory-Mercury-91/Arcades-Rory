-- Retire le chronomètre. À coller tel quel dans l'éditeur SQL.
-- Les anciennes migrations restent en l'état. Les colonnes et la signature
-- de yams_create_room sont conservées : les fonctions actuelles les lisent encore.
-- Le minuteur ne s'arme plus, et une réponse « toujours là » n'inscrit plus de score.

update yams.rooms
set timed = false,
    skip_count = 0,
    timer_phase = 'play',
    deadline = null
where timed
   or deadline is not null
   or timer_phase <> 'play'
   or skip_count <> 0;

create or replace function yams.tick(p_code text)
returns void
language plpgsql
security definer
set search_path = yams, public
as $$
begin
  update yams.rooms
  set timed = false,
      skip_count = 0,
      timer_phase = 'play',
      deadline = null
  where code = upper(coalesce(p_code, ''))
    and (timed or deadline is not null or timer_phase <> 'play' or skip_count <> 0);
end;
$$;

create or replace function yams.arm_timer(p_code text)
returns void
language plpgsql
security definer
set search_path = yams, public
as $$
begin
  perform yams.tick(p_code);
end;
$$;

create or replace function yams.apply_penalty(p_code text)
returns void
language plpgsql
security definer
set search_path = yams, public
as $$
begin
  perform yams.tick(p_code);
end;
$$;

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
  values (new_code, 'lobby', cap, manches, mode, false, coalesce(p_hints, true));
  insert into yams.players (room_code, seat, name, token, scores)
  values (new_code, 0, left(coalesce(nullif(btrim(p_name), ''), 'Joueur 1'), 24), new_token, yams.empty_book(manches));
  return yams.room_state(new_code, new_token);
end;
$$;
