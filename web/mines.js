function mineTotal(boardSize) {
  if (boardSize <= 9) return 10;
  if (boardSize === 12) return 22;
  return 40;
}

function neighbors(boardSize, index) {
  const row = Math.floor(index / boardSize);
  const col = index % boardSize;
  const list = [];
  for (let dr = -1; dr <= 1; dr += 1) {
    for (let dc = -1; dc <= 1; dc += 1) {
      if (!dr && !dc) continue;
      const nextRow = row + dr;
      const nextCol = col + dc;
      if (nextRow >= 0 && nextCol >= 0 && nextRow < boardSize && nextCol < boardSize) list.push(nextRow * boardSize + nextCol);
    }
  }
  return list;
}

function placeMines(boardSize, safeIndex) {
  const bag = [];
  for (let index = 0; index < boardSize * boardSize; index += 1) {
    if (index !== safeIndex) bag.push(index);
  }
  for (let index = bag.length - 1; index > 0; index -= 1) {
    const swap = Math.floor(Math.random() * (index + 1));
    const cell = bag[index];
    bag[index] = bag[swap];
    bag[swap] = cell;
  }
  return new Set(bag.slice(0, mineTotal(boardSize)));
}

function openCell(state, index) {
  if (state.revealed.has(index) || state.flags.has(index)) return "repeat";
  if (!state.mines) state.mines = placeMines(state.size, index);
  if (state.mines.has(index)) {
    state.revealed.set(index, -1);
    return "mine";
  }
  const queue = [index];
  while (queue.length) {
    const current = queue.pop();
    if (state.revealed.has(current) || state.mines.has(current) || state.flags.has(current)) continue;
    const near = neighbors(state.size, current);
    const count = near.filter((id) => state.mines.has(id)).length;
    state.revealed.set(current, count);
    if (count === 0) {
      near.forEach((id) => {
        if (!state.revealed.has(id) && !state.flags.has(id)) queue.push(id);
      });
    }
  }
  return "safe";
}

function cleared(state) {
  let safe = 0;
  state.revealed.forEach((value) => { if (value >= 0) safe += 1; });
  return safe >= state.size * state.size - mineTotal(state.size);
}

function botIndex(state) {
  const safe = [];
  const danger = new Set();
  state.revealed.forEach((value, index) => {
    if (value < 0) return;
    const near = neighbors(state.size, index);
    const hidden = near.filter((id) => !state.revealed.has(id) && !state.flags.has(id));
    const bombs = near.filter((id) => state.revealed.get(id) === -1).length;
    if (hidden.length && value === bombs) safe.push(...hidden);
    if (hidden.length && value - bombs === hidden.length) hidden.forEach((id) => danger.add(id));
  });
  const open = [...new Set(safe)].filter((id) => !state.revealed.has(id) && !state.flags.has(id));
  if (open.length) return open[0];
  const pool = [];
  for (let index = 0; index < state.size * state.size; index += 1) {
    if (!state.revealed.has(index) && !state.flags.has(index) && !danger.has(index)) pool.push(index);
  }
  if (!pool.length) {
    for (let index = 0; index < state.size * state.size; index += 1) {
      if (!state.revealed.has(index) && !state.flags.has(index)) pool.push(index);
    }
  }
  if (!pool.length) return null;
  return pool[Math.floor(Math.random() * pool.length)];
}

let size = 9;
let players = 2;
let tool = "open";
let local = null;
let remote = null;
let net = null;
const grid = document.getElementById("grid");
const status = document.getElementById("status");

function minesSettings() {
  const online = Boolean(remote);
  const boardSize = local ? local.size : (online && remote.config ? Number(remote.config.size) || size : size);
  const mode = local
    ? (local.mode === "bot" ? "Contre l'ordinateur" : local.names.length + " joueurs")
    : (online ? "En ligne" : "Pas encore lancée");
  return [
    ["Grille", boardSize + " × " + boardSize, mineTotal(boardSize) + " mines, placées au hasard au premier coup."],
    ["Partie", mode, "Contre l'ordinateur, ou de 2 à 4 joueurs. Une mine élimine. Le dernier restant gagne."],
    ["Table", online ? "En ligne · " + remote.code : "Sur ce téléphone", "Sur ce téléphone : sans connexion. En ligne : les autres rejoignent avec le code, puis tu lances."]
  ];
}

function leaveTable() {
  match.release(net, remote);
  remote = null;
  local = null;
}

function paintPlayers() {
  document.getElementById("players-value").textContent = String(players);
  document.getElementById("online-players-value").textContent = String(players);
}

function paintSize() {
  document.getElementById("size-note").textContent = size + " × " + size + ", " + mineTotal(size) + " mines.";
}

function paintNames(rival) {
  const box = document.getElementById("name-box");
  const who = rival == null ? match.rival : rival;
  const count = who === "bot" ? 1 : players;
  const previous = [...box.querySelectorAll("input")].map((input) => input.value);
  box.replaceChildren();
  for (let index = 1; index < count; index += 1) {
    const label = document.createElement("label");
    label.className = "field";
    label.append(document.createTextNode("Joueur " + (index + 1)));
    const input = document.createElement("input");
    input.maxLength = 24;
    input.autocomplete = "off";
    input.placeholder = "Joueur " + (index + 1);
    input.value = previous[index - 1] || "";
    label.append(input);
    box.append(label);
  }
}

