-- Triomino : 56 tuiles. Chacun choisit ses tuiles dans la pioche,
-- à tour de rôle, puis une tuile de départ. La plus forte est posée
-- au centre et désigne qui commence. Les autres retournent dans la pioche.
-- À coller tel quel dans l'éditeur SQL.

create or replace function arcade.trio_set()
returns jsonb
language plpgsql
immutable
as $$
declare
  v_set jsonb := '[]'::jsonb;
  v_a integer;
  v_b integer;
  v_c integer;
begin
  for v_a in 0..5 loop
    for v_b in v_a..5 loop
      for v_c in v_b..5 loop
        v_set := v_set || jsonb_build_array(jsonb_build_array(v_a, v_b, v_c));
      end loop;
    end loop;
  end loop;
  return v_set;
end;
$$;

create or replace function arcade.trio_verts(p_q integer, p_r integer, p_up boolean)
returns text[]
language sql
immutable
as $$
  select case when p_up then
    array[p_q::text || ',' || p_r::text, (p_q + 1)::text || ',' || p_r::text, p_q::text || ',' || (p_r + 1)::text]
  else
    array[p_q::text || ',' || (p_r + 1)::text, (p_q + 1)::text || ',' || p_r::text, (p_q + 1)::text || ',' || (p_r + 1)::text]
  end;
$$;

create or replace function arcade.trio_edge(p_a text, p_b text)
returns text
language sql
immutable
as $$
  select case when p_a < p_b then p_a || '|' || p_b else p_b || '|' || p_a end;
$$;

create or replace function arcade.trio_near(p_q integer, p_r integer, p_up boolean)
returns table(nq integer, nr integer, nup boolean)
language sql
immutable
as $$
  select * from (values
    (p_q, p_r - 1, false),
    (p_q, p_r, false),
    (p_q - 1, p_r, false)
  ) as down_cells(nq, nr, nup)
  where p_up
  union all
  select * from (values
    (p_q, p_r + 1, true),
    (p_q + 1, p_r, true),
    (p_q, p_r, true)
  ) as up_cells(nq, nr, nup)
  where not p_up;
$$;

create or replace function arcade.trio_without(p_list jsonb, p_index integer)
returns jsonb
language sql
immutable
as $$
  select coalesce(jsonb_agg(item.value order by item.ord), '[]'::jsonb)
  from (
    select value, ordinality as ord
    from jsonb_array_elements(coalesce(p_list, '[]'::jsonb)) with ordinality
    where ordinality - 1 <> p_index
  ) item;
$$;

create or replace function arcade.trio_sum(p_hand jsonb)
returns integer
language sql
immutable
as $$
  select coalesce(sum((tile.value->>0)::integer + (tile.value->>1)::integer + (tile.value->>2)::integer), 0)::integer
  from jsonb_array_elements(coalesce(p_hand, '[]'::jsonb)) as tile(value);
$$;

create or replace function arcade.trio_better(p_tile jsonb, p_other jsonb)
returns boolean
language plpgsql
immutable
as $$
declare
  v_triple boolean := (p_tile->>0) = (p_tile->>1) and (p_tile->>1) = (p_tile->>2);
  v_other boolean := (p_other->>0) = (p_other->>1) and (p_other->>1) = (p_other->>2);
  v_sum integer := (p_tile->>0)::integer + (p_tile->>1)::integer + (p_tile->>2)::integer;
  v_other_sum integer := (p_other->>0)::integer + (p_other->>1)::integer + (p_other->>2)::integer;
  v_max integer := greatest((p_tile->>0)::integer, (p_tile->>1)::integer, (p_tile->>2)::integer);
  v_other_max integer := greatest((p_other->>0)::integer, (p_other->>1)::integer, (p_other->>2)::integer);
begin
  if v_triple <> v_other then
    return v_triple;
  end if;
  if v_triple and (p_tile->>0)::integer <> (p_other->>0)::integer then
    return (p_tile->>0)::integer > (p_other->>0)::integer;
  end if;
  if v_sum <> v_other_sum then
    return v_sum > v_other_sum;
  end if;
  if v_max <> v_other_max then
    return v_max > v_other_max;
  end if;
  return false;
