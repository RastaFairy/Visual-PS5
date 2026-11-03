'use strict';
/* PS5HS tema claro/oscuro (1.1.59): alterna html[data-theme] y persiste la elección.
   La paleta clara vive en styles.css bajo html[data-theme='light']. */
(() => {
  const THEME_KEY = 'ps5hs-theme-v1';
  let theme = 'dark';
  try { theme = localStorage.getItem(THEME_KEY) || 'dark'; } catch { theme = 'dark'; }
  if (theme !== 'light' && theme !== 'dark') theme = 'dark';

  function applyTheme(next) {
    theme = next === 'light' ? 'light' : 'dark';
    document.documentElement.dataset.theme = theme;
    const btn = document.querySelector('#themeToggle');
    if (btn) {
      btn.textContent = theme === 'light' ? '☾' : '☀';
      btn.title = theme === 'light' ? 'Switch to dark theme' : 'Cambiar al tema claro';
    }
  }

  function toggle() {
    applyTheme(theme === 'light' ? 'dark' : 'light');
    try { localStorage.setItem(THEME_KEY, theme); } catch {}
  }

  const btn = document.querySelector('#themeToggle');
  if (btn) btn.addEventListener('click', toggle);
  applyTheme(theme);

  window.PS5HSUITheme = { applyTheme, toggle, get current() { return theme; } };
})();
