const COLORS = ["#2aa7b8", "#2f6f9f", "#2f8f5b", "#e2b33c", "#e07a2f", "#7a4ea3"];
const LETTERS = ["C", "B", "V", "J", "O", "M"];
const INK = ["#241c16", "#fffaf3", "#fffaf3", "#241c16", "#241c16", "#fffaf3"];

function scoreGuess(secret, guess) {
  const left = secret.slice();
  const tryColors = guess.slice();
  let black = 0;
  for (let i = 0; i < 4; i += 1) {
    if (tryColors[i] === left[i]) {
      black += 1;
      left[i] = -1;
      tryColors[i] = -2;
    }
  }
  let white = 0;
  for (let i = 0; i < 4; i += 1) {
    if (tryColors[i] < 0) continue;
    const at = left.indexOf(tryColors[i]);
    if (at >= 0) {
      white += 1;
      left[at] = -1;
    }
  }
  return { black, white };
}

function randomCode() {
  return [0, 1, 2, 3].map(() => Math.floor(Math.random() * COLORS.length));
}

function pegs(code) {
  return `<span class="pegs">${code.map((color) => `<span class="peg" style="background:${COLORS[color]};color:${INK[color]}">${LETTERS[color]}</span>`).join("")}</span>`;
}

function marks(result) {
  const dots = [];
  const placed = Number(result.black) || 0;
  const present = Number(result.white) || 0;
  for (let i = 0; i < placed; i += 1) dots.push(`<i class="mark placed"></i>`);
  for (let i = 0; i < present; i += 1) dots.push(`<i class="mark present"></i>`);
  while (dots.length < 4) dots.push(`<i class="mark"></i>`);
  return `<span class="marks" aria-label="${placed} bien placés, ${present} bonnes couleurs">${dots.join("")}</span>`;
}

const history = document.getElementById("history");
const reveal = document.getElementById("reveal");
const draftRow = document.getElementById("draft");
const palette = document.getElementById("palette");
const status = document.getElementById("status");
const pass = document.getElementById("pass");
let local = null;
let remote = null;
let net = null;
let draft = [];
let picking = 0;
let tries = 8;

function mastermindSettings() {
  const online = Boolean(remote);
  const mode = local
    ? (local.bot ? "Contre l'ordinateur" : "À deux")
    : (online ? "En ligne" : (match.rival === "two" ? "À deux" : "Contre l'ordinateur"));
  const limit = local ? local.tries : (online && remote.config ? remote.config.tries : tries);
  return [
    ["Partie", mode, "L'ordinateur pose le code, ou un joueur le compose et l'autre devine."],
    ["Essais", String(limit || tries), "Entre 4 et 12 propositions. Huit par défaut."],
    ["Table", online ? "En ligne · " + remote.code : "Sur ce téléphone", "Sur ce téléphone : sans connexion. En ligne : les autres rejoignent avec le code."]
  ];
}

function leaveTable() {
  pass.classList.add("hidden");
  match.release(net, remote);
  remote = null;
  local = null;
}

const match = Arcade.mountMatch({
  title: "Mastermind",
  game: "mastermind",
  board: "play",
  settings: mastermindSettings,
  onReset() { leaveTable(); },
  onLeave() { leaveTable(); },
  onLocal() { startLocal(); },
  onOnline(name) {
    net.create(name, {
      bot: false,
      role: match.chosen("role", "role") || "maker",
      tries
    }).catch((error) => { document.getElementById("create-error").textContent = error.message; });
  },
  onStart() {
    net.act("start", {}).catch((error) => { document.getElementById("lobby-note").textContent = error.message; });
  },
  currentRemote() { return remote; },
  syncWhere(mode, rival) {
    document.getElementById("two-box").classList.toggle("hidden", rival !== "two");
  },
  optionsHtml: `<p class="lead">Nombre d'essais</p>
    <div class="stepper">
      <button type="button" id="tries-less" aria-label="Moins d'essais">−</button>
      <strong id="tries-value">8</strong>
      <button type="button" id="tries-more" aria-label="Plus d'essais">+</button>
    </div>`,
  localHtml: `<div class="choice" id="rival">
      <button type="button" data-rival="bot" class="is-on">Contre l'ordinateur</button>
      <button type="button" data-rival="two">À deux</button>
    </div>
    <div id="two-box" class="hidden stack">
      <label class="field">Joueur 2
        <input id="name-1" maxlength="24" autocomplete="name" placeholder="Joueur 2">
      </label>
      <p class="lead">Qui compose le code</p>
      <div class="choice" id="maker">
        <button type="button" data-maker="0" class="is-on">Joueur 1</button>
        <button type="button" data-maker="1">Joueur 2</button>
      </div>
    </div>`,
  onlineHtml: `<p class="lead">Ton rôle</p>
    <div class="choice" id="role">
      <button type="button" data-role="maker" class="is-on">Je pose le code</button>
      <button type="button" data-role="breaker">Je devine</button>
    </div>
    <p class="lead">L'invitation s'affiche après la création.</p>`
});