end;
$$;

create or replace function arcade.trio_place(p_placed jsonb, p_q integer, p_r integer, p_up boolean, p_tile jsonb, p_rot integer)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_item jsonb;
  v_verts text[];
  v_rot integer;
  v_tile jsonb;
  v_corner integer;
  v_key text;
  v_number integer;
  v_values jsonb := '{}'::jsonb;
  v_counts jsonb := '{}'::jsonb;
  v_edges jsonb := '{}'::jsonb;
  v_new text[];
  v_edge text;
  v_shared integer := 0;
  v_shared_at integer := -1;
  v_missing integer;
  v_bridge boolean := false;
  v_hex integer := 0;
  v_sum integer;
  v_bonus integer;
begin
  if exists (
    select 1 from jsonb_array_elements(coalesce(p_placed, '[]'::jsonb)) as item(value)
    where (item.value->>'q')::integer = p_q
      and (item.value->>'r')::integer = p_r
      and coalesce((item.value->>'up')::boolean, false) = p_up
  ) then
    return null;
  end if;
  if jsonb_array_length(coalesce(p_placed, '[]'::jsonb)) = 0 then
    if p_q is distinct from 0 or p_r is distinct from 0 or p_up is distinct from true then
      return null;
    end if;
    v_sum := (p_tile->>0)::integer + (p_tile->>1)::integer + (p_tile->>2)::integer;
    return jsonb_build_object('points', v_sum, 'bonus', 0, 'bridge', false, 'hex', 0, 'sum', v_sum);
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(p_placed, '[]'::jsonb)) loop
    v_verts := arcade.trio_verts((v_item->>'q')::integer, (v_item->>'r')::integer, coalesce((v_item->>'up')::boolean, false));
    v_tile := v_item->'tile';
    v_rot := coalesce((v_item->>'rot')::integer, 0);
    for v_corner in 0..2 loop
      v_key := v_verts[v_corner + 1];
      v_number := (v_tile->>((v_corner - v_rot + 3) % 3))::integer;
      v_values := jsonb_set(v_values, array[v_key], to_jsonb(v_number), true);
      v_counts := jsonb_set(v_counts, array[v_key], to_jsonb(coalesce((v_counts->>v_key)::integer, 0) + 1), true);
    end loop;
    v_edges := jsonb_set(v_edges, array[arcade.trio_edge(v_verts[1], v_verts[2])], 'true'::jsonb, true);
    v_edges := jsonb_set(v_edges, array[arcade.trio_edge(v_verts[2], v_verts[3])], 'true'::jsonb, true);
    v_edges := jsonb_set(v_edges, array[arcade.trio_edge(v_verts[3], v_verts[1])], 'true'::jsonb, true);
  end loop;
  v_new := arcade.trio_verts(p_q, p_r, p_up);
  for v_corner in 0..2 loop
    v_key := v_new[v_corner + 1];
    v_number := (p_tile->>((v_corner - p_rot + 3) % 3))::integer;
    if v_values ? v_key and (v_values->>v_key)::integer <> v_number then
      return null;
    end if;
  end loop;
  foreach v_edge in array array[
    arcade.trio_edge(v_new[1], v_new[2]),
    arcade.trio_edge(v_new[2], v_new[3]),
    arcade.trio_edge(v_new[3], v_new[1])
  ] loop
    if v_edges ? v_edge then
      v_shared := v_shared + 1;
      v_shared_at := case v_edge
        when arcade.trio_edge(v_new[1], v_new[2]) then 0
        when arcade.trio_edge(v_new[2], v_new[3]) then 1
        else 2
      end;
    end if;
  end loop;
  if v_shared < 1 then
    return null;
  end if;
  v_missing := case v_shared_at when 0 then 2 when 1 then 0 else 1 end;
  v_bridge := v_shared = 1 and (v_values ? v_new[v_missing + 1]);
  for v_corner in 0..2 loop
    v_key := v_new[v_corner + 1];
    if coalesce((v_counts->>v_key)::integer, 0) + 1 = 6 then
      v_hex := v_hex + 1;
    end if;
  end loop;
  v_sum := (p_tile->>0)::integer + (p_tile->>1)::integer + (p_tile->>2)::integer;
  v_bonus := (case when v_bridge then 40 else 0 end)
    + (case v_hex when 1 then 50 when 2 then 60 when 3 then 70 else 0 end);
  return jsonb_build_object('points', v_sum + v_bonus, 'bonus', v_bonus, 'bridge', v_bridge, 'hex', v_hex, 'sum', v_sum);
