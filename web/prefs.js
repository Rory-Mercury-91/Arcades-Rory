/* Nom, thème, suivi de feuille et place des tuiles. Lu avant les feuilles de style. */
(function () {
  const NAME_KEY = "arcade-player-name";
  const THEME_KEY = "arcade-theme";
  const FOLLOW_KEY = "yams-follow-sheet";
  const HAND_KEY = "triomino-hand-place";
  const LIGHT = "#efe6d8";
  const DARK = "#171410";

  function theme() {
    try {
      const value = localStorage.getItem(THEME_KEY);
      if (value === "light" || value === "dark") return value;
    } catch (error) { /* stockage refusé */ }
    return "system";
  }

  function applyTheme(value) {
    const chosen = value === "light" || value === "dark" ? value : "system";
    const root = document.documentElement;
    if (chosen === "system") delete root.dataset.theme;
    else root.dataset.theme = chosen;
    document.querySelectorAll('meta[name="theme-color"]').forEach((meta) => {
      const slot = meta.getAttribute("data-slot");
      if (chosen === "light" || chosen === "dark") {
        meta.setAttribute("content", chosen === "dark" ? DARK : LIGHT);
        meta.removeAttribute("media");
        return;
      }
      if (slot !== "light" && slot !== "dark") return;
      meta.setAttribute("content", slot === "dark" ? DARK : LIGHT);
      meta.setAttribute("media", slot === "dark" ? "(prefers-color-scheme: dark)" : "(prefers-color-scheme: light)");
    });
  }

  function playerName() {
    try { return (localStorage.getItem(NAME_KEY) || "").trim().slice(0, 24); }
    catch (error) { return ""; }
  }

  function setPlayerName(value) {
    const clean = String(value || "").slice(0, 24);
    try {
      if (clean.trim()) localStorage.setItem(NAME_KEY, clean);
      else localStorage.removeItem(NAME_KEY);
    } catch (error) { /* stockage refusé */ }
  }

  function setTheme(value) {
    const chosen = value === "light" || value === "dark" ? value : "system";
    try {
      if (chosen === "system") localStorage.removeItem(THEME_KEY);
      else localStorage.setItem(THEME_KEY, chosen);
    } catch (error) { /* stockage refusé */ }
    applyTheme(chosen);
  }

  function followSheet() {
    try { return localStorage.getItem(FOLLOW_KEY) !== "0"; }
    catch (error) { return true; }
  }

  function setFollowSheet(on) {
    try { localStorage.setItem(FOLLOW_KEY, on ? "1" : "0"); }
    catch (error) { /* stockage refusé */ }
  }

  function handPlace() {
    try { return localStorage.getItem(HAND_KEY) === "modal" ? "modal" : "board"; }
    catch (error) { return "board"; }
  }

  function setHandPlace(place) {
    try { localStorage.setItem(HAND_KEY, place === "modal" ? "modal" : "board"); }
    catch (error) { /* stockage refusé */ }
  }

  const HAND_COLUMNS_KEY = "triomino-hand-columns";

  function handColumns() {
    try { return localStorage.getItem(HAND_COLUMNS_KEY) === "4" ? 4 : 3; }
    catch (error) { return 3; }
  }

  function setHandColumns(count) {
    try { localStorage.setItem(HAND_COLUMNS_KEY, Number(count) === 4 ? "4" : "3"); }
    catch (error) { /* stockage refusé */ }
  }

  applyTheme(theme());
  document.addEventListener("DOMContentLoaded", () => applyTheme(theme()));

  function onResume(callback) {
    let last = 0;
    function fire() {
      const now = Date.now();
      if (now - last < 500) return;
      last = now;
      callback();
    }
    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "visible") fire();
    });
    window.addEventListener("pageshow", fire);
    window.addEventListener("focus", fire);
    window.addEventListener("yams-resume", fire);
  }

  window.Prefs = { playerName, setPlayerName, theme, setTheme, followSheet, setFollowSheet, handPlace, setHandPlace, handColumns, setHandColumns, onResume };
})();