const shell = match.shell;
const show = match.show;
let wasDone = false;

function paintCareer() {
  shell.paintStats();
}

function noteLocalEnd() {
  if (!local || local.phase !== "done" || local.noted) return;
  local.noted = true;
  const found = local.guesses.length && local.guesses[local.guesses.length - 1].black === 4;
  if (local.bot) Arcade.recordStats("mastermind", [{ name: local.names[0], result: found ? "win" : "loss" }]);
  else {
    const winner = found ? 1 - local.maker : local.maker;
    Arcade.recordStats("mastermind", local.names.map((name, index) => ({ name, result: index === winner ? "win" : "loss" })));
  }
  paintCareer();
  Arcade.announceOnce("mastermind", true, `<p>${Arcade.escapeHtml(localStatus())}</p>`);
}

function noteRemote(state) {
  Arcade.announceOnce("mastermind", state.phase === "done", `<p>${Arcade.escapeHtml(remoteText(state))}</p>`);
  if (state.phase !== "done") {
    wasDone = false;
    return;
  }
  if (wasDone) return;
  wasDone = true;
  const me = (state.names || [])[state.you] || "Joueur";
  const solved = Boolean(state.view && state.view.solved);
  const maker = state.config && state.config.maker != null ? Number(state.config.maker) : 0;
  const win = solved ? state.winner === state.you : maker === state.you;
  Arcade.recordStats("mastermind", [{ name: me, result: win ? "win" : "loss" }]);
  paintCareer();
}

function paintDraft() {
  draftRow.innerHTML = [0, 1, 2, 3].map((index) => {
    const color = draft[index];
    const on = index === picking ? " is-on" : "";
    if (color == null) return `<button type="button" class="slot${on}" data-slot="${index}">${index + 1}</button>`;
    return `<button type="button" class="slot is-filled${on}" data-slot="${index}" style="background:${COLORS[color]};color:${INK[color]}">${LETTERS[color]}</button>`;
  }).join("");
}

function paintHistory(rows) {
  history.innerHTML = rows.map((row, index) => {
    return `<div class="guess"><span class="guess-index">${index + 1}</span>${pegs(row.code)}${marks(row)}</div>`;
  }).join("");
}

function paintReveal(code) {
  reveal.innerHTML = code && code.length ? pegs(code) : "";
}

function paintPalette() {
  palette.innerHTML = COLORS.map((color, index) => {
    const ink = INK[index] === "#fffaf3" ? " ink-light" : "";
    return `<button type="button" class="swatch${ink}" data-color="${index}" style="background:${color};color:${INK[index]}">${LETTERS[index]}</button>`;
  }).join("");
}

function draftReady() {
  return [0, 1, 2, 3].every((index) => draft[index] != null);
}

function resetDraft() {
  draft = [];
  picking = 0;
}

function localStatus() {
  if (!local) return "";
  if (local.phase === "make") return (local.names[local.maker] || "Joueur") + " compose le code secret.";
  const last = local.guesses[local.guesses.length - 1];
  if (last && last.black === 4) return "Code trouvé.";
  if (local.phase === "done") return "Code non trouvé.";
  if (local.phase === "guess") return "Essai " + (local.guesses.length + 1) + " / " + local.tries + ".";
  return "";
}

function renderLocal() {
  show("play");
  status.textContent = localStatus();
  paintHistory(local.guesses);
  const composing = local.phase === "make" || local.phase === "guess";
  document.getElementById("send").hidden = !composing;
  draftRow.hidden = !composing;
  palette.hidden = !composing;
  paintReveal(local.phase === "done" && !(local.guesses.length && local.guesses[local.guesses.length - 1].black === 4) ? local.secret : null);
  paintDraft();
  noteLocalEnd();
}

function openPass(copy, next) {
  local.phase = next;
  document.getElementById("pass-copy").textContent = copy;
  pass.classList.remove("hidden");
  renderLocal();
  draftRow.hidden = true;
  palette.hidden = true;
  document.getElementById("send").hidden = true;
}

function startLocal() {
  Arcade.dismissEnd();
  remote = null;
  shell.setOnline(false);
  resetDraft();
  const two = match.rival === "two";
  const first = Arcade.playerName();
  const second = document.getElementById("name-1").value.trim();
  const maker = two ? Number(match.chosen("maker", "maker") || 0) : -1;
  local = {
    bot: !two,
    names: two ? [first || "Joueur 1", second || "Joueur 2"] : [first || "Toi", "Ordi"],
    maker,
    tries,
    phase: "guess",
    secret: two ? null : randomCode(),
    guesses: []
  };
  if (!two) {
    renderLocal();
    return;
  }
  if (maker === 0) {
    local.phase = "make";
    renderLocal();
    return;
  }
  openPass((local.names[1] || "Joueur 2") + " compose le code. Passe-lui le téléphone.", "pass-make");
}