const match = Arcade.mountMatch({
  title: "Démineur",
  game: "mines",
  board: "play",
  settings: minesSettings,
  onReset() { leaveTable(); },
  onLeave() { leaveTable(); },
  onLocal() { startLocal(); },
  onOnline(name) {
    net.create(name, { bot: false, size, humans: players }).catch((error) => {
      document.getElementById("create-error").textContent = error.message;
    });
  },
  onStart() {
    net.act("start", {}).catch((error) => { document.getElementById("lobby-note").textContent = error.message; });
  },
  currentRemote() { return remote; },
  syncWhere(mode, rival) {
    document.getElementById("count-box").classList.toggle("hidden", rival === "bot");
    paintNames(rival);
  },
  optionsHtml: `<p class="lead">Taille de la grille</p>
    <div class="choice" id="sizes">
      <button type="button" data-size="8">8</button>
      <button type="button" data-size="9" class="is-on">9</button>
      <button type="button" data-size="12">12</button>
      <button type="button" data-size="16">16</button>
    </div>
    <p class="status" id="size-note">9 × 9, 10 mines.</p>`,
  localHtml: `<div class="choice" id="rival">
      <button type="button" data-rival="bot" class="is-on">Contre l'ordinateur</button>
      <button type="button" data-rival="multi">À plusieurs</button>
    </div>
    <div id="count-box" class="hidden">
      <p class="lead">Joueurs</p>
      <div class="stepper">
        <button type="button" id="players-less" aria-label="Retirer un joueur">−</button>
        <strong id="players-value">2</strong>
        <button type="button" id="players-more" aria-label="Ajouter un joueur">+</button>
      </div>
    </div>
    <div id="name-box" class="stack"></div>`,
  onlineHtml: `<p class="lead">Joueurs</p>
    <div class="stepper">
      <button type="button" id="online-players-less" aria-label="Retirer un joueur">−</button>
      <strong id="online-players-value">2</strong>
      <button type="button" id="online-players-more" aria-label="Ajouter un joueur">+</button>
    </div>
    <p class="lead">De 2 à 4. L'invitation s'affiche après la création. Tu lances quand tout le monde est là.</p>`
});

const shell = match.shell;
const show = match.show;

function cellFace(value, flagged, showMine) {
  if (value != null && value >= 0) return { cls: "mine open", label: value ? String(value) : "" };
  if (value === -1 || showMine) return { cls: "mine bomb", label: "×" };
  if (flagged) return { cls: "mine flag", label: "X" };
  return { cls: "mine", label: "" };
}

function paintGrid(boardSize, revealed, flags, mineList, over) {
  grid.style.gridTemplateColumns = `repeat(${boardSize}, 1fr)`;
  const flagSet = flags instanceof Set ? flags : new Set((flags || []).map(Number));
  const mineSet = mineList instanceof Set ? mineList : new Set((mineList || []).map(Number));
  let html = "";
  for (let index = 0; index < boardSize * boardSize; index += 1) {
    let value = null;
    if (revealed instanceof Map) value = revealed.has(index) ? revealed.get(index) : null;
    else if (revealed && Object.prototype.hasOwnProperty.call(revealed, String(index))) value = revealed[String(index)];
    const showMine = Boolean(over) && mineSet.has(index) && (value == null || value < 0);
    const face = cellFace(value, flagSet.has(index), showMine);
    html += `<button type="button" class="${face.cls}" data-i="${index}">${face.label}</button>`;
  }
  grid.innerHTML = html;
}

function localText() {
  if (local.over === "win") return (local.names[local.winner] || "Quelqu'un") + " gagne.";
  if (local.over === "empty") return "Plus aucun joueur.";
  if (local.over === "clear") return "Grille découverte.";
  const extra = local.mode === "bot" && local.turn === 1 ? " (ordinateur)" : "";
  return "Au tour de " + local.names[local.turn] + extra + ".";
}

function paintLocal() {
  const over = Boolean(local.over);
  paintGrid(local.size, local.revealed, local.flags, over && local.mines ? local.mines : [], over);
  status.textContent = localText();
  Arcade.announceOnce("mines", over, `<p>${Arcade.escapeHtml(localText())}</p>`);
}

function nextAlive(state) {
  for (let step = 1; step <= state.names.length; step += 1) {
    const seat = (state.turn + step) % state.names.length;
    if (state.alive[seat]) return seat;
  }
  return state.turn;
}

function finishIfNeeded() {
  const alive = local.alive.map((on, seat) => (on ? seat : -1)).filter((seat) => seat >= 0);
  if (cleared(local)) {
    local.over = "clear";
    return;
  }
  if (alive.length === 1) {
    local.over = "win";
    local.winner = alive[0];
  } else if (alive.length === 0) local.over = "empty";
}

function toggleLocalFlag(index) {
  if (!local || local.over || local.revealed.has(index)) return;
  if (local.mode === "bot" && local.turn !== 0) return;
  if (local.flags.has(index)) local.flags.delete(index);
  else local.flags.add(index);
  paintLocal();
}

