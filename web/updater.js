// Bandeau de mise à jour Android. Le téléchargement de l'APK s'ouvre dans le navigateur.
(function () {
  const REPO = "Rory-Mercury-91/Arcades-Rory";
  const DISMISS_KEY = "yams-dismissed-update";
  const HOUR = 60 * 60 * 1000;

  function internals() {
    return window.__TAURI_INTERNALS__ || null;
  }

  function invoke(command, args) {
    return internals().invoke(command, args || {});
  }

  function isAndroid() {
    return /android/i.test(navigator.userAgent);
  }

  function isNewer(latest, current) {
    const parse = (value) => String(value || "").replace(/^v/i, "").split(".").map((part) => parseInt(part, 10) || 0);
    const left = parse(latest);
    const right = parse(current);
    for (let index = 0; index < 3; index += 1) {
      if ((left[index] || 0) > (right[index] || 0)) return true;
      if ((left[index] || 0) < (right[index] || 0)) return false;
    }
    return false;
  }

  async function checkAndroid() {
    const current = await invoke("plugin:app|version");
    const response = await fetch("https://api.github.com/repos/" + REPO + "/releases/latest", {
      headers: { Accept: "application/vnd.github+json" }
    });
    if (!response.ok) return null;
    const payload = await response.json();
    const latest = String(payload.tag_name || "").replace(/^v/i, "");
    if (!latest || !isNewer(latest, current)) return null;
    const asset = (payload.assets || []).find((item) => {
      const name = String(item.name || "").toLowerCase();
      return name.includes("android") && name.endsWith(".apk");
    });
    if (!asset || !asset.browser_download_url) return null;
    return { kind: "android", version: latest, downloadUrl: asset.browser_download_url };
  }

  function dismissed() {
    try { return localStorage.getItem(DISMISS_KEY) || ""; } catch (error) { return ""; }
  }

  function remember(version) {
    try { localStorage.setItem(DISMISS_KEY, version); } catch (error) { /* stockage refusé */ }
  }

  function ensureStyle() {
    if (document.getElementById("update-style")) return;
    const style = document.createElement("style");
    style.id = "update-style";
    style.textContent = `
      .update-banner {
        position: fixed;
        z-index: 40;
        left: 12px;
        right: 12px;
        bottom: calc(12px + var(--system-nav-inset, env(safe-area-inset-bottom, 0px)));
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        max-width: 456px;
        margin: 0 auto;
        padding: 12px;
        border: 1px solid var(--line);
        border-radius: 16px;
        background: var(--card);
        color: var(--ink);
        box-shadow: 0 10px 30px rgba(0, 0, 0, 0.18);
      }
      .update-banner[hidden] { display: none !important; }
      .update-banner p { margin: 0; }
      .update-banner strong { display: block; }
      .update-banner span { color: var(--muted); font-size: 14px; }
      .update-banner .actions { display: flex; align-items: center; gap: 8px; flex: none; }
      .update-banner button {
        height: 40px;
        border-radius: 12px;
        border: 1px solid var(--line);
        background: var(--card);
      }
      .update-banner .apply {
        padding: 0 12px;
        background: var(--accent);
        border-color: var(--accent);
        color: var(--accent-ink);
        font-weight: 700;
      }
      .update-banner .dismiss { width: 40px; font-size: 18px; }
    `;
    document.head.appendChild(style);
  }

  function banner() {
    let node = document.getElementById("update-banner");
    if (node) return node;
    ensureStyle();
    node = document.createElement("div");
    node.id = "update-banner";
    node.className = "update-banner";
    node.hidden = true;
    node.setAttribute("role", "status");
    node.innerHTML = `<p><strong id="update-title"></strong><span id="update-copy"></span></p><div class="actions"><button type="button" class="apply" id="update-apply">Mettre à jour</button><button type="button" class="dismiss" id="update-dismiss" aria-label="Ignorer cette mise à jour">×</button></div>`;
    document.body.appendChild(node);
    return node;
  }

  let current = null;
  let busy = false;

  function paint() {
    const node = banner();
    if (!current || current.version === dismissed()) {
      node.hidden = true;
      return;
    }
    document.getElementById("update-title").textContent = "Mise à jour " + current.version;
    document.getElementById("update-copy").textContent = "Le téléchargement s'ouvre dans le navigateur.";
    const apply = document.getElementById("update-apply");
    apply.disabled = busy;
    apply.textContent = busy ? "Installation…" : "Mettre à jour";
    node.hidden = false;
  }

  async function look() {
    try {
      const found = await checkAndroid();
      current = found;
      paint();
    } catch (error) {
      console.warn("Vérification de mise à jour impossible :", error);
    }
  }

  async function apply() {
    if (!current || busy) return;
    busy = true;
    paint();
    try {
      await invoke("plugin:opener|open_url", { url: current.downloadUrl });
    } catch (error) {
      console.warn("Mise à jour impossible :", error);
      const copy = document.getElementById("update-copy");
      if (copy) copy.textContent = "La mise à jour n'a pas abouti.";
    } finally {
      busy = false;
      paint();
    }
  }

  function start() {
    const node = banner();
    document.getElementById("update-apply").onclick = () => { apply(); };
    document.getElementById("update-dismiss").onclick = () => {
      if (current) remember(current.version);
      node.hidden = true;
    };
    look();
    window.setInterval(() => {
      if (document.visibilityState === "visible") look();
    }, HOUR);
    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "visible") look();
    });
  }

  if (!internals() || !isAndroid()) return;
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start);
  else start();
})();