function submitLocal() {
  if (!local || !draftReady()) {
    status.textContent = "Choisis quatre couleurs, de la case 1 à la case 4.";
    return;
  }
  const code = draft.slice(0, 4);
  resetDraft();
  if (local.phase === "make") {
    local.secret = code;
    const guesser = 1 - local.maker;
    openPass("Le code est caché. Passe le téléphone à " + (local.names[guesser] || "l'autre joueur") + ".", "pass-guess");
    return;
  }
  const result = scoreGuess(local.secret, code);
  local.guesses.push({ code, black: result.black, white: result.white });
  if (result.black === 4 || local.guesses.length >= local.tries) local.phase = "done";
  renderLocal();
}

function paintLobby(state) {
  const names = state.names || [];
  const maker = state.config && state.config.maker != null ? Number(state.config.maker) : 0;
  const limit = state.config && state.config.tries ? state.config.tries : 8;
  const ready = names.length >= 2;
  match.fillLobby(state, {
    role: (state.you === maker ? "Tu poses le code." : "Tu devines le code.") + " " + limit + " essais.",
    note: ready ? "Les deux joueurs sont là." : "En attente du deuxième joueur.",
    ready,
    host: state.you === 0
  });
}

function remoteText(state) {
  const names = state.names || [];
  const maker = state.config && state.config.maker != null ? Number(state.config.maker) : 0;
  const limit = state.config && state.config.tries ? state.config.tries : 8;
  const count = (state.view && state.view.guesses ? state.view.guesses.length : 0);
  if (state.phase === "code") return state.you === maker ? "Compose le code secret." : (names[maker] || "L'autre joueur") + " compose le code.";
  if (state.phase === "done" && state.view && state.view.solved) return (names[state.winner] || "Quelqu'un") + " a trouvé le code.";
  if (state.phase === "done") return "Code non trouvé.";
  return "Essai " + (count + 1) + " / " + limit + ". Au tour de " + (names[state.turn] || "?") + ".";
}

net = Arcade.room("mastermind", (state) => {
  local = null;
  remote = state;
  shell.setOnline(true);
  if (state.phase === "lobby") {
    wasDone = false;
    Arcade.announceOnce("mastermind", false, "");
    paintLobby(state);
    return;
  }
  show("play");
  const view = state.view || { guesses: [] };
  paintHistory(view.guesses || []);
  status.textContent = remoteText(state);
  const myTurn = state.phase !== "done" && state.you === state.turn;
  document.getElementById("send").hidden = !myTurn;
  draftRow.hidden = !myTurn;
  palette.hidden = !myTurn;
  paintReveal(state.phase === "done" && !(view.solved) ? view.secret : null);
  paintDraft();
  noteRemote(state);
}, match.noteError);

palette.addEventListener("click", (event) => {
  const button = event.target.closest("[data-color]");
  if (!button) return;
  draft[picking] = Number(button.dataset.color);
  if (picking < 3) picking += 1;
  paintDraft();
});
draftRow.addEventListener("click", (event) => {
  const button = event.target.closest("[data-slot]");
  if (!button) return;
  picking = Number(button.dataset.slot);
  paintDraft();
});
document.getElementById("send").onclick = () => {
  if (local) submitLocal();
  else if (remote) {
    if (!draftReady()) {
      status.textContent = "Choisis quatre couleurs, de la case 1 à la case 4.";
      return;
    }
    const action = remote.phase === "code" ? "secret" : "guess";
    net.act(action, { code: draft.slice(0, 4) }).then(() => resetDraft()).catch((error) => { status.textContent = error.message; });
  }
};
document.getElementById("pass-ok").onclick = () => {
  pass.classList.add("hidden");
  if (!local) return;
  if (local.phase === "pass-make") local.phase = "make";
  else if (local.phase === "pass-guess") local.phase = "guess";
  resetDraft();
  renderLocal();
};
document.getElementById("tries-less").onclick = () => {
  tries = Math.max(4, tries - 1);
  document.getElementById("tries-value").textContent = String(tries);
};
document.getElementById("tries-more").onclick = () => {
  tries = Math.min(12, tries + 1);
  document.getElementById("tries-value").textContent = String(tries);
};
match.bindChoice("maker");
match.bindChoice("role");
document.getElementById("hint-help").onclick = () => {
  const legend = document.getElementById("hint-legend");
  legend.hidden = !legend.hidden;
  document.getElementById("hint-help").setAttribute("aria-expanded", legend.hidden ? "false" : "true");
};
document.getElementById("again").onclick = () => {
  if (remote) net.act("again", {}).catch((error) => { status.textContent = error.message; });
  else if (local) startLocal();
};
document.getElementById("leave").onclick = leaveTable;
paintPalette();
paintCareer();
if (Arcade.onlineOk()) net.resume();