function clickLocal(index) {
  if (!local || local.over || local.revealed.has(index)) return;
  if (local.mode === "bot" && local.turn !== 0) return;
  if (tool === "flag") {
    toggleLocalFlag(index);
    return;
  }
  const result = openCell(local, index);
  if (result === "repeat") return;
  if (result === "mine") {
    local.alive[local.turn] = false;
    finishIfNeeded();
    if (!local.over) local.turn = nextAlive(local);
  } else {
    finishIfNeeded();
    if (!local.over) local.turn = nextAlive(local);
  }
  if (local.mode === "bot" && !local.over && local.turn === 1) {
    const choice = botIndex(local);
    if (choice == null) local.turn = 0;
    else {
      const botResult = openCell(local, choice);
      if (botResult === "mine") {
        local.alive[1] = false;
        local.over = "win";
        local.winner = 0;
      } else if (botResult !== "repeat") {
        finishIfNeeded();
        if (!local.over) local.turn = 0;
      } else local.turn = 0;
    }
  }
  paintLocal();
}

function readNames() {
  return [...document.querySelectorAll("#name-box input")].map((input) => input.value.trim());
}

function startLocal() {
  Arcade.dismissEnd();
  remote = null;
  shell.setOnline(false);
  const typed = readNames();
  const mine = Arcade.playerName() || (match.rival === "bot" ? "Toi" : "Joueur 1");
  const names = match.rival === "bot"
    ? [mine, "Ordi"]
    : [mine].concat(Array.from({ length: players - 1 }, (_, index) => typed[index] || "Joueur " + (index + 2)));
  local = {
    mode: match.rival === "bot" ? "bot" : "multi",
    size,
    mines: null,
    revealed: new Map(),
    flags: new Set(),
    names,
    alive: names.map(() => true),
    turn: 0,
    over: "",
    winner: 0
  };
  show("play");
  paintLocal();
}

function paintLobby(state) {
  const names = state.names || [];
  const cap = Number(state.config && state.config.humans) || 2;
  const boardSize = Number(state.config && state.config.size) || size;
  const ready = names.length >= cap;
  match.fillLobby(state, {
    role: "Grille " + boardSize + " × " + boardSize + ", " + mineTotal(boardSize) + " mines.",
    note: ready ? "Tout le monde est là." : "En attente : " + names.length + " / " + cap + ".",
    ready,
    host: state.you === 0
  });
}

function remoteText(state) {
  const names = state.names || [];
  const view = state.view || {};
  const eliminated = (view.eliminated || []).map(Number);
  if (state.phase === "done" && state.winner === -2) return "Plus aucun joueur.";
  if (state.phase === "done" && state.winner != null && state.winner >= 0) return (names[state.winner] || "Joueur") + " gagne.";
  if (state.phase === "done") return "Grille découverte.";
  const turn = "Au tour de " + (names[state.turn] || "?") + ".";
  if (eliminated.indexOf(state.you) >= 0) return "Tu es éliminé. " + turn;
  return turn;
}

function paintRemote(state) {
  const view = state.view || {};
  const over = state.phase === "done";
  paintGrid(view.size || 9, view.revealed || {}, view.flags || [], over ? view.mines || [] : [], over);
  status.textContent = remoteText(state);
}

net = Arcade.room("mines", (state) => {
  local = null;
  remote = state;
  shell.setOnline(true);
  if (state.phase === "lobby") {
    Arcade.announceOnce("mines", false, "");
    paintLobby(state);
    return;
  }
  show("play");
  paintRemote(state);
  Arcade.announceOnce("mines", state.phase === "done", `<p>${Arcade.escapeHtml(remoteText(state))}</p>`);
}, match.noteError);

function shiftPlayers(delta) {
  players = Math.max(2, Math.min(4, players + delta));
  paintPlayers();
  paintNames();
}

match.bindChoice("sizes", (button) => {
  size = Number(button.dataset.size);
  paintSize();
});
match.bindChoice("tool", (button) => { tool = button.dataset.tool; });
document.getElementById("players-less").onclick = () => shiftPlayers(-1);
document.getElementById("players-more").onclick = () => shiftPlayers(1);
document.getElementById("online-players-less").onclick = () => shiftPlayers(-1);
document.getElementById("online-players-more").onclick = () => shiftPlayers(1);
grid.addEventListener("click", (event) => {
  const button = event.target.closest("[data-i]");
  if (!button) return;
  const index = Number(button.dataset.i);
  if (local) clickLocal(index);
  else if (remote && remote.phase === "play" && remote.you === remote.turn) {
    const action = tool === "flag" ? "flag" : "open";
    net.act(action, { i: index }).catch((error) => { status.textContent = error.message; });
  }
});
document.getElementById("again").onclick = () => {
  if (remote) net.act("again", {}).catch((error) => { status.textContent = error.message; });
  else if (local) startLocal();
};
document.getElementById("leave").onclick = leaveTable;
paintPlayers();
paintSize();
if (Arcade.onlineOk()) net.resume();
