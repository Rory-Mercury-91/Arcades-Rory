-- Mastermind à deux : le joueur qui a posé le code place les indices.
-- Son code reste visible seulement pour lui, jusqu'à la fin de la partie.
-- À coller tel quel dans l'éditeur SQL.

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
      'pending', v_room.board->'pending',
      'secret', case
        when v_room.phase = 'done' then v_room.secret->'code'
        when coalesce((v_room.config->>'bot')::boolean, false) then null
        when v_seat = coalesce((v_room.config->>'maker')::integer, 0) and v_room.phase in ('code', 'play', 'mark') then v_room.secret->'code'
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
