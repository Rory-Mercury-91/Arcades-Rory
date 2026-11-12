// Petit Bac : une lettre, neuf colonnes, tout le monde écrit, puis on vote.
const Bac = (function () {
  const CATEGORIES = [
    { id: "prenom", label: "Prénoms masculins / féminins" },
    { id: "metier", label: "Métiers" },
    { id: "objet", label: "Objets du quotidien" },
    { id: "fruit", label: "Fruits / Légumes" },
    { id: "fleur", label: "Fleurs / Arbres" },
    { id: "animal", label: "Animaux / Mammifères / Oiseaux / Insectes / Poissons / Races de chien" },
    { id: "lieu", label: "Pays / Villes / Capitales" },
    { id: "eau", label: "Mers et océans / Fleuves et rivières" },
    { id: "titre", label: "Titres de films / Titres de séries télé / Titres de dessins animés (anime japonais compris) / Titres d'émissions de télé" }
  ];
  const LETTERS = "ABCDEFGHIJLMNOPQRSTUVZ";
  const STOP_MS = 60000;
  const CAT_COUNT = CATEGORIES.length;

  function blanks(count, fill) {
    const list = [];
    for (let index = 0; index < count; index += 1) list.push(typeof fill === "function" ? fill(index) : fill);
    return list;
  }

  function emptyRow() {
    return blanks(CAT_COUNT, "");
  }

  function clip(text) {
    return String(text || "").replace(/\s+/g, " ").trim().slice(0, 48);
  }

  function fold(text) {
    return String(text || "")
      .replace(/œ/gi, "oe")
      .replace(/æ/gi, "ae")
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .replace(/['’`´]/g, " ")
      .replace(/[-_/.,]/g, " ")
      .replace(/\s+/g, " ")
      .trim();
  }

  function wordKey(text) {
    let value = fold(text);
    value = value.replace(/^(le|la|les|un|une|des|de|l|d) /, "");
    if (value.length > 3 && value.slice(-3) === "aux") value = value.slice(0, -3) + "al";
    else if (value.length > 1 && value.slice(-1) === "x") value = value.slice(0, -1);
    else if (value.length > 1 && value.slice(-1) === "s" && value.slice(-2) !== "ss") value = value.slice(0, -1);
    return value;
  }

  function readRow(list) {
    const row = emptyRow();
    if (!Array.isArray(list)) return row;
    for (let index = 0; index < CAT_COUNT; index += 1) row[index] = clip(list[index]);
    return row;
  }

  function filled(row) {
    return readRow(row).every((word) => word !== "");
  }

  function pickLetter(used) {
    const seen = Array.isArray(used) ? used : [];
    const pool = LETTERS.split("").filter((letter) => seen.indexOf(letter) < 0);
    const source = pool.length ? pool : LETTERS.split("");
    return source[Math.floor(Math.random() * source.length)];
  }

  function allTrue(list) {
    return (list || []).every(Boolean);
  }

  function createGame(names, rounds) {
    const people = (names || []).map((name, index) => String(name || "").trim() || ("Joueur " + (index + 1)));
    const count = Math.max(2, Math.min(5, people.length || 2));
    while (people.length < count) people.push("Joueur " + (people.length + 1));
    const taken = people.slice(0, count);
    const letter = pickLetter([]);
    return {
      names: taken,
      scores: blanks(count, 0),
      gained: blanks(count, 0),
      answers: blanks(count, emptyRow),
      ballots: blanks(count, function () { return {}; }),
      submitted: blanks(count, false),
      voted: blanks(count, false),
      marks: blanks(count, function () { return blanks(CAT_COUNT, null); }),
      letter,
      used: [letter],
      round: 1,
      rounds: Math.max(3, Math.min(8, Number(rounds) || 5)),
      stopAt: null,
      phase: "write",
      turn: 0,
      winner: null
    };
  }

  function seatOk(state, seat) {
    return Number.isInteger(seat) && seat >= 0 && seat < state.names.length;
  }

  function saveAnswers(state, seat, answers) {
    if (!state || state.phase !== "write") return "Ce n'est plus le moment d'écrire.";
    if (!seatOk(state, seat)) return "Joueur inconnu.";
    if (state.submitted[seat]) return "Tes réponses sont déjà validées.";
    state.answers[seat] = readRow(answers);
    return "";
  }

  function nextPending(flags, seat) {
    const after = flags.findIndex((done, index) => !done && index > seat);
    if (after >= 0) return after;
    const wrap = flags.findIndex((done) => !done);
    return wrap >= 0 ? wrap : seat;
  }

  function maybeCloseWrite(state, now) {
    if (state.phase !== "write") return false;
    const due = state.stopAt && now >= state.stopAt;
    if (!due && !allTrue(state.submitted)) return false;
    state.submitted = state.names.map(() => true);
    state.stopAt = null;
    state.phase = "vote";
    state.turn = 0;
    state.ballots = state.names.map(function () { return {}; });
    state.voted = state.names.map(() => false);
    return true;
  }

  function draft(state, seat, answers) {
    return saveAnswers(state, seat, answers);
  }

  function submit(state, seat, answers, now) {
    const error = saveAnswers(state, seat, answers);
    if (error) return error;
    state.submitted[seat] = true;
    state.turn = nextPending(state.submitted, seat);
    maybeCloseWrite(state, now || Date.now());
    return "";
  }

  function stop(state, seat, answers, now) {
    const error = saveAnswers(state, seat, answers);
    if (error) return error;
    if (!filled(state.answers[seat])) return "Remplis toutes les catégories pour crier stop.";
    state.submitted[seat] = true;
    const at = now || Date.now();
    if (!state.stopAt) state.stopAt = at + STOP_MS;
    state.turn = nextPending(state.submitted, seat);
    maybeCloseWrite(state, at);
    return "";
  }

  function tick(state, now) {
    if (!state || state.phase !== "write") return "";
    maybeCloseWrite(state, now || Date.now());
    return "";
  }

  function cleanBallot(state, seat, ballot) {
    const clean = {};
    const raw = ballot && typeof ballot === "object" ? ballot : {};
    Object.keys(raw).forEach((key) => {
      const parts = String(key).split(":");
      const other = Number(parts[0]);
      const cat = Number(parts[1]);
      if (other === seat) return;
      if (!seatOk(state, other)) return;
      if (!Number.isInteger(cat) || cat < 0 || cat >= CAT_COUNT) return;
      const mark = raw[key];
      if (mark === "v" || mark === "x") clean[other + ":" + cat] = mark;
    });
    return clean;
  }

  function tally(state) {
    const count = state.names.length;
    const points = blanks(count, 0);
    const marks = blanks(count, function () { return blanks(CAT_COUNT, null); });
    for (let cat = 0; cat < CAT_COUNT; cat += 1) {
      const accepted = [];
      for (let seat = 0; seat < count; seat += 1) {
        const text = clip(state.answers[seat][cat]);
        if (!text) {
          accepted[seat] = false;
          marks[seat][cat] = { text: "", points: 0, accepted: false, key: "" };
          continue;
        }
        let yes = 0;
        let no = 0;
        for (let other = 0; other < count; other += 1) {
          if (other === seat) continue;
          const vote = (state.ballots[other] || {})[seat + ":" + cat];
          if (vote === "v") yes += 1;
          else if (vote === "x") no += 1;
        }
        accepted[seat] = !(no > yes);
        marks[seat][cat] = { text, points: 0, accepted: accepted[seat], key: wordKey(text) };
      }
      const ok = [];
      for (let seat = 0; seat < count; seat += 1) {
        if (accepted[seat]) ok.push(seat);
      }
      if (ok.length === 1) {
        marks[ok[0]][cat].points = 15;
        points[ok[0]] += 15;
        continue;
      }
      const groups = {};
      ok.forEach((seat) => {
        const key = marks[seat][cat].key || ("#" + seat);
        if (!groups[key]) groups[key] = [];
        groups[key].push(seat);
      });
      Object.keys(groups).forEach((key) => {
        const gain = groups[key].length >= 2 ? 5 : 10;
        groups[key].forEach((seat) => {
          marks[seat][cat].points = gain;
          points[seat] += gain;
        });
      });
    }
    return { points, marks };
  }

  function closeVotes(state) {
    const result = tally(state);
    state.gained = result.points;
    state.marks = result.marks;
    state.scores = state.scores.map((score, index) => Number(score || 0) + result.points[index]);
    if (state.round >= state.rounds) {
      state.phase = "done";
      const best = Math.max.apply(null, state.scores);
      const tops = state.scores.filter((score) => score === best);
      state.winner = tops.length === 1 ? state.scores.indexOf(best) : -1;
      return;
    }
    state.phase = "show";
  }

  function vote(state, seat, ballot) {
    if (!state || state.phase !== "vote") return "Ce n'est plus le moment de voter.";
    if (!seatOk(state, seat)) return "Joueur inconnu.";
    if (state.voted[seat]) return "Tes votes sont déjà validés.";
    state.ballots[seat] = cleanBallot(state, seat, ballot);
    state.voted[seat] = true;
    state.turn = nextPending(state.voted, seat);
    if (allTrue(state.voted)) closeVotes(state);
    return "";
  }

  function nextRound(state) {
    if (!state || state.phase !== "show") return "La manche n'est pas terminée.";
    const letter = pickLetter(state.used);
    state.letter = letter;
    state.used = state.used.concat(letter);
    state.round += 1;
    state.answers = state.names.map(emptyRow);
    state.ballots = state.names.map(function () { return {}; });
    state.submitted = state.names.map(() => false);
    state.voted = state.names.map(() => false);
    state.marks = state.names.map(function () { return blanks(CAT_COUNT, null); });
    state.gained = state.names.map(() => 0);
    state.stopAt = null;
    state.phase = "write";
    state.turn = 0;
    state.winner = null;
    return "";
  }

  return {
    CATEGORIES, LETTERS, STOP_MS, CAT_COUNT,
    fold, wordKey, clip, readRow, filled, pickLetter, createGame,
    draft, submit, stop, tick, vote, nextRound, tally
  };
})();

if (typeof module !== "undefined" && module.exports) module.exports = Bac;

if (typeof document !== "undefined") {
  const sheet = document.getElementById("sheet");
  const status = document.getElementById("status");
  let count = 2;
  let rounds = 5;
  let local = null;
  let remote = null;
  let net = null;
  let draft = null;
  let ballot = {};
  let sheetKey = "";
  let clock = 0;
  let saveTimer = 0;
  let wasDone = false;
  let noted = false;
  let roundId = "";

  function bacSettings() {
    const players = local ? local.names.length : (remote && remote.config && remote.config.humans ? Number(remote.config.humans) : count);
    const total = local ? local.rounds : (remote && remote.config && remote.config.rounds ? Number(remote.config.rounds) : rounds);
    const online = Boolean(remote);
    return [
      ["Joueurs", String(players), "De 2 à 5 joueurs. En ligne, chacun écrit sur son téléphone."],
      ["Manche", String(total), "Une lettre par manche, sans K, W, X ni Y. Le / dans une catégorie veut dire l'un ou l'autre."],
      ["Points", "0 · 5 · 10 · 15", "Vide ou refusé : 0. Mot partagé : 5. Mot unique : 10. Seul à avoir répondu : 15."],
      ["Votes", "V, X ou abstention", "On ignore les abstentions. S'il y a plus de X que de V, la réponse tombe. À égalité, elle passe."],
      ["Table", online ? "En ligne · " + remote.code : "Sur ce téléphone", "Sur ce téléphone, on se passe l'écran. En ligne, STOP laisse une minute aux autres."]
    ];
  }

  function leaveTable() {
    match.release(net, remote);
    remote = null;
    local = null;
  }

  const match = Arcade.mountMatch({
    title: "Petit Bac",
    game: "bac",
    board: "play",
    settings: bacSettings,
    rules: bacRules,
    guide: bacSteps,
    onReset() { leaveTable(); },
    onLeave() { leaveTable(); },
    onLocal() { startLocal(); },
    onOnline(name) {
      net.create(name, { humans: count, rounds }).catch((error) => {
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
      <p class="lead">Manches</p>
      <div class="stepper">
        <button type="button" id="rounds-less" aria-label="Moins de manches">−</button>
        <strong id="rounds-value">5</strong>
        <button type="button" id="rounds-more" aria-label="Plus de manches">+</button>
      </div>`,
    localHtml: `<div id="name-box" class="stack"></div>`,
    onlineHtml: `<p class="lead">Chacun écrit sur son téléphone. Une lettre, neuf catégories, puis on vote.</p>`
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

  function bacRules() {
    return [
      ["Catégories", "Une colonne par ligne. Le / veut dire l'un ou l'autre : prénom garçon ou fille, fruit ou légume, film ou série…"],
      ["Écriture", "Tout le monde cherche en même temps. Valider mes réponses envoie la feuille, même incomplète. STOP, si tout est rempli, laisse une minute aux autres."],
      ["Mots", "On ignore accents, majuscules et pluriel. Chat vaut chats, pas chaton ni chatte. L'orthographe doit être juste : sinon on refuse."],
      ["Votes", "V accepte, X refuse, Abs s'abstient. L'abstention ne compte pas. S'il y a plus de refus que de validations, le mot tombe. À égalité, il passe."],
      ["Points", "Vide ou refusé : 0. Deux joueurs ou plus avec le même mot : 5. Mot que personne d'autre n'a : 10. Seul à avoir une réponse valide dans la colonne : 15."]
    ];
  }

  function bacSteps() {
    return [
      ...Arcade.gateTour((mode) => match.setWhere(mode), {
        title: "Petit Bac",
        text: "De 2 à 5 joueurs. Une lettre, neuf catégories. En ligne, chacun a sa feuille.",
        target: () => document.getElementById("step-create")
      }, "En ligne, les autres rejoignent avec le code. L'invitation s'affiche après la création."),
      Object.assign(Arcade.chromeStep(), { page: "play" }),
      {
        page: "play",
        title: "La lettre",
        render: Arcade.pictured("Tous les mots de la manche commencent par cette lettre.", `<p class="coach-code">M</p>`),
        target: () => document.getElementById("letter")
      },
      {
        page: "play",
        title: "La feuille",
        render: Arcade.pictured("Une catégorie, une case. En bas, tu envoies tes réponses.", `<p class="coach-go">Valider mes réponses</p>`),
        target: () => document.getElementById("sheet")
      },
      Arcade.lobbyStep()
    ];
  }

  function showStatus(text) {
    status.textContent = text || "";
    status.hidden = !status.textContent;
  }

  function ranking(model) {
    return model.names.map((name, index) => ({ name, score: Number(model.scores[index]) || 0, index }))
      .sort((left, right) => right.score - left.score || left.index - right.index)
      .map((item) => item.name + " " + item.score)
      .join(" · ");
  }

  function podiumHtml(model) {
    const people = model.names.map((name, index) => ({
      index,
      name: name || ("Joueur " + (index + 1)),
      total: Number(model.scores[index]) || 0
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
      return `<li>${index + 1}. ${Arcade.escapeHtml(person.name)} · ${person.total} pts</li>`;
    }).join("");
    return `<p>${Arcade.escapeHtml(lead)}</p><div class="podium ${places.length === 2 ? "is-duo" : "is-trio"}">${stand}</div><ul class="lobby-list">${list}</ul>`;
  }

  function results(model) {
    const best = Math.max.apply(null, model.scores.map((score) => Number(score) || 0));
    return model.names.map((name, index) => {
      const score = Number(model.scores[index]) || 0;
      let result = "loss";
      if (score === best) result = model.scores.filter((value) => Number(value) === best).length > 1 ? "draw" : "win";
      return { name, result };
    });
  }

  function noteEnd(model) {
    const done = model.phase === "done";
    Arcade.announceOnce("bac", done, done ? podiumHtml(model) : "");
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
      Arcade.recordStats("bac", results(model));
      match.totals.remember(model.names, model.scores, roundId);
      shell.paintStats();
      match.totals.paint(document.getElementById("round-totals"), model.names, model.scores, false);
      return;
    }
    if (wasDone) return;
    wasDone = true;
    const mine = results(model).find((person, index) => index === remote.you);
    if (mine) Arcade.recordStats("bac", [mine]);
    const stamp = remote.code + ":" + model.scores.join(",") + ":" + model.round;
    match.totals.remember(model.names, model.scores, stamp);
    shell.paintStats();
    match.totals.paint(document.getElementById("round-totals"), model.names, model.scores, false);
  }

  function currentSeat(model) {
    if (local) return model.turn;
    return remote ? remote.you : 0;
  }

  function remain(model, now) {
    if (!model.stopAt) return 0;
    return Math.max(0, Math.ceil((model.stopAt - now) / 1000));
  }

  function statusText(model) {
    const seat = currentSeat(model);
    const who = model.names[seat] || "Joueur";
    if (model.phase === "done") {
      const lead = model.winner >= 0 ? model.names[model.winner] + " gagne. " : "Égalité. ";
      return lead + ranking(model);
    }
    if (model.phase === "show") {
      return "Manche " + model.round + " · " + ranking(model);
    }
    if (model.phase === "vote") {
      if (local) return who + " vote. V accepte, X refuse, Abs s'abstient.";
      if (model.voted[seat]) return "En attente des autres votes.";
      return "V accepte, X refuse, Abs s'abstient.";
    }
    if (model.stopAt) {
      const left = remain(model, Date.now());
      return left ? "STOP. Encore " + left + " s." : "On arrête.";
    }
    if (local) return who + " écrit. Lettre " + model.letter + ".";
    if (model.submitted[seat]) return "En attente des autres joueurs.";
    const ready = (model.submitted || []).filter(Boolean).length;
    return ready ? ready + " / " + model.names.length + " ont validé." : "Remplis la feuille, puis valide.";
  }

  function liveAnswers(model) {
    const seat = currentSeat(model);
    if (draft && draft.round === model.round && draft.letter === model.letter && draft.seat === seat) {
      return draft.row.slice();
    }
    if (local) return (model.answers[seat] || Bac.readRow([])).slice();
    return Bac.readRow(model.mine || []);
  }

  function keepDraft(model) {
    const seat = currentSeat(model);
    if (model.phase !== "write" || model.submitted[seat]) {
      draft = null;
      return;
    }
    draft = { round: model.round, letter: model.letter, seat, row: liveAnswers(model) };
  }

  function queueDraft() {
    if (!remote || !net || !draft) return;
    window.clearTimeout(saveTimer);
    saveTimer = window.setTimeout(() => {
      net.act("draft", { answers: draft.row }).catch(() => {});
    }, 450);
  }

  function markButtons(hidden, shown) {
    ["submit", "stop", "ballot", "next", "again"].forEach((id) => {
      document.getElementById(id).hidden = shown.indexOf(id) < 0;
    });
    document.getElementById("leave").hidden = hidden;
  }

  function paintScores(model) {
    const seat = currentSeat(model);
    Arcade.paintSeats(document.getElementById("scores"), model.names.map((name, index) => ({
      name,
      score: Number(model.scores[index]) || 0,
      active: model.phase === "write" || model.phase === "vote" ? index === seat && !(model.phase === "write" ? model.submitted[index] : model.voted[index]) : false
    })));
  }

  function voteValue(seat, cat) {
    const key = seat + ":" + cat;
    if (Object.prototype.hasOwnProperty.call(ballot, key)) return ballot[key];
    return "";
  }

  function paintWrite(model) {
    const seat = currentSeat(model);
    const locked = Boolean(model.submitted[seat]);
    const row = liveAnswers(model);
    sheet.replaceChildren();
    Bac.CATEGORIES.forEach((category, cat) => {
      const label = document.createElement("label");
      label.className = "bac-row";
      const title = document.createElement("span");
      title.className = "bac-label";
      title.textContent = category.label;
      const input = document.createElement("input");
      input.type = "text";
      input.maxLength = 48;
      input.autocomplete = "off";
      input.spellcheck = true;
      input.dataset.cat = String(cat);
      input.setAttribute("aria-label", category.label);
      input.value = row[cat] || "";
      input.disabled = locked;
      label.append(title, input);
      sheet.append(label);
    });
  }

  function paintVote(model) {
    const me = currentSeat(model);
    const locked = Boolean(model.voted[me]);
    sheet.replaceChildren();
    Bac.CATEGORIES.forEach((category, cat) => {
      const row = document.createElement("div");
      row.className = "bac-row";
      const title = document.createElement("span");
      title.className = "bac-label";
      title.textContent = category.label;
      const list = document.createElement("ul");
      list.className = "bac-answers";
      model.names.forEach((name, seat) => {
        const text = Bac.clip((model.answers[seat] || [])[cat]);
        const item = document.createElement("li");
        const prop = document.createElement("div");
        prop.className = "bac-prop";
        const who = document.createElement("span");
        who.className = "bac-who";
        who.textContent = seat === me ? "Toi" : name;
        const word = document.createElement("span");
        word.className = "bac-word";
        word.textContent = text || "vide";
        if (!text) word.classList.add("is-out");
        prop.append(who, word);
        item.append(prop);
        if (text && seat !== me && !locked) {
          const votes = document.createElement("div");
          votes.className = "bac-vote";
          votes.setAttribute("role", "group");
          votes.setAttribute("aria-label", "Vote sur " + text);
          [
            { mark: "v", label: "Valider" },
            { mark: "x", label: "Refuser" },
            { mark: "", label: "Abstention" }
          ].forEach((choice) => {
            const button = document.createElement("button");
            button.type = "button";
            button.dataset.vote = choice.mark;
            button.dataset.seat = String(seat);
            button.dataset.cat = String(cat);
            button.setAttribute("aria-label", choice.label);
            button.textContent = choice.mark === "v" ? "V" : (choice.mark === "x" ? "X" : "Abs");
            if (voteValue(seat, cat) === choice.mark) button.classList.add("is-on");
            votes.append(button);
          });
          item.append(votes);
        }
        list.append(item);
      });
      row.append(title, list);
      sheet.append(row);
    });
  }

  function paintShow(model) {
    sheet.replaceChildren();
    Bac.CATEGORIES.forEach((category, cat) => {
      const row = document.createElement("div");
      row.className = "bac-row";
      const title = document.createElement("span");
      title.className = "bac-label";
      title.textContent = category.label;
      const list = document.createElement("ul");
      list.className = "bac-answers";
      model.names.forEach((name, seat) => {
        const mark = ((model.marks || [])[seat] || [])[cat] || { text: "", points: 0, accepted: false };
        const item = document.createElement("li");
        const prop = document.createElement("div");
        prop.className = "bac-prop";
        const who = document.createElement("span");
        who.className = "bac-who";
        who.textContent = name;
        const word = document.createElement("span");
        word.className = "bac-word" + (mark.accepted ? "" : " is-out");
        word.textContent = mark.text || "vide";
        prop.append(who, word);
        const pts = document.createElement("span");
        pts.className = "bac-pts";
        pts.textContent = String(Number(mark.points) || 0);
        item.append(prop, pts);
        list.append(item);
      });
      row.append(title, list);
      sheet.append(row);
    });
  }

  function viewFromRemote(state) {
    const view = state.view || {};
    const step = view.step || (state.phase === "play" ? "write" : state.phase);
    return {
      names: state.names || [],
      scores: view.scores || [],
      gained: view.gained || [],
      answers: Array.isArray(view.answers) ? view.answers : [],
      mine: view.mine || [],
      submitted: view.submitted || [],
      voted: view.voted || [],
      marks: view.marks || [],
      letter: view.letter || "",
      used: view.used || [],
      round: Number(view.round) || 1,
      rounds: Number(view.rounds) || Number(state.config && state.config.rounds) || 5,
      stopAt: view.stopAt == null ? null : Number(view.stopAt),
      phase: step === "play" ? "write" : step,
      turn: state.you,
      winner: state.winner,
      you: state.you
    };
  }

  function syncBallot(model) {
    if (model.phase !== "vote") {
      ballot = {};
      return;
    }
    const mine = (model.ballots && model.ballots[currentSeat(model)]) || {};
    if (remote && remote.view && remote.view.ballot) {
      ballot = Object.assign({}, remote.view.ballot, ballot);
      return;
    }
    if (!Object.keys(ballot).length) ballot = Object.assign({}, mine);
  }

  function paintActions(model) {
    const seat = currentSeat(model);
    const online = Boolean(remote);
    if (model.phase === "write") {
      const done = Boolean(model.submitted[seat]);
      markButtons(false, done ? [] : (online ? ["submit", "stop"] : ["submit"]));
      document.getElementById("submit").disabled = done;
      document.getElementById("stop").disabled = done;
      return;
    }
    if (model.phase === "vote") {
      markButtons(false, model.voted[seat] ? [] : ["ballot"]);
      return;
    }
    if (model.phase === "show") {
      markButtons(false, ["next"]);
      return;
    }
    markButtons(false, ["again"]);
  }

  function render() {
    const model = local || (remote ? viewFromRemote(remote) : null);
    if (!model) return;
    show("play");
    document.getElementById("letter").hidden = !model.letter || model.phase === "done";
    document.getElementById("letter").textContent = model.letter || "";
    document.getElementById("round-note").textContent = model.phase === "done"
      ? ranking(model)
      : ("Manche " + model.round + " / " + model.rounds);
    paintScores(model);
    match.totals.paint(document.getElementById("round-totals"), model.names, model.scores, model.phase !== "done");
    const seat = currentSeat(model);
    const key = [model.phase, model.letter, model.round, seat, model.submitted && model.submitted.join(""), model.voted && model.voted.join(""), model.stopAt || ""].join("|");
    if (key !== sheetKey) {
      sheetKey = key;
      if (model.phase === "write") paintWrite(model);
      else if (model.phase === "vote") {
        syncBallot(model);
        paintVote(model);
      } else paintShow(model);
    }
    paintActions(model);
    showStatus(statusText(model));
    noteEnd(model);
    if (model.phase === "write") Arcade.guideOn("bac-tutorial", bacSteps, "play");
    if (model.phase === "write" && model.stopAt) {
      if (!clock) clock = window.setInterval(() => {
        const live = local || (remote ? viewFromRemote(remote) : null);
        if (!live || live.phase !== "write" || !live.stopAt) {
          window.clearInterval(clock);
          clock = 0;
          return;
        }
        showStatus(statusText(live));
        if (Date.now() >= live.stopAt) {
          window.clearInterval(clock);
          clock = 0;
          if (local) {
            Bac.tick(local, Date.now());
            afterLocal();
          } else if (net) {
            const row = liveAnswers(live);
            const already = live.submitted[currentSeat(live)];
            net.act(already ? "tick" : "submit", { answers: row }).catch((error) => { showStatus(error.message); });
          }
        }
      }, 250);
    } else if (clock) {
      window.clearInterval(clock);
      clock = 0;
    }
  }

  function afterLocal() {
    if (local.phase === "write" || local.phase === "vote") keepDraft(local);
    render();
  }

  function startLocal() {
    local = Bac.createGame(playerNames(), rounds);
    remote = null;
    draft = null;
    ballot = {};
    sheetKey = "";
    wasDone = false;
    noted = false;
    roundId = String(Date.now());
    shell.setOnline(false);
    render();
  }

  function sendWrite(action) {
    const model = local || (remote ? viewFromRemote(remote) : null);
    if (!model || model.phase !== "write") return;
    const row = liveAnswers(model);
    if (local) {
      const error = action === "stop" ? Bac.stop(local, currentSeat(local), row) : Bac.submit(local, currentSeat(local), row);
      if (error) {
        showStatus(error);
        return;
      }
      draft = null;
      afterLocal();
      return;
    }
    if (!remote) return;
    net.act(action, { answers: row }).catch((error) => { showStatus(error.message); });
  }

  sheet.addEventListener("input", (event) => {
    const input = event.target.closest("input[data-cat]");
    if (!input) return;
    const model = local || (remote ? viewFromRemote(remote) : null);
    if (!model || model.phase !== "write") return;
    const row = liveAnswers(model);
    row[Number(input.dataset.cat)] = input.value;
    draft = { round: model.round, letter: model.letter, seat: currentSeat(model), row: Bac.readRow(row) };
    if (local) local.answers[currentSeat(local)] = draft.row.slice();
    else queueDraft();
  });

  sheet.addEventListener("click", (event) => {
    const button = event.target.closest("button[data-vote]");
    if (!button) return;
    const model = local || (remote ? viewFromRemote(remote) : null);
    if (!model || model.phase !== "vote") return;
    const key = button.dataset.seat + ":" + button.dataset.cat;
    ballot[key] = button.dataset.vote;
    paintVote(model);
  });

  function sendVote() {
    const model = local || (remote ? viewFromRemote(remote) : null);
    if (!model || model.phase !== "vote") return;
    if (local) {
      const error = Bac.vote(local, currentSeat(local), ballot);
      if (error) {
        showStatus(error);
        return;
      }
      ballot = {};
      afterLocal();
      return;
    }
    net.act("vote", { ballot }).catch((error) => { showStatus(error.message); });
  }

  document.getElementById("submit").onclick = () => sendWrite("submit");
  document.getElementById("stop").onclick = () => sendWrite("stop");
  document.getElementById("ballot").onclick = sendVote;
  document.getElementById("next").onclick = () => {
    if (local) {
      const error = Bac.nextRound(local);
      if (error) {
        showStatus(error);
        return;
      }
      draft = null;
      ballot = {};
      sheetKey = "";
      afterLocal();
      return;
    }
    net.act("next", {}).catch((error) => { showStatus(error.message); });
  };
  document.getElementById("again").onclick = () => {
    if (remote) net.act("again", {}).catch((error) => { showStatus(error.message); });
    else if (local) startLocal();
  };
  document.getElementById("leave").onclick = leaveTable;
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
  document.getElementById("rounds-less").onclick = () => {
    rounds = Math.max(3, rounds - 1);
    document.getElementById("rounds-value").textContent = String(rounds);
  };
  document.getElementById("rounds-more").onclick = () => {
    rounds = Math.min(8, rounds + 1);
    document.getElementById("rounds-value").textContent = String(rounds);
  };

  function paintLobby(state) {
    const humans = state.config && state.config.humans ? Number(state.config.humans) : 2;
    const total = state.config && state.config.rounds ? Number(state.config.rounds) : 5;
    const ready = (state.names || []).length >= humans;
    match.fillLobby(state, {
      role: humans + " joueurs, " + total + " manches.",
      note: ready ? "Tout le monde est là." : "En attente des autres joueurs.",
      ready,
      host: state.you === 0
    });
  }

  net = Arcade.room("bac", (state) => {
    local = null;
    remote = state;
    shell.setOnline(true, state.code);
    if (state.phase === "lobby") {
      wasDone = false;
      draft = null;
      ballot = {};
      sheetKey = "";
      Arcade.announceOnce("bac", false, "");
      paintLobby(state);
      return;
    }
    const model = viewFromRemote(state);
    if (model.phase !== "write") draft = null;
    if (model.phase !== "vote") ballot = {};
    else if (state.view && state.view.ballot) ballot = Object.assign({}, state.view.ballot, ballot);
    render();
  }, match.noteError);

  paintNames();
  match.setWhere("online");
  shell.paintStats();
  if (Arcade.onlineOk()) net.resume();
}
