const Arcade = (() => {
  function playerName() {
    return window.Prefs ? Prefs.playerName() : "";
  }

  function onlineOk() {
    return Boolean(window.YAMS_SUPABASE_URL && window.YAMS_SUPABASE_ANON_KEY);
  }

  function escapeHtml(value) {
    return String(value).replace(/[&<>"']/g, (char) => ({
      "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
    }[char]));
  }

  async function rpc(name, args) {
    const response = await fetch(String(window.YAMS_SUPABASE_URL).replace(/\/$/, "") + "/rest/v1/rpc/" + name, {
      method: "POST",
      headers: {
        apikey: window.YAMS_SUPABASE_ANON_KEY,
        Authorization: "Bearer " + window.YAMS_SUPABASE_ANON_KEY,
        "Content-Type": "application/json"
      },
      body: JSON.stringify(args)
    });
    let data = {};
    try { data = await response.json(); } catch (error) { data = {}; }
    if (!response.ok) throw new Error(data.message || data.error || "La table ne répond pas.");
    if (!data.ok) throw new Error(data.error || "La table ne répond pas.");
    return data;
  }

  const OPEN_KEY = "arcade-open-tables";

  function loadOpen() {
    try {
      const data = JSON.parse(localStorage.getItem(OPEN_KEY) || "[]");
      if (!Array.isArray(data)) return [];
      return data.filter((row) => row && row.game && row.code && row.token);
    } catch (error) {
      return [];
    }
  }

  function saveOpen(rows) {
    try {
      localStorage.setItem(OPEN_KEY, JSON.stringify(rows.slice(0, 12)));
    } catch (error) {
      // Le stockage local peut être refusé.
    }
  }

  function remember(game, code, token) {
    const clean = String(code || "").toUpperCase();
    if (!game || !clean || !token) return;
    if (game === "yams") {
      localStorage.setItem("yams-room-code", clean);
      localStorage.setItem("yams-room-token", token);
    } else {
      localStorage.setItem("arcade-" + game + "-code", clean);
      localStorage.setItem("arcade-" + game + "-token", token);
    }
    const rows = loadOpen().filter((row) => !(row.game === game && row.code === clean));
    rows.unshift({ game, code: clean, token, at: Date.now() });
    saveOpen(rows);
  }

  function recall(game) {
    if (game === "yams") {
      return {
        code: localStorage.getItem("yams-room-code") || "",
        token: localStorage.getItem("yams-room-token") || ""
      };
    }
    return {
      code: localStorage.getItem("arcade-" + game + "-code") || "",
      token: localStorage.getItem("arcade-" + game + "-token") || ""
    };
  }

  function unpinTable(game, code) {
    const clean = String(code || "").toUpperCase();
    if (!game || !clean) return;
    saveOpen(loadOpen().filter((row) => !(row.game === game && row.code === clean)));
    const saved = recall(game);
    if (String(saved.code || "").toUpperCase() !== clean) return;
    if (game === "yams") {
      localStorage.removeItem("yams-room-code");
      localStorage.removeItem("yams-room-token");
      return;
    }
    localStorage.removeItem("arcade-" + game + "-code");
    localStorage.removeItem("arcade-" + game + "-token");
  }

  function forget(game) {
    unpinTable(game, recall(game).code);
  }

  function seedOpen() {
    const rows = loadOpen();
    function add(game, code, token) {
      const clean = String(code || "").toUpperCase();
      if (!clean || !token) return;
      if (rows.some((row) => row.game === game && row.code === clean)) return;
      rows.unshift({ game, code: clean, token, at: Date.now() });
    }
    GAMES.forEach((game) => {
      const saved = recall(game.id);
      add(game.id, saved.code, saved.token);
    });
    saveOpen(rows);
  }

  function room(game, onState, onError) {
    let timer = 0;
    let code = "";
    let token = "";

    async function pull() {
      if (!token) return;
      try {
        const data = await rpc("arcade_state", { p_code: code, p_token: token });
        onState(data.state);
      } catch (error) {
        if (String(error.message).indexOf("introuvable") !== -1) {
          stop();
        }
        if (onError) onError(error.message);
      }
    }

    function start() {
      if (timer) return;
      timer = window.setInterval(pull, 1500);
    }

    function wake() {
      if (!token) return;
      window.clearInterval(timer);
      timer = 0;
      start();
      pull();
    }

    if (window.Prefs && typeof Prefs.onResume === "function") Prefs.onResume(wake);

    function stop() {
      window.clearInterval(timer);
      timer = 0;
      token = "";
      code = "";
      forget(game);
    }

    return {
      code: () => code,
      stop,
      async create(name, config) {
        const data = await rpc("arcade_create", { p_game: game, p_name: name, p_config: config || {} });
        token = data.token;
        code = data.state.code;
        remember(game, code, token);
        onState(data.state);
        start();
      },
      async join(joinCode, name) {
        const saved = recall(game);
        const data = await rpc("arcade_join", {
          p_code: joinCode,
          p_name: name,
          p_token: saved.code === joinCode ? saved.token : ""
        });
        token = data.token;
        code = data.state.code;
        remember(game, code, token);
        onState(data.state);
        start();
      },
      async act(action, payload) {
        const data = await rpc("arcade_act", {
          p_code: code,
          p_token: token,
          p_action: action,
          p_payload: payload || {}
        });
        onState(data.state);
      },
      async leave() {
        const savedCode = code;
        const savedToken = token;
        if (savedToken) {
          try {
            await rpc("arcade_leave", { p_code: savedCode, p_token: savedToken });
          } catch (error) { /* table déjà retirée */ }
        }
        stop();
      },
      resume() {
        const saved = recall(game);
        if (!saved.token || !saved.code) return false;
        token = saved.token;
        code = saved.code;
        start();
        pull();
        return true;
      }
    };
  }

  function loadStats(game) {
    try {
      const data = JSON.parse(localStorage.getItem("arcade-stats-" + game) || "");
      if (data && Array.isArray(data.rows)) return data;
    } catch (error) { /* stockage refusé */ }
    return { rows: [] };
  }

  function groupKey(names) {
    return names.map((name) => String(name || "").trim().toLocaleLowerCase("fr")).filter(Boolean).sort().join("|");
  }

  function loadRounds(game) {
    try {
      const data = JSON.parse(localStorage.getItem("arcade-rounds-" + game) || "");
      if (data && Array.isArray(data.groups)) return data;
    } catch (error) { /* stockage refusé */ }
    return { groups: [] };
  }

  function saveRounds(game, data) {
    try { localStorage.setItem("arcade-rounds-" + game, JSON.stringify(data)); } catch (error) { /* stockage refusé */ }
  }

  // Les manches terminées restent sur le téléphone, pour le même groupe de joueurs.
  function rememberRound(game, names, scores, stamp) {
    const key = groupKey(names);
    if (!key || !Array.isArray(scores) || scores.length !== names.length || !stamp) return;
    const data = loadRounds(game);
    let group = data.groups.find((item) => item.key === key);
    if (!group) {
      group = { key, names: names.slice(), rounds: [], stamps: [] };
      data.groups.push(group);
    }
    if ((group.stamps || []).indexOf(stamp) >= 0) return;
    group.names = names.slice();
    group.rounds.push(scores.map((score) => Number(score) || 0));
    group.rounds = group.rounds.slice(-30);
    group.stamps = (group.stamps || []).concat(stamp).slice(-30);
    data.groups = data.groups.slice(-12);
    saveRounds(game, data);
  }

  function roundTotals(game, names) {
    const totals = names.map(() => 0);
    const group = loadRounds(game).groups.find((item) => item.key === groupKey(names));
    if (!group) return totals;
    group.rounds.forEach((round) => {
      names.forEach((name, index) => {
        const saved = group.names.findIndex((item) => String(item || "").trim().toLocaleLowerCase("fr") === String(name || "").trim().toLocaleLowerCase("fr"));
        if (saved >= 0) totals[index] += Number(round[saved]) || 0;
      });
    });
    return totals;
  }

  function seriesLines(game) {
    return loadRounds(game).groups.map((group) => {
      const totals = group.names.map((_, index) => group.rounds.reduce((sum, round) => sum + (Number(round[index]) || 0), 0));
      const people = group.names.map((name, index) => name + " " + totals[index]).join(" · ");
      const count = group.rounds.length;
      return people + " — " + count + (count > 1 ? " manches" : " manche");
    });
  }

  function paintRoundTotals(game, node, names, scores, includeLive, seat) {
    if (!node) return;
    if (!names || !names.length) {
      node.hidden = true;
      return;
    }
    const chosen = Number.isInteger(seat) && seat >= 0 && seat < names.length ? seat : -1;
    const indexes = chosen >= 0 ? [chosen] : names.map((_, index) => index);
    node.hidden = false;
    const saved = roundTotals(game, names);
    if (indexes.length === 1) {
      const index = indexes[0];
      const live = includeLive ? (Number(scores && scores[index]) || 0) : 0;
      node.innerHTML = `<h2>Score général</h2><strong>${(saved[index] || 0) + live}</strong>`;
      return;
    }
    const rows = indexes.map((index) => {
      const live = includeLive ? (Number(scores && scores[index]) || 0) : 0;
      return `<li><span>${escapeHtml(names[index])}</span><strong>${(saved[index] || 0) + live}</strong></li>`;
    }).join("");
    node.innerHTML = `<h2>Score général</h2><ul>${rows}</ul>`;
  }

  function paintSeats(node, people) {
    if (!node) return;
    node.className = "tabs";
    node.replaceChildren();
    const scores = (people || []).map((person) => Number(person.score) || 0);
    const best = scores.length ? Math.max(...scores) : 0;
    (people || []).forEach((person, index) => {
      const item = document.createElement("div");
      item.className = "tab";
      if (person.active) item.classList.add("is-active");
      if (best > 0 && scores[index] === best) item.classList.add("is-leader");
      const seatNode = document.createElement("span");
      seatNode.className = "seat";
      seatNode.textContent = "#" + (index + 1);
      const who = document.createElement("span");
      who.className = "who";
      who.textContent = person.name || ("Joueur " + (index + 1));
      const pts = document.createElement("span");
      pts.className = "pts";
      pts.textContent = String(scores[index]);
      item.append(seatNode, who, pts);
      if (Number.isInteger(person.tiles)) {
        const left = document.createElement("span");
        left.className = "left";
        const count = person.tiles;
        left.textContent = count + (count > 1 ? " tuiles" : " tuile");
        item.append(left);
      }
      node.append(item);
    });
  }

  function recordStats(game, people) {
    const data = loadStats(game);
    people.forEach((person) => {
      data.rows.push({ name: person.name || "Joueur", result: person.result, at: Date.now() });
    });
    data.rows = data.rows.slice(-40);
    try { localStorage.setItem("arcade-stats-" + game, JSON.stringify(data)); } catch (error) { /* stockage refusé */ }
    return data;
  }

  function statsView(game) {
    const data = loadStats(game);
    const names = {};
    data.rows.forEach((row) => {
      if (!names[row.name]) names[row.name] = { win: 0, loss: 0, draw: 0 };
      if (row.result === "win" || row.result === "loss" || row.result === "draw") names[row.name][row.result] += 1;
    });
    const lines = Object.keys(names).map((name) => {
      const item = names[name];
      const parts = [
        item.win + (item.win > 1 ? " victoires" : " victoire"),
        item.loss + (item.loss > 1 ? " défaites" : " défaite")
      ];
      if (item.draw) parts.push(item.draw + (item.draw > 1 ? " nuls" : " nul"));
      return name + " : " + parts.join(", ");
    });
    const recent = data.rows.slice(-8).reverse().map((row) => {
      const word = row.result === "win" ? "Victoire" : row.result === "loss" ? "Défaite" : "Nul";
      return word + (row.name ? " · " + row.name : "");
    });
    return { lines, recent };
  }

  const gearIcon = `<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M19.14 12.94c.04-.31.06-.63.06-.94s-.02-.63-.06-.94l2.03-1.58a.5.5 0 0 0 .12-.64l-1.92-3.32a.5.5 0 0 0-.6-.22l-2.39.96a7.2 7.2 0 0 0-1.63-.94l-.36-2.54a.5.5 0 0 0-.5-.42h-3.84a.5.5 0 0 0-.5.42l-.36 2.54c-.58.23-1.12.54-1.63.94l-2.39-.96a.5.5 0 0 0-.6.22L2.71 8.84a.5.5 0 0 0 .12.64l2.03 1.58c-.04.31-.06.63-.06.94s.02.63.06.94l-2.03 1.58a.5.5 0 0 0-.12.64l1.92 3.32c.13.23.4.32.64.22l2.39-.96c.5.4 1.05.72 1.63.94l.36 2.54c.05.24.26.42.5.42h3.84c.24 0 .45-.18.5-.42l.36-2.54c.58-.22 1.12-.54 1.63-.94l2.39.96c.24.1.51 0 .64-.22l1.92-3.32a.5.5 0 0 0-.12-.64l-2.03-1.58zM12 15.5A3.5 3.5 0 1 1 12 8.5a3.5 3.5 0 0 1 0 7z"/></svg>`;
  const tablesIcon = `<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3.5" y="4" width="17" height="16" rx="2.2" fill="none" stroke="currentColor" stroke-width="1.8"/><path fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" d="M7.5 8.5h9M7.5 12h9M7.5 15.5h5"/></svg>`;
  const backIcon = `<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" d="M9 14 4 9l5-5"/><path fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" d="M4 9h10.5a5.5 5.5 0 0 1 0 11H12"/></svg>`;
  const refreshIcon = `<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" d="M21 12a9 9 0 0 0-9-9 9.7 9.7 0 0 0-6.7 2.7L3 8"/><path fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" d="M3 3v5h5"/><path fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" d="M3 12a9 9 0 0 0 9 9 9.7 9.7 0 0 0 6.7-2.7L21 16"/><path fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" d="M21 21v-5h-5"/></svg>`;
  const rulesIcon = `<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="8.2" fill="none" stroke="currentColor" stroke-width="1.8"/><path fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" d="M9.4 9.3a2.7 2.7 0 1 1 3.4 2.6c-.7.3-1.2.8-1.2 1.6V14.2"/><circle cx="11.6" cy="17" r="0.9" fill="currentColor"/></svg>`;
  const statsIcon = `<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="13" width="4.5" height="8" rx="1.2" fill="currentColor"/><rect x="9.75" y="8" width="4.5" height="13" rx="1.2" fill="currentColor"/><rect x="16.5" y="3" width="4.5" height="18" rx="1.2" fill="currentColor"/></svg>`;
  const playIcon = `<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3.5" y="3.5" width="17" height="17" rx="3.5" fill="none" stroke="currentColor" stroke-width="1.8"/><circle cx="8.2" cy="8.2" r="1.25" fill="currentColor"/><circle cx="15.8" cy="8.2" r="1.25" fill="currentColor"/><circle cx="8.2" cy="12" r="1.25" fill="currentColor"/><circle cx="15.8" cy="12" r="1.25" fill="currentColor"/><circle cx="8.2" cy="15.8" r="1.25" fill="currentColor"/><circle cx="15.8" cy="15.8" r="1.25" fill="currentColor"/></svg>`;

  function mountShell(options) {
    const tools = options.tools !== false;
    const header = document.createElement("header");
    header.className = "topbar";
    const backButton = `<button type="button" class="icon-btn" id="shell-back" aria-label="Retour"${options.back === false ? " hidden" : ""}>${backIcon}</button>`;
    const hubLinks = options.hub ? `<div class="brand-common">
        <a class="icon-btn" href="admin.html" aria-label="Tables">${tablesIcon}</a>
        <a class="icon-btn" id="hub-settings" href="parametres.html" aria-label="Paramètres">${gearIcon}</a>
        ${backButton}
      </div>` : "";
    const linkMark = `<span class="link-mark" id="shell-link" title="Sur ce téléphone" aria-label="Sur ce téléphone">
          <svg class="link-off" viewBox="0 0 24 24" aria-hidden="true"><path fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" d="M4 9.5c3.6-3 12.4-3 16 0M7.2 13c2.2-1.8 7.4-1.8 9.6 0M10 16.2c1.1-.8 2.9-.8 4 0"/><circle cx="12" cy="19" r="1.15" fill="currentColor"/><path fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" d="M5 5l14 14"/></svg>
          <svg class="link-on" viewBox="0 0 24 24" aria-hidden="true"><path fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" d="M4 9.5c3.6-3 12.4-3 16 0M7.2 13c2.2-1.8 7.4-1.8 9.6 0M10 16.2c1.1-.8 2.9-.8 4 0"/><circle cx="12" cy="19" r="1.15" fill="currentColor"/></svg>
        </span>`;
    const common = tools ? `<div class="brand-common">
        <a class="icon-btn" href="index.html" aria-label="Tous les jeux"><svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="3" width="7.5" height="7.5" rx="1.6" fill="currentColor"/><rect x="13.5" y="3" width="7.5" height="7.5" rx="1.6" fill="currentColor"/><rect x="3" y="13.5" width="7.5" height="7.5" rx="1.6" fill="currentColor"/><rect x="13.5" y="13.5" width="7.5" height="7.5" rx="1.6" fill="currentColor"/></svg></a>
        <button type="button" class="icon-btn is-active" id="shell-play" aria-pressed="true" aria-label="Jeu">${playIcon}</button>
        <button type="button" class="icon-btn" id="shell-stats-tab" aria-pressed="false" aria-label="Évolution">${statsIcon}</button>
        ${backButton}
      </div>` : (options.hub ? "" : `<div class="brand-common">${backButton}</div>`);
    const toolsRow = tools ? `<div class="game-tools" id="shell-tools" hidden>
        <button type="button" class="table-code" id="table-code" hidden aria-label="Copier l'invitation"></button>
        <div class="tool-actions">
          <button type="button" class="icon-btn" id="shell-reset" aria-label="Remettre à zéro">${refreshIcon}</button>
          <button type="button" class="icon-btn" id="add-manche" hidden aria-label="Ajouter une manche">+1</button>
          <button type="button" class="icon-btn" id="rules-open" aria-label="Règles">${rulesIcon}</button>
          <button type="button" class="icon-btn" id="shell-settings-open" aria-label="Réglages">${gearIcon}</button>
          <button type="button" class="icon-btn" id="shell-leave" aria-label="Quitter la table"><svg viewBox="0 0 24 24" aria-hidden="true"><path fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" d="M6 6l12 12M18 6 6 18"/></svg></button>
        </div>
      </div>` : "";
    header.innerHTML = `<div class="brand-row">
      ${tools ? linkMark : ""}
      <h1>${escapeHtml(options.title || "Jeu")}</h1>
      ${common || hubLinks}
    </div>${toolsRow}`;
    document.body.prepend(header);
    const backNode = document.getElementById("shell-back");
    function leaveBack() {
      if (typeof options.onBack === "function") options.onBack();
      else window.location.href = "index.html";
    }
    function setBack(visible) {
      if (backNode) backNode.hidden = !visible;
    }
    if (!tools) {
      if (backNode) backNode.onclick = leaveBack;
      return { setOnline() {}, paintStats() {}, showPlay() {}, setBack };
    }
    const evolution = document.createElement("section");
    evolution.className = "page";
    evolution.id = "shell-evolution";
    evolution.hidden = true;
    evolution.innerHTML = `<h2 class="section-title">Évolution</h2><div id="shell-stats"></div>`;
    header.insertAdjacentElement("afterend", evolution);

    document.body.insertAdjacentHTML("beforeend", `<div class="dialog" id="shell-settings" hidden>
      <div class="dialog-card" role="dialog" aria-modal="true" aria-labelledby="shell-settings-title">
        <h2 id="shell-settings-title">Paramètres</h2>
        <ul class="settings-list" id="shell-settings-list"></ul>
        <button type="button" class="btn text" id="shell-settings-close">Fermer</button>
      </div>
    </div>
    <div class="dialog is-center" id="rules-dialog" hidden>
      <div class="dialog-card is-sheet" role="dialog" aria-modal="true" aria-labelledby="rules-title">
        <h2 id="rules-title">Règles</h2>
        <div id="rules-body"></div>
        <button type="button" class="btn primary" id="rules-guide">Lancer l'aide</button>
        <button type="button" class="btn text" id="rules-close">Fermer</button>
      </div>
    </div>
    <div class="dialog is-center" id="shell-reset-dialog" hidden>
      <div class="dialog-card" role="dialog" aria-modal="true" aria-labelledby="shell-reset-title">
        <h2 id="shell-reset-title">Remettre à zéro</h2>
        <p>La partie en cours s'efface. Tu reviens à l'accueil des jeux.</p>
        <button type="button" class="btn primary" id="shell-reset-yes">Tout effacer</button>
        <button type="button" class="btn text" id="shell-reset-no">Annuler</button>
      </div>
    </div>`);

    function paintLink(online, code) {
      const mark = document.getElementById("shell-link");
      mark.classList.toggle("is-online", Boolean(online));
      const label = online ? "En ligne" : "Sur ce téléphone";
      mark.title = label;
      mark.setAttribute("aria-label", label);
      const button = document.getElementById("table-code");
      if (!button) return;
      const shown = Boolean(online && code);
      button.hidden = !shown;
      button.dataset.code = shown ? code : "";
      if (shown && button.dataset.copied !== "1") {
        button.textContent = code;
        button.setAttribute("aria-label", "Copier l'invitation, table " + code);
      }
    }

    function paintStats() {
      const view = statsView(options.game);
      const lines = view.lines.length ? view.lines : ["Aucune partie terminée."];
      const recent = view.recent.map((line) => `<li>${escapeHtml(line)}</li>`).join("");
      const series = seriesLines(options.game);
      const kept = series.length
        ? `<p class="lead">Score général, sur ce téléphone</p><ul class="lobby-list">${series.map((line) => `<li>${escapeHtml(line)}</li>`).join("")}</ul>`
        : "";
      document.getElementById("shell-stats").innerHTML = kept
        + lines.map((line) => `<p class="lead">${escapeHtml(line)}</p>`).join("")
        + (recent ? `<ul class="lobby-list">${recent}</ul>` : "");
    }

    function showView(name) {
      const play = name !== "evolution";
      const app = document.getElementById("app");
      if (app) app.hidden = !play;
      evolution.hidden = play;
      const gameButton = document.getElementById("shell-play");
      const statsButton = document.getElementById("shell-stats-tab");
      gameButton.classList.toggle("is-active", play);
      statsButton.classList.toggle("is-active", !play);
      gameButton.setAttribute("aria-pressed", play ? "true" : "false");
      statsButton.setAttribute("aria-pressed", play ? "false" : "true");
      if (backNode) backNode.setAttribute("aria-label", play ? "Retour" : "Retour au jeu");
      if (!play) paintStats();
    }

    if (backNode) {
      backNode.onclick = () => {
        if (!evolution.hidden) {
          showView("play");
          return;
        }
        leaveBack();
      };
    }

    document.getElementById("shell-play").onclick = () => showView("play");
    document.getElementById("shell-stats-tab").onclick = () => showView("evolution");
    document.getElementById("shell-settings-open").onclick = () => {
      const rows = typeof options.settings === "function" ? options.settings() : [];
      document.getElementById("shell-settings-list").innerHTML = rows.map((row, index) => {
        const helpId = "shell-help-" + index;
        return `<li><span class="setting-label">${escapeHtml(row[0])}</span><strong class="setting-value">${escapeHtml(row[1])}</strong><button type="button" class="help-btn" data-help="${helpId}" aria-expanded="false" aria-label="Explication de ${escapeHtml(row[0])}">?</button></li><p class="help-text" id="${helpId}" hidden>${escapeHtml(row[2] || "")}</p>`;
      }).join("");
      document.getElementById("shell-settings").hidden = false;
    };
    document.getElementById("shell-settings").addEventListener("click", (event) => {
      const button = event.target.closest("[data-help]");
      if (!button) return;
      const node = document.getElementById(button.dataset.help);
      if (!node) return;
      node.hidden = !node.hidden;
      button.setAttribute("aria-expanded", node.hidden ? "false" : "true");
    });
    document.getElementById("shell-settings-close").onclick = () => { document.getElementById("shell-settings").hidden = true; };
    document.getElementById("shell-reset").onclick = () => { document.getElementById("shell-reset-dialog").hidden = false; };
    document.getElementById("shell-reset-no").onclick = () => { document.getElementById("shell-reset-dialog").hidden = true; };
    document.getElementById("shell-reset-yes").onclick = () => {
      document.getElementById("shell-reset-dialog").hidden = true;
      if (options.onReset) options.onReset();
      showView("play");
    };
    const leaveNode = document.getElementById("shell-leave");
    if (leaveNode) {
      leaveNode.onclick = () => {
        if (options.onLeave) options.onLeave();
      };
    }
    function setLeave(on) {
      if (leaveNode) leaveNode.hidden = !on;
      const again = document.getElementById("add-manche");
      if (again) again.hidden = !on;
    }
    const rulesButton = document.getElementById("rules-open");
    if (rulesButton) {
      rulesButton.hidden = typeof options.rules !== "function";
      rulesButton.onclick = () => {
        const rows = options.rules ? options.rules() : [];
        document.getElementById("rules-body").innerHTML = `<ul class="rules">${rows.map((row) => `<li><strong>${escapeHtml(row[0])}.</strong> ${escapeHtml(row[1])}</li>`).join("")}</ul>`;
        const guide = document.getElementById("rules-guide");
        guide.hidden = typeof options.guide !== "function";
        document.getElementById("rules-dialog").hidden = false;
      };
    }
    document.getElementById("rules-close").onclick = () => { document.getElementById("rules-dialog").hidden = true; };
    document.getElementById("rules-dialog").addEventListener("click", (event) => {
      if (event.target.id === "rules-dialog") document.getElementById("rules-dialog").hidden = true;
    });
    document.getElementById("rules-guide").onclick = () => {
      document.getElementById("rules-dialog").hidden = true;
      forgetFlag(options.game + "-tutorial");
      forgetFlag("arcade-chrome-tour");
      clearHelpOrigin();
      if (typeof options.guide === "function") guideOn(options.game + "-tutorial", options.guide, "all");
    };
    document.getElementById("add-manche").onclick = () => {
      dismissEnd();
      const again = document.getElementById("again");
      if (again) again.click();
    };
    document.getElementById("table-code").onclick = async () => {
      const button = document.getElementById("table-code");
      const code = button.dataset.code;
      if (!code) return;
      const text = options.title + ". Pour me rejoindre, utilise le code : " + code + ".";
      let copied = false;
      try {
        await navigator.clipboard.writeText(text);
        copied = true;
      } catch (error) {
        try {
          if (navigator.share) {
            await navigator.share({ text });
            copied = true;
          }
        } catch (shareError) {
          if (shareError && shareError.name === "AbortError") return;
        }
      }
      if (!copied) return;
      button.dataset.copied = "1";
      button.textContent = "Copié";
      window.setTimeout(() => {
        button.dataset.copied = "";
        if (button.dataset.code) button.textContent = button.dataset.code;
      }, 1400);
    };
    function setPlaying(on) {
      const row = document.getElementById("shell-tools");
      if (row) row.hidden = !on;
    }

    paintLink(false);
    paintStats();
    return {
      setOnline: paintLink,
      paintStats,
      setPlaying,
      setLeave,
      setBack,
      showPlay() { showView("play"); }
    };
  }

  const endStamps = {};
  let endKey = "";

  function ensureEnd() {
    if (document.getElementById("end-dialog")) return;
    document.body.insertAdjacentHTML("beforeend", `<div class="dialog is-center" id="end-dialog" hidden>
      <div class="dialog-card" role="dialog" aria-modal="true" aria-labelledby="end-title">
        <h2 id="end-title">Fin de partie</h2>
        <div id="end-body"></div>
        <button type="button" class="btn primary" id="end-again">Rejouer</button>
        <button type="button" class="btn text" id="end-leave">Quitter</button>
      </div>
    </div>`);
    document.getElementById("end-again").onclick = () => {
      dismissEnd();
      const again = document.getElementById("again");
      if (again) again.click();
    };
    document.getElementById("end-leave").onclick = () => {
      dismissEnd();
      const leave = document.getElementById("leave");
      if (leave) leave.click();
    };
  }

  function announceOnce(bucket, active, html) {
    ensureEnd();
    const dialog = document.getElementById("end-dialog");
    if (!active) {
      if (endStamps[bucket]) {
        endStamps[bucket] = "";
        if (endKey.indexOf(bucket + ":") === 0) {
          endKey = "";
          dialog.hidden = true;
        }
      }
      return;
    }
    if (!endStamps[bucket]) endStamps[bucket] = bucket + ":" + Date.now();
    if (endStamps[bucket] === endKey) return;
    endKey = endStamps[bucket];
    document.getElementById("end-body").innerHTML = html;
    dialog.hidden = false;
    suspendCoach();
  }

  function dismissEnd() {
    Object.keys(endStamps).forEach((key) => { endStamps[key] = ""; });
    endKey = "";
    const dialog = document.getElementById("end-dialog");
    if (dialog) dialog.hidden = true;
  }

  // Catalogue du hub. Les tables temporaires ne sont pas un jeu.
  const GAMES = [
    { id: "yams", title: "Yams", href: "yams.html", text: "La feuille de score, en local ou en ligne." },
    { id: "morpion", title: "Morpion", href: "morpion.html", text: "Trois cases alignées. À deux, ou contre l'ordinateur." },
    { id: "mastermind", title: "Mastermind", href: "mastermind.html", text: "Devine le code de quatre couleurs." },
    { id: "mines", title: "Démineur", href: "mines.html", text: "Un carré, des mines cachées. Seul ou chacun son tour." },
    { id: "triomino", title: "Triomino", href: "triomino.html", text: "Des tuiles triangulaires à relier. De 2 à 5 joueurs." }
  ];

  function gameTitle(id) {
    const found = GAMES.find((game) => game.id === id);
    return found ? found.title : id;
  }

  function gameCards() {
    return GAMES.map((game) => {
      return `<a class="card" href="${escapeHtml(game.href)}"><strong>${escapeHtml(game.title)}</strong><span>${escapeHtml(game.text)}</span></a>`;
    }).join("");
  }

  function savedArcadeToken(code) {
    const clean = String(code || "").toUpperCase();
    for (let index = 0; index < GAMES.length; index += 1) {
      if (GAMES[index].id === "yams") continue;
      const saved = recall(GAMES[index].id);
      if (saved.code === clean && saved.token) return saved.token;
    }
    return "";
  }

  async function joinTable(code, name) {
    const clean = String(code || "").trim().toUpperCase();
    const who = String(name || playerName() || "").trim() || "Joueur";
    if (!clean) throw new Error("Saisis le code de la table.");
    if (!onlineOk()) throw new Error("La table en ligne n'est pas configurée sur cet appareil.");
    try {
      const data = await rpc("arcade_join", { p_code: clean, p_name: who, p_token: savedArcadeToken(clean) });
      const game = GAMES.find((item) => item.id === data.state.game);
      remember(data.state.game, data.state.code, data.token);
      rememberHelpOrigin("join");
      window.location.href = game ? game.href : "index.html";
      return;
    } catch (error) {
      if (String(error.message).indexOf("introuvable") === -1) throw error;
    }
    const yamsCode = localStorage.getItem("yams-room-code") || "";
    const yamsToken = yamsCode === clean ? (localStorage.getItem("yams-room-token") || "") : "";
    const data = await rpc("yams_join_room", { p_code: clean, p_name: who, p_token: yamsToken });
    remember("yams", data.state.code, data.token);
    rememberHelpOrigin("join");
    window.location.href = "yams.html";
  }

  let openEpoch = 0;

  function tableNames(game, state) {
    if (!state) return [];
    if (game === "yams") return (state.players || []).map((player) => player && player.name).filter(Boolean);
    return (state.names || []).filter(Boolean);
  }

  async function paintOpenTables() {
    const box = document.getElementById("open-tables");
    if (!box) return;
    const epoch = ++openEpoch;
    seedOpen();
    const rows = loadOpen();
    if (!rows.length || !onlineOk()) {
      box.innerHTML = "";
      return;
    }
    box.innerHTML = `<p class="lead">En cours</p><div class="stack" id="open-list"></div>`;
    const list = document.getElementById("open-list");
    const shown = [];
    for (let index = 0; index < rows.length; index += 1) {
      const row = rows[index];
      try {
        const data = row.game === "yams"
          ? await rpc("yams_state", { p_code: row.code, p_token: row.token })
          : await rpc("arcade_state", { p_code: row.code, p_token: row.token });
        if (epoch !== openEpoch) return;
        if (!data.state || data.state.phase === "done") {
          unpinTable(row.game, row.code);
          continue;
        }
        shown.push({ game: row.game, code: row.code, token: row.token, names: tableNames(row.game, data.state) });
      } catch (error) {
        if (epoch !== openEpoch) return;
        if (String(error.message).indexOf("introuvable") !== -1) unpinTable(row.game, row.code);
      }
    }
    if (epoch !== openEpoch) return;
    if (!shown.length || !list) {
      box.innerHTML = "";
      return;
    }
    list.innerHTML = shown.map((row) => {
      const who = row.names.join(", ");
      const detail = "Table " + row.code + (who ? " · " + who : "");
      return `<button type="button" data-open-game="${escapeHtml(row.game)}" data-open-code="${escapeHtml(row.code)}"><strong>${escapeHtml(gameTitle(row.game))}</strong><small>${escapeHtml(detail)}</small></button>`;
    }).join("");
    list.querySelectorAll("button").forEach((button) => {
      button.onclick = () => {
        const row = loadOpen().find((item) => item.game === button.dataset.openGame && item.code === button.dataset.openCode);
        if (!row) return;
        remember(row.game, row.code, row.token);
        const found = GAMES.find((item) => item.id === row.game);
        window.location.href = found ? found.href : "index.html";
      };
    });
  }

  function mountDoor() {
    const app = document.getElementById("app");
    let shell;
    function showDoor(step) {
      document.getElementById("door-home").classList.toggle("hidden", step !== "home");
      document.getElementById("door-create").classList.toggle("hidden", step !== "create");
      document.getElementById("door-join").classList.toggle("hidden", step !== "join");
      shell.setBack(step !== "home");
      if (step === "home") paintOpenTables();
    }
    shell = mountShell({
      title: "Jeux",
      tools: false,
      hub: true,
      back: false,
      onBack() { showDoor("home"); }
    });
    app.innerHTML = `<p class="lead">Sur ce téléphone, ou à plusieurs avec un code.</p>
      <section id="door-home" class="stack">
        <button type="button" id="door-go-create">Créer une partie</button>
        <button type="button" id="door-go-join">Rejoindre une partie</button>
        <div class="open-tables" id="open-tables"></div>
      </section>
      <section id="door-create" class="hidden">
        <nav class="cards" id="hub-games"></nav>
      </section>
      <section id="door-join" class="hidden stack">
        <label class="field">Code
          <input id="join-code" maxlength="4" autocapitalize="characters" autocomplete="off" placeholder="CODE">
        </label>
        <p class="status" id="join-error"></p>
        <button type="button" class="primary" id="join-go">Rejoindre</button>
      </section>`;
    document.getElementById("hub-games").innerHTML = gameCards();
    document.getElementById("door-go-create").onclick = () => showDoor("create");
    document.getElementById("door-go-join").onclick = () => showDoor("join");
    paintOpenTables();
    const codeInput = document.getElementById("join-code");
    codeInput.addEventListener("input", () => { codeInput.value = codeInput.value.toUpperCase(); });
    document.getElementById("join-go").onclick = () => {
      const errorNode = document.getElementById("join-error");
      errorNode.textContent = "";
      joinTable(codeInput.value, playerName()).catch((error) => {
        errorNode.textContent = error.message;
      });
    };
    document.getElementById("hub-games").addEventListener("click", (event) => {
      if (event.target.closest("a")) {
        rememberFlag("arcade-hub-tour");
        rememberHelpOrigin("create");
      }
    });
    coach({
      key: "arcade-hub-tour",
      onDone(skipped) { if (!skipped) showDoor("home"); },
      steps: [
        {
          title: "Bienvenue et personnalisation",
          text: "L'icône ⚙️ permet d'accéder aux paramètres. C'est ici que vous pouvez personnaliser votre nom (utilisé pour toutes vos parties en ligne) et choisir le thème visuel (clair, sombre ou aligné sur votre téléphone).",
          target: () => document.getElementById("hub-settings"),
          prepare: () => showDoor("home")
        },
        {
          title: "Créer une partie",
          text: "En cliquant sur « Créer une partie », choisissez votre jeu, le nombre de joueur et ajoutez les noms des joueurs (pour une partie sur cet appareil). Vous pouvez jouer tranquillement ici ou transformer votre partie en table connectée accessible à distance grâce à un code.",
          target: () => document.getElementById("door-go-create"),
          prepare: () => showDoor("home")
        },
        {
          title: "Rejoindre une partie",
          text: "Vous avez reçu un code ? Cliquez sur « Rejoindre une partie », entrez le code de la table pour vous connecter instantanément et rejoignez la partie en cours.",
          target: () => document.getElementById("join-code"),
          prepare: () => showDoor("join")
        },
        {
          title: "Choisir son jeu",
          text: "Yams, Démineur, Morpion, Mastermind ou Triomino... Chaque jeu propose ses propres mécaniques et options de personnalisation pour s'adapter à vos envies du moment.",
          target: () => document.getElementById("hub-games"),
          prepare: () => showDoor("create")
        },
        {
          title: "Prêt à jouer !",
          text: "Vous avez toutes les cartes en main. Explorez les menus, lancez une partie et bon divertissement ! (PS : une aide guidée spécifique se lancera automatiquement la première fois pour chaque jeu).",
          target: () => document.getElementById("door-home"),
          prepare: () => showDoor("home")
        }
      ]
    });
    if (readFlag("arcade-hub-tour")) {
      const door = new URLSearchParams(window.location.search).get("door");
      if (door === "create" || door === "join") showDoor(door);
    }
  }

  function mountSettings() {
    const app = document.getElementById("app");
    mountShell({ title: "Paramètres", tools: false });
    app.innerHTML = `<p class="lead">Ton nom sert à créer et à rejoindre. À plusieurs sur ce téléphone, les autres joueurs sont demandés à part.</p>
      <section class="stack">
        <label class="field">Ton nom
          <input id="pref-name" maxlength="24" autocomplete="name" placeholder="Ton nom">
        </label>
        <p class="lead">Thème</p>
        <div class="choice thirds" id="pref-theme">
          <button type="button" data-theme="system">Téléphone</button>
          <button type="button" data-theme="light">Clair</button>
          <button type="button" data-theme="dark">Sombre</button>
        </div>
        <p class="lead">Feuille Yams</p>
        <p class="status">Les dés restent visibles pour tout le monde. La feuille suit le joueur en cours, ou reste sur la tienne.</p>
        <div class="choice" id="pref-follow">
          <button type="button" data-follow="1">Suivre le tour</button>
          <button type="button" data-follow="0">Rester sur moi</button>
        </div>
        <p class="lead">Triomino</p>
        <p class="status">Les tuiles restent sous le plateau, ou s'ouvrent avec Mes tuiles.</p>
        <div class="choice" id="pref-hand">
          <button type="button" data-hand="board">Sous le plateau</button>
          <button type="button" data-hand="modal">Dans Mes tuiles</button>
        </div>
        <p class="status">La main aligne 3 ou 4 tuiles sur chaque ligne.</p>
        <div class="choice" id="pref-hand-columns">
          <button type="button" data-columns="3">3 par ligne</button>
          <button type="button" data-columns="4">4 par ligne</button>
        </div>
        <p class="lead">Aide</p>
        <p class="status" id="guide-note">L'aide guidée reprend à l'accueil, puis dans la partie.</p>
        <button type="button" class="primary" id="guide-reset">Relancer l'aide</button>
      </section>`;
    const name = document.getElementById("pref-name");
    name.value = playerName();
    name.addEventListener("input", () => { if (window.Prefs) Prefs.setPlayerName(name.value); });
    function paint() {
      const chosen = window.Prefs ? Prefs.theme() : "system";
      document.querySelectorAll("#pref-theme button").forEach((button) => {
        button.classList.toggle("is-on", button.dataset.theme === chosen);
      });
      const follow = window.Prefs ? Prefs.followSheet() : true;
      document.querySelectorAll("#pref-follow button").forEach((button) => {
        button.classList.toggle("is-on", (button.dataset.follow === "1") === follow);
      });
      const hand = window.Prefs ? Prefs.handPlace() : "board";
      document.querySelectorAll("#pref-hand button").forEach((button) => {
        button.classList.toggle("is-on", button.dataset.hand === hand);
      });
      const columns = window.Prefs && Prefs.handColumns() === 4 ? "4" : "3";
      document.querySelectorAll("#pref-hand-columns button").forEach((button) => {
        button.classList.toggle("is-on", button.dataset.columns === columns);
      });
    }
    bindChoice("pref-theme", (button) => {
      if (window.Prefs) Prefs.setTheme(button.dataset.theme);
      paint();
    });
    bindChoice("pref-follow", (button) => {
      if (window.Prefs) Prefs.setFollowSheet(button.dataset.follow === "1");
      paint();
    });
    bindChoice("pref-hand", (button) => {
      if (window.Prefs) Prefs.setHandPlace(button.dataset.hand);
      paint();
    });
    bindChoice("pref-hand-columns", (button) => {
      if (window.Prefs) Prefs.setHandColumns(Number(button.dataset.columns));
      paint();
    });
    document.getElementById("guide-reset").onclick = () => {
      forgetGuides();
      document.getElementById("guide-note").textContent = "C'est fait. L'aide recommence à l'accueil.";
    };
    paint();
  }

  function chosen(group, attribute) {
    const button = document.querySelector("#" + group + " .is-on");
    return button ? button.dataset[attribute] : "";
  }

  function bindChoice(id, onPick) {
    const node = document.getElementById(id);
    if (!node) return;
    node.addEventListener("click", (event) => {
      const button = event.target.closest("button");
      if (!button || !button.parentElement || button.parentElement !== node) return;
      node.querySelectorAll("button").forEach((item) => item.classList.toggle("is-on", item === button));
      if (onPick) onPick(button);
    });
  }

  // Accueil, création, code d'invitation et salon. Le jeu fournit ses réglages.
  function mountMatch(options) {
    const app = document.getElementById("app");
    const boardId = options.board || "play";
    let screen = "gate";
    const shell = mountShell({
      title: options.title,
      game: options.game,
      settings: options.settings,
      rules: options.rules,
      guide: options.guide,
      onReset: options.onReset,
      onLeave: options.onLeave,
      onBack() {
        if (screen === "gate") window.location.href = "index.html";
        else if (options.onLeave) options.onLeave();
      }
    });
    app.insertAdjacentHTML("afterbegin", `<section id="gate">
      <div id="step-create">
        <div class="choice" id="where">
          <button type="button" data-where="local" class="is-on">Sur ce téléphone</button>
          <button type="button" data-where="online">En ligne</button>
        </div>
        <div id="create-options"></div>
        <div id="local-box" class="stack"></div>
        <div id="online-box" class="hidden stack"></div>
        <p class="status" id="create-error"></p>
        <div class="stack">
          <button type="button" class="primary" id="create-go">Créer la partie</button>
        </div>
      </div>
    </section>
    <section id="lobby" class="hidden stack">
      <p class="lead" id="lobby-role"></p>
      <p class="lobby-code" id="lobby-code"></p>
      <button type="button" id="lobby-copy">Copier l'invitation</button>
      <ul class="lobby-list" id="lobby-players"></ul>
      <p class="status" id="lobby-note"></p>
      <button type="button" class="primary" id="lobby-start">Lancer la partie</button>
      <button type="button" class="ghost" id="lobby-leave">Quitter la table</button>
    </section>`);
    document.getElementById("create-options").innerHTML = options.optionsHtml || "";
    document.getElementById("local-box").innerHTML = options.localHtml || "";
    document.getElementById("online-box").innerHTML = options.onlineHtml || "";

    let where = "local";
    let rival = "bot";
    const gate = document.getElementById("gate");
    const lobby = document.getElementById("lobby");

    function show(panel) {
      screen = panel;
      gate.classList.toggle("hidden", panel !== "gate");
      lobby.classList.toggle("hidden", panel !== "lobby");
      const board = document.getElementById(boardId);
      if (board) board.classList.toggle("hidden", panel !== boardId);
      shell.setPlaying(panel !== "gate");
      if (shell.setLeave) shell.setLeave(panel === boardId);
    }

    function showStep() {
      show("gate");
    }

    function paintWhere() {
      document.getElementById("local-box").classList.toggle("hidden", where !== "local");
      document.getElementById("online-box").classList.toggle("hidden", where !== "online");
      if (options.syncWhere) options.syncWhere(where, rival);
    }

    function noteError(message) {
      if (String(message).indexOf("introuvable") !== -1) {
        shell.setOnline(false);
        showStep();
      }
      const board = document.getElementById(boardId);
      const target = lobby.classList.contains("hidden")
        ? (board && board.classList.contains("hidden") ? "create-error" : "status")
        : "lobby-note";
      const node = document.getElementById(target);
      if (node) node.textContent = message;
    }

    function fillLobby(state, info) {
      show("lobby");
      document.getElementById("lobby-code").textContent = state.code;
      document.getElementById("lobby-role").textContent = info.role;
      document.getElementById("lobby-players").innerHTML = (state.names || []).map((name) => `<li>${escapeHtml(name)}</li>`).join("");
      document.getElementById("lobby-note").textContent = info.note;
      const start = document.getElementById("lobby-start");
      start.hidden = !info.host;
      start.disabled = !info.ready;
    }

    function release(net, remote) {
      dismissEnd();
      if (remote && remote.phase === "done") net.leave();
      else if (remote) net.stop();
      shell.setOnline(false);
      window.location.href = "index.html";
    }

    async function copyInvite(remote) {
      if (!remote) return;
      const text = options.title + ". Pour me rejoindre, utilise le code : " + remote.code + ".";
      try {
        if (navigator.share) {
          await navigator.share({ text });
          return;
        }
      } catch (error) {
        if (error && error.name === "AbortError") return;
      }
      try {
        await navigator.clipboard.writeText(text);
        document.getElementById("lobby-note").textContent = "Invitation copiée.";
      } catch (error) {
        document.getElementById("lobby-note").textContent = text;
      }
    }

    bindChoice("where", (button) => {
      where = button.dataset.where;
      paintWhere();
    });
    if (document.getElementById("rival")) {
      bindChoice("rival", (button) => {
        rival = button.dataset.rival;
        paintWhere();
      });
    }
    document.getElementById("create-go").onclick = () => {
      document.getElementById("create-error").textContent = "";
      if (where === "local") {
        if (options.onLocal) options.onLocal();
        return;
      }
      if (!onlineOk()) {
        document.getElementById("create-error").textContent = "La table en ligne n'est pas configurée sur cet appareil.";
        return;
      }
      const name = playerName() || "Joueur";
      if (options.onOnline) options.onOnline(name);
    };
    document.getElementById("lobby-start").onclick = () => {
      if (options.onStart) options.onStart();
    };
    document.getElementById("lobby-copy").onclick = () => {
      const remote = options.currentRemote ? options.currentRemote() : null;
      copyInvite(remote);
    };
    document.getElementById("lobby-leave").onclick = () => {
      if (options.onLeave) options.onLeave();
    };
    function setWhere(mode) {
      where = mode === "online" ? "online" : "local";
      document.querySelectorAll("#where button").forEach((button) => {
        button.classList.toggle("is-on", button.dataset.where === where);
      });
      paintWhere();
    }

    paintWhere();
    queueMicrotask(() => {
      if (typeof options.guide !== "function") return;
      guideOn(options.game + "-tutorial", options.guide, "all");
    });

    return {
      shell,
      show,
      showStep,
      chosen,
      bindChoice,
      paintWhere,
      setWhere,
      noteError,
      fillLobby,
      release,
      get where() { return where; },
      get rival() { return rival; },
      totals: {
        paint(node, names, scores, includeLive, seat) { paintRoundTotals(options.game, node, names, scores, includeLive, seat); },
        remember(names, scores, stamp) { rememberRound(options.game, names, scores, stamp); }
      }
    };
  }

  let coachRun = null;

  const GUIDE_KEYS = ["arcade-hub-tour", "arcade-chrome-tour", "yams-tutorial", "morpion-tutorial", "mastermind-tutorial", "mines-tutorial", "triomino-tutorial"];

  function readFlag(key) {
    try { return localStorage.getItem(key) === "1"; } catch (error) { return true; }
  }

  function rememberFlag(key) {
    try { localStorage.setItem(key, "1"); } catch (error) { /* stockage refusé */ }
  }

  function forgetFlag(key) {
    try { localStorage.removeItem(key); } catch (error) { /* stockage refusé */ }
  }

  function forgetGuides() {
    GUIDE_KEYS.forEach((key) => {
      try { localStorage.removeItem(key); } catch (error) { /* stockage refusé */ }
    });
  }

  function ensureCoach() {
    if (document.getElementById("coach-style")) return;
    const style = document.createElement("style");
    style.id = "coach-style";
    style.textContent = `
      .coach-shade { position: fixed; inset: 0; z-index: 40; background: rgba(20, 14, 10, 0.55); }
      .is-coached { position: relative; z-index: 41; outline: 3px solid var(--accent); outline-offset: 4px; border-radius: 16px; }
      .coach-card {
        position: fixed; z-index: 42; left: 16px; right: 16px; max-width: 448px; margin: 0 auto;
        bottom: calc(16px + env(safe-area-inset-bottom, 0px));
        padding: 16px; border-radius: 18px; background: var(--card); color: var(--ink);
        border: 1px solid var(--line); box-shadow: var(--shadow, 0 12px 40px rgba(0,0,0,0.18));
      }
      .coach-card.is-top { bottom: auto; top: calc(16px + env(safe-area-inset-top, 0px)); }
      .coach-card p { margin: 0 0 8px; }
      .coach-copy { max-height: min(46vh, 380px); overflow: auto; }
      .coach-row { display: flex; align-items: center; gap: 10px; margin: 0 0 8px; }
      .coach-glyph {
        display: inline-flex; align-items: center; justify-content: center;
        width: 40px; height: 40px; flex: none; border: 1px solid var(--line);
        border-radius: 12px; background: var(--card); color: var(--ink);
        font-size: 13px; font-weight: 700; line-height: 1;
      }
      .coach-glyph svg { width: 22px; height: 22px; display: block; }
      .coach-glyph.is-active { background: var(--accent); border-color: var(--accent); color: var(--accent-ink); }
      .coach-glyph.is-mark { border-color: transparent; background: transparent; }
      .coach-glyph.is-online { color: var(--up); }
      .coach-pair { display: flex; justify-content: center; gap: 28px; margin: 4px 0 8px; }
      .coach-pair .sample {
        display: flex; flex-direction: column; align-items: center; gap: 6px;
        color: var(--muted); font-size: 13px; font-weight: 700; text-align: center;
      }
      .coach-token {
        display: grid; place-items: center; width: 56px; height: 56px; border-radius: 12px;
        background: var(--card); border: 1px solid var(--line); color: var(--ink);
        font-size: 28px; font-weight: 800;
      }
      .coach-token.is-mark { background: var(--accent); border-color: var(--accent); color: var(--accent-ink); }
      .coach-dot { width: 22px; height: 22px; border-radius: 50%; background: var(--line); }
      .coach-dot.is-placed { background: #c44536; }
      .coach-dot.is-present { background: #f7f4ee; border: 1px solid #6f6256; }
      .coach-stage {
        margin: 8px 0 4px; padding: 12px; border-radius: 14px;
        background: var(--bg, #171410); border: 1px solid var(--line);
      }
      .coach-choice, .coach-pegs, .coach-tris { display: flex; justify-content: center; gap: 10px; }
      .coach-choice span, .coach-go {
        display: inline-flex; align-items: center; justify-content: center;
        min-height: 36px; padding: 0 12px; border-radius: 12px;
        border: 1px solid var(--line); color: var(--muted); font-weight: 700;
      }
      .coach-choice span.is-on, .coach-go {
        background: var(--accent); border-color: var(--accent); color: var(--accent-ink);
      }
      .coach-go { width: 100%; margin: 8px 0 0; }
      .coach-code {
        margin: 10px 0 0; text-align: center; font-weight: 800; font-size: 28px;
        letter-spacing: 0.14em;
      }
      .coach-xo, .coach-mine {
        display: grid; grid-template-columns: repeat(3, 36px); gap: 4px;
        justify-content: center;
      }
      .coach-xo span, .coach-mine span {
        display: grid; place-items: center; width: 36px; height: 36px;
        border-radius: 8px; border: 1px solid var(--line); font-weight: 800;
      }
      .coach-xo .is-o { color: var(--muted); }
      .coach-xo .is-next { outline: 2px solid var(--accent); }
      .coach-mine .is-bomb { background: #c44536; color: #fffaf3; }
      .coach-mine .is-mark { color: var(--accent); }
      .coach-pegs span {
        display: grid; place-items: center; width: 36px; height: 36px;
        border-radius: 50%; font-weight: 800; color: #241c16;
      }
      .coach-pegs .is-ink { color: #fffaf3; }
      .coach-sheet { display: flex; flex-direction: column; gap: 6px; }
      .coach-sheet div {
        display: flex; justify-content: space-between; align-items: center;
        min-height: 36px; padding: 0 10px; border-radius: 10px; border: 1px solid var(--line);
      }
      .coach-sheet strong { font-size: 18px; }
      .coach-sheet .is-bar strong { color: var(--muted); }
      .coach-tris svg { width: 74px; height: 66px; display: block; }
      .coach-scores { display: flex; justify-content: center; gap: 12px; }
      .coach-scores div {
        min-width: 88px; padding: 8px 10px; border-radius: 12px;
        border: 1px solid var(--line); text-align: center;
      }
      .coach-scores span { display: block; color: var(--muted); font-size: 12px; }
      .coach-scores strong { font-size: 22px; }
      .coach-card h2 { margin: 0 0 8px; font-size: 22px; }
      .coach-count { color: var(--muted); font-size: 13px; font-weight: 700; }
      .coach-card .coach-next, .coach-card .coach-skip {
        display: block; width: 100%; min-height: 48px; margin-top: 8px; border-radius: 12px;
        font-weight: 700; cursor: pointer;
      }
      .coach-card .coach-next { background: var(--accent); border: 1px solid var(--accent); color: var(--accent-ink); }
      .coach-card .coach-skip { background: transparent; border: 0; color: var(--muted); }
    `;
    document.head.appendChild(style);
  }

  function clearCoachMark() {
    document.querySelectorAll(".topbar").forEach((bar) => {
      if (!("coachLift" in bar.dataset)) return;
      bar.style.zIndex = bar.dataset.coachLift;
      delete bar.dataset.coachLift;
    });
    document.querySelectorAll(".is-coached").forEach((node) => {
      node.classList.remove("is-coached");
      node.style.pointerEvents = "";
    });
  }

  function liftCoachBar(node) {
    const bar = node.closest(".topbar");
    if (!bar || "coachLift" in bar.dataset) return;
    bar.dataset.coachLift = bar.style.zIndex || "";
    bar.style.zIndex = "41";
  }

  function chromeButtons() {
    const bar = document.querySelector(".topbar");
    if (!bar) return [];
    return [...bar.querySelectorAll(".link-mark, a.icon-btn, button.icon-btn, .table-code")].filter((node) => {
      return !node.hidden && node.getClientRects().length > 0;
    });
  }

  function chromeCaption(node) {
    const back = node.getAttribute("aria-label") === "Retour au jeu"
      ? "Retour au jeu."
      : "Retour à l'écran précédent.";
    const captions = {
      "link-mark": "En ligne, ou hors ligne sur ce téléphone.",
      "shell-link": "En ligne, ou hors ligne sur ce téléphone.",
      "page-game": "Retour au jeu.",
      "shell-play": "Retour au jeu.",
      "page-evolution": "Évolution des parties jouées.",
      "shell-stats-tab": "Évolution des parties jouées.",
      "page-back": back,
      "shell-back": back,
      "reset-top": "Remet la partie à zéro.",
      "shell-reset": "Remet la partie à zéro.",
      "add-manche": "Ajoute une manche.",
      "rules-open": "Affiche les règles.",
      "settings-open": "Affiche les paramètres de la partie.",
      "shell-settings-open": "Affiche les paramètres de la partie.",
      "room-leave": "Quitte la table.",
      "shell-leave": "Quitte la table.",
      "table-code": "Copie le code de la table."
    };
    if (captions[node.id]) return captions[node.id];
    if (node.getAttribute("aria-label") === "Tous les jeux") return "Retour au hub.";
    return node.getAttribute("aria-label") || "";
  }

  function chromeGlyph(node) {
    const glyph = document.createElement("span");
    glyph.className = "coach-glyph";
    glyph.setAttribute("aria-hidden", "true");
    if (node.classList.contains("link-mark")) {
      glyph.classList.add("is-mark");
      glyph.classList.toggle("is-online", node.classList.contains("is-online"));
      const shown = node.querySelector(node.classList.contains("is-online") ? ".link-on" : ".link-off");
      if (shown) glyph.appendChild(shown.cloneNode(true));
      return glyph;
    }
    glyph.classList.toggle("is-active", node.classList.contains("is-active"));
    const icon = node.querySelector("svg");
    if (icon) glyph.appendChild(icon.cloneNode(true));
    else glyph.textContent = node.textContent.trim();
    return glyph;
  }

  function paintChromeCopy(copy) {
    copy.replaceChildren();
    chromeButtons().forEach((node) => {
      const row = document.createElement("p");
      row.className = "coach-row";
      row.appendChild(chromeGlyph(node));
      const words = document.createElement("span");
      words.textContent = chromeCaption(node);
      row.appendChild(words);
      copy.appendChild(row);
    });
  }

  function chromeNodes() {
    const link = document.getElementById("link-mark") || document.getElementById("shell-link");
    const common = document.querySelector(".brand-common");
    const tools = document.querySelector(".tool-actions") || document.querySelector(".game-tools");
    return [link, common, tools].filter((node) => node && !node.hidden && node.getClientRects().length > 0);
  }

  function chromeStep() {
    return {
      title: "Les boutons",
      render: paintChromeCopy,
      target: chromeNodes,
      prepare() { rememberFlag("arcade-chrome-tour"); }
    };
  }

  function chromeGuide(next) {
    const startNext = () => { if (typeof next === "function") next(); };
    if (readFlag("arcade-chrome-tour")) {
      startNext();
      return;
    }
    coach({
      key: "arcade-chrome-tour",
      follow: typeof next === "function",
      onDone(skipped) { if (!skipped) startNext(); },
      steps: [chromeStep()]
    });
  }

  let coachGuardOn = false;

  function coachClickAllowed(event) {
    const card = document.getElementById("coach-card");
    return Boolean(card && card.contains(event.target));
  }

  const COACH_BLOCKED = ["pointerdown", "pointerup", "click", "auxclick", "contextmenu", "touchstart", "touchend"];

  function blockCoachPointer(event) {
    if (!coachRun || coachClickAllowed(event)) return;
    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();
  }

  function armCoachGuard() {
    if (coachGuardOn) return;
    COACH_BLOCKED.forEach((type) => document.addEventListener(type, blockCoachPointer, true));
    coachGuardOn = true;
  }

  function disarmCoachGuard() {
    if (!coachGuardOn) return;
    COACH_BLOCKED.forEach((type) => document.removeEventListener(type, blockCoachPointer, true));
    coachGuardOn = false;
  }

  function closeCoach() {
    clearCoachMark();
    disarmCoachGuard();
    const shade = document.getElementById("coach-shade");
    const card = document.getElementById("coach-card");
    if (shade) shade.remove();
    if (card) card.remove();
    coachRun = null;
  }

  function suspendCoach() {
    if (!coachRun) return;
    closeCoach();
  }

  function guideCursor(key) {
    try {
      const raw = localStorage.getItem(key);
      if (raw === "1") return -1;
      if (raw && raw.indexOf("step:") === 0) {
        const index = Number(raw.slice(5));
        return Number.isFinite(index) ? index : 0;
      }
      return 0;
    } catch (error) {
      return -1;
    }
  }

  function writeCursor(key, index) {
    try { localStorage.setItem(key, "step:" + index); } catch (error) { /* stockage refusé */ }
  }

  function guidePage() {
    const lobby = document.getElementById("lobby");
    if (lobby && !lobby.hidden && !lobby.classList.contains("hidden")) return "lobby";
    const gate = document.getElementById("gate");
    if (gate && !gate.hidden && !gate.classList.contains("hidden")) return "gate";
    const deal = document.getElementById("deal-box");
    if (deal && !deal.hidden) return "deal";
    return "play";
  }

  function rememberHelpOrigin(origin) {
    try { sessionStorage.setItem("arcade-help-from", origin); } catch (error) { /* stockage refusé */ }
  }

  function clearHelpOrigin() {
    try { sessionStorage.removeItem("arcade-help-from"); } catch (error) { /* stockage refusé */ }
  }

  function returnToHelpOrigin() {
    let origin = "";
    try { origin = sessionStorage.getItem("arcade-help-from") || ""; } catch (error) { origin = ""; }
    clearHelpOrigin();
    if (origin !== "create" && origin !== "join") return;
    window.location.href = "index.html?door=" + origin;
  }

  function guideOn(key, steps, page) {
    const end = document.getElementById("end-dialog");
    if (end && !end.hidden) return;
    const podium = document.getElementById("podium-dialog");
    if (podium && !podium.hidden) return;
    const every = page === "all";
    if (every) {
      try {
        const raw = localStorage.getItem(key);
        if (raw && raw.indexOf("step:") === 0) localStorage.removeItem(key);
      } catch (error) { /* stockage refusé */ }
    }
    const all = typeof steps === "function" ? steps() : steps;
    const cursor = guideCursor(key);
    if (cursor < 0 || !all) return;
    const picked = [];
    all.forEach((step, index) => {
      if (index < cursor) return;
      if (!every && (step.page || "play") !== page) return;
      picked.push({ step, index });
    });
    if (!picked.length) return;
    const lastIndex = picked[picked.length - 1].index;
    const more = !every && lastIndex + 1 < all.length;
    coach({
      key,
      manual: true,
      follow: more,
      offset: picked[0].index,
      total: every ? picked.length : all.length,
      steps: picked.map((item) => item.step),
      onDone(skipped) {
        if (skipped) {
          rememberFlag(key);
          clearHelpOrigin();
          return;
        }
        if (more) {
          writeCursor(key, lastIndex + 1);
          const next = guidePage();
          if (next !== page) guideOn(key, steps, next);
          return;
        }
        rememberFlag(key);
        if (every) returnToHelpOrigin();
      }
    });
  }

  function pictured(note, html) {
    return function render(copy) {
      copy.replaceChildren();
      const text = document.createElement("p");
      text.textContent = note;
      const stage = document.createElement("div");
      stage.className = "coach-stage";
      stage.innerHTML = html;
      copy.append(text, stage);
    };
  }

  const whereMock = `<div class="coach-choice"><span class="is-on">Sur ce téléphone</span><span>En ligne</span></div>`;
  const onlineMock = `<div class="coach-choice"><span>Sur ce téléphone</span><span class="is-on">En ligne</span></div><p class="coach-code">AB12</p>`;
  const createMock = `<p class="coach-go">Créer la partie</p>`;
  const tableMock = `<p class="coach-code">AB12</p><p class="coach-go">Lancer la partie</p>`;

  function gateTour(setWhere, local, onlineText) {
    return [
      {
        page: "gate",
        title: local.title,
        render: pictured(local.text, whereMock),
        target: local.target,
        prepare() { setWhere("local"); }
      },
      {
        page: "gate",
        title: "En ligne",
        render: pictured(onlineText, onlineMock),
        target() {
          const box = document.getElementById("online-box");
          if (box && box.textContent.trim()) return box;
          return document.getElementById("where");
        },
        prepare() { setWhere("online"); }
      },
      {
        page: "gate",
        title: "À toi",
        render: pictured("Une fois l'aide finie, ce bouton lance la partie.", createMock),
        target: () => document.getElementById("create-go"),
        prepare() { setWhere("local"); }
      }
    ];
  }

  function lobbyStep() {
    return {
      page: "lobby",
      title: "La table",
      render: pictured("Le code se lit ici. Copie l'invitation. Quand tout le monde est là, lance la partie.", tableMock),
      target: () => document.getElementById("lobby")
    };
  }

  function playGuide(key, steps, playing) {
    if (!playing) return;
    guideOn(key, steps, "play");
  }

  function finishCoach(skipped) {
    if (!coachRun) return;
    const done = coachRun.onDone;
    const key = coachRun.key;
    const manual = coachRun.manual;
    closeCoach();
    if (!manual) rememberFlag(key);
    if (done) done(Boolean(skipped));
  }

  function paintCoach() {
    if (!coachRun) return;
    const step = coachRun.steps[coachRun.index];
    if (!step) {
      finishCoach();
      return;
    }
    if (step.prepare) step.prepare();
    clearCoachMark();
    const target = step.target ? step.target() : null;
    ensureCoach();
    let shade = document.getElementById("coach-shade");
    let card = document.getElementById("coach-card");
    if (!shade) {
      shade = document.createElement("div");
      shade.id = "coach-shade";
      shade.className = "coach-shade";
      document.body.appendChild(shade);
    }
    if (!card) {
      card = document.createElement("div");
      card.id = "coach-card";
      card.className = "coach-card";
      card.setAttribute("role", "dialog");
      card.setAttribute("aria-modal", "true");
      card.innerHTML = `<p class="coach-count"></p><h2></h2><p class="coach-copy"></p><button type="button" class="coach-next">Suivant</button><button type="button" class="coach-skip">Passer</button>`;
      card.querySelector(".coach-next").onclick = () => {
        if (!coachRun) return;
        if (coachRun.index >= coachRun.steps.length - 1) finishCoach(false);
        else {
          coachRun.index += 1;
          paintCoach();
        }
      };
      card.querySelector(".coach-skip").onclick = () => finishCoach(true);
      document.body.appendChild(card);
    }
    const total = coachRun.total || coachRun.steps.length;
    card.querySelector(".coach-count").textContent = ((coachRun.offset || 0) + coachRun.index + 1) + " / " + total;
    card.querySelector("h2").textContent = step.title;
    const copy = card.querySelector(".coach-copy");
    if (typeof step.render === "function") step.render(copy);
    else {
      copy.replaceChildren();
      const text = typeof step.text === "function" ? step.text() : step.text;
      copy.textContent = text || "";
    }
    const last = coachRun.index >= coachRun.steps.length - 1;
    card.querySelector(".coach-next").textContent = last && !coachRun.follow ? "Terminer" : "Suivant";
    armCoachGuard();
    const targets = !target ? [] : (Array.isArray(target) ? target.filter(Boolean) : [target]);
    targets.forEach((node) => {
      liftCoachBar(node);
      node.classList.add("is-coached");
      node.style.pointerEvents = "none";
    });
    if (targets.length) {
      targets[0].scrollIntoView({ block: "nearest", inline: "nearest" });
      const rect = targets[targets.length - 1].getBoundingClientRect();
      card.classList.toggle("is-top", rect.top > window.innerHeight * 0.55);
      coachRun.marked = targets[0];
    }
  }

  function coach(options) {
    if (!options || readFlag(options.key)) return;
    const same = coachRun && coachRun.key === options.key;
    if (same && coachRun.marked && coachRun.marked.isConnected) return;
    coachRun = {
      key: options.key,
      steps: options.steps,
      onDone: options.onDone,
      follow: Boolean(options.follow),
      manual: Boolean(options.manual),
      offset: options.offset || 0,
      total: options.total || options.steps.length,
      index: same ? coachRun.index : 0
    };
    paintCoach();
  }

  return {
    onlineOk, escapeHtml, rpc, room, recordStats, statsView, mountShell, announceOnce, dismissEnd,
    games: GAMES, gameTitle, playerName, remember, unpinTable, mountDoor, mountSettings, joinTable, mountMatch, coach, chromeGuide, chromeStep, playGuide, guideOn, gateTour, pictured, lobbyStep, paintSeats
  };
})();