end;
$$;

create or replace function arcade.trio_can(p_placed jsonb, p_tile jsonb)
returns boolean
language sql
stable
as $$
  select case
    when jsonb_array_length(coalesce(p_placed, '[]'::jsonb)) = 0 then true
    else exists (
      select 1
      from jsonb_array_elements(coalesce(p_placed, '[]'::jsonb)) as item(value)
      cross join lateral arcade.trio_near((item.value->>'q')::integer, (item.value->>'r')::integer, coalesce((item.value->>'up')::boolean, false)) as near
      cross join generate_series(0, 2) as rot(value)
      where arcade.trio_place(p_placed, near.nq, near.nr, near.nup, p_tile, rot.value) is not null
    )
  end;
$$;

create or replace function arcade.trio_hand_can(p_placed jsonb, p_hand jsonb)
returns boolean
language sql
stable
as $$
  select exists (
    select 1
    from jsonb_array_elements(coalesce(p_hand, '[]'::jsonb)) as tile(value)
    where arcade.trio_can(p_placed, tile.value)
  );
$$;

create or replace function arcade.trio_finish(p_scores jsonb)
returns integer
language plpgsql
immutable
as $$
declare
  v_best integer;
  v_count integer;
  v_seat integer := -1;
  v_value integer;
  v_index integer := 0;
begin
  select max(score.value::integer) into v_best
  from jsonb_array_elements(p_scores) as score(value);
  select count(*) into v_count
  from jsonb_array_elements(p_scores) as score(value)
  where score.value::integer = v_best;
  if v_count <> 1 then
    return -1;
  end if;
  for v_value in select score.value::integer from jsonb_array_elements(p_scores) as score(value) loop
    if v_value = v_best then
      v_seat := v_index;
    end if;
    v_index := v_index + 1;
  end loop;
  return v_seat;
end;
$$;

create or replace function arcade.trio_advance(p_board jsonb, p_secret jsonb, p_turn integer, p_humans integer)
returns jsonb
language plpgsql
stable
as $$
declare
  v_board jsonb := p_board;
  v_turn integer := p_turn;
  v_step integer;
  v_values integer[];
  v_lowest integer;
  v_seats integer := 0;
  v_seat integer;
  v_chosen integer := -1;
  v_others integer;
  v_gain integer := 0;
  v_score integer;
begin
  v_board := jsonb_set(v_board, '{draws}', '0'::jsonb);
  v_board := v_board - 'must';
  if jsonb_array_length(coalesce(p_secret->'pile', '[]'::jsonb)) > 0 then
    return jsonb_build_object(
      'board', v_board,
      'secret', p_secret,
      'phase', 'play',
      'turn', (v_turn + 1) % p_humans,
      'winner', null
    );
  end if;
  for v_step in 1..p_humans loop
    v_turn := (v_turn + 1) % p_humans;
    if arcade.trio_hand_can(coalesce(v_board->'placed', '[]'::jsonb), p_secret->'hands'->v_turn) then
      return jsonb_build_object('board', v_board, 'secret', p_secret, 'phase', 'play', 'turn', v_turn, 'winner', null);
    end if;
  end loop;
  v_values := array[]::integer[];
  for v_step in 0..p_humans - 1 loop
    v_values := v_values || arcade.trio_sum(p_secret->'hands'->v_step);
  end loop;
  v_lowest := v_values[1];
  foreach v_score in array v_values loop
    if v_score < v_lowest then
      v_lowest := v_score;
    end if;
  end loop;
  for v_step in 1..p_humans loop
    if v_values[v_step] = v_lowest then
      v_seats := v_seats + 1;
      v_chosen := v_step - 1;
    end if;
  end loop;
  if v_seats <> 1 then
    v_chosen := -1;
  else
    v_others := 0;
    foreach v_score in array v_values loop
      v_others := v_others + v_score;
    end loop;
    v_others := v_others - v_values[v_chosen + 1];
    v_gain := v_others - v_values[v_chosen + 1];
    v_score := coalesce((v_board->'scores'->>v_chosen)::integer, 0) + v_gain;
    v_board := jsonb_set(v_board, array['scores', v_chosen::text], to_jsonb(v_score));
  end if;
  v_board := jsonb_set(v_board, '{last}', jsonb_build_object(
    'seat', v_chosen, 'kind', 'block', 'gain', v_gain, 'bridge', false, 'hex', 0, 'bonus', 0
  ));
  return jsonb_build_object(
    'board', v_board,
    'secret', p_secret,
    'phase', 'done',
    'turn', v_turn,
    'winner', arcade.trio_finish(v_board->'scores')
  );
