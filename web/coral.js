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

  /*
   * The living colony — a slowly rotating coral whose three boughs are the three
   * providers and whose tips are the models Coral can actually cast. It is the
   * cross-provider claim made visual: one skeleton, three species, and any tip can
   * take any role.
   *
   * The tips are the app's REAL catalog (AIProvider.models / Constants). If the
   * catalog changes, change it here too — a landing page that invents a model is
   * worse than one with no picture.
   *
   * Colours come from the CSS custom properties, so the stylesheet stays the single
   * source of truth and the drawing follows the theme.
   */
  (function () {
    var canvas = document.getElementById('colony');
    if (!canvas || !canvas.getContext) return;
    var ctx = canvas.getContext('2d');
    var reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    var DPR = Math.min(2, window.devicePixelRatio || 1);
    var W = 0, H = 0;

    // [x, y, z, provider, isTip, label] — root at the bottom, growing into 3 boughs.
    var N = [
      [ 0.00, -1.15,  0.00, 'coral',  0],
      [ 0.00, -0.50,  0.00, 'coral',  0],
      // Claude bough (left) — the deepest catalog, so the widest bough.
      [-0.32, -0.14,  0.12, 'claude', 0],
      [-0.55,  0.18,  0.28, 'claude', 0],
      [-0.42,  0.10, -0.05, 'claude', 0],
      [-0.84,  0.52,  0.34, 'claude', 1, 'Opus 4.8'],
      [-0.56,  0.68,  0.10, 'claude', 1, 'Sonnet 5'],
      [-0.92,  0.28,  0.55, 'claude', 1, 'Haiku 4.5'],
      [-0.60,  0.20, -0.32, 'claude', 1, 'Fable 5'],
      // Codex bough (right / front).
      [ 0.36, -0.10, -0.10, 'codex',  0],
      [ 0.62,  0.26, -0.18, 'codex',  0],
      [ 1.02,  0.46, -0.34, 'codex',  1, 'GPT-5'],
      [ 0.74,  0.88,  0.10, 'codex',  1, 'GPT-5 mini'],
      // Gemini bough (back).
      [-0.05, -0.04, -0.38, 'gemini', 0],
      [ 0.08,  0.32, -0.62, 'gemini', 0],
      [ 0.04,  0.78, -0.96, 'gemini', 1, 'Gemini 2.5 Pro'],
      [-0.38,  0.50, -0.84, 'gemini', 1, '2.5 Flash']
    ];
    // [parent, child, baseWidth]
    var E = [
      [0, 1, 4.4],
      [1, 2, 2.9], [2, 3, 2.0], [2, 4, 1.8], [3, 5, 1.2], [3, 6, 1.2], [4, 7, 1.2], [4, 8, 1.2],
      [1, 9, 2.9], [9, 10, 2.0], [10, 11, 1.2], [10, 12, 1.2],
      [1, 13, 2.9], [13, 14, 2.0], [14, 15, 1.2], [14, 16, 1.2]
    ];

    var COL = {};
    function readPalette() {
      var s = getComputedStyle(root);
      [['coral', '--coral'], ['claude', '--p-claude'], ['codex', '--p-codex'], ['gemini', '--p-gemini']]
        .forEach(function (pair) {
          var hex = s.getPropertyValue(pair[1]).trim().replace('#', '');
          if (hex.length === 3) hex = hex[0] + hex[0] + hex[1] + hex[1] + hex[2] + hex[2];
          var v = parseInt(hex, 16);
          COL[pair[0]] = isNaN(v) ? [255, 107, 84]
            : [(v >> 16) & 255, (v >> 8) & 255, v & 255];
        });
      // On a light ground the depth fade has to start higher or far branches vanish.
      COL.floor = (root.getAttribute('data-theme') || (systemDark() ? 'dark' : 'light')) === 'dark' ? 0.28 : 0.42;
    }
    function rgba(name, a) {
      var c = COL[name] || COL.coral;
      return 'rgba(' + c[0] + ',' + c[1] + ',' + c[2] + ',' + a + ')';
    }

    function resize() {
      var r = canvas.getBoundingClientRect();
      W = r.width; H = r.height;
      canvas.width = Math.max(1, Math.round(W * DPR));
      canvas.height = Math.max(1, Math.round(H * DPR));
      ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
    }

    var ang = 0.2, tilt = 0.30;

    /// Rotate + tilt + perspective, in unit space (scale and offset come later).
    function raw(p) {
      var cy = Math.cos(ang), sy = Math.sin(ang);
      var xr = p[0] * cy - p[2] * sy, zr = p[0] * sy + p[2] * cy, yr = p[1];
      var cx = Math.cos(tilt), sx = Math.sin(tilt);
      var yr2 = yr * cx - zr * sx, zr2 = yr * sx + zr * cx;
      var persp = 1 / (2.3 - zr2 * 0.7);
      return { u: xr * persp, v: -yr2 * persp, z: zr2, s: persp };
    }

    /// Project every node, then AUTO-FIT the result to the canvas. The colony spins,
    /// so its silhouette changes every frame — a fixed scale either clips the root at
    /// some angles or wastes half the box at others. Fitting the actual bounding box
    /// keeps it centred and whole at every rotation, whatever the node table says.
    /// The scale is smoothed so the tree doesn't visibly breathe as it turns.
    var fitScale = 0, fitCX = 0, fitCY = 0;
    function projectAll() {
      var pad = 0.13;                       // room for the outward-pushed model labels
      var raws = N.map(raw);
      var minU = Infinity, maxU = -Infinity, minV = Infinity, maxV = -Infinity;
      raws.forEach(function (r) {
        if (r.u < minU) minU = r.u; if (r.u > maxU) maxU = r.u;
        if (r.v < minV) minV = r.v; if (r.v > maxV) maxV = r.v;
      });
      var spanU = Math.max(0.001, maxU - minU), spanV = Math.max(0.001, maxV - minV);
      var target = Math.min(W * (1 - pad * 2) / spanU, H * (1 - pad * 2) / spanV);
      fitScale = fitScale ? fitScale + (target - fitScale) * 0.08 : target;
      fitCX = (minU + maxU) / 2;
      fitCY = (minV + maxV) / 2;
      return raws.map(function (r) {
        return {
          x: W / 2 + (r.u - fitCX) * fitScale,
          y: H / 2 + (r.v - fitCY) * fitScale,
          z: r.z, s: r.s, R: fitScale * 0.5
        };
      });
    }

    function frame() {
      if (!W || !H) return;
      ctx.clearRect(0, 0, W, H);
      var P = projectAll();

      // Coral glow at the crown — the orchestrator's seat.
      var cr = P[1], gr = Math.min(W, H) * 0.26;
      var g = ctx.createRadialGradient(cr.x, cr.y, 0, cr.x, cr.y, gr);
      g.addColorStop(0, rgba('coral', 0.22));
      g.addColorStop(1, rgba('coral', 0));
      ctx.fillStyle = g;
      ctx.beginPath(); ctx.arc(cr.x, cr.y, gr, 0, 6.283); ctx.fill();

      ctx.lineCap = 'round';
      ctx.lineJoin = 'round';
      var floor = COL.floor;

      // Branches, painter's order (far first) so the depth reads.
      E.slice()
        .sort(function (u, v) { return (P[u[0]].z + P[u[1]].z) - (P[v[0]].z + P[v[1]].z); })
        .forEach(function (e) {
          var a = P[e[0]], b = P[e[1]];
          var depth = (((a.z + b.z) / 2) + 1) / 2;
          ctx.strokeStyle = rgba(N[e[1]][3], floor + (0.95 - floor) * depth);
          ctx.lineWidth = e[2] * ((a.s + b.s) / 2) * (a.R / 190) * 0.95;
          ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y); ctx.stroke();
        });

      // Polyps. Model tips get a halo so the catalog reads as the living edge.
      N.map(function (_, i) { return i; })
        .sort(function (i, j) { return P[i].z - P[j].z; })
        .forEach(function (i) {
          var n = N[i], pr = P[i], depth = (pr.z + 1) / 2;
          var al = floor + (0.95 - floor) * depth;
          var rad = (n[4] ? 3.0 : 1.7) * pr.s * (pr.R / 190);
          if (n[4]) {
            ctx.beginPath(); ctx.arc(pr.x, pr.y, rad + 4 * pr.s, 0, 6.283);
            ctx.fillStyle = rgba(n[3], al * 0.18); ctx.fill();
          }
          ctx.beginPath(); ctx.arc(pr.x, pr.y, rad, 0, 6.283);
          ctx.fillStyle = rgba(n[3], al); ctx.fill();
        });

      // Model names, pushed outward from the crown so they never cross a branch.
      ctx.font = '600 11.5px ui-monospace, SFMono-Regular, "SF Mono", Menlo, monospace';
      ctx.textBaseline = 'middle';
      var hx = P[1].x, hy = P[1].y, placed = [];
      N.map(function (n, i) { return i; })
        .filter(function (i) { return N[i][4] && N[i][5]; })
        .sort(function (i, j) { return P[j].z - P[i].z; })   // nearest label wins the space
        .forEach(function (i) {
          var n = N[i], pr = P[i], depth = (pr.z + 1) / 2;
          var dx = pr.x - hx, dy = pr.y - hy, L = Math.hypot(dx, dy) || 1;
          dx /= L; dy /= L;
          var right = dx >= 0;
          var tx = pr.x + dx * 8 + (right ? 7 : -7), ty = pr.y + dy * 8;
          var w = ctx.measureText(n[5]).width;
          var box = { l: right ? tx : tx - w, r: right ? tx + w : tx, t: ty - 8, b: ty + 8 };
          var hit = placed.some(function (q) {
            return !(box.r < q.l - 4 || box.l > q.r + 4 || box.b < q.t - 2 || box.t > q.b + 2);
          });
          if (hit) return;
          placed.push(box);
          ctx.textAlign = right ? 'left' : 'right';
          ctx.fillStyle = rgba(n[3], Math.min(1, floor + (0.95 - floor) * depth + 0.15));
          ctx.fillText(n[5], tx, ty);
        });
    }

    var raf = 0, running = false;
    function tick() {
      if (!document.hidden) { ang += 0.0045; frame(); }
      raf = requestAnimationFrame(tick);
    }
    function stop() { if (running) { running = false; cancelAnimationFrame(raf); } }
    function start() { if (!running && !reduce) { running = true; raf = requestAnimationFrame(tick); } }

    readPalette();
    resize();
    frame();

    window.addEventListener('resize', function () { resize(); if (!running) frame(); });
    // Follow the theme: the header toggle stamps data-theme, the OS fires the query.
    new MutationObserver(function () { readPalette(); frame(); })
      .observe(root, { attributes: true, attributeFilter: ['data-theme'] });
    if (window.matchMedia) {
      var mq = window.matchMedia('(prefers-color-scheme: dark)');
      var onScheme = function () { readPalette(); frame(); };
      if (mq.addEventListener) mq.addEventListener('change', onScheme);
      else if (mq.addListener) mq.addListener(onScheme);
    }

    // Only animate while it's on screen — an off-screen rAF loop is a battery leak
    // on a page whose whole pitch is that the app costs nothing at rest.
    if (!reduce && 'IntersectionObserver' in window) {
      new IntersectionObserver(function (entries) {
        entries.forEach(function (e) { e.isIntersecting ? start() : stop(); });
      }, { threshold: 0.05 }).observe(canvas);
    } else if (!reduce) {
      start();
    }
  })();
})();
