const LINES = [[0, 1, 2], [3, 4, 5], [6, 7, 8], [0, 3, 6], [1, 4, 7], [2, 5, 8], [0, 4, 8], [2, 4, 6]];

function winnerOf(cells) {
  for (let i = 0; i < LINES.length; i += 1) {
    const [a, b, c] = LINES[i];
    if (cells[a] && cells[a] === cells[b] && cells[b] === cells[c]) return cells[a];
  }
  if (cells.every((cell) => cell)) return "draw";
  return "";
}

function minimax(cells, mark) {
  const found = winnerOf(cells);
  if (found === "X") return { score: 1 };
  if (found === "O") return { score: -1 };
  if (found === "draw") return { score: 0 };
  let best = null;
  for (let i = 0; i < 9; i += 1) {
    if (cells[i]) continue;
    cells[i] = mark;
    const next = minimax(cells, mark === "X" ? "O" : "X");
    cells[i] = "";
    const score = next.score;
    if (!best || (mark === "X" ? score > best.score : score < best.score)) best = { score, index: i };
  }
  return best || { score: 0 };
}

const grid = document.getElementById("grid");
const status = document.getElementById("status");
let local = null;
let remote = null;
let net = null;

function morpionSettings() {
  const online = Boolean(remote);
  const mode = local
    ? (local.bot ? "Contre l'ordinateur" : "À deux")
    : (online ? "En ligne" : (match.rival === "two" ? "À deux" : "Contre l'ordinateur"));
  return [
    ["Partie", mode, "Contre l'ordinateur, à deux sur ce téléphone, ou à deux en ligne avec un code."],
    ["Table", online ? "En ligne · " + remote.code : "Sur ce téléphone", "Sur ce téléphone : sans connexion. En ligne : les autres rejoignent avec le code."]
  ];
}

function leaveTable() {
  match.release(net, remote);
  remote = null;
  local = null;
}

const match = Arcade.mountMatch({
  title: "Morpion",
  game: "morpion",
  board: "board",
  settings: morpionSettings,
  onReset() { leaveTable(); },
  onLeave() { leaveTable(); },
  onLocal() { startLocal(); },
  onOnline(name) {
    net.create(name, { bot: false, mark: match.chosen("online-side", "mark") || "X" }).catch((error) => {
      document.getElementById("create-error").textContent = error.message;
    });
  },
  onStart() {
    net.act("start", {}).catch((error) => { document.getElementById("lobby-note").textContent = error.message; });
  },
  currentRemote() { return remote; },
  syncWhere(mode, rival) {
    document.getElementById("two-box").classList.toggle("hidden", rival !== "two");
  },
  localHtml: `<div class="choice" id="rival">
      <button type="button" data-rival="bot" class="is-on">Contre l'ordinateur</button>
      <button type="button" data-rival="two">À deux</button>
    </div>
    <div id="two-box" class="hidden stack">
      <label class="field">Joueur 2
        <input id="name-1" maxlength="24" autocomplete="name" placeholder="Joueur 2">
      </label>
      <p class="lead">Joueur 1 joue</p>
      <div class="choice" id="side">
        <button type="button" data-mark="X" class="is-on">X</button>
        <button type="button" data-mark="O">O</button>
      </div>
      <p class="lead">X commence.</p>
    </div>`,
  onlineHtml: `<p class="lead">Tu joues</p>
    <div class="choice" id="online-side">
      <button type="button" data-mark="X" class="is-on">X</button>
      <button type="button" data-mark="O">O</button>
    </div>
    <p class="lead">X commence. L'invitation s'affiche après la création.</p>`
});

const shell = match.shell;
const show = match.show;
let wasDone = false;

function paintCareer() {
  shell.paintStats();
}

function noteLocal() {
  const found = winnerOf(local.cells);
  if (!found || local.noted) return;
  local.noted = true;
  if (found === "draw") {
    const people = local.bot
      ? [{ name: local.names[0], result: "draw" }]
      : local.names.map((name) => ({ name, result: "draw" }));
    Arcade.recordStats("morpion", people);
  }
  else if (local.bot) Arcade.recordStats("morpion", [{ name: local.names[0], result: local.marks[0] === found ? "win" : "loss" }]);
  else {
    const seat = local.marks.indexOf(found);
    Arcade.recordStats("morpion", local.names.map((name, index) => ({ name, result: index === seat ? "win" : "loss" })));
  }
  paintCareer();
  Arcade.announceOnce("morpion", true, `<p>${Arcade.escapeHtml(localText())}</p>`);
}