end;
$$;

create or replace function arcade.trio_deal(p_humans integer)
returns jsonb
language plpgsql
volatile
as $$
declare
  v_humans integer := greatest(2, least(5, coalesce(p_humans, 2)));
  v_each integer := case when v_humans = 2 then 9 else 7 end;
  v_deck jsonb;
  v_hands jsonb := '[]'::jsonb;
  v_starters jsonb := '[]'::jsonb;
  v_scores jsonb := '[]'::jsonb;
  v_seat integer;
begin
  select coalesce(jsonb_agg(tile.value order by random()), '[]'::jsonb) into v_deck
  from jsonb_array_elements(arcade.trio_set()) as tile(value);
  for v_seat in 0..v_humans - 1 loop
    v_hands := v_hands || jsonb_build_array('[]'::jsonb);
    v_starters := v_starters || jsonb_build_array('null'::jsonb);
    v_scores := v_scores || '0'::jsonb;
  end loop;
  return jsonb_build_object(
    'board', jsonb_build_object(
      'placed', '[]'::jsonb,
      'scores', v_scores,
      'draws', 0,
      'deal', 'hand',
      'need', v_each
    ),
    'secret', jsonb_build_object('hands', v_hands, 'pile', v_deck, 'starters', v_starters),
    'phase', 'deal',
    'turn', 0
  );
end;
$$;

create or replace function arcade.trio_pick(
  p_board jsonb,
  p_secret jsonb,
  p_seat integer,
  p_humans integer,
  p_payload jsonb
)
returns jsonb
language plpgsql
volatile
as $$
declare
  v_board jsonb := p_board;
  v_secret jsonb := p_secret;
  v_pile jsonb := coalesce(p_secret->'pile', '[]'::jsonb);
  v_hands jsonb := coalesce(p_secret->'hands', '[]'::jsonb);
  v_starters jsonb := coalesce(p_secret->'starters', '[]'::jsonb);
  v_need integer := coalesce((p_board->>'need')::integer, 0);
  v_deal text := coalesce(p_board->>'deal', 'hand');
  v_indexes jsonb := coalesce(p_payload->'indexes', '[]'::jsonb);
  v_count integer;
  v_index integer;
  v_seen text[] := array[]::text[];
  v_tile jsonb;
  v_hand jsonb;
  v_seat integer;
  v_best integer := 0;
  v_next integer;
  v_open jsonb;
