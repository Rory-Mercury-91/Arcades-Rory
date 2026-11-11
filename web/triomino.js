// Triomino : 56 tuiles, trois rotations, pas de retournement.
// L'ordre des chiffres est celui de la tuile, dans le sens des aiguilles d'une montre.
const Trio = (function () {
  const TILES = [];
  for (let a = 0; a <= 5; a += 1) {
    for (let b = a; b <= 5; b += 1) {
      for (let c = b; c <= 5; c += 1) TILES.push([a, b, c]);
    }
  }

  function same(left, right) {
    return !!left && !!right && left[0] === right[0] && left[1] === right[1] && left[2] === right[2];
  }

  function handValue(hand) {
    return hand.reduce((sum, tile) => sum + tile[0] + tile[1] + tile[2], 0);
  }

  function vertices(q, r, up) {
    if (up) return [[q, r], [q + 1, r], [q, r + 1]];
    return [[q, r + 1], [q + 1, r], [q + 1, r + 1]];
  }

  function neighbors(q, r, up) {
    if (up) return [[q, r - 1, false], [q, r, false], [q - 1, r, false]];
    return [[q, r + 1, true], [q + 1, r, true], [q, r, true]];
  }

  function edgeKey(first, second) {
    const left = first[0] + "," + first[1];
    const right = second[0] + "," + second[1];
    return left < right ? left + "|" + right : right + "|" + left;
  }

  function edgesOf(q, r, up) {
    const verts = vertices(q, r, up);
    return [edgeKey(verts[0], verts[1]), edgeKey(verts[1], verts[2]), edgeKey(verts[2], verts[0])];
  }

  function cellKey(q, r, up) {
    return q + "," + r + "," + (up ? 1 : 0);
  }

  function boardIndex(placed) {
    const values = new Map();
    const counts = new Map();
    const edges = new Set();
    const cells = new Set();
    placed.forEach((item) => {
      cells.add(cellKey(item.q, item.r, item.up));
      const verts = vertices(item.q, item.r, item.up);
      verts.forEach((vert, index) => {
        const key = vert[0] + "," + vert[1];
        const number = item.tile[(index - item.rot + 3) % 3];
        values.set(key, number);
        counts.set(key, (counts.get(key) || 0) + 1);
      });
      edgesOf(item.q, item.r, item.up).forEach((edge) => edges.add(edge));
    });
    return { values, counts, edges, cells };
  }

  function candidateCells(placed) {
    const seen = new Set();
    const cells = [];
    placed.forEach((item) => {
      neighbors(item.q, item.r, item.up).forEach(([q, r, up]) => {
        const key = cellKey(q, r, up);
        if (seen.has(key)) return;
        seen.add(key);
        cells.push({ q, r, up });
      });
    });
    return cells;
  }

  // Un pont : un seul côté complet, et le troisième sommet est déjà posé.
  // Un hexagone : six tuiles autour d'un même sommet.
  function placementOn(index, q, r, up, tile, rot) {
    if (index.cells.has(cellKey(q, r, up))) return null;
    const verts = vertices(q, r, up);
    const numbers = [0, 1, 2].map((corner) => tile[(corner - rot + 3) % 3]);
    for (let corner = 0; corner < 3; corner += 1) {
      const key = verts[corner][0] + "," + verts[corner][1];
      const previous = index.values.get(key);
      if (previous != null && previous !== numbers[corner]) return null;
    }
    const edges = edgesOf(q, r, up);
    let shared = 0;
    let sharedAt = -1;
    edges.forEach((edge, corner) => {
      if (index.edges.has(edge)) {
        shared += 1;
        sharedAt = corner;
      }
    });
    if (shared < 1) return null;
    const missing = sharedAt === 0 ? 2 : sharedAt === 1 ? 0 : 1;
    const third = verts[missing][0] + "," + verts[missing][1];
    const bridge = shared === 1 && index.values.has(third);
    let hex = 0;
    verts.forEach((vert) => {
      const key = vert[0] + "," + vert[1];
      if ((index.counts.get(key) || 0) + 1 === 6) hex += 1;
    });
    const sum = tile[0] + tile[1] + tile[2];
    const bonus = (bridge ? 40 : 0) + (hex === 1 ? 50 : hex === 2 ? 60 : hex === 3 ? 70 : 0);
    return { points: sum + bonus, bonus, bridge, hex, sum };
  }

  function firstSpot(tile, rot) {
    const sum = tile[0] + tile[1] + tile[2];
    return { q: 0, r: 0, up: true, rot, points: sum, bonus: 0, bridge: false, hex: 0, sum };
  }

  function placement(placed, q, r, up, tile, rot) {
    if (!placed.length) {
      if (q !== 0 || r !== 0 || !up) return null;
      return firstSpot(tile, rot);
    }
    return placementOn(boardIndex(placed), q, r, up, tile, rot);
  }

  function spots(placed, tile) {
    if (!placed.length) return [0, 1, 2].map((rot) => firstSpot(tile, rot));
    const index = boardIndex(placed);
    const found = [];
    candidateCells(placed).forEach((cell) => {
      for (let rot = 0; rot < 3; rot += 1) {
        const info = placementOn(index, cell.q, cell.r, cell.up, tile, rot);
        if (info) found.push({ q: cell.q, r: cell.r, up: cell.up, rot, ...info });
      }
    });
    found.sort((left, right) => right.points - left.points || left.q - right.q || left.r - right.r || left.rot - right.rot);
    return found;
  }

  function around(placed) {
    if (!placed.length) return [{ q: 0, r: 0, up: true }];
    const taken = boardIndex(placed).cells;
    return candidateCells(placed).filter((cell) => !taken.has(cell.q + "," + cell.r + "," + (cell.up ? 1 : 0)));
  }

  function canPlay(placed, hand) {
    return hand.some((tile) => spots(placed, tile).length > 0);
  }

  function rank(tile) {
    const triple = tile[0] === tile[1] && tile[1] === tile[2];
    return [triple ? 1 : 0, triple ? tile[0] : 0, tile[0] + tile[1] + tile[2], Math.max(tile[0], tile[1], tile[2])];
  }

  function better(tile, other) {
    const left = rank(tile);
    const right = rank(other);
    for (let index = 0; index < left.length; index += 1) {
      if (left[index] !== right[index]) return left[index] > right[index];
    }
    return false;
  }

  function shuffle(list) {
    const copy = list.map((tile) => tile.slice());
    for (let index = copy.length - 1; index > 0; index -= 1) {
      const swap = Math.floor(Math.random() * (index + 1));
      const tile = copy[index];
      copy[index] = copy[swap];
      copy[swap] = tile;
    }
    return copy;
  }

  function finish(state) {
    state.phase = "done";
    state.must = null;
    const best = Math.max(...state.scores);
    const tops = state.scores.filter((score) => score === best);
    state.winner = tops.length === 1 ? state.scores.indexOf(best) : -1;
  }

  function endBlocked(state) {
    const values = state.hands.map(handValue);
    const lowest = Math.min(...values);
    const seats = values.map((value, index) => (value === lowest ? index : -1)).filter((index) => index >= 0);
    let seat = -1;
    let gain = 0;
    if (seats.length === 1) {
      seat = seats[0];
      const others = values.reduce((sum, value) => sum + value, 0) - values[seat];
      gain = others - values[seat];
      state.scores[seat] += gain;
    }
    state.last = { seat, kind: "block", gain, bridge: false, hex: 0, bonus: 0 };
    finish(state);
  }

  function advance(state) {
    state.draws = 0;
    state.must = null;
    const count = state.names.length;
    if (state.pile.length > 0) {
      state.turn = (state.turn + 1) % count;
      return;
    }
    for (let step = 0; step < count; step += 1) {
      state.turn = (state.turn + 1) % count;
      if (canPlay(state.placed, state.hands[state.turn])) return;
    }
    endBlocked(state);
  }

  function createGame(names, deck) {
    const source = deck ? deck.map((tile) => tile.slice()) : shuffle(TILES);
    const each = names.length === 2 ? 9 : 7;
    return {
      names: names.slice(),
      scores: names.map(() => 0),
      hands: names.map(() => []),
      starters: names.map(() => null),
      pile: source,
      placed: [],
      turn: 0,
      draws: 0,
      must: null,
      phase: "deal",
      deal: "hand",
      need: each,
      last: null,
      winner: null
    };
  }

  // Le joueur dont c'est le tour retire les tuiles choisies. La plus forte des tuiles de départ est posée.
  function take(state, indexes) {
    if (!state || state.phase !== "deal") return "La donne est terminée.";
    const list = Array.isArray(indexes) ? indexes : [];
    const unique = [];
    list.forEach((value) => {
      const index = Number(value);
      if (!Number.isInteger(index) || unique.indexOf(index) >= 0) return;
      unique.push(index);
    });
    if (unique.length !== list.length || unique.length !== state.need || unique.some((index) => index < 0 || index >= state.pile.length)) {
      return state.need === 1 ? "Choisis une tuile." : "Choisis " + state.need + " tuiles.";
    }
    const seat = state.turn;
    const picked = unique.slice().sort((left, right) => right - left).map((index) => state.pile.splice(index, 1)[0]);
    if (state.deal === "hand") {
      picked.forEach((tile) => state.hands[seat].push(tile));
      state.turn = (seat + 1) % state.names.length;
      if (state.turn === 0) {
        state.deal = "start";
        state.need = 1;
      }
      return "";
    }
    state.starters[seat] = picked[0].slice();
    state.turn = (seat + 1) % state.names.length;
    if (state.turn !== 0) return "";
    let best = 0;
    state.starters.forEach((tile, index) => {
      if (better(tile, state.starters[best])) best = index;
    });
    const opening = state.starters[best];
    state.starters.forEach((tile, index) => {
      if (index !== best) state.pile.push(tile.slice());
    });
    state.pile = shuffle(state.pile);
    state.placed = [{ q: 0, r: 0, up: true, rot: 0, tile: opening.slice(), seat: -1 }];
    state.turn = best;
    state.phase = "play";
    state.deal = "";
    state.need = 0;
    state.last = {
      seat: best,
      kind: "start",
      gain: 0,
      tile: opening.slice(),
      drawn: state.starters.map((tile) => tile.slice()),
      bridge: false,
      hex: 0,
      bonus: 0
    };
    return "";
  }

  function play(state, index, q, r, up, rot) {
    if (state.phase !== "play") return "La partie est terminée.";
    const hand = state.hands[state.turn];
    const tile = hand[index];
    if (!tile) return "Cette tuile n'est pas dans ta main.";
    if (state.must && !same(tile, state.must)) return "Tu dois poser la tuile piochée.";
    const info = placement(state.placed, q, r, up, tile, rot);
    if (!info) return "Cette tuile ne se pose pas ici.";
    const actor = state.turn;
    const opening = state.placed.length === 0;
    hand.splice(index, 1);
    state.placed.push({ q, r, up, rot, tile: tile.slice(), seat: actor });
    state.scores[actor] += info.points;
    let gain = info.points;
    let kind = opening ? "open" : "play";
    if (hand.length === 0) {
      let extra = 25;
      state.hands.forEach((other, seat) => {
        if (seat !== actor) extra += handValue(other);
      });
      state.scores[actor] += extra;
      gain += extra;
      kind = "out";
    }
    state.last = { seat: actor, kind, gain, tile: tile.slice(), bridge: info.bridge, hex: info.hex, bonus: info.bonus };
    state.draws = 0;
    state.must = null;
    if (kind === "out") finish(state);
    else advance(state);
    return "";
  }

  function draw(state, index, assisted) {
    if (state.phase !== "play") return "La partie est terminée.";
    if (state.must) return "Tu dois d'abord poser la tuile piochée.";
    if (state.draws >= 3) return "Trois pioches maximum.";
    if (!state.pile.length) return "La pioche est vide.";
    const at = index == null ? state.pile.length - 1 : index;
    if (!Number.isInteger(at) || at < 0 || at >= state.pile.length) return "Cette tuile n'est plus dans la pioche.";
    const actor = state.turn;
    const tile = state.pile.splice(at, 1)[0];
    state.hands[actor].push(tile);
    state.scores[actor] -= 5;
    state.draws += 1;
    const help = assisted !== false;
    if (help && spots(state.placed, tile).length) {
      state.must = tile.slice();
      state.last = { seat: actor, kind: "draw", gain: -5, tile: tile.slice(), bridge: false, hex: 0, bonus: 0 };
      return "";
    }
    if (help && state.draws >= 3) {
      state.scores[actor] -= 10;
      state.last = { seat: actor, kind: "pass", gain: -25, bridge: false, hex: 0, bonus: 0 };
      advance(state);
      return "";
    }
    state.last = { seat: actor, kind: "draw", gain: -5, tile: tile.slice(), bridge: false, hex: 0, bonus: 0 };
    return "";
  }

  function pass(state) {
    if (state.phase !== "play") return "La partie est terminée.";
    if (state.must) return "Tu dois d'abord poser la tuile piochée.";
    if (state.draws < 3) return "Tu peux encore piocher.";
    const actor = state.turn;
    state.scores[actor] -= 10;
    state.last = { seat: actor, kind: "pass", gain: -25, bridge: false, hex: 0, bonus: 0 };
    advance(state);
    return "";
  }

  return { tiles: TILES, same, handValue, vertices, createGame, take, play, draw, pass, spots, around, placement, canPlay };
})();

