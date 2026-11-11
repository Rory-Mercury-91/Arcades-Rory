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

  function remember(game, code, token) {
    localStorage.setItem("arcade-" + game + "-code", code);
    localStorage.setItem("arcade-" + game + "-token", token);
  }

  function recall(game) {
    return {
      code: localStorage.getItem("arcade-" + game + "-code") || "",
      token: localStorage.getItem("arcade-" + game + "-token") || ""
    };
  }

  function forget(game) {
    localStorage.removeItem("arcade-" + game + "-code");
    localStorage.removeItem("arcade-" + game + "-token");
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

  function mountShell(options) {
    const tools = options.tools !== false;
    const header = document.createElement("header");
    header.className = "topbar";
    const backButton = `<button type="button" class="icon-btn" id="shell-back" aria-label="Retour"${options.back === false ? " hidden" : ""}>${backIcon}</button>`;
    const hubLinks = options.hub ? `<div class="brand-common">
        <a class="icon-btn" href="admin.html" aria-label="Tables">${tablesIcon}</a>
        <a class="icon-btn" href="parametres.html" aria-label="Paramètres">${gearIcon}</a>
        ${backButton}
      </div>` : "";
    const linkMark = `<span class="link-mark" id="shell-link" title="Sur ce téléphone" aria-label="Sur ce téléphone">
          <svg class="link-off" viewBox="0 0 24 24" aria-hidden="true"><path fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" d="M4 9.5c3.6-3 12.4-3 16 0M7.2 13c2.2-1.8 7.4-1.8 9.6 0M10 16.2c1.1-.8 2.9-.8 4 0"/><circle cx="12" cy="19" r="1.15" fill="currentColor"/><path fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" d="M5 5l14 14"/></svg>
          <svg class="link-on" viewBox="0 0 24 24" aria-hidden="true"><path fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" d="M4 9.5c3.6-3 12.4-3 16 0M7.2 13c2.2-1.8 7.4-1.8 9.6 0M10 16.2c1.1-.8 2.9-.8 4 0"/><circle cx="12" cy="19" r="1.15" fill="currentColor"/></svg>
        </span>`;
    const common = tools ? `<div class="brand-common">
        <a class="icon-btn" href="index.html" aria-label="Tous les jeux"><svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="3" width="7.5" height="7.5" rx="1.6" fill="currentColor"/><rect x="13.5" y="3" width="7.5" height="7.5" rx="1.6" fill="currentColor"/><rect x="3" y="13.5" width="7.5" height="7.5" rx="1.6" fill="currentColor"/><rect x="13.5" y="13.5" width="7.5" height="7.5" rx="1.6" fill="currentColor"/></svg></a>
        ${backButton}
      </div>` : (options.hub ? "" : `<div class="brand-common">${backButton}</div>`);
    const toolsRow = tools ? `<div class="game-tools" id="shell-tools" hidden>
        <button type="button" class="icon-btn" id="shell-reset" aria-label="Remettre à zéro">${refreshIcon}</button>
        <div class="modes" role="tablist" aria-label="Affichage">
          <button type="button" class="icon-btn is-active" id="shell-play" role="tab" aria-selected="true" aria-label="Jeu"><svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3.5" y="3.5" width="17" height="17" rx="3.5" fill="none" stroke="currentColor" stroke-width="1.8"/><circle cx="8.2" cy="8.2" r="1.25" fill="currentColor"/><circle cx="15.8" cy="8.2" r="1.25" fill="currentColor"/><circle cx="8.2" cy="12" r="1.25" fill="currentColor"/><circle cx="15.8" cy="12" r="1.25" fill="currentColor"/><circle cx="8.2" cy="15.8" r="1.25" fill="currentColor"/><circle cx="15.8" cy="15.8" r="1.25" fill="currentColor"/></svg></button>
          <button type="button" class="icon-btn" id="shell-stats-tab" role="tab" aria-selected="false" aria-label="Évolution"><svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="13" width="4.5" height="8" rx="1.2" fill="currentColor"/><rect x="9.75" y="8" width="4.5" height="13" rx="1.2" fill="currentColor"/><rect x="16.5" y="3" width="4.5" height="18" rx="1.2" fill="currentColor"/></svg></button>
        </div>
        <button type="button" class="icon-btn" id="shell-settings-open" aria-label="Réglages">${gearIcon}</button>
      </div>` : "";
    header.innerHTML = `<div class="brand-row">
      ${tools ? linkMark : ""}
      <h1>${escapeHtml(options.title || "Jeu")}</h1>
      ${common || hubLinks}
    </div>${toolsRow}`;
    document.body.prepend(header);
    const backNode = document.getElementById("shell-back");
    if (backNode) {
      backNode.onclick = () => {
        if (typeof options.onBack === "function") options.onBack();
        else window.location.href = "index.html";
      };
    }
    function setBack(visible) {
      if (backNode) backNode.hidden = !visible;
    }
    if (!tools) return { setOnline() {}, paintStats() {}, showPlay() {}, setBack };
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
    <div class="dialog is-center" id="shell-reset-dialog" hidden>
      <div class="dialog-card" role="dialog" aria-modal="true" aria-labelledby="shell-reset-title">
        <h2 id="shell-reset-title">Remettre à zéro</h2>
        <p>La partie en cours s'efface. Tu reviens à l'accueil des jeux.</p>
        <button type="button" class="btn primary" id="shell-reset-yes">Tout effacer</button>
        <button type="button" class="btn text" id="shell-reset-no">Annuler</button>
      </div>
    </div>`);

    function paintLink(online) {
      const mark = document.getElementById("shell-link");
      mark.classList.toggle("is-online", online);
      const label = online ? "En ligne" : "Sur ce téléphone";
      mark.title = label;
      mark.setAttribute("aria-label", label);
    }

    function paintStats() {
      const view = statsView(options.game);
      const lines = view.lines.length ? view.lines : ["Aucune partie terminée."];
      const recent = view.recent.map((line) => `<li>${escapeHtml(line)}</li>`).join("");
      document.getElementById("shell-stats").innerHTML = lines.map((line) => `<p class="lead">${escapeHtml(line)}</p>`).join("")
        + (recent ? `<ul class="lobby-list">${recent}</ul>` : "");
    }

    function showView(name) {
      const play = name !== "evolution";
      const app = document.getElementById("app");
      if (app) app.hidden = !play;
      evolution.hidden = play;
      document.getElementById("shell-play").classList.toggle("is-active", play);
      document.getElementById("shell-stats-tab").classList.toggle("is-active", !play);
      document.getElementById("shell-play").setAttribute("aria-selected", play ? "true" : "false");
      document.getElementById("shell-stats-tab").setAttribute("aria-selected", play ? "false" : "true");
      if (!play) paintStats();
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
    function setPlaying(on) {
      const row = document.getElementById("shell-tools");
      if (row) row.hidden = !on;
      if (!on) showView("play");
    }

    paintLink(false);
    paintStats();
    return {
      setOnline: paintLink,
      paintStats,
      setPlaying,
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
        <button type="button" class="btn primary" id="end-close">Fermer</button>
      </div>
    </div>`);
    document.getElementById("end-close").onclick = () => {
      document.getElementById("end-dialog").hidden = true;
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
    { id: "mines", title: "Démineur", href: "mines.html", text: "Un carré, des mines cachées. Seul ou chacun son tour." }
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
      window.location.href = game ? game.href : "index.html";
      return;
    } catch (error) {
      if (String(error.message).indexOf("introuvable") === -1) throw error;
    }
    const yamsCode = localStorage.getItem("yams-room-code") || "";
    const yamsToken = yamsCode === clean ? (localStorage.getItem("yams-room-token") || "") : "";
    const data = await rpc("yams_join_room", { p_code: clean, p_name: who, p_token: yamsToken });
    localStorage.setItem("yams-room-code", data.state.code);
    localStorage.setItem("yams-room-token", data.token);
    window.location.href = "yams.html";
  }

  function mountDoor() {
    const app = document.getElementById("app");
    let shell;
    function showDoor(step) {
      document.getElementById("door-home").classList.toggle("hidden", step !== "home");
      document.getElementById("door-create").classList.toggle("hidden", step !== "create");
      document.getElementById("door-join").classList.toggle("hidden", step !== "join");
      shell.setBack(step !== "home");
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
    const codeInput = document.getElementById("join-code");
    codeInput.addEventListener("input", () => { codeInput.value = codeInput.value.toUpperCase(); });
    document.getElementById("join-go").onclick = () => {
      const errorNode = document.getElementById("join-error");
      errorNode.textContent = "";
      joinTable(codeInput.value, playerName()).catch((error) => {
        errorNode.textContent = error.message;
      });
    };
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
    }
    bindChoice("pref-theme", (button) => {
      if (window.Prefs) Prefs.setTheme(button.dataset.theme);
      paint();
    });
    bindChoice("pref-follow", (button) => {
      if (window.Prefs) Prefs.setFollowSheet(button.dataset.follow === "1");
      paint();
    });
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
      onReset: options.onReset,
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
      <button type="button" class="ghost" id="lobby-leave">Quitter</button>
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
    paintWhere();

    return {
      shell,
      show,
      showStep,
      chosen,
      bindChoice,
      paintWhere,
      noteError,
      fillLobby,
      release,
      get where() { return where; },
      get rival() { return rival; }
    };
  }

  return {
    onlineOk, escapeHtml, rpc, room, recordStats, statsView, mountShell, announceOnce, dismissEnd,
    games: GAMES, gameTitle, playerName, mountDoor, mountSettings, joinTable, mountMatch
  };
})();