begin
  select count(*)::integer into v_count from jsonb_array_elements(v_indexes);
  if v_deal not in ('hand', 'start') or v_count <> v_need or v_need < 1 then
    return jsonb_build_object('error', case when v_need = 1 then 'Choisis une tuile.' else 'Choisis ' || v_need || ' tuiles.' end);
  end if;
  v_hand := coalesce(v_hands->p_seat, '[]'::jsonb);
  for v_index in
    select (item.value::text)::integer
    from jsonb_array_elements(v_indexes) as item(value)
    order by 1 desc
  loop
    if v_index::text = any (v_seen) or v_index < 0 or v_index >= jsonb_array_length(v_pile) then
      return jsonb_build_object('error', 'Tuile invalide.');
    end if;
    v_seen := v_seen || v_index::text;
    v_tile := v_pile->v_index;
    v_pile := arcade.trio_without(v_pile, v_index);
    if v_deal = 'hand' then
      v_hand := v_hand || jsonb_build_array(v_tile);
    end if;
  end loop;
  v_next := (p_seat + 1) % greatest(p_humans, 1);
  v_secret := jsonb_set(v_secret, '{pile}', v_pile);
  if v_deal = 'hand' then
    v_secret := jsonb_set(v_secret, array['hands', p_seat::text], v_hand);
    if v_next = 0 then
      v_board := jsonb_set(v_board, '{deal}', '"start"'::jsonb);
      v_board := jsonb_set(v_board, '{need}', '1'::jsonb);
    end if;
    return jsonb_build_object('error', '', 'board', v_board, 'secret', v_secret, 'phase', 'deal', 'turn', v_next, 'winner', null);
  end if;
  v_starters := jsonb_set(v_starters, array[p_seat::text], v_tile);
  v_secret := jsonb_set(v_secret, '{starters}', v_starters);
  if v_next <> 0 then
    return jsonb_build_object('error', '', 'board', v_board, 'secret', v_secret, 'phase', 'deal', 'turn', v_next, 'winner', null);
  end if;
  for v_seat in 1..p_humans - 1 loop
    if arcade.trio_better(v_starters->v_seat, v_starters->v_best) then
      v_best := v_seat;
    end if;
  end loop;
  v_open := v_starters->v_best;
  for v_seat in 0..p_humans - 1 loop
    if v_seat <> v_best then
      v_pile := v_pile || jsonb_build_array(v_starters->v_seat);
    end if;
  end loop;
  select coalesce(jsonb_agg(tile.value order by random()), '[]'::jsonb) into v_pile
  from jsonb_array_elements(v_pile) as tile(value);
  v_board := jsonb_set(v_board, '{placed}', jsonb_build_array(jsonb_build_object(
    'q', 0, 'r', 0, 'up', true, 'rot', 0, 'tile', v_open, 'seat', -1
  )));
  v_board := v_board - 'deal' - 'need';
  v_board := jsonb_set(v_board, '{last}', jsonb_build_object(
    'seat', v_best, 'kind', 'start', 'gain', 0, 'tile', v_open,
    'drawn', v_starters, 'bridge', false, 'hex', 0, 'bonus', 0
  ));
  v_secret := jsonb_set(v_secret, '{pile}', v_pile) - 'starters';
  return jsonb_build_object('error', '', 'board', v_board, 'secret', v_secret, 'phase', 'play', 'turn', v_best, 'winner', null);
end;
$$;

create or replace function arcade.trio_act(
  p_board jsonb,
  p_secret jsonb,
  p_seat integer,
  p_humans integer,
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
    if arcade.trio_can(coalesce(v_board->'placed', '[]'::jsonb), v_tile) then
      v_board := jsonb_set(v_board, '{must}', v_tile);
      v_board := jsonb_set(v_board, '{last}', jsonb_build_object(
        'seat', v_actor, 'kind', 'draw', 'gain', -5, 'tile', v_tile, 'bridge', false, 'hex', 0, 'bonus', 0
      ));
      return jsonb_build_object('error', '', 'board', v_board, 'secret', v_secret, 'phase', 'play', 'turn', p_seat, 'winner', null);
    end if;
    if v_draws >= 3 then
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

create or replace function arcade.known_game(p_game text)
returns boolean
language sql
immutable
as $$
  select lower(coalesce(p_game, '')) in ('morpion', 'mastermind', 'mines', 'triomino');
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
  elsif v_room.game = 'triomino' and p_action in ('play', 'draw') then
    if v_room.phase <> 'play' or v_room.turn_seat <> p_seat then
      return 'Ce n''est pas ton tour.';
    end if;
    v_trio := arcade.trio_act(v_room.board, v_room.secret, p_seat, coalesce((v_room.config->>'humans')::integer, 2), p_action, coalesce(p_payload, '{}'::jsonb));
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
