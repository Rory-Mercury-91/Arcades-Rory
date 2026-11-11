-- Triomino libre : piocher ajoute la tuile à la main, sans l'imposer.
-- On peut repiocher tant qu'on n'a pas posé, trois fois au plus, puis Passer.
-- Le mode guidé continue d'imposer une tuile qui se pose.
-- À coller tel quel dans l'éditeur SQL, après 20261111144500_triomino.sql.

drop function if exists arcade.trio_act(jsonb, jsonb, integer, integer, text, jsonb);

create or replace function arcade.trio_act(
  p_board jsonb,
  p_secret jsonb,
  p_seat integer,
  p_humans integer,
  p_action text,
  p_payload jsonb,
  p_free boolean default false
)
returns jsonb
language plpgsql
volatile
as $$
declare
  v_board jsonb := p_board;
  v_secret jsonb := p_secret;
  v_hand jsonb;
  v_tile jsonb;
  v_index integer;
  v_q integer;
  v_r integer;
  v_up boolean;
  v_rot integer;
  v_info jsonb;
  v_points integer;
  v_gain integer;
  v_kind text;
  v_extra integer;
  v_other integer;
  v_score integer;
  v_draws integer;
  v_pile jsonb;
  v_actor integer := p_seat;
begin
  v_hand := coalesce(v_secret->'hands'->p_seat, '[]'::jsonb);
  if p_action = 'draw' then
    if v_board ? 'must' then
      return jsonb_build_object('error', 'Tu dois d''abord poser la tuile piochée.');
    end if;
    v_draws := coalesce((v_board->>'draws')::integer, 0);
    if v_draws >= 3 then
      return jsonb_build_object('error', 'Trois pioches maximum.');
    end if;
    v_pile := coalesce(v_secret->'pile', '[]'::jsonb);
    if jsonb_array_length(v_pile) = 0 then
      return jsonb_build_object('error', 'La pioche est vide.');
    end if;
    v_index := (p_payload->>'index')::integer;
    if v_index is null then
      v_index := jsonb_array_length(v_pile) - 1;
    end if;
    if v_index < 0 or v_index >= jsonb_array_length(v_pile) then
      return jsonb_build_object('error', 'Cette tuile n''est plus dans la pioche.');
    end if;
    v_tile := v_pile->v_index;
    v_pile := arcade.trio_without(v_pile, v_index);
    v_hand := v_hand || jsonb_build_array(v_tile);
    v_secret := jsonb_set(v_secret, '{pile}', v_pile);
    v_secret := jsonb_set(v_secret, array['hands', p_seat::text], v_hand);
    v_score := coalesce((v_board->'scores'->>p_seat)::integer, 0) - 5;
    v_board := jsonb_set(v_board, array['scores', p_seat::text], to_jsonb(v_score));
    v_draws := v_draws + 1;
    v_board := jsonb_set(v_board, '{draws}', to_jsonb(v_draws));
    if not p_free and arcade.trio_can(coalesce(v_board->'placed', '[]'::jsonb), v_tile) then
      v_board := jsonb_set(v_board, '{must}', v_tile);
      v_board := jsonb_set(v_board, '{last}', jsonb_build_object(
        'seat', v_actor, 'kind', 'draw', 'gain', -5, 'tile', v_tile, 'bridge', false, 'hex', 0, 'bonus', 0
      ));
      return jsonb_build_object('error', '', 'board', v_board, 'secret', v_secret, 'phase', 'play', 'turn', p_seat, 'winner', null);
    end if;
    if not p_free and v_draws >= 3 then
      v_score := coalesce((v_board->'scores'->>p_seat)::integer, 0) - 10;
      v_board := jsonb_set(v_board, array['scores', p_seat::text], to_jsonb(v_score));
      v_board := jsonb_set(v_board, '{last}', jsonb_build_object(
        'seat', v_actor, 'kind', 'pass', 'gain', -25, 'bridge', false, 'hex', 0, 'bonus', 0
      ));
      return arcade.trio_advance(v_board, v_secret, p_seat, p_humans) || jsonb_build_object('error', '');
    end if;
    v_board := jsonb_set(v_board, '{last}', jsonb_build_object(
      'seat', v_actor, 'kind', 'draw', 'gain', -5, 'tile', v_tile, 'bridge', false, 'hex', 0, 'bonus', 0
    ));
    return jsonb_build_object('error', '', 'board', v_board, 'secret', v_secret, 'phase', 'play', 'turn', p_seat, 'winner', null);
  end if;

  if p_action = 'pass' then
    if not p_free then
      return jsonb_build_object('error', 'En mode guidé, le tour passe tout seul.');
    end if;
    if v_board ? 'must' then
      return jsonb_build_object('error', 'Tu dois d''abord poser la tuile piochée.');
    end if;
    v_draws := coalesce((v_board->>'draws')::integer, 0);
    if v_draws < 3 then
      return jsonb_build_object('error', 'Tu peux encore piocher.');
    end if;
    v_score := coalesce((v_board->'scores'->>p_seat)::integer, 0) - 10;
    v_board := jsonb_set(v_board, array['scores', p_seat::text], to_jsonb(v_score));
    v_board := jsonb_set(v_board, '{last}', jsonb_build_object(
      'seat', v_actor, 'kind', 'pass', 'gain', -25, 'bridge', false, 'hex', 0, 'bonus', 0
    ));
    return arcade.trio_advance(v_board, v_secret, p_seat, p_humans) || jsonb_build_object('error', '');
  end if;

  v_index := (p_payload->>'index')::integer;
  v_q := (p_payload->>'q')::integer;
  v_r := (p_payload->>'r')::integer;
  v_rot := (p_payload->>'rot')::integer;
  v_up := coalesce((p_payload->>'up')::boolean, false);
  if v_index is null or v_index < 0 or v_index >= jsonb_array_length(v_hand) then
    return jsonb_build_object('error', 'Cette tuile n''est pas dans ta main.');
  end if;
  if v_rot is null or v_rot < 0 or v_rot > 2 or v_q is null or v_r is null or v_q < -40 or v_q > 40 or v_r < -40 or v_r > 40 then
    return jsonb_build_object('error', 'Emplacement invalide.');
  end if;
  v_tile := v_hand->v_index;
  if v_board ? 'must' and v_tile <> v_board->'must' then
    return jsonb_build_object('error', 'Tu dois poser la tuile piochée.');
  end if;
  v_info := arcade.trio_place(coalesce(v_board->'placed', '[]'::jsonb), v_q, v_r, v_up, v_tile, v_rot);
  if v_info is null then
    return jsonb_build_object('error', 'Cette tuile ne se pose pas ici.');
  end if;
  v_hand := arcade.trio_without(v_hand, v_index);
  v_secret := jsonb_set(v_secret, array['hands', p_seat::text], v_hand);
  v_board := jsonb_set(
    v_board,
    '{placed}',
    coalesce(v_board->'placed', '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
      'q', v_q, 'r', v_r, 'up', v_up, 'rot', v_rot, 'tile', v_tile, 'seat', p_seat
    ))
  );
  v_points := (v_info->>'points')::integer;
  v_score := coalesce((v_board->'scores'->>p_seat)::integer, 0) + v_points;
  v_board := jsonb_set(v_board, array['scores', p_seat::text], to_jsonb(v_score));
  v_gain := v_points;
  v_kind := case
    when jsonb_array_length(coalesce(v_board->'placed', '[]'::jsonb)) = 1 then 'open'
    else 'play'
  end;
  if jsonb_array_length(v_hand) = 0 then
    v_extra := 25;
    for v_other in 0..p_humans - 1 loop
      if v_other <> p_seat then
        v_extra := v_extra + arcade.trio_sum(v_secret->'hands'->v_other);
      end if;
    end loop;
    v_score := coalesce((v_board->'scores'->>p_seat)::integer, 0) + v_extra;
    v_board := jsonb_set(v_board, array['scores', p_seat::text], to_jsonb(v_score));
    v_gain := v_gain + v_extra;
    v_kind := 'out';
  end if;
  v_board := v_board - 'must';
  v_board := jsonb_set(v_board, '{draws}', '0'::jsonb);
  v_board := jsonb_set(v_board, '{last}', jsonb_build_object(
    'seat', v_actor,
    'kind', v_kind,
    'gain', v_gain,
    'tile', v_tile,
    'bridge', coalesce((v_info->>'bridge')::boolean, false),
    'hex', coalesce((v_info->>'hex')::integer, 0),
    'bonus', coalesce((v_info->>'bonus')::integer, 0)
  ));
  if v_kind = 'out' then
    return jsonb_build_object(
      'error', '',
      'board', v_board,
      'secret', v_secret,
      'phase', 'done',
      'turn', p_seat,
      'winner', arcade.trio_finish(v_board->'scores')
    );
  end if;
  return arcade.trio_advance(v_board, v_secret, p_seat, p_humans) || jsonb_build_object('error', '');
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
    elsif v_room.game = 'triomino' then
      v_trio := arcade.trio_deal(coalesce((v_room.config->>'humans')::integer, 2));
      v_room.board := v_trio->'board';
      v_room.secret := v_trio->'secret';
      v_room.phase := coalesce(v_trio->>'phase', 'deal');
      v_room.turn_seat := coalesce((v_trio->>'turn')::integer, 0);
      v_room.winner := null;
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
