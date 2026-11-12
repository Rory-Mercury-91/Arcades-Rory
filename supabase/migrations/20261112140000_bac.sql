-- Petit Bac : une lettre, neuf catégories, écriture simultanée, puis votes.
-- À coller tel quel dans l'éditeur SQL, après 20261111203000_triomino_libre_pioche.sql.

create or replace function arcade.bac_row()
returns jsonb
language sql
immutable
as $$
  select coalesce(jsonb_agg(''::text order by gs), '[]'::jsonb)
  from generate_series(1, 9) as gs;
$$;

create or replace function arcade.bac_fold(p_text text)
returns text
language plpgsql
immutable
as $$
declare
  v text := lower(coalesce(p_text, ''));
begin
  v := replace(v, 'œ', 'oe');
  v := replace(v, 'æ', 'ae');
  v := translate(v, 'àáâäãåçèéêëìíîïñòóôöõùúûüýÿ', 'aaaaaaceeeeiiiinooooouuuuyy');
  v := regexp_replace(v, '[''’`´]', ' ', 'g');
  v := regexp_replace(v, '[-_/.,]', ' ', 'g');
  v := regexp_replace(v, '\s+', ' ', 'g');
  return trim(v);
end;
$$;

create or replace function arcade.bac_key(p_text text)
returns text
language plpgsql
immutable
as $$
declare
  v text := arcade.bac_fold(p_text);
begin
  v := regexp_replace(v, '^(le|la|les|un|une|des|de|l|d) ', '');
  if length(v) > 3 and right(v, 3) = 'aux' then
    v := left(v, length(v) - 3) || 'al';
  elsif length(v) > 1 and right(v, 1) = 'x' then
    v := left(v, length(v) - 1);
  elsif length(v) > 1 and right(v, 1) = 's' and right(v, 2) <> 'ss' then
    v := left(v, length(v) - 1);
  end if;
  return v;
end;
$$;

create or replace function arcade.bac_read_row(p_answers jsonb)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_row jsonb := '[]'::jsonb;
  v_i integer;
  v_text text;
begin
  for v_i in 0..8 loop
    v_text := left(trim(regexp_replace(coalesce(p_answers->>v_i, ''), '\s+', ' ', 'g')), 48);
    v_row := v_row || to_jsonb(coalesce(v_text, ''));
  end loop;
  return v_row;
end;
$$;

create or replace function arcade.bac_filled(p_row jsonb)
returns boolean
language sql
immutable
as $$
  select not exists (
    select 1
    from jsonb_array_elements_text(coalesce(p_row, '[]'::jsonb)) as word
    where coalesce(word, '') = ''
  )
  and jsonb_array_length(coalesce(p_row, '[]'::jsonb)) = 9;
$$;

create or replace function arcade.bac_pick(p_used jsonb)
returns text
language plpgsql
volatile
as $$
declare
  v_pool text;
  v_letter text;
begin
  select string_agg(ch, '')
    into v_pool
  from unnest(string_to_array('ABCDEFGHIJLMNOPQRSTUVZ', null)) as ch
  where not coalesce(p_used, '[]'::jsonb) @> to_jsonb(ch);
  if coalesce(v_pool, '') = '' then
    v_pool := 'ABCDEFGHIJLMNOPQRSTUVZ';
  end if;
  v_letter := substr(v_pool, 1 + floor(random() * length(v_pool))::integer, 1);
  return v_letter;
end;
$$;

create or replace function arcade.bac_flags(p_humans integer, p_value boolean)
returns jsonb
language sql
immutable
as $$
  select coalesce(jsonb_agg(p_value order by gs), '[]'::jsonb)
  from generate_series(1, greatest(p_humans, 0)) as gs;
$$;

create or replace function arcade.bac_zeros(p_humans integer)
returns jsonb
language sql
immutable
as $$
  select coalesce(jsonb_agg(0 order by gs), '[]'::jsonb)
  from generate_series(1, greatest(p_humans, 0)) as gs;
