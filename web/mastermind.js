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
let markPegs = ["", "", "", ""];
let markKey = "";

function mastermindSettings() {
  const online = Boolean(remote);
  const mode = local
    ? (local.bot ? "Contre l'ordinateur" : "À deux")
    : (online ? "En ligne" : (match.rival === "two" ? "À deux" : "Contre l'ordinateur"));
  const limit = local ? local.tries : (online && remote.config ? remote.config.tries : tries);
  return [
    ["Partie", mode, "À deux, un joueur compose le code et place les indices. L'autre devine. Contre l'ordinateur, les indices sont posés tout seuls."],
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
  rules() {
    return [
      ["Code", "Quatre couleurs à deviner, dans le nombre d'essais choisi."],
      ["Indices", "Un pion rouge : bonne couleur, bien placée. Un pion blanc : bonne couleur, mal placée. À deux, celui qui a posé le code place ces pions."],
      ["Manche", "+1 relance une partie avec les mêmes joueurs. Les résultats restent dans Évolution, sur ce téléphone."]
    ];
  },
  guide: mastermindSteps,
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

function paintHistory(rows, pending) {
  const lines = rows.map((row, index) => {
    return `<div class="guess"><span class="guess-index">${index + 1}</span>${pegs(row.code)}${marks(row)}</div>`;
  });
  if (pending && pending.code && pending.code.length === 4) {
    lines.push(`<div class="guess"><span class="guess-index">${rows.length + 1}</span>${pegs(pending.code)}<span class="marks" aria-label="Indices en attente"></span></div>`);
  }
  history.innerHTML = lines.join("");
}

function paintSecret(code) {
  const row = document.getElementById("secret-row");
  const showCode = Boolean(code && code.length === 4);
  row.classList.toggle("hidden", !showCode);
  document.getElementById("secret-pegs").innerHTML = showCode
    ? code.map((color) => `<span class="peg" style="background:${COLORS[color]};color:${INK[color]}">${LETTERS[color]}</span>`).join("")
    : "";
}

function paintMarkPegs() {
  const labels = { "": "Indice vide", placed: "Bien placée", present: "Bonne couleur" };
  document.getElementById("mark-pegs").innerHTML = markPegs.map((peg, index) => {
    const kind = peg === "placed" ? " is-placed" : peg === "present" ? " is-present" : "";
    return `<button type="button" class="mark-peg${kind}" data-mark="${index}" aria-label="${labels[peg] || "Indice vide"}"></button>`;
  }).join("");
}

function syncMark(code, active) {
  const key = active && code ? code.join("-") : "";
  if (key !== markKey) {
    markKey = key;
    markPegs = ["", "", "", ""];
  }
  document.getElementById("mark-box").classList.toggle("hidden", !active);
  if (active) paintMarkPegs();
}

function markCounts() {
  return {
    black: markPegs.filter((peg) => peg === "placed").length,
    white: markPegs.filter((peg) => peg === "present").length
  };
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
  if (local.phase === "make" || local.phase === "pass-make") return (local.names[local.maker] || "Joueur") + " compose le code secret.";
  if (local.phase === "mark" || local.phase === "pass-mark") return (local.names[local.maker] || "Joueur") + " place les indices.";
  const last = local.guesses[local.guesses.length - 1];
  if (last && last.black === 4) return "Code trouvé.";
  if (local.phase === "done") return "Code non trouvé.";
  if (local.phase === "guess" || local.phase === "pass-guess") return "Essai " + (local.guesses.length + 1) + " / " + local.tries + ".";
  return "";
}

function renderLocal() {
  show("play");
  status.textContent = localStatus();
  const composing = local.phase === "make" || local.phase === "guess";
  const marking = local.phase === "mark";
  document.getElementById("send").hidden = !composing;
  draftRow.hidden = !composing;
  palette.hidden = !composing;
  paintSecret(!local.bot && marking ? local.secret : null);
  paintHistory(local.guesses, marking && local.pending ? { code: local.pending } : null);
  syncMark(local.pending, marking);
  paintReveal(local.phase === "done" && !(local.guesses.length && local.guesses[local.guesses.length - 1].black === 4) ? local.secret : null);
  paintDraft();
  noteLocalEnd();
  maybeGuide();
}

function openPass(copy, next) {
  local.phase = next;
  document.getElementById("pass-copy").textContent = copy;
  pass.classList.remove("hidden");
  renderLocal();
  draftRow.hidden = true;
  palette.hidden = true;
  document.getElementById("send").hidden = true;
  document.getElementById("mark-box").classList.add("hidden");
  document.getElementById("secret-row").classList.add("hidden");
}

function startLocal() {
  Arcade.dismissEnd();
  remote = null;
  shell.setOnline(false);
  resetDraft();
  markPegs = ["", "", "", ""];
  markKey = "";
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
    guesses: [],
    pending: null
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
  if (!local.bot) {
    local.pending = code;
    openPass("Passe le téléphone à " + (local.names[local.maker] || "l'autre joueur") + ". Il place les indices.", "pass-mark");
    return;
  }
  const result = scoreGuess(local.secret, code);
  local.guesses.push({ code, black: result.black, white: result.white });
  if (result.black === 4 || local.guesses.length >= local.tries) local.phase = "done";
  renderLocal();
}

function submitMarks() {
  if (local) {
    if (local.phase !== "mark" || !local.pending) return;
    const given = markCounts();
    const truth = scoreGuess(local.secret, local.pending);
    if (given.black !== truth.black || given.white !== truth.white) {
      status.textContent = "Ces indices ne correspondent pas au code.";
      return;
    }
    local.guesses.push({ code: local.pending, black: given.black, white: given.white });
    local.pending = null;
    markPegs = ["", "", "", ""];
    markKey = "";
    if (given.black === 4 || local.guesses.length >= local.tries) {
      local.phase = "done";
      renderLocal();
      return;
    }
    const guesser = 1 - local.maker;
    openPass("Passe le téléphone à " + (local.names[guesser] || "l'autre joueur") + ".", "pass-guess");
    return;
  }
  if (!remote || remote.phase !== "mark") return;
  net.act("mark", markCounts()).catch((error) => { status.textContent = error.message; });
}

function mastermindSteps() {
  return [
    ...Arcade.gateTour((mode) => match.setWhere(mode), {
      title: "Mastermind",
      text: "Quatre couleurs à deviner. Règle le nombre d'essais, et qui compose le code.",
      target: () => document.getElementById("step-create")
    }, "En ligne, tu poses le code ou tu devines. L'invitation s'affiche après la création."),
    Object.assign(Arcade.chromeStep(), { page: "play" }),
    {
      page: "play",
      title: "La proposition",
      render: Arcade.pictured(
        "Quatre cases. Choisis une couleur pour chacune, puis valide.",
        `<div class="coach-pegs"><span style="background:#2aa7b8">C</span><span class="is-ink" style="background:#2f6f9f">B</span><span class="is-ink" style="background:#2f8f5b">V</span><span style="background:#e2b33c">J</span></div><p class="coach-go">Valider</p>`
      ),
      target: () => document.getElementById("draft")
    },
    {
      page: "play",
      title: "Les indices",
      render: Arcade.pictured(
        "Le rouge : bien placée. Le blanc : bonne couleur. À deux, c'est celui qui a posé le code qui les place.",
        `<div class="coach-pair"><div class="sample"><span class="coach-dot is-placed"></span><span>Bien placée</span></div><div class="sample"><span class="coach-dot is-present"></span><span>Bonne couleur</span></div></div>`
      ),
      target: () => document.getElementById("hint-help")
    },
    Arcade.lobbyStep()
  ];
}

function maybeGuide() {
  const passBox = document.getElementById("pass");
  const passing = passBox && !passBox.classList.contains("hidden");
  const playing = local
    ? (local.phase === "make" || local.phase === "guess")
    : Boolean(remote && (remote.phase === "code" || remote.phase === "play"));
  Arcade.playGuide("mastermind-tutorial", mastermindSteps, playing && !passing);
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
  if (state.phase === "mark") return state.you === maker ? "Place les indices de cette proposition." : (names[maker] || "L'autre joueur") + " place les indices.";
  if (state.phase === "done" && state.view && state.view.solved) return (names[state.winner] || "Quelqu'un") + " a trouvé le code.";
  if (state.phase === "done") return "Code non trouvé.";
  return "Essai " + (count + 1) + " / " + limit + ". Au tour de " + (names[state.turn] || "?") + ".";
}

net = Arcade.room("mastermind", (state) => {
  local = null;
  remote = state;
  shell.setOnline(true, state.code);
  if (state.phase === "lobby") {
    wasDone = false;
    Arcade.announceOnce("mastermind", false, "");
    paintSecret(null);
    syncMark(null, false);
    paintLobby(state);
    return;
  }
  show("play");
  const view = state.view || { guesses: [] };
  const bot = Boolean(state.config && state.config.bot);
  const myTurn = state.phase !== "done" && state.you === state.turn;
  const marking = state.phase === "mark" && myTurn;
  const showSecret = !bot && state.phase !== "done" && Array.isArray(view.secret) && view.secret.length === 4;
  paintSecret(showSecret ? view.secret : null);
  paintHistory(view.guesses || [], view.pending || null);
  syncMark(view.pending && view.pending.code, marking);
  status.textContent = remoteText(state);
  document.getElementById("send").hidden = !myTurn || marking;
  draftRow.hidden = !myTurn || marking;
  palette.hidden = !myTurn || marking;
  paintReveal(state.phase === "done" && !(view.solved) ? view.secret : null);
  paintDraft();
  noteRemote(state);
  maybeGuide();
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
  else if (local.phase === "pass-mark") local.phase = "mark";
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
document.getElementById("mark-pegs").addEventListener("click", (event) => {
  const button = event.target.closest("[data-mark]");
  if (!button) return;
  const index = Number(button.dataset.mark);
  const order = ["", "placed", "present"];
  const at = Math.max(0, order.indexOf(markPegs[index]));
  markPegs[index] = order[(at + 1) % order.length];
  paintMarkPegs();
});
document.getElementById("mark-send").onclick = submitMarks;
document.getElementById("again").onclick = () => {
  if (remote) net.act("again", {}).catch((error) => { status.textContent = error.message; });
  else if (local) startLocal();
};
document.getElementById("leave").onclick = leaveTable;
paintPalette();
paintCareer();
if (Arcade.onlineOk()) net.resume();