function noteRemote(state) {
  Arcade.announceOnce("morpion", state.phase === "done", `<p>${Arcade.escapeHtml(remoteText(state))}</p>`);
  if (state.phase !== "done") {
    wasDone = false;
    return;
  }
  if (wasDone) return;
  wasDone = true;
  const me = (state.names || [])[state.you] || "Joueur";
  const result = state.winner === -1 ? "draw" : (state.winner === state.you ? "win" : "loss");
  Arcade.recordStats("morpion", [{ name: me, result }]);
  paintCareer();
}

function paint(cells, text) {
  status.textContent = text;
  grid.innerHTML = cells.map((cell, index) => {
    return `<button type="button" class="xo" data-i="${index}">${cell || ""}</button>`;
  }).join("");
}

function localText() {
  const found = winnerOf(local.cells);
  if (found === "draw") return "Match nul.";
  if (found) {
    const seat = local.marks.indexOf(found);
    return (local.names[seat] || found) + " gagne.";
  }
  const mark = local.marks[local.turn];
  const extra = local.bot && local.turn === 1 ? " (ordinateur)" : "";
  return "Au tour de " + local.names[local.turn] + " (" + mark + ")" + extra + ".";
}

function playLocal(index) {
  if (!local || local.cells[index] || winnerOf(local.cells)) return;
  if (local.bot && local.turn !== 0) return;
  local.cells[index] = local.marks[local.turn];
  if (!winnerOf(local.cells)) {
    local.turn = 1 - local.turn;
    if (local.bot && local.turn === 1) {
      const choice = minimax(local.cells.slice(), local.marks[1]);
      if (choice.index != null) local.cells[choice.index] = local.marks[1];
      if (!winnerOf(local.cells)) local.turn = 0;
    }
  }
  paint(local.cells, localText());
  noteLocal();
}

function startLocal() {
  Arcade.dismissEnd();
  remote = null;
  shell.setOnline(false);
  const two = match.rival === "two";
  const first = Arcade.playerName();
  const second = document.getElementById("name-1").value.trim();
  const playerMark = two ? (match.chosen("side", "mark") || "X") : "X";
  local = {
    cells: Array(9).fill(""),
    bot: !two,
    names: two ? [first || "Joueur 1", second || "Joueur 2"] : [first || "Toi", "Ordi"],
    marks: playerMark === "O" ? ["O", "X"] : ["X", "O"],
    turn: 0
  };
  local.turn = local.marks.indexOf("X");
  show("board");
  paint(local.cells, localText());
}

function paintLobby(state) {
  const names = state.names || [];
  const marks = (state.view && state.view.marks) || ["X", "O"];
  const ready = names.length >= 2;
  match.fillLobby(state, {
    role: "Tu joues " + (marks[state.you] || "?") + ". X commence.",
    note: ready ? "Les deux joueurs sont là." : "En attente du deuxième joueur.",
    ready,
    host: state.you === 0
  });
}

function remoteText(state) {
  const names = state.names || [];
  const marks = (state.view && state.view.marks) || ["X", "O"];
  if (state.winner === -1) return "Match nul.";
  if (state.winner != null && state.winner >= 0) return (names[state.winner] || "Joueur") + " gagne.";
  return "Au tour de " + (names[state.turn] || "?") + " (" + (marks[state.turn] || "?") + ").";
}

net = Arcade.room("morpion", (state) => {
  local = null;
  remote = state;
  shell.setOnline(true);
  if (state.phase === "lobby") {
    wasDone = false;
    Arcade.announceOnce("morpion", false, "");
    paintLobby(state);
    return;
  }
  show("board");
  paint(state.view.cells || Array(9).fill(""), remoteText(state));
  noteRemote(state);
}, match.noteError);

grid.addEventListener("click", (event) => {
  const button = event.target.closest("[data-i]");
  if (!button) return;
  const index = Number(button.dataset.i);
  if (local) playLocal(index);
  else if (remote && remote.you === remote.turn && remote.phase === "play") {
    net.act("play", { i: index }).catch((error) => { status.textContent = error.message; });
  }
});

match.bindChoice("side");
match.bindChoice("online-side");
document.getElementById("again").onclick = () => {
  if (remote) net.act("again", {}).catch((error) => { status.textContent = error.message; });
  else if (local) startLocal();
};
document.getElementById("leave").onclick = leaveTable;
paintCareer();
if (Arcade.onlineOk()) net.resume();