$$;

create or replace function arcade.bac_open(p_humans integer, p_rounds integer, p_used jsonb default '[]'::jsonb, p_scores jsonb default null)
returns jsonb
language plpgsql
volatile
as $$
declare
  v_humans integer := greatest(2, least(5, coalesce(p_humans, 2)));
  v_rounds integer := greatest(3, least(8, coalesce(p_rounds, 5)));
  v_letter text := arcade.bac_pick(coalesce(p_used, '[]'::jsonb));
  v_used jsonb := coalesce(p_used, '[]'::jsonb) || jsonb_build_array(v_letter);
  v_answers jsonb;
  v_ballots jsonb;
  v_round integer := jsonb_array_length(coalesce(p_used, '[]'::jsonb)) + 1;
begin
  select coalesce(jsonb_agg(arcade.bac_row() order by gs), '[]'::jsonb)
    into v_answers
  from generate_series(1, v_humans) as gs;
  select coalesce(jsonb_agg('{}'::jsonb order by gs), '[]'::jsonb)
    into v_ballots
  from generate_series(1, v_humans) as gs;
  return jsonb_build_object(
    'board', jsonb_build_object(
      'letter', v_letter,
      'round', v_round,
      'rounds', v_rounds,
      'used', v_used,
      'scores', coalesce(p_scores, arcade.bac_zeros(v_humans)),
      'gained', arcade.bac_zeros(v_humans),
      'submitted', arcade.bac_flags(v_humans, false),
      'voted', arcade.bac_flags(v_humans, false),
      'step', 'write'
    ),
    'secret', jsonb_build_object(
      'answers', v_answers,
      'ballots', v_ballots
    )
  );
end;
$$;

create or replace function arcade.bac_phase(p_step text)
returns text
language sql
immutable
as $$
  select case p_step
    when 'vote' then 'vote'
    when 'show' then 'show'
    when 'done' then 'done'
    else 'play'
  end;
$$;

create or replace function arcade.bac_all(p_flags jsonb)
returns boolean
language sql
immutable
as $$
  select coalesce(p_flags, '[]'::jsonb) <> '[]'::jsonb
    and not exists (
      select 1
      from jsonb_array_elements(p_flags) as item(value)
      where item.value = 'false'::jsonb
    );
$$;

create or replace function arcade.bac_tally(p_answers jsonb, p_ballots jsonb, p_humans integer)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_cat integer;
  v_seat integer;
  v_other integer;
  v_text text;
  v_key text;
  v_yes integer;
  v_no integer;
  v_ok integer;
  v_gain integer;
  v_points integer[] := array_fill(0, array[p_humans]);
  v_marks jsonb := '[]'::jsonb;
  v_row jsonb;
  v_item jsonb;
  v_accepted boolean;
  v_group jsonb;