if (typeof module !== "undefined" && module.exports) module.exports = Trio;

if (typeof document !== "undefined") {
  const SIDE = 88;
  const NS = "http://www.w3.org/2000/svg";
  const board = document.getElementById("board");
  const handRow = document.getElementById("hand");
  const status = document.getElementById("status");
  let count = 2;
  let local = null;
  let remote = null;
  let net = null;
  let picked = null;
  let chosen = null;
  let zoom = 1;
  let fitAsked = false;
  let dealPick = new Set();
  let dealKey = "";
  let aid = "guide";
  let boardOnly = false;
  let stick = "";
  let wasDone = false;
  let noted = false;
  let roundId = "";
  let pilePick = null;
  let openingKey = "";
  let openingOpen = false;
  let openingTimer = 0;

  function triominoSettings() {
    const players = local ? local.names.length : (remote && remote.config && remote.config.humans ? Number(remote.config.humans) : count);
    const each = Number(players) === 2 ? 9 : 7;
    const online = Boolean(remote);
    const free = aidIsFree();
    return [
      ["Joueurs", String(players), "2 joueurs : 9 tuiles. De 3 à 5 joueurs : 7 tuiles."],
      ["Ouverture", each + " tuiles chacun", "Chacun choisit ses tuiles dans la pioche, face cachée, à tour de rôle. Puis chacun pioche une tuile de départ : la plus forte est posée au centre et désigne qui commence. Les autres retournent dans la pioche."],
      ["Cases", free ? "Libre" : "Guidé", "Guidé ne montre que les cases où la tuile peut marquer. Libre montre toutes les cases autour : tu tournes et tu vois si les chiffres collent."],
      ["Pioche", "Trois fois au plus", "Face cachée, 5 points. Guidé impose la tuile si elle se pose. Libre la laisse dans la main : tu la regardes, et tu repioches si tu ne peux pas la poser."],
      ["Points", "Somme, pont, hexagone", "La tuile marque ses trois chiffres. Pont +40. Hexagone +50, double +60, triple +70. Piocher coûte 5."],
      ["Table", online ? "En ligne · " + remote.code : "Sur ce téléphone", "Sur ce téléphone, on se passe l'écran. En ligne, chacun voit sa main."]
    ];
  }

  function leaveTable() {
    closeOpening();
    openingKey = "";
    match.release(net, remote);
    remote = null;
    local = null;
  }

  const match = Arcade.mountMatch({
    title: "Triomino",
    game: "triomino",
    board: "play",
    settings: triominoSettings,
    rules: triominoRules,
    guide: triominoSteps,
    onReset() { leaveTable(); },
    onLeave() { leaveTable(); },
    onLocal() { startLocal(); },
    onOnline(name) {
      net.create(name, { humans: count, aid: chosenAid() }).catch((error) => {
        document.getElementById("create-error").textContent = error.message;
      });
    },
    onStart() {
      net.act("start", {}).catch((error) => { document.getElementById("lobby-note").textContent = error.message; });
    },
    currentRemote() { return remote; },
    optionsHtml: `<p class="lead">Joueurs</p>
      <div class="stepper">
        <button type="button" id="count-less" aria-label="Moins de joueurs">−</button>
        <strong id="count-value">2</strong>
        <button type="button" id="count-more" aria-label="Plus de joueurs">+</button>
      </div>
      <p class="lead">Cases</p>
      <div class="choice" id="aid" role="group" aria-label="Affichage des cases">
        <button type="button" data-aid="guide" class="is-on">Guidé</button>
        <button type="button" data-aid="free">Libre</button>
      </div>`,
    localHtml: `<div id="name-box" class="stack"></div>`
  });

  const shell = match.shell;
  const show = match.show;

  function paintNames() {
    const box = document.getElementById("name-box");
    const current = [...box.querySelectorAll("input")].map((input) => input.value);
    box.replaceChildren();
    for (let index = 1; index < count; index += 1) {
      const label = document.createElement("label");
      label.className = "field";
      label.append(document.createTextNode("Joueur " + (index + 1)));
      const input = document.createElement("input");
      input.maxLength = 24;
      input.autocomplete = "name";
      input.placeholder = "Joueur " + (index + 1);
      input.value = current[index - 1] || "";
      label.append(input);
      box.append(label);
    }
  }

  function playerNames() {
    const names = [Arcade.playerName() || "Joueur 1"];
    document.querySelectorAll("#name-box input").forEach((input, index) => {
      names.push(input.value.trim() || ("Joueur " + (index + 2)));
    });
    return names;
  }

  function statusText(model) {
    if (model.phase === "done") {
      const lead = model.winner >= 0 ? model.names[model.winner] + " gagne. " : "Égalité. ";
      return lead + ranking(model);
    }
    if (model.phase === "deal") return dealLine(model);
    if (model.must) return "Pose la tuile piochée.";
    return "";
  }

  function showStatus(text) {
    status.textContent = text || "";
    status.hidden = !status.textContent;
  }

  function ranking(model) {
    return model.names.map((name, index) => ({ name, score: model.scores[index], index }))
      .sort((left, right) => right.score - left.score || left.index - right.index)
      .map((item) => item.name + " " + item.score)
      .join(" · ");
  }

  function tileWord(count) {
    return count > 1 ? "tuiles" : "tuile";
  }

  function podiumHtml(model) {
    const people = model.names.map((name, index) => ({
      index,
      name: name || ("Joueur " + (index + 1)),
      total: Number(model.scores[index]) || 0,
      tiles: Number(model.counts[index]) || 0
    }));
    const ranked = people.slice().sort((left, right) => right.total - left.total || left.index - right.index);
    const winner = ranked.find((person) => person.index === Number(model.winner));
    const lead = winner && Number(model.winner) >= 0 ? winner.name + " gagne." : "Égalité.";
    const places = ranked.slice(0, Math.min(3, ranked.length));
    const order = places.length === 2 ? [places[1], places[0]] : [places[1], places[0], places[2]].filter(Boolean);
    const stand = order.map((person) => {
      const place = ranked.indexOf(person) + 1;
      return `<div class="place place-${place}"><span class="rank">${place}</span><span class="who">${Arcade.escapeHtml(person.name)}</span><span class="pts">${person.total}</span></div>`;
    }).join("");
    const list = ranked.map((person, index) => {
      return `<li>${index + 1}. ${Arcade.escapeHtml(person.name)} · ${person.total} pts · ${person.tiles} ${tileWord(person.tiles)}</li>`;
    }).join("");
    return `<p>${Arcade.escapeHtml(lead)}</p><div class="podium ${places.length === 2 ? "is-duo" : "is-trio"}">${stand}</div><ul class="lobby-list">${list}</ul>`;
  }

  function dealLine(model) {
    const name = model.names[model.turn] || "Un joueur";
    if (model.you === model.turn) {
      if (model.deal === "start") return "Choisis ta tuile de départ, face cachée. La plus forte commence, et elle est posée au centre.";
      return "Choisis " + model.need + " tuiles, puis Piocher.";
    }
    if (model.deal === "start") return name + " est en train de piocher sa tuile de départ.";
    return name + " est en train de piocher.";
  }

  function pixel(vert) {
    return [vert[0] * SIDE + vert[1] * SIDE / 2, -vert[1] * SIDE * Math.sqrt(3) / 2];
  }

  function triangle(parent, points, className, numbers, numberClass, pull, numberLayer) {
    const shape = document.createElementNS(NS, "polygon");
    shape.setAttribute("points", points.map((point) => point.join(",")).join(" "));
    shape.setAttribute("class", className);
    parent.append(shape);
    const center = points.reduce((sum, point) => [sum[0] + point[0], sum[1] + point[1]], [0, 0]).map((value) => value / 3);
    const spinning = className.indexOf("trio-preview") >= 0 || className.indexOf("trio-wrong") >= 0;
    if (className.indexOf("trio-ghost") < 0 && !spinning) {
      const hole = document.createElementNS(NS, "circle");
      hole.setAttribute("class", "trio-hole");
      hole.setAttribute("cx", String(center[0]));
      hole.setAttribute("cy", String(center[1]));
      hole.setAttribute("r", "4.2");
      (numberLayer || parent).append(hole);
    }
    if (spinning) spinMark(numberLayer || parent, center);
    if (!numbers) return shape;
    const host = numberLayer || parent;
    const weight = pull == null ? 0.66 : pull;
    numbers.forEach((number, index) => {
      const text = document.createElementNS(NS, "text");
      text.setAttribute("class", numberClass || "trio-num");
      text.setAttribute("x", String(points[index][0] * weight + center[0] * (1 - weight)));
      text.setAttribute("y", String(points[index][1] * weight + center[1] * (1 - weight)));
      text.setAttribute("text-anchor", "middle");
      text.setAttribute("dominant-baseline", "middle");
      text.textContent = String(number);
      host.append(text);
    });
    return shape;
  }

  function spinMark(parent, center) {
    const group = document.createElementNS(NS, "g");
    group.setAttribute("class", "trio-spin");
    group.setAttribute("transform", "translate(" + center[0] + " " + center[1] + ")");
    const hit = document.createElementNS(NS, "circle");
    hit.setAttribute("r", "14");
    hit.setAttribute("fill", "transparent");
    const arc = document.createElementNS(NS, "path");
    arc.setAttribute("class", "trio-spin-arc");
    arc.setAttribute("d", "M 0 -6.5 A 6.5 6.5 0 1 1 -4.9 4.3");
    const head = document.createElementNS(NS, "polygon");
    head.setAttribute("class", "trio-spin-head");
    head.setAttribute("points", "-4.9,4.3 -8.6,1.6 -3.4,1");
    const label = document.createElementNS(NS, "title");
    label.textContent = "Tourner la tuile";
    group.append(hit, arc, head, label);
    parent.append(group);
  }

  function cornerNumbers(tile, rot) {
    return [0, 1, 2].map((corner) => tile[(corner - rot + 3) % 3]);
  }

  function aidIsFree() {
    if (remote && remote.config) return remote.config.aid === "free";
    return aid === "free";
  }

  function handSvg(tile, shown) {
    const svg = document.createElementNS(NS, "svg");
    const top = -SIDE * Math.sqrt(3) / 2;
    const pad = 14;
    const boxW = SIDE + pad * 2;
    const boxH = -top + pad * 2;
    const width = shown || 124;
    svg.setAttribute("viewBox", (-pad) + " " + (top - pad) + " " + boxW + " " + boxH);
    svg.setAttribute("width", String(width));
    svg.setAttribute("height", String(Math.round(width * boxH / boxW)));
    const points = Trio.vertices(0, 0, true).map(pixel);
    triangle(svg, points, "trio-tile", cornerNumbers(tile, 0), "trio-num", 0.46);
    return svg;
  }

  function backSvg(shown) {
    const svg = document.createElementNS(NS, "svg");
    const top = -SIDE * Math.sqrt(3) / 2;
    const pad = 14;
    const boxW = SIDE + pad * 2;
    const boxH = -top + pad * 2;
    const width = shown || 62;
    svg.setAttribute("viewBox", (-pad) + " " + (top - pad) + " " + boxW + " " + boxH);
    svg.setAttribute("width", String(width));
    svg.setAttribute("height", String(Math.round(width * boxH / boxW)));
    const points = Trio.vertices(0, 0, true).map(pixel);
    triangle(svg, points, "trio-tile", null, null, 0.46);
    return svg;
  }

  function paintBoardName(model) {
    const node = document.getElementById("board-name");
    if (!node) return;
    const seat = scoreSeat(model);
    const name = seat >= 0 ? (model.names[seat] || "") : "";
    node.textContent = name;
    node.hidden = !name || model.phase === "deal";
  }

  function paintBoard(model) {
    const legal = new Set();
    if (model.interactive && picked != null && model.hand[picked]) {
      Trio.spots(model.placed, model.hand[picked]).forEach((spot) => {
        legal.add(spot.q + "," + spot.r + "," + (spot.up ? 1 : 0));
      });
    }
    const free = aidIsFree();
    const cells = model.interactive && picked != null && model.hand[picked]
      ? Trio.around(model.placed).filter((cell) => free || legal.has(cell.q + "," + cell.r + "," + (cell.up ? 1 : 0)))
      : [];
    const svg = document.createElementNS(NS, "svg");
    const group = document.createElementNS(NS, "g");
    const numberLayer = document.createElementNS(NS, "g");
    svg.append(group);
    const all = [];
    model.placed.forEach((item, index) => {
      const points = Trio.vertices(item.q, item.r, item.up).map(pixel);
      const classes = ["trio-tile"];
      if (item.seat === model.you) classes.push("trio-mine");
      const last = index === model.placed.length - 1;
      if (last) classes.push("trio-last");
      const shape = triangle(group, points, classes.join(" "), cornerNumbers(item.tile, item.rot), "trio-num", 0.36, numberLayer);
      if (last && shape) {
        const title = document.createElementNS(NS, "title");
        title.textContent = "Dernière tuile posée";
        shape.append(title);
      }
      all.push(...points);
    });
    cells.forEach((cell) => {
      const points = Trio.vertices(cell.q, cell.r, cell.up).map(pixel);
      const selected = chosen && chosen.q === cell.q && chosen.r === cell.r && chosen.up === cell.up;
      const fit = selected ? Trio.placement(model.placed, cell.q, cell.r, cell.up, model.hand[picked], chosen.rot) : null;
      const wrap = document.createElementNS(NS, "g");
      if (selected) wrap.setAttribute("class", fit ? "trio-preview" : "trio-wrong");
      const shape = triangle(
        wrap,
        points,
        selected ? (fit ? "trio-preview" : "trio-wrong") : "trio-ghost",
        selected ? cornerNumbers(model.hand[picked], chosen.rot) : null,
        fit ? "trio-num is-on" : "trio-num is-dim",
        0.36,
        numberLayer
      );
      shape.setAttribute("data-q", String(cell.q));
      shape.setAttribute("data-r", String(cell.r));
      shape.setAttribute("data-up", cell.up ? "1" : "0");
      const label = document.createElementNS(NS, "title");
      label.textContent = selected ? "Tourner la tuile" : "Poser ici";
      shape.append(label);
      group.append(wrap);
      all.push(...points);
    });
    group.append(numberLayer);
    if (!all.length) all.push([0, 0], [SIDE, 0], [SIDE / 2, -SIDE]);
    const xs = all.map((point) => point[0]);
    const ys = all.map((point) => point[1]);
    const pad = 22;
    const minX = Math.min(...xs) - pad;
    const minY = Math.min(...ys) - pad;
    const width = Math.max(...xs) - minX + pad;
    const height = Math.max(...ys) - minY + pad;
    svg.setAttribute("viewBox", minX + " " + minY + " " + width + " " + height);
    const boxWidth = Math.max(320, width);
    const boxHeight = Math.max(220, height);
    const fitting = fitAsked;
    if (fitting) {
      zoom = containZoom(boxWidth, boxHeight);
      fitAsked = false;
    }
    svg.setAttribute("width", String(Math.round(boxWidth * zoom)));
    svg.setAttribute("height", String(Math.round(boxHeight * zoom)));
    board.replaceChildren(svg);
    if (fitting) {
      board.scrollTop = 0;
      board.scrollLeft = 0;
    }
  }

  // Tout cadre le plateau dans l'espace visible, sans le dépasser.
  function containZoom(boxWidth, boxHeight) {
    const play = document.getElementById("play");
    const roomWidth = Math.max(160, (play ? play.clientWidth : window.innerWidth) - 8);
    const tall = play && play.classList.contains("is-board") ? 0.68 : 0.58;
    const roomHeight = Math.max(180, Math.round(window.innerHeight * tall) - 16);
    const scale = Math.min(roomWidth / boxWidth, roomHeight / boxHeight, 1);
    return Math.max(0.2, Math.round(scale * 100) / 100);
  }

  function handInModal() {
    return window.Prefs && Prefs.handPlace() === "modal";
  }

  function scoreSeat(model) {
    if (model.you >= 0) return model.you;
    return model.turn;
  }

  function paintHand(model) {
    applyHandColumns(handRow);
    handRow.hidden = handInModal();
    handRow.replaceChildren();
    model.hand.forEach((tile, index) => {
      const button = document.createElement("button");
      button.type = "button";
      button.append(handSvg(tile));
      button.setAttribute("aria-label", "Tuile " + tile.join(" "));
      if (index === picked) button.classList.add("is-on");
      if (!model.interactive || (model.must && !Trio.same(tile, model.must))) button.disabled = true;
      button.onclick = () => {
        if (!model.interactive) return;
        if (model.must && !Trio.same(tile, model.must)) return;
        picked = index;
        chosen = null;
        render();
      };
      handRow.append(button);
    });
  }

  function handColumns() {
    return window.Prefs && Prefs.handColumns() === 4 ? 4 : 3;
  }

  function applyHandColumns(node) {
    if (node) node.style.setProperty("--hand-columns", String(handColumns()));
  }

  function paintScores(model) {
    const active = model.phase === "done" ? model.winner : model.turn;
    Arcade.paintSeats(document.getElementById("scores"), model.names.map((name, index) => ({
      name,
      score: model.scores[index] || 0,
      tiles: Number(model.counts[index]) || 0,
      active: index === active
    })));
  }

  function chosenFit(model) {
    if (!chosen || picked == null || !model.hand[picked]) return null;
    return Trio.placement(model.placed, chosen.q, chosen.r, chosen.up, model.hand[picked], chosen.rot);
  }

  function paintActions(model) {
    const fit = chosenFit(model);
    const place = document.getElementById("place");
    const drawButton = document.getElementById("draw");
    const lift = document.getElementById("lift");
    const handButton = document.getElementById("show-hand");
    const modal = handInModal();
    const playing = model.phase === "play" && !boardOnly;
    handButton.hidden = !modal || !playing || !model.hand.length;
    place.hidden = !model.interactive || !chosen;
    place.disabled = !fit;
    lift.hidden = !model.interactive || !chosen;
    if (chosen && !fit) place.textContent = "Ce côté ne colle pas";
    if (fit) {
      const words = ["Poser · " + fit.points];
      if (fit.bridge) words.push("pont");
      if (fit.hex === 1) words.push("hexagone");
      if (fit.hex === 2) words.push("double hexagone");
      if (fit.hex === 3) words.push("triple hexagone");
      place.textContent = words.join(" · ");
    }
    const canDraw = model.interactive && !model.must && model.draws < 3 && model.pile > 0;
    drawButton.hidden = !canDraw;
    const passButton = document.getElementById("pass-draw");
    passButton.hidden = !aidIsFree() || !model.interactive || !!model.must || model.phase !== "play" || model.draws < 3;
  }

  function render() {
    const model = local ? localModel() : remoteModel();
    if (!model) return;
    show("play");
    if (model.must) {
      const forced = model.hand.findIndex((tile) => Trio.same(tile, model.must));
      if (forced >= 0) picked = forced;
    }
    showStatus(statusText(model));
    paintScores(model);
    paintBoardName(model);
    match.totals.paint(
      document.getElementById("round-totals"),
      model.names,
      model.scores,
      model.phase !== "done" || !(local ? noted : wasDone),
      scoreSeat(model)
    );
    paintDeal(model);
    paintBoard(model);
    paintHand(model);
    paintActions(model);
    paintView();
    noteEnd(model);
    maybeGuide(model);
    if (model.phase === "deal") openingKey = "";
    else showOpening(model);
  }

  function localModel() {
    const hand = local ? local.hands[local.turn].map((tile) => tile.slice()) : [];
    return {
      names: local.names,
      scores: local.scores,
      counts: local.hands.map((cards) => cards.length),
      placed: local.placed,
      hand,
      pile: local.pile.length,
      deal: local.deal || "",
      need: local.need || 0,
      turn: local.turn,
      draws: local.draws,
      must: local.must,
      phase: local.phase,
      last: local.last,
      winner: local.winner,
      you: local.turn,
      interactive: local.phase === "play" || local.phase === "deal"
    };
  }

  function remoteModel() {
    if (!remote || remote.phase === "lobby") return null;
    const view = remote.view || {};
    const placed = (view.placed || []).map((item) => ({
      q: Number(item.q),
      r: Number(item.r),
      up: item.up === true || item.up === "true",
      rot: Number(item.rot) || 0,
      tile: (item.tile || []).map(Number),
      seat: item.seat == null || item.seat === "" ? 0 : Number(item.seat)
    }));
    const hand = (view.hand || []).map((tile) => tile.map(Number));
    const signature = remote.you + ":" + remote.turn + ":" + remote.phase + ":" + placed.length + ":" + JSON.stringify(hand) + ":" + (view.draws || 0);
    if (signature !== stick) {
      stick = signature;
      picked = null;
      chosen = null;
    }
    return {
      names: remote.names || [],
      scores: view.scores || [],
      counts: view.counts || [],
      placed,
      hand,
      pile: Number(view.pile) || 0,
      deal: view.deal || "",
      need: Number(view.need) || 0,
      turn: remote.turn,
      draws: Number(view.draws) || 0,
      must: view.must ? view.must.map(Number) : null,
      phase: remote.phase,
      last: view.last || null,
      winner: remote.winner,
      you: remote.you,
      interactive: (remote.phase === "play" || remote.phase === "deal") && remote.you === remote.turn
    };
  }

  function results(model) {
    const best = Math.max(...model.scores.map((score) => Number(score) || 0));
    return model.names.map((name, index) => {
      const score = Number(model.scores[index]) || 0;
      let result = "loss";
      if (score === best) result = model.scores.filter((value) => Number(value) === best).length > 1 ? "draw" : "win";
      return { name, result };
    });
  }

  function noteEnd(model) {
    const done = model.phase === "done";
    Arcade.announceOnce("triomino", done, done ? podiumHtml(model) : "");
    const again = document.getElementById("end-again");
    if (again) again.textContent = "Nouvelle partie";
    if (!done) {
      wasDone = false;
      noted = false;
      return;
    }
    if (local) {
      if (noted) return;
      noted = true;
      Arcade.recordStats("triomino", results(model));
      match.totals.remember(model.names, model.scores, roundId);
      shell.paintStats();
      match.totals.paint(document.getElementById("round-totals"), model.names, model.scores, false, scoreSeat(model));
      return;
    }
    if (wasDone) return;
    wasDone = true;
    const mine = results(model).find((person, index) => index === remote.you);
    if (mine) Arcade.recordStats("triomino", [mine]);
    const stamp = remote.code + ":" + model.scores.join(",") + ":" + (model.placed || []).length;
    match.totals.remember(model.names, model.scores, stamp);
    shell.paintStats();
    match.totals.paint(document.getElementById("round-totals"), model.names, model.scores, false, scoreSeat(model));
  }

  function triominoRules() {
    const players = local ? local.names.length : (remote && remote.config && remote.config.humans ? Number(remote.config.humans) : count);
    const each = Number(players) === 2 ? 9 : 7;
    return [
      ["Donne", "Chacun pioche " + each + " tuiles, face cachée, à tour de rôle. Puis chacun choisit une tuile de départ. La plus forte est posée au centre et désigne qui commence. Les autres retournent dans la pioche."],
      ["Pose", "Les chiffres qui se touchent sont les mêmes. Touche une case, tourne la tuile avec la flèche, puis Poser. Reprendre retire la tuile."],
      ["Points", "La tuile marque la somme de ses chiffres. Pont +40. Hexagone +50, double +60, triple +70."],
      ["Pioche", "Face cachée, 5 points, trois fois au plus dans le tour. Guidé impose la tuile dès qu'elle se pose. Libre la laisse dans la main : tu cherches toi-même, et tu repioches si tu ne peux pas. Au bout de trois sans poser, Passer retire 10 points de plus."],
      ["Fin", "Poser sa dernière tuile donne 25 points plus la valeur des tuiles adverses. Si personne ne peut jouer, la plus petite main unique marque la différence. Le score général additionne les manches gardées sur ce téléphone. +1 en relance une avec les mêmes joueurs."]
    ];
  }

  function trioFace(top, left, right, back) {
    const fill = back ? "#6a1218" : "#b4232c";
    const marks = back
      ? `<circle cx="40" cy="44" r="4" fill="#f0d78c"/>`
      : `<text x="40" y="30" text-anchor="middle" fill="#f4d98a" font-size="14" font-weight="700">${top}</text><text x="24" y="58" text-anchor="middle" fill="#f4d98a" font-size="14" font-weight="700">${left}</text><text x="56" y="58" text-anchor="middle" fill="#f4d98a" font-size="14" font-weight="700">${right}</text>`;
    return `<svg viewBox="0 0 80 70" aria-hidden="true"><polygon points="40,6 74,66 6,66" fill="${fill}" stroke="#f0d78c" stroke-width="3"/>${marks}</svg>`;
  }

  function triominoSteps() {
    return [
      ...Arcade.gateTour((mode) => match.setWhere(mode), {
        title: "Triomino",
        text: "De 2 à 5 joueurs. Guidé montre seulement les cases jouables, Libre les montre toutes.",
        target: () => document.getElementById("step-create")
      }, "En ligne, les autres rejoignent avec le code. L'invitation s'affiche après la création."),
      Object.assign(Arcade.chromeStep(), { page: "deal" }),
      {
        page: "deal",
        title: "La donne",
        render: Arcade.pictured(
          "Les tuiles restent face cachée. Choisis-en le nombre demandé, puis Piocher.",
          `<div class="coach-tris">${trioFace("", "", "", true)}${trioFace("", "", "", true)}${trioFace("", "", "", true)}</div><p class="coach-go">Piocher</p>`
        ),
        target: () => document.getElementById("deal-box")
      },
      {
        page: "play",
        title: "La main",
        render: Arcade.pictured(
          "Touche une tuile, puis une case. La flèche au centre la tourne.",
          `<div class="coach-tris">${trioFace(5, 0, 3)}</div>`
        ),
        target: () => document.getElementById("hand")
      },
      {
        page: "play",
        title: "Le plateau",
        render: Arcade.pictured(
          "Les chiffres qui se touchent sont les mêmes.",
          `<div class="coach-tris">${trioFace(5, 1, 2)}${trioFace(4, 0, 5)}</div>`
        ),
        target: () => document.getElementById("board")
      },
      {
        page: "play",
        title: "Le score",
        render: Arcade.pictured(
          "Les pastilles montrent le score de la manche. En dessous, le score général est le tien, sur ce téléphone.",
          `<div class="coach-scores"><div><span>Toi</span><strong>12</strong></div></div>`
        ),
        target: () => document.getElementById("round-totals")
      },
      Arcade.lobbyStep()
    ];
  }

  function maybeGuide(model) {
    if (!model.interactive) return;
    const page = model.phase === "deal" ? "deal" : (model.phase === "play" ? "play" : "");
    if (page) Arcade.guideOn("triomino-tutorial", triominoSteps, page);
  }

  function paintView() {
    const play = document.getElementById("play");
    const button = document.getElementById("show-board");
    play.classList.toggle("is-board", boardOnly);
    button.classList.toggle("is-on", boardOnly);
    button.setAttribute("aria-pressed", boardOnly ? "true" : "false");
    button.textContent = boardOnly ? "Jeu" : "Plateau";
  }

  function closeMine() {
    document.getElementById("mine").classList.add("hidden");
  }

  function openMine() {
    const model = local ? localModel() : remoteModel();
    if (!model || !model.hand.length) return;
    const box = document.getElementById("mine-tiles");
    applyHandColumns(box);
    box.replaceChildren();
    model.hand.forEach((tile, index) => {
      const button = document.createElement("button");
      button.type = "button";
      button.append(handSvg(tile, 132));
      button.setAttribute("aria-label", "Tuile " + tile.join(" "));
      if (index === picked) button.classList.add("is-on");
      const blocked = !model.interactive || (model.must && !Trio.same(tile, model.must));
      button.disabled = blocked;
      button.onclick = () => {
        if (blocked) return;
        picked = index;
        chosen = null;
        closeMine();
        render();
      };
      box.append(button);
    });
    document.getElementById("mine").classList.remove("hidden");
  }

  function closeOpening() {
    window.clearTimeout(openingTimer);
    openingOpen = false;
    const overlay = document.getElementById("opening");
    if (overlay) overlay.classList.add("hidden");
    const bar = document.querySelector("#opening-bar span");
    if (bar) {
      bar.style.transition = "none";
      bar.style.width = "0";
    }
  }

  function finishOpening() {
    if (!openingOpen) return;
    closeOpening();
    render();
  }

  function showOpening(model) {
    const last = model.last;
    if (!last || last.kind !== "start" || !Array.isArray(last.drawn) || openingOpen) return;
    const key = last.drawn.map((tile) => tile.join("-")).join("|") + ":" + last.seat;
    if (key === openingKey) return;
    openingKey = key;
    openingOpen = true;
    const box = document.getElementById("opening-tiles");
    box.replaceChildren();
    last.drawn.forEach((tile, index) => {
      const figure = document.createElement("figure");
      if (index === last.seat) figure.classList.add("is-on");
      figure.append(handSvg(tile, 120));
      const caption = document.createElement("figcaption");
      caption.textContent = model.names[index] || ("Joueur " + (index + 1));
      figure.append(caption);
      box.append(figure);
    });
    document.getElementById("opening-title").textContent = (model.names[last.seat] || "Un joueur") + " commence";
    const bar = document.querySelector("#opening-bar span");
    bar.style.transition = "none";
    bar.style.width = "0";
    document.getElementById("opening").classList.remove("hidden");
    const delay = 10000;
    window.requestAnimationFrame(() => {
      bar.style.transition = "width " + delay + "ms linear";
      bar.style.width = "100%";
    });
    window.clearTimeout(openingTimer);
    openingTimer = window.setTimeout(finishOpening, delay);
  }

  function afterLocal() {
    if (local.phase === "done") {
      picked = null;
      chosen = null;
    }
    render();
  }

  function startLocal() {
    Arcade.dismissEnd();
    remote = null;
    shell.setOnline(false);
    wasDone = false;
    noted = false;
    picked = null;
    chosen = null;
    aid = chosenAid();
    dealPick = new Set();
    dealKey = "";
    roundId = Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
    local = Trio.createGame(playerNames());
    render();
  }

  function paintDeal(model) {
    const play = document.getElementById("play");
    const box = document.getElementById("deal-box");
    const dealing = model.phase === "deal";
    play.classList.toggle("is-deal", model.phase === "deal");
    box.hidden = !dealing;
    if (!dealing) return;
    const tiles = document.getElementById("deal-tiles");
    const key = model.turn + ":" + model.deal + ":" + model.pile;
    if (key !== dealKey) {
      dealKey = key;
      dealPick = new Set();
      tiles.replaceChildren();
      for (let index = 0; index < model.pile; index += 1) {
        const button = document.createElement("button");
        button.type = "button";
        button.append(backSvg(84));
        button.setAttribute("aria-label", "Choisir cette tuile");
        button.onclick = () => {
          const current = local ? localModel() : remoteModel();
          if (!current || !current.interactive || current.phase !== "deal") return;
          if (dealPick.has(index)) dealPick.delete(index);
          else if (dealPick.size < current.need) dealPick.add(index);
          paintDeal(current);
          showStatus(statusText(current));
        };
        tiles.append(button);
      }
    }
    tiles.querySelectorAll("button").forEach((button, index) => {
      button.classList.toggle("is-on", dealPick.has(index));
      button.disabled = !model.interactive;
    });
    const countNode = document.getElementById("deal-count");
    const label = model.need === 1 ? "Tuile de départ" : "Tuiles";
    countNode.textContent = label + " · " + dealPick.size + " / " + model.need;
    const go = document.getElementById("deal-go");
    go.hidden = !model.interactive;
    go.disabled = dealPick.size !== model.need;
  }

  function confirmDeal() {
    const go = document.getElementById("deal-go");
    if (go.disabled) return;
    const indexes = [...dealPick];
    go.disabled = true;
    if (local) {
      const error = Trio.take(local, indexes);
      if (error) {
        showStatus(error);
        go.disabled = false;
        return;
      }
      dealPick = new Set();
      dealKey = "";
      afterLocal();
      return;
    }
    if (!remote) return;
    net.act("pick", { indexes }).catch((error) => {
      showStatus(error.message);
      const current = remoteModel();
      if (current) paintDeal(current);
    });
  }

  function turnChosen() {
    if (!chosen) return;
    chosen = { q: chosen.q, r: chosen.r, up: chosen.up, rot: (chosen.rot + 1) % 3 };
    render();
  }

  function commit() {
    if (picked == null || !chosen) return;
    const model = local ? localModel() : remoteModel();
    if (!model || !chosenFit(model)) {
      showStatus("Tourne la tuile jusqu'à ce que les chiffres collent.");
      return;
    }
    if (local) {
      const error = Trio.play(local, picked, chosen.q, chosen.r, chosen.up, chosen.rot);
      if (error) {
        showStatus(error);
        return;
      }
      picked = null;
      chosen = null;
      afterLocal();
      return;
    }
    if (!remote) return;
    net.act("play", { index: picked, q: chosen.q, r: chosen.r, up: chosen.up, rot: chosen.rot })
      .catch((error) => { showStatus(error.message); });
  }

  function closePile() {
    pilePick = null;
    document.getElementById("pile").classList.add("hidden");
  }

  function paintPilePick() {
    document.querySelectorAll("#pile-tiles button").forEach((button, index) => {
      button.classList.toggle("is-on", index === pilePick);
    });
    const go = document.getElementById("pile-go");
    if (go) go.disabled = pilePick == null;
  }

  function openPile() {
    const model = local ? localModel() : remoteModel();
    if (!model || !model.interactive || model.must || model.draws >= 3 || model.pile < 1) return;
    pilePick = null;
    const box = document.getElementById("pile-tiles");
    box.replaceChildren();
    for (let index = 0; index < model.pile; index += 1) {
      const button = document.createElement("button");
      button.type = "button";
      button.append(backSvg());
      button.setAttribute("aria-label", "Choisir cette tuile");
      button.onclick = () => {
        pilePick = index;
        paintPilePick();
      };
      box.append(button);
    }
    paintPilePick();
    document.getElementById("pile").classList.remove("hidden");
  }

  function takeFromPile(index) {
    closePile();
    if (local) {
      const error = Trio.draw(local, index, !aidIsFree());
      if (error) {
        showStatus(error);
        return;
      }
      picked = null;
      chosen = null;
      afterLocal();
      return;
    }
    if (!remote) return;
    net.act("draw", { index }).catch((error) => { showStatus(error.message); });
  }

  function giveUp() {
    const model = local ? localModel() : remoteModel();
    if (!model || !aidIsFree() || !model.interactive || model.draws < 3) return;
    if (local) {
      const error = Trio.pass(local);
      if (error) {
        showStatus(error);
        return;
      }
      picked = null;
      chosen = null;
      afterLocal();
      return;
    }
    if (!remote) return;
    net.act("pass", {}).catch((error) => { showStatus(error.message); });
  }

  function paintLobby(state) {
    const humans = state.config && state.config.humans ? Number(state.config.humans) : 2;
    const each = humans === 2 ? 9 : 7;
    const ready = (state.names || []).length >= humans;
    match.fillLobby(state, {
      role: humans + " joueurs, " + each + " tuiles chacun.",
      note: ready ? "Tout le monde est là." : "En attente des autres joueurs.",
      ready,
      host: state.you === 0
    });
  }

  net = Arcade.room("triomino", (state) => {
    local = null;
    remote = state;
    shell.setOnline(true, state.code);
    if (state.phase === "lobby") {
      wasDone = false;
      Arcade.announceOnce("triomino", false, "");
      paintLobby(state);
      return;
    }
    render();
  }, match.noteError);

  board.addEventListener("click", (event) => {
    if (event.target.closest(".trio-spin")) {
      turnChosen();
      return;
    }
    const node = event.target.closest("[data-q]");
    if (!node) return;
    const model = local ? localModel() : remoteModel();
    if (!model || !model.interactive || picked == null) return;
    const q = Number(node.dataset.q);
    const r = Number(node.dataset.r);
    const up = node.dataset.up === "1";
    if (chosen && chosen.q === q && chosen.r === r && chosen.up === up) turnChosen();
    else {
      chosen = { q, r, up, rot: 0 };
      render();
    }
  });
  function chosenAid() {
    const button = document.querySelector("#aid .is-on");
    return button && button.dataset.aid === "free" ? "free" : "guide";
  }

  document.getElementById("opening").onclick = () => finishOpening();
  document.getElementById("deal-go").onclick = confirmDeal;
  document.getElementById("place").onclick = commit;
  document.getElementById("lift").onclick = () => {
    chosen = null;
    render();
  };
  document.getElementById("show-hand").onclick = openMine;
  document.getElementById("mine-close").onclick = closeMine;
  document.getElementById("show-board").onclick = () => {
    boardOnly = !boardOnly;
    render();
  };
  document.getElementById("zoom-in").onclick = () => {
    zoom = Math.min(2.6, Math.round((zoom + 0.25) * 100) / 100);
    render();
  };
  document.getElementById("zoom-out").onclick = () => {
    zoom = Math.max(0.2, Math.round((zoom - 0.25) * 100) / 100);
    render();
  };
  document.getElementById("zoom-fit").onclick = () => {
    fitAsked = true;
    render();
  };
  document.getElementById("draw").onclick = openPile;
  document.getElementById("pass-draw").onclick = giveUp;
  document.getElementById("pile-go").onclick = () => {
    if (pilePick == null) return;
    const index = pilePick;
    takeFromPile(index);
  };
  document.getElementById("pile-close").onclick = closePile;
  match.bindChoice("aid");
  document.getElementById("count-less").onclick = () => {
    count = Math.max(2, count - 1);
    document.getElementById("count-value").textContent = String(count);
    paintNames();
  };
  document.getElementById("count-more").onclick = () => {
    count = Math.min(5, count + 1);
    document.getElementById("count-value").textContent = String(count);
    paintNames();
  };
  document.getElementById("again").onclick = () => {
    if (remote) net.act("again", {}).catch((error) => { showStatus(error.message); });
    else if (local) startLocal();
  };
  document.getElementById("leave").onclick = leaveTable;
  paintNames();
  shell.paintStats();
  if (Arcade.onlineOk()) net.resume();
}
