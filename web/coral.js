/*
 * coral.js — the three behaviours the landing page needs. No dependencies, no requests.
 *
 * 1. Theme toggle, mirroring the app's Settings → Appearance (auto / light / dark).
 *    Auto follows the OS; an explicit choice is remembered in localStorage and stamped
 *    on <html data-theme> so it wins over the prefers-color-scheme defaults in coral.css.
 * 2. `brew install` copy button.
 * 3. A hairline under the header once you scroll (same treatment as the app's top bar).
 */
(function () {
  'use strict';

  var root = document.documentElement;
  var KEY = 'coral.theme';

  function stored() {
    try { return localStorage.getItem(KEY); } catch (e) { return null; }
  }
  function persist(v) {
    try { v ? localStorage.setItem(KEY, v) : localStorage.removeItem(KEY); } catch (e) { /* private mode */ }
  }
  function systemDark() {
    return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
  }
  function apply(theme) {
    if (theme === 'light' || theme === 'dark') root.setAttribute('data-theme', theme);
    else root.removeAttribute('data-theme');
    var isDark = theme === 'dark' || (!theme && systemDark());
    document.querySelectorAll('[data-theme-toggle]').forEach(function (btn) {
      btn.setAttribute('aria-pressed', String(isDark));
      var on = btn.querySelector('[data-icon="dark"]');
      var off = btn.querySelector('[data-icon="light"]');
      if (on) on.style.display = isDark ? '' : 'none';
      if (off) off.style.display = isDark ? 'none' : '';
    });
  }

  apply(stored());

  document.addEventListener('click', function (e) {
    var toggle = e.target.closest('[data-theme-toggle]');
    if (toggle) {
      var next = (root.getAttribute('data-theme') || (systemDark() ? 'dark' : 'light')) === 'dark' ? 'light' : 'dark';
      persist(next);
      apply(next);
      return;
    }

    var copy = e.target.closest('[data-copy]');
    if (copy) {
      var text = copy.getAttribute('data-copy');
      var done = copy.getAttribute('data-copied') || 'Copied';
      var label = copy.textContent;
      var flash = function () {
        copy.textContent = done;
        setTimeout(function () { copy.textContent = label; }, 1600);
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(flash, function () { /* denied */ });
      } else {
        var ta = document.createElement('textarea');
        ta.value = text;
        ta.setAttribute('readonly', '');
        ta.style.position = 'fixed';
        ta.style.opacity = '0';
        document.body.appendChild(ta);
        ta.select();
        try { document.execCommand('copy'); flash(); } catch (err) { /* no-op */ }
        document.body.removeChild(ta);
      }
    }
  });

  var header = document.querySelector('.site-header');
  if (header) {
    var onScroll = function () { header.classList.toggle('scrolled', window.scrollY > 8); };
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
  }
})();