begin
  for v_seat in 0..p_humans - 1 loop
    v_row := '[]'::jsonb;
    for v_cat in 0..8 loop
      v_row := v_row || jsonb_build_array(jsonb_build_object('text', '', 'points', 0, 'accepted', false, 'key', ''));
    end loop;
    v_marks := v_marks || jsonb_build_array(v_row);
  end loop;

  for v_cat in 0..8 loop
    v_group := '{}'::jsonb;
    v_ok := 0;
    for v_seat in 0..p_humans - 1 loop
      v_text := trim(coalesce(p_answers->v_seat->>v_cat, ''));
      if v_text = '' then
        v_marks := jsonb_set(v_marks, array[v_seat::text, v_cat::text], jsonb_build_object(
          'text', '', 'points', 0, 'accepted', false, 'key', ''
        ));
        continue;
      end if;
      v_yes := 0;
      v_no := 0;
      for v_other in 0..p_humans - 1 loop
        if v_other = v_seat then
          continue;
        end if;
        if coalesce(p_ballots->v_other->> (v_seat::text || ':' || v_cat::text), '') = 'v' then
          v_yes := v_yes + 1;
        elsif coalesce(p_ballots->v_other->> (v_seat::text || ':' || v_cat::text), '') = 'x' then
          v_no := v_no + 1;
        end if;
      end loop;
      v_accepted := not (v_no > v_yes);
      v_key := arcade.bac_key(v_text);
      v_marks := jsonb_set(v_marks, array[v_seat::text, v_cat::text], jsonb_build_object(
        'text', v_text, 'points', 0, 'accepted', v_accepted, 'key', v_key
      ));
      if v_accepted then
        v_ok := v_ok + 1;
        v_group := jsonb_set(
          v_group,
          array[v_key],
          coalesce(v_group->v_key, '[]'::jsonb) || jsonb_build_array(v_seat)
        );
      end if;
    end loop;
    if v_ok = 1 then
      for v_seat in 0..p_humans - 1 loop
        if coalesce((v_marks->v_seat->v_cat->>'accepted')::boolean, false) then
          v_marks := jsonb_set(v_marks, array[v_seat::text, v_cat::text, 'points'], to_jsonb(15));
          v_points[v_seat + 1] := v_points[v_seat + 1] + 15;
        end if;
      end loop;
    else
      for v_key in select jsonb_object_keys(v_group)
      loop
        v_gain := case when jsonb_array_length(v_group->v_key) >= 2 then 5 else 10 end;
        for v_item in select value from jsonb_array_elements(v_group->v_key)
        loop
          v_seat := (v_item #>> '{}')::integer;
          v_marks := jsonb_set(v_marks, array[v_seat::text, v_cat::text, 'points'], to_jsonb(v_gain));
          v_points[v_seat + 1] := v_points[v_seat + 1] + v_gain;
        end loop;
      end loop;
    end if;
  end loop;

  return jsonb_build_object(
    'points', (select coalesce(jsonb_agg(val), '[]'::jsonb) from unnest(v_points) as val),
    'marks', v_marks
  );
end;
$$;

create or replace function arcade.bac_close_write(p_board jsonb, p_secret jsonb, p_humans integer)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_board jsonb := p_board;
  v_secret jsonb := p_secret;
  v_ballots jsonb;
begin
  select coalesce(jsonb_agg('{}'::jsonb order by gs), '[]'::jsonb)
    into v_ballots
  from generate_series(1, p_humans) as gs;
  v_board := jsonb_set(v_board, '{submitted}', arcade.bac_flags(p_humans, true));
  v_board := jsonb_set(v_board, '{voted}', arcade.bac_flags(p_humans, false));
  v_board := jsonb_set(v_board, '{step}', to_jsonb('vote'::text));
  v_board := v_board - 'stopAt';
  v_secret := jsonb_set(v_secret, '{ballots}', v_ballots);
  return jsonb_build_object('board', v_board, 'secret', v_secret);
end;
$$;

create or replace function arcade.bac_maybe_close(p_board jsonb, p_secret jsonb, p_humans integer)
returns jsonb
language plpgsql
stable
as $$
declare
  v_now bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
  v_stop bigint;
begin
  if coalesce(p_board->>'step', 'write') <> 'write' then
    return null;
  end if;
  v_stop := (p_board->>'stopAt')::bigint;
  if arcade.bac_all(p_board->'submitted') or (v_stop is not null and v_now >= v_stop) then
    return arcade.bac_close_write(p_board, p_secret, p_humans);
  end if;
  return null;
end;
$$;

create or replace function arcade.bac_finish(p_board jsonb, p_secret jsonb, p_humans integer)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_board jsonb := p_board;
  v_tally jsonb := arcade.bac_tally(p_secret->'answers', p_secret->'ballots', p_humans);
  v_points jsonb := v_tally->'points';
  v_seat integer;
  v_score integer;
  v_best integer := -1;
  v_tops integer := 0;
  v_winner integer := -1;
  v_round integer := coalesce((p_board->>'round')::integer, 1);
  v_rounds integer := coalesce((p_board->>'rounds')::integer, 5);
begin
  v_board := jsonb_set(v_board, '{gained}', v_points);
  v_board := jsonb_set(v_board, '{marks}', v_tally->'marks');
  for v_seat in 0..p_humans - 1 loop
    v_score := coalesce((v_board->'scores'->>v_seat)::integer, 0) + coalesce((v_points->>v_seat)::integer, 0);
    v_board := jsonb_set(v_board, array['scores', v_seat::text], to_jsonb(v_score));
    if v_score > v_best then
      v_best := v_score;
      v_tops := 1;
      v_winner := v_seat;
    elsif v_score = v_best then
      v_tops := v_tops + 1;
    end if;
  end loop;
  if v_round >= v_rounds then
    v_board := jsonb_set(v_board, '{step}', to_jsonb('done'::text));
    if v_tops <> 1 then
      v_winner := -1;
    end if;
    return jsonb_build_object('board', v_board, 'winner', v_winner);
  end if;
  v_board := jsonb_set(v_board, '{step}', to_jsonb('show'::text));
  return jsonb_build_object('board', v_board, 'winner', null);
end;
$$;

create or replace function arcade.bac_act(
  p_board jsonb,
  p_secret jsonb,
  p_seat integer,
  p_humans integer,
  p_rounds integer,
  p_action text,
  p_payload jsonb
)
returns jsonb
language plpgsql
volatile
as $$
declare
  v_board jsonb := p_board;
  v_secret jsonb := p_secret;
  v_closed jsonb;
  v_row jsonb;
  v_ballot jsonb := '{}'::jsonb;
  v_key text;
  v_mark text;
  v_parts text[];
  v_other integer;
  v_cat integer;
  v_open jsonb;
  v_done jsonb;
  v_humans integer := greatest(2, least(5, coalesce(p_humans, 2)));
begin
  v_closed := arcade.bac_maybe_close(v_board, v_secret, v_humans);
  if v_closed is not null then
    v_board := v_closed->'board';
    v_secret := v_closed->'secret';
  end if;

  if p_action = 'tick' then
    return jsonb_build_object(
      'error', '',
      'board', v_board,
      'secret', v_secret,
      'phase', arcade.bac_phase(v_board->>'step'),
      'turn', 0,
      'winner', null
    );
  end if;

  if p_action in ('draft', 'submit', 'stop') then
    if coalesce(v_board->>'step', 'write') <> 'write' then
      return jsonb_build_object('error', 'Ce n''est plus le moment d''écrire.');
    end if;
    if p_seat < 0 or p_seat >= v_humans then
      return jsonb_build_object('error', 'Joueur inconnu.');
    end if;
    if coalesce((v_board->'submitted'->>p_seat)::boolean, false) then
      return jsonb_build_object('error', 'Tes réponses sont déjà validées.');
    end if;
    v_row := arcade.bac_read_row(p_payload->'answers');
    v_secret := jsonb_set(v_secret, array['answers', p_seat::text], v_row);
    if p_action = 'draft' then
      return jsonb_build_object(
        'error', '',
        'board', v_board,
        'secret', v_secret,
        'phase', 'play',
        'turn', 0,
        'winner', null
      );
    end if;
    if p_action = 'stop' then
      if not arcade.bac_filled(v_row) then
        return jsonb_build_object('error', 'Remplis toutes les catégories pour crier stop.');
      end if;
      if v_board->>'stopAt' is null then
        v_board := jsonb_set(
          v_board,
          '{stopAt}',
          to_jsonb((extract(epoch from clock_timestamp() + interval '60 seconds') * 1000)::bigint)
        );
      end if;
    end if;
    v_board := jsonb_set(v_board, array['submitted', p_seat::text], 'true'::jsonb);
    v_closed := arcade.bac_maybe_close(v_board, v_secret, v_humans);
    if v_closed is not null then
      v_board := v_closed->'board';
      v_secret := v_closed->'secret';
    end if;
    return jsonb_build_object(
      'error', '',
      'board', v_board,
      'secret', v_secret,
      'phase', arcade.bac_phase(v_board->>'step'),
      'turn', 0,
      'winner', null
    );
  end if;

  if p_action = 'vote' then
    if coalesce(v_board->>'step', '') <> 'vote' then
      return jsonb_build_object('error', 'Ce n''est plus le moment de voter.');
    end if;
    if p_seat < 0 or p_seat >= v_humans then
      return jsonb_build_object('error', 'Joueur inconnu.');
    end if;
    if coalesce((v_board->'voted'->>p_seat)::boolean, false) then
      return jsonb_build_object('error', 'Tes votes sont déjà validés.');
    end if;
    v_row := coalesce(p_payload->'ballot', '{}'::jsonb);
    if jsonb_typeof(v_row) = 'object' then
      for v_key in select jsonb_object_keys(v_row)
      loop
        v_parts := string_to_array(v_key, ':');
        if array_length(v_parts, 1) <> 2 then
          continue;
        end if;
        begin
          v_other := v_parts[1]::integer;
          v_cat := v_parts[2]::integer;
        exception when others then
          continue;
        end;
        if v_other = p_seat or v_other < 0 or v_other >= v_humans or v_cat < 0 or v_cat > 8 then
          continue;
        end if;
        v_mark := v_row->>v_key;
        if v_mark in ('v', 'x') then
          v_ballot := jsonb_set(v_ballot, array[v_other::text || ':' || v_cat::text], to_jsonb(v_mark));
        end if;
      end loop;
    end if;
    v_secret := jsonb_set(v_secret, array['ballots', p_seat::text], v_ballot);
    v_board := jsonb_set(v_board, array['voted', p_seat::text], 'true'::jsonb);
    if arcade.bac_all(v_board->'voted') then
      v_done := arcade.bac_finish(v_board, v_secret, v_humans);
      v_board := v_done->'board';
      return jsonb_build_object(
        'error', '',
        'board', v_board,
        'secret', v_secret,
        'phase', arcade.bac_phase(v_board->>'step'),
        'turn', 0,
        'winner', v_done->'winner'
      );
    end if;
    return jsonb_build_object(
      'error', '',
      'board', v_board,
      'secret', v_secret,
      'phase', 'vote',
      'turn', 0,
      'winner', null
    );
  end if;

  if p_action = 'next' then
    if coalesce(v_board->>'step', '') <> 'show' then
      return jsonb_build_object('error', 'La manche n''est pas terminée.');
    end if;
    v_open := arcade.bac_open(v_humans, coalesce((v_board->>'rounds')::integer, p_rounds), coalesce(v_board->'used', '[]'::jsonb), coalesce(v_board->'scores', arcade.bac_zeros(v_humans)));
    return jsonb_build_object(
      'error', '',
      'board', v_open->'board',
      'secret', v_open->'secret',
      'phase', 'play',
      'turn', 0,
      'winner', null
    );
  end if;

  return jsonb_build_object('error', 'Coup inconnu.');
end;
$$;

create or replace function arcade.known_game(p_game text)
returns boolean
language sql
immutable
as $$
  select lower(coalesce(p_game, '')) in ('morpion', 'mastermind', 'mines', 'triomino', 'bac');
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
  end if;
  return '{}'::jsonb;
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
    elsif v_room.game = 'bac' then
      v_bac := arcade.bac_open(coalesce((v_room.config->>'humans')::integer, 2), coalesce((v_room.config->>'rounds')::integer, 5));
      v_room.board := v_bac->'board';
      v_room.secret := v_bac->'secret';
      v_room.phase := 'play';
      v_room.turn_seat := 0;
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
