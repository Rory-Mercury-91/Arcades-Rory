// Grilles solo : Sudoku et Chat Doku. Même salon Arcade, mêmes boutons, une seule logique de grille.
const Doku = (() => {
  const CAT_SVG = `<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M7.2 9.1 4.6 4.8c-.3-.5.3-1.1.8-.8L9 6.6c.6-.3 1.3-.5 2-.6h2c.7.1 1.4.3 2 .6l3.6-2.6c.5-.3 1.1.3.8.8l-2.6 4.3c1.2 1.2 1.9 2.7 1.9 4.3 0 3.3-3 5.7-5.7 5.7h0c-2.7 0-5.7-2.4-5.7-5.7 0-1.6.7-3.1 1.9-4.3z"/><circle cx="9.4" cy="13" r="1.15" fill="var(--card)"/><circle cx="14.6" cy="13" r="1.15" fill="var(--card)"/></svg>`;

  function shuffle(list) {
    const next = list.slice();
    for (let index = next.length - 1; index > 0; index -= 1) {
      const swap = Math.floor(Math.random() * (index + 1));
      const hold = next[index];
      next[index] = next[swap];
      next[swap] = hold;
    }
    return next;
  }

  function digits(size) {
    return Array.from({ length: size }, (_, index) => index + 1);
  }

  function boxShape(size) {
    if (size === 9) return { w: 3, h: 3 };
    if (size === 6) return { w: 3, h: 2 };
    return { w: 2, h: 2 };
  }

  function around(size, index) {
    const row = Math.floor(index / size);
    const col = index % size;
    const list = [];
    [[-1, 0], [1, 0], [0, -1], [0, 1]].forEach(([dr, dc]) => {
      const nextRow = row + dr;
      const nextCol = col + dc;
      if (nextRow >= 0 && nextCol >= 0 && nextRow < size && nextCol < size) {
        list.push(nextRow * size + nextCol);
      }
    });
    return list;
  }

  function ring(size, index) {
    const row = Math.floor(index / size);
    const col = index % size;
    const list = [];
    for (let dr = -1; dr <= 1; dr += 1) {
      for (let dc = -1; dc <= 1; dc += 1) {
        if (!dr && !dc) continue;
        const nextRow = row + dr;
        const nextCol = col + dc;
        if (nextRow < 0 || nextCol < 0 || nextRow >= size || nextCol >= size) continue;
        list.push(nextRow * size + nextCol);
      }
    }
    return list;
  }

  function emptyNotes(size) {
    return Array.from({ length: size * size }, () => []);
  }

  function sudokuCan(size, values, index, value) {
    const row = Math.floor(index / size);
    const col = index % size;
    for (let i = 0; i < size; i += 1) {
      if (values[row * size + i] === value) return false;
      if (values[i * size + col] === value) return false;
    }
    const shape = boxShape(size);
    const originRow = Math.floor(row / shape.h) * shape.h;
    const originCol = Math.floor(col / shape.w) * shape.w;
    for (let dr = 0; dr < shape.h; dr += 1) {
      for (let dc = 0; dc < shape.w; dc += 1) {
        if (values[(originRow + dr) * size + originCol + dc] === value) return false;
      }
    }
    return true;
  }

  function sudokuCount(values, size, limit) {
    const grid = values.slice();
    let found = 0;
    function walk() {
      if (found >= limit) return;
      let best = -1;
      let options = null;
      for (let index = 0; index < grid.length; index += 1) {
        if (grid[index]) continue;
        const choices = [];
        for (let value = 1; value <= size; value += 1) {
          if (sudokuCan(size, grid, index, value)) choices.push(value);
        }
        if (!choices.length) return;
        if (!options || choices.length < options.length) {
          best = index;
          options = choices;
          if (choices.length === 1) break;
        }
      }
      if (best < 0) {
        found += 1;
        return;
      }
      const order = shuffle(options);
      for (let i = 0; i < order.length; i += 1) {
        grid[best] = order[i];
        walk();
        if (found >= limit) {
          grid[best] = 0;
          return;
        }
      }
      grid[best] = 0;
    }
    walk();
    return found;
  }

  function sudokuFill(size) {
    const grid = Array(size * size).fill(0);
    function walk(index) {
      if (index >= grid.length) return true;
      if (grid[index]) return walk(index + 1);
      const order = shuffle(digits(size));
      for (let i = 0; i < order.length; i += 1) {
        if (!sudokuCan(size, grid, index, order[i])) continue;
        grid[index] = order[i];
        if (walk(index + 1)) return true;
      }
      grid[index] = 0;
      return false;
    }
    return walk(0) ? grid : null;
  }

  function clueTarget(size, level) {
    if (size === 4) return level === "hard" ? 5 : level === "medium" ? 6 : 8;
    if (size === 6) return level === "hard" ? 10 : level === "medium" ? 14 : 18;
    return level === "hard" ? 28 : level === "medium" ? 32 : 38;
  }

  function sudokuMake(size, level) {
    const full = sudokuFill(size);
    if (!full) return sudokuMake(size, level);
    const given = full.slice();
    const order = shuffle(Array.from({ length: given.length }, (_, index) => index));
    const target = clueTarget(size, level);
    for (let i = 0; i < order.length; i += 1) {
      const index = order[i];
      const saved = given[index];
      given[index] = 0;
      if (sudokuCount(given, size, 2) !== 1) given[index] = saved;
      const clues = given.filter(Boolean).length;
      if (clues <= target) break;
    }
    return {
      kind: "sudoku",
      size,
      given,
      values: given.slice(),
      colors: null,
      solution: full,
      notes: emptyNotes(size)
    };
  }

  function chatCount(size, colors, locked, limit) {
    const spots = [];
    let found = 0;
    function walk(row, usedCols, usedColors) {
      if (found >= limit) return;
      if (row === size) {
        found += 1;
        return;
      }
      const forced = locked[row];
      const cols = forced >= 0 ? [forced] : shuffle(Array.from({ length: size }, (_, index) => index));
      for (let i = 0; i < cols.length; i += 1) {
        const col = cols[i];
        if (usedCols & (1 << col)) continue;
        const index = row * size + col;
        const tone = colors[index];
        if (usedColors & (1 << tone)) continue;
        let close = false;
        for (let j = 0; j < spots.length; j += 1) {
          const other = spots[j];
          const otherRow = Math.floor(other / size);
          const otherCol = other % size;
          if (Math.abs(row - otherRow) <= 1 && Math.abs(col - otherCol) <= 1) {
            close = true;
            break;
          }
        }
        if (close) continue;
        spots.push(index);
        walk(row + 1, usedCols | (1 << col), usedColors | (1 << tone));
        spots.pop();
        if (found >= limit) return;
      }
    }
    walk(0, 0, 0);
    return found;
  }

  function placeCats(size) {
    const cols = [];
    function walk(row, used) {
      if (row === size) return true;
      const order = shuffle(Array.from({ length: size }, (_, index) => index));
      for (let i = 0; i < order.length; i += 1) {
        const col = order[i];
        if (used & (1 << col)) continue;
        if (row > 0 && Math.abs(cols[row - 1] - col) <= 1) continue;
        cols[row] = col;
        if (walk(row + 1, used | (1 << col))) return true;
      }
      return false;
    }
    if (!walk(0, 0)) return null;
    return cols.map((col, row) => row * size + col);
  }

  function growRegions(size, spots) {
    const total = size * size;
    const colors = Array(total).fill(-1);
    const counts = Array(size).fill(1);
    spots.forEach((index, color) => { colors[index] = color; });
    let guard = 0;
    while (colors.indexOf(-1) >= 0 && guard < total * 24) {
      guard += 1;
      const options = [];
      for (let index = 0; index < total; index += 1) {
        if (colors[index] >= 0) continue;
        const seen = new Set();
        around(size, index).forEach((next) => {
          const color = colors[next];
          if (color < 0 || seen.has(color)) return;
          seen.add(color);
          options.push({ index, color, weight: 1 / counts[color] });
        });
      }
      if (!options.length) {
        const empty = colors.findIndex((color) => color < 0);
        const row = Math.floor(empty / size);
        const col = empty % size;
        let best = 0;
        let bestDist = 99;
        spots.forEach((index, color) => {
          const dist = Math.abs(Math.floor(index / size) - row) + Math.abs((index % size) - col);
          if (dist < bestDist) {
            bestDist = dist;
            best = color;
          }
        });
        colors[empty] = best;
        counts[best] += 1;
        continue;
      }
      let pick = Math.random() * options.reduce((sum, item) => sum + item.weight, 0);
      let chosen = options[0];
      for (let i = 0; i < options.length; i += 1) {
        pick -= options[i].weight;
        if (pick <= 0) {
          chosen = options[i];
          break;
        }
      }
      colors[chosen.index] = chosen.color;
      counts[chosen.color] += 1;
    }
    return colors;
  }

  function chatClues(size, level) {
    if (level === "easy") return Math.max(1, Math.floor(size / 3));
    if (level === "medium") return size <= 6 ? 1 : 1;
    return 0;
  }

  function chatMake(size, level) {
    for (let attempt = 0; attempt < 48; attempt += 1) {
      const spots = placeCats(size);
      if (!spots) continue;
      const colors = growRegions(size, spots);
      const want = chatClues(size, level);
      const keep = shuffle(spots.slice()).slice(0, want);
      const given = Array(size * size).fill(0);
      keep.forEach((index) => { given[index] = 1; });
      const locked = Array(size).fill(-1);
      let clash = false;
      given.forEach((value, index) => {
        if (!value) return;
        const row = Math.floor(index / size);
        if (locked[row] >= 0) clash = true;
        locked[row] = index % size;
      });
      if (clash) continue;
      const found = chatCount(size, colors, locked, 2);
      if (found !== 1 && want === 0) {
        const extra = spots[Math.floor(Math.random() * spots.length)];
        given[extra] = 1;
        locked[Math.floor(extra / size)] = extra % size;
        if (chatCount(size, colors, locked, 2) !== 1) continue;
      } else if (found !== 1) continue;
      const solution = Array(size * size).fill(0);
      spots.forEach((index) => { solution[index] = 1; });
      return {
        kind: "chatdoku",
        size,
        given,
        values: given.slice(),
        colors,
        solution,
        notes: emptyNotes(size)
      };
    }
    return chatMake(size, "easy");
  }

  function make(kind, size, level) {
    const rank = level === "hard" || level === "medium" ? level : "easy";
    if (kind === "sudoku") {
      const grid = size === 4 || size === 6 ? size : 9;
      return sudokuMake(grid, rank);
    }
    const grid = Math.max(5, Math.min(9, size || 7));
    return chatMake(grid, rank);
  }

  function sudokuConflicts(size, values) {
    const bad = new Set();
    function mark(list) {
      const seen = new Map();
      list.forEach((index) => {
        const value = values[index];
        if (!value) return;
        if (!seen.has(value)) seen.set(value, []);
        seen.get(value).push(index);
      });
      seen.forEach((cells) => {
        if (cells.length > 1) cells.forEach((index) => bad.add(index));
      });
    }
    for (let row = 0; row < size; row += 1) {
      mark(Array.from({ length: size }, (_, col) => row * size + col));
    }
    for (let col = 0; col < size; col += 1) {
      mark(Array.from({ length: size }, (_, row) => row * size + col));
    }
    const box = boxShape(size);
    for (let originRow = 0; originRow < size; originRow += box.h) {
      for (let originCol = 0; originCol < size; originCol += box.w) {
        const cells = [];
        for (let dr = 0; dr < box.h; dr += 1) {
          for (let dc = 0; dc < box.w; dc += 1) cells.push((originRow + dr) * size + originCol + dc);
        }
        mark(cells);
      }
    }
    return bad;
  }

  function chatConflicts(size, colors, values) {
    const bad = new Set();
    const spots = [];
    values.forEach((value, index) => {
      if (value) spots.push(index);
    });
    const rows = new Map();
    const cols = new Map();
    const tones = new Map();
    spots.forEach((index) => {
      const row = Math.floor(index / size);
      const col = index % size;
      if (!rows.has(row)) rows.set(row, []);
      if (!cols.has(col)) cols.set(col, []);
      if (!tones.has(colors[index])) tones.set(colors[index], []);
      rows.get(row).push(index);
      cols.get(col).push(index);
      tones.get(colors[index]).push(index);
    });
    function bunch(map) {
      map.forEach((cells) => {
        if (cells.length > 1) cells.forEach((index) => bad.add(index));
      });
    }
    bunch(rows);
    bunch(cols);
    bunch(tones);
    spots.forEach((index) => {
      ring(size, index).forEach((next) => {
        if (values[next]) {
          bad.add(index);
          bad.add(next);
        }
      });
    });
    return bad;
  }

  function conflicts(puzzle) {
    if (puzzle.kind === "sudoku") return sudokuConflicts(puzzle.size, puzzle.values);
    return chatConflicts(puzzle.size, puzzle.colors, puzzle.values);
  }

  function solved(puzzle) {
    if (conflicts(puzzle).size) return false;
    if (puzzle.kind === "sudoku") {
      return puzzle.values.every((value) => value > 0);
    }
    const cats = puzzle.values.filter((value) => value).length;
    return cats === puzzle.size;
  }

  function payloadOf(puzzle) {
    return {
      kind: puzzle.kind,
      size: puzzle.size,
      given: puzzle.given.slice(),
      solution: puzzle.solution.slice(),
      colors: puzzle.colors ? puzzle.colors.slice() : []
    };
  }

  function fromView(kind, view) {
    const size = Number(view.size) || (kind === "sudoku" ? 9 : 7);
    const given = (view.given || []).map((value) => Number(value) || 0);
    const values = (view.values || given).map((value) => Number(value) || 0);
    return {
      kind,
      size,
      given,
      values,
      colors: kind === "chatdoku" ? (view.colors || []).map((value) => Number(value) || 0) : null,
      solution: (view.solution || []).map((value) => Number(value) || 0),
      notes: emptyNotes(size)
    };
  }

  function kindInfo(kind) {
    if (kind === "chatdoku") {
      return {
        id: "chatdoku",
        title: "Chat Doku",
        sizes: [5, 6, 7, 8, 9],
        defaultSize: 7
      };
    }
    return {
      id: "sudoku",
      title: "Sudoku",
      sizes: [4, 6, 9],
      defaultSize: 9
    };
  }

  function levelLabel(level) {
    if (level === "hard") return "Difficile";
    if (level === "medium") return "Moyen";
    return "Facile";
  }

  function mount(kind) {
    const info = kindInfo(kind);
    let size = info.defaultSize;
    let level = "easy";
    let pencil = false;
    let selected = -1;
    let local = null;
    let remote = null;
    let net = null;
    let lastStamp = "";
    let dealing = false;

    const grid = document.getElementById("grid");
    const pad = document.getElementById("pad");
    const status = document.getElementById("status");

    function current() {
      return local || (remote ? fromView(kind, remote.view || {}) : null);
    }

    function settingsRows() {
      const online = Boolean(remote);
      const puzzle = current();
      const boardSize = puzzle ? puzzle.size : size;
      return [
        ["Grille", boardSize + " × " + boardSize, kind === "sudoku"
          ? "Chiffres de 1 à " + boardSize + ", sans doublon sur la ligne, la colonne ni le bloc."
          : "Un chat par ligne, colonne et couleur. Jamais l'un contre l'autre, même en diagonal."],
        ["Niveau", levelLabel(puzzle && remote && remote.config ? remote.config.level : level), "Facile laisse plus d'indices. Difficile en retire davantage."],
        ["Table", online ? "En ligne · " + remote.code : "Sur ce téléphone", "Solo. En ligne, le code sert à reprendre la même grille plus tard."]
      ];
    }

    function rules() {
      if (kind === "sudoku") {
        return [
          ["Chiffres", "Remplis chaque case. Un chiffre ne se répète ni sur sa ligne, ni sur sa colonne, ni dans son bloc."],
          ["Indices", "Les cases déjà remplies restent. Le crayon pose des petits chiffres, sans valider."],
          ["Fin", "Quand la grille est juste, la partie est gagnée. Rejouer tire une nouvelle grille."]
        ];
      }
      return [
        ["Chats", "Pose un chat par ligne et par colonne. Deux chats ne peuvent pas se toucher, même par un coin."],
        ["Couleurs", "Chaque couleur n'accueille qu'un chat. La grille change à chaque partie, jusqu'à neuf couleurs."],
        ["Fin", "Quand tous les chats sont bien placés, la partie est gagnée. Rejouer tire une nouvelle grille."]
      ];
    }

    function steps() {
      const onlineNote = "En ligne, c'est encore solo : une table à toi, avec un code pour reprendre plus tard.";
      if (kind === "sudoku") {
        return [
          ...Arcade.gateTour((mode) => match.setWhere(mode), {
            title: "Sudoku",
            text: "Choisis la taille et le niveau, puis lance. Une grille, à remplir tout seul.",
            target: () => document.getElementById("step-create")
          }, onlineNote),
          Object.assign(Arcade.chromeStep(), { page: "play" }),
          {
            page: "play",
            title: "La grille",
            render: Arcade.pictured(
              "Touche une case, puis un chiffre. Un même chiffre ne revient ni en ligne, ni en colonne, ni dans le bloc.",
              `<div class="coach-doku is-sudo"><span>5</span><span></span><span>1</span><span></span><span>8</span><span>3</span><span>4</span><span></span><span>2</span></div>`
            ),
            target: () => document.getElementById("grid")
          },
          {
            page: "play",
            title: "Le crayon",
            render: Arcade.pictured("Le crayon pose des petits chiffres pour se souvenir des possibilités, sans remplir la case.", `<p class="coach-go">Crayon</p>`),
            target: () => document.getElementById("pad")
          }
        ];
      }
      return [
        ...Arcade.gateTour((mode) => match.setWhere(mode), {
          title: "Chat Doku",
          text: "Choisis la taille. Plus c'est grand, plus il y a de couleurs — neuf au plus.",
          target: () => document.getElementById("step-create")
        }, onlineNote),
        Object.assign(Arcade.chromeStep(), { page: "play" }),
        {
          page: "play",
          title: "Les chats",
          render: Arcade.pictured(
            "Un chat par ligne, par colonne et par couleur. Ils ne se touchent pas, même par un coin.",
            `<div class="coach-doku is-cat">${CAT_SVG}<span></span><span></span><span></span>${CAT_SVG}<span></span><span></span><span></span>${CAT_SVG}</div>`
          ),
          target: () => document.getElementById("grid")
        }
      ];
    }

    function leaveTable() {
      match.release(net, remote);
      remote = null;
      local = null;
    }

    const sizeButtons = info.sizes.map((value) => {
      return `<button type="button" data-size="${value}"${value === info.defaultSize ? ' class="is-on"' : ""}>${value}</button>`;
    }).join("");

    const match = Arcade.mountMatch({
      title: info.title,
      game: kind,
      board: "play",
      settings: settingsRows,
      rules,
      guide: steps,
      onReset() { leaveTable(); },
      onLeave() { leaveTable(); },
      onLocal() { startLocal(); },
      onOnline(name) {
        const puzzle = make(kind, size, level);
        net.create(name, Object.assign({ level }, payloadOf(puzzle))).catch((error) => {
          document.getElementById("create-error").textContent = error.message;
        });
      },
      onStart() {
        net.act("start", {}).catch((error) => {
          document.getElementById("lobby-note").textContent = error.message;
        });
      },
      currentRemote() { return remote; },
      optionsHtml: `<p class="lead">Taille</p>
        <div class="choice${info.sizes.length > 4 ? " wrap" : " thirds"}" id="sizes">${sizeButtons}</div>
        <p class="lead">Niveau</p>
        <div class="choice thirds" id="levels">
          <button type="button" data-level="easy" class="is-on">Facile</button>
          <button type="button" data-level="medium">Moyen</button>
          <button type="button" data-level="hard">Difficile</button>
        </div>`,
      localHtml: `<p class="lead">Une grille, à toi seul. Pas de tour, pas d'adversaire.</p>`,
      onlineHtml: `<p class="lead">Toujours solo. Le code te permet de reprendre la même grille plus tard, sur ce téléphone ou un autre.</p>`
    });

    const shell = match.shell;
    const show = match.show;

    function maybeGuide() {
      const playing = local ? !solved(local) : Boolean(remote && remote.phase === "play");
      Arcade.playGuide(kind + "-tutorial", steps, playing);
    }

    function statusText(puzzle, over) {
      if (over) return "Grille terminée.";
      if (kind === "sudoku") {
        return pencil ? "Crayon : les petits chiffres ne remplissent pas la case." : "Choisis une case, puis un chiffre.";
      }
      const left = puzzle.size - puzzle.values.filter(Boolean).length;
      if (left <= 0) return "Vérifie les chats en trop, ou les couleurs en double.";
      return left + (left > 1 ? " chats à placer." : " chat à placer.");
    }

    function paintPad(puzzle, over) {
      if (kind !== "sudoku") {
        pad.innerHTML = "";
        pad.hidden = true;
        return;
      }
      pad.hidden = false;
      const used = Array(puzzle.size + 1).fill(0);
      puzzle.values.forEach((value) => { if (value) used[value] += 1; });
      let html = "";
      for (let value = 1; value <= puzzle.size; value += 1) {
        const full = used[value] >= puzzle.size;
        html += `<button type="button" data-digit="${value}"${full ? ' class="is-full"' : ""}>${value}</button>`;
      }
      html += `<button type="button" data-digit="0" aria-label="Effacer">⌫</button>`;
      html += `<button type="button" data-pencil="1" class="${pencil ? "is-on" : ""}">Crayon</button>`;
      pad.innerHTML = html;
      pad.querySelectorAll("button").forEach((button) => { button.disabled = over; });
    }

    function paintGrid(puzzle, over) {
      const bad = over ? new Set() : conflicts(puzzle);
      grid.style.gridTemplateColumns = `repeat(${puzzle.size}, 1fr)`;
      grid.className = "doku-board" + (kind === "sudoku" ? " is-sudo" : " is-cat");
      grid.dataset.size = String(puzzle.size);
      const box = boxShape(puzzle.size);
      let html = "";
      for (let index = 0; index < puzzle.size * puzzle.size; index += 1) {
        const row = Math.floor(index / puzzle.size);
        const col = index % puzzle.size;
        const locked = Boolean(puzzle.given[index]);
        const classes = ["doku-cell"];
        if (locked) classes.push("is-given");
        if (selected === index) classes.push("is-on");
        if (bad.has(index)) classes.push("is-bad");
        if (kind === "sudoku") {
          if ((col + 1) % box.w === 0) classes.push("is-box-right");
          if ((row + 1) % box.h === 0) classes.push("is-box-bottom");
        }
        const tone = kind === "chatdoku" ? ` data-tone="${puzzle.colors[index]}"` : "";
        let inner = "";
        if (kind === "chatdoku") {
          inner = puzzle.values[index] ? CAT_SVG : "";
        } else if (puzzle.values[index]) {
          inner = String(puzzle.values[index]);
        } else if ((puzzle.notes[index] || []).length) {
          inner = `<small>${puzzle.notes[index].join(" ")}</small>`;
        }
        html += `<button type="button" class="${classes.join(" ")}" data-i="${index}"${tone}${over || (kind === "chatdoku" && locked) ? " disabled" : ""} aria-label="Case ${row + 1}, ${col + 1}">${inner}</button>`;
      }
      grid.innerHTML = html;
    }

    function finishIfNeeded(puzzle, stamp) {
      const over = solved(puzzle);
      if (over && stamp && stamp !== lastStamp) {
        lastStamp = stamp;
        Arcade.recordStats(kind, [{ name: Arcade.playerName() || "Toi", result: "win" }]);
      }
      return over;
    }

    function paintLocal() {
      const over = finishIfNeeded(local, local.stamp);
      paintGrid(local, over);
      paintPad(local, over);
      document.getElementById("hint").disabled = over;
      status.textContent = statusText(local, over);
      Arcade.announceOnce(kind, over, `<p>${Arcade.escapeHtml(statusText(local, true))}</p>`);
      maybeGuide();
    }

    function paintRemote(state) {
      const puzzle = fromView(kind, state.view || {});
      const over = state.phase === "done";
      paintGrid(puzzle, over);
      paintPad(puzzle, over);
      document.getElementById("hint").disabled = over;
      status.textContent = statusText(puzzle, over);
      Arcade.announceOnce(kind, over, `<p>${Arcade.escapeHtml(statusText(puzzle, true))}</p>`);
      if (over) finishIfNeeded(puzzle, state.code + ":" + (state.view && state.view.stamp));
      maybeGuide();
    }

    function startLocal() {
      Arcade.dismissEnd();
      remote = null;
      shell.setOnline(false);
      selected = -1;
      pencil = false;
      lastStamp = "";
      local = make(kind, size, level);
      local.stamp = String(Date.now());
      show("play");
      paintLocal();
    }

    function applyLocal(index, value) {
      if (!local || solved(local)) return;
      if (local.given[index]) return;
      if (kind === "chatdoku") {
        local.values[index] = local.values[index] ? 0 : 1;
        paintLocal();
        return;
      }
      if (pencil && value) {
        const notes = local.notes[index];
        const at = notes.indexOf(value);
        if (at >= 0) notes.splice(at, 1);
        else notes.push(value);
        notes.sort((a, b) => a - b);
        local.values[index] = 0;
      } else {
        local.values[index] = value;
        local.notes[index] = [];
      }
      paintLocal();
    }

    function hintLocal() {
      if (!local || solved(local)) return;
      const holes = [];
      local.values.forEach((value, index) => {
        if (!local.given[index] && value !== local.solution[index]) holes.push(index);
      });
      if (!holes.length) return;
      const index = holes[Math.floor(Math.random() * holes.length)];
      local.values[index] = local.solution[index];
      local.notes[index] = [];
      selected = index;
      paintLocal();
    }

    function dealRemote() {
      if (dealing) return;
      dealing = true;
      const puzzle = make(kind, size, level);
      net.act("deal", payloadOf(puzzle)).catch((error) => {
        dealing = false;
        status.textContent = error.message;
      });
    }

    net = Arcade.room(kind, (state) => {
      local = null;
      remote = state;
      shell.setOnline(true, state.code);
      if (state.phase === "lobby") {
        Arcade.announceOnce(kind, false, "");
        match.fillLobby(state, {
          role: info.title + " · solo",
          note: "Table prête.",
          ready: true,
          host: state.you === 0
        });
        return;
      }
      show("play");
      const view = state.view || {};
      if (!(view.given || []).length) {
        dealRemote();
        status.textContent = "Préparation de la grille…";
        return;
      }
      dealing = false;
      paintRemote(state);
    }, match.noteError);

    match.bindChoice("sizes", (button) => {
      size = Number(button.dataset.size);
    });
    match.bindChoice("levels", (button) => {
      level = button.dataset.level;
    });

    grid.addEventListener("click", (event) => {
      const button = event.target.closest("[data-i]");
      if (!button) return;
      const index = Number(button.dataset.i);
      if (local) {
        if (kind === "chatdoku") applyLocal(index, 1);
        else {
          selected = index;
          paintLocal();
        }
        return;
      }
      if (!remote || remote.phase !== "play") return;
      if (kind === "chatdoku") {
        const puzzle = fromView(kind, remote.view || {});
        if (puzzle.given[index]) return;
        net.act("place", { i: index, v: puzzle.values[index] ? 0 : 1 }).catch((error) => {
          status.textContent = error.message;
        });
        return;
      }
      selected = index;
      paintRemote(remote);
    });

    pad.addEventListener("click", (event) => {
      const pencilBtn = event.target.closest("[data-pencil]");
      if (pencilBtn) {
        pencil = !pencil;
        const puzzle = current();
        if (puzzle) {
          if (local) paintLocal();
          else if (remote) paintRemote(remote);
        }
        return;
      }
      const digitBtn = event.target.closest("[data-digit]");
      if (!digitBtn) return;
      const value = Number(digitBtn.dataset.digit);
      if (selected < 0) return;
      if (local) applyLocal(selected, value);
      else if (remote && remote.phase === "play") {
        net.act("place", { i: selected, v: value }).catch((error) => {
          status.textContent = error.message;
        });
      }
    });

    document.addEventListener("keydown", (event) => {
      if (kind !== "sudoku") return;
      const play = document.getElementById("play");
      if (!play || play.classList.contains("hidden")) return;
      const puzzle = current();
      if (!puzzle || solved(puzzle)) return;
      if (event.key === "Backspace" || event.key === "Delete") {
        if (selected >= 0) {
          if (local) applyLocal(selected, 0);
          else if (remote) net.act("place", { i: selected, v: 0 }).catch(() => {});
        }
        return;
      }
      const value = Number(event.key);
      if (value >= 1 && value <= puzzle.size && selected >= 0) {
        if (local) applyLocal(selected, value);
        else if (remote) net.act("place", { i: selected, v: value }).catch(() => {});
      }
    });

    document.getElementById("hint").onclick = () => {
      if (local) hintLocal();
      else if (remote && remote.phase === "play") {
        net.act("hint", {}).catch((error) => { status.textContent = error.message; });
      }
    };
    document.getElementById("again").onclick = () => {
      selected = -1;
      lastStamp = "";
      if (local) startLocal();
      else if (remote) {
        const puzzle = make(kind, size, level);
        net.act("again", payloadOf(puzzle)).catch((error) => { status.textContent = error.message; });
      }
    };
    document.getElementById("leave").onclick = leaveTable;
    if (Arcade.onlineOk()) net.resume();
  }

  const api = { make, conflicts, solved, mount, payloadOf, kindInfo };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  return api;
})();
