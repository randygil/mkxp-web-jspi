// Physical game controller support (Gamepad API) with a remapping screen.
//
// WEB PORT: like the keyboard and the touch pad, a controller drives the game through the
// scancode bridge (window.webSetKey -> web_set_scancode), so every action reaches
// Ruby's Input exactly as the keyboard key the game's prompts name (C, X, Z, D, A, S, Q, W).
// The engine's own SDL joystick path is not used: the single-threaded web build never
// pumps SDL events into keyStates.
//
// A binding is a token: 'b<i>' (button i pressed) or 'a<i>+' / 'a<i>-' (axis i pushed past
// the threshold). Each action holds a list of tokens. Maps are stored in localStorage per
// controller profile: 'standard' for every pad the browser maps to the W3C standard layout
// (Xbox / PlayStation / Switch Pro / most Bluetooth pads), or the pad's id otherwise.
//
// UI: a "Controller" button appears in #offlinebtns once a pad is seen; it opens the
// remapping screen. Holding Select + Start for 1.5 s opens it from the pad too. The screen
// is navigable with the pad itself (up/down, confirm = rebind, action = add, back = close).

(function () {
  var SC = { up: 82, down: 81, left: 80, right: 79,
             C: 6, X: 27, Z: 29, D: 7, A: 4, S: 22, Q: 20, W: 26 };

  var ACTIONS = [
    ['up', 'Up'], ['down', 'Down'], ['left', 'Left'], ['right', 'Right'],
    ['C', 'Confirm / talk (C)'], ['X', 'Back / run / menu (X)'],
    ['Z', 'Action (Z)'], ['D', 'Special / registered item (D)'],
    ['A', 'Page up (A)'], ['S', 'Page down (S)'], ['Q', 'Q'], ['W', 'W']
  ];

  // Standard layout: 0 bottom, 1 right, 2 left, 3 top face button, 4/5 bumpers,
  // 6/7 triggers, 8 select, 9 start, 10/11 stick clicks, 12-15 d-pad, 16 home.
  // Bottom = confirm, right = back (hold to run), Start = menu (X), like the handhelds.
  var DEFAULTS = {
    up: ['b12', 'a1-'], down: ['b13', 'a1+'], left: ['b14', 'a0-'], right: ['b15', 'a0+'],
    C: ['b0'], X: ['b1', 'b9'], Z: ['b2', 'b8'], D: ['b3'],
    A: ['b4'], S: ['b5'], Q: ['b6'], W: ['b7']
  };

  var AXIS_ON = 0.5;        // stick past this = pressed
  var CAPTURE_AXIS = 0.7;   // stricter while capturing, so a resting stick is not bound
  var STORE = 'gamepadMap:v1';

  function clone(o) { return JSON.parse(JSON.stringify(o)); }
  function profileOf(gp) { return gp.mapping === 'standard' ? 'standard' : gp.id; }

  var maps = {};
  try { maps = JSON.parse(localStorage.getItem(STORE) || '{}') || {}; } catch (e) { maps = {}; }
  function saveMaps() { try { localStorage.setItem(STORE, JSON.stringify(maps)); } catch (e) {} }
  function mapFor(profile) {
    var m = maps[profile];
    if (!m) return DEFAULTS;
    // Actions added after the map was saved fall back to their defaults.
    for (var k in DEFAULTS) if (!m[k]) m[k] = DEFAULTS[k].slice();
    return m;
  }

  function tokenOn(gp, t, axisOn) {
    var i = parseInt(t.slice(1), 10);
    if (t.charAt(0) === 'b') {
      var b = gp.buttons[i];
      return !!b && (b.pressed || b.value > 0.5);
    }
    var v = gp.axes[i];
    if (typeof v !== 'number') return false;
    return t.charAt(t.length - 1) === '+' ? v > axisOn : v < -axisOn;
  }

  function activeTokens(gp) {
    var out = [];
    for (var i = 0; i < gp.buttons.length; i++) if (tokenOn(gp, 'b' + i)) out.push('b' + i);
    for (var j = 0; j < gp.axes.length; j++) {
      if (tokenOn(gp, 'a' + j + '+', CAPTURE_AXIS)) out.push('a' + j + '+');
      if (tokenOn(gp, 'a' + j + '-', CAPTURE_AXIS)) out.push('a' + j + '-');
    }
    return out;
  }

  // Which actions are held on this pad right now.
  function actionsHeld(gp) {
    var m = mapFor(profileOf(gp)), held = {};
    for (var a in m) {
      for (var k = 0; k < m[a].length; k++) {
        if (tokenOn(gp, m[a][k], AXIS_ON)) { held[a] = true; break; }
      }
    }
    return held;
  }

  // Human names for tokens, by brand where the standard layout makes them known.
  function faceNames(gp) {
    var id = (gp && gp.id || '').toLowerCase();
    if (/xbox|045e|xinput/.test(id)) return ['A', 'B', 'X', 'Y'];
    if (/054c|playstation|dualshock|dualsense|wireless controller/.test(id)) return ['✕', '○', '□', '△'];
    if (/057e|nintendo|pro controller|joy-con/.test(id)) return ['B', 'A', 'Y', 'X'];
    return ['A', 'B', 'X', 'Y'];
  }
  function tokenName(t, gp) {
    var i = parseInt(t.slice(1), 10);
    var std = !gp || gp.mapping === 'standard';
    if (t.charAt(0) === 'b') {
      if (std) {
        var f = faceNames(gp);
        var n = [f[0], f[1], f[2], f[3], 'LB', 'RB', 'LT', 'RT', 'Select', 'Start', 'L3', 'R3',
                 'D-pad ↑', 'D-pad ↓', 'D-pad ←', 'D-pad →', 'Home'][i];
        if (n) return n;
      }
      return 'Button ' + i;
    }
    var plus = t.charAt(t.length - 1) === '+';
    if (std && i < 4) {
      var stick = i < 2 ? 'Left stick ' : 'Right stick ';
      return stick + (i % 2 === 0 ? (plus ? '→' : '←') : (plus ? '↓' : '↑'));
    }
    return 'Axis ' + i + (plus ? '+' : '−');
  }

  // --- Feeding the game ---------------------------------------------------------------
  var sent = {};   // scancode -> true while this module holds it down
  function sync(want) {
    var sc;
    for (sc in sent) {
      if (!want[sc] && window.webSetKey && window.webSetKey(+sc, false) === true) delete sent[sc];
    }
    for (sc in want) {
      if (!sent[sc] && window.webSetKey && window.webSetKey(+sc, true) === true) sent[sc] = true;
    }
  }
  function releaseAll() { sync({}); }

  function pads() {
    var list = [];
    try {
      var g = navigator.getGamepads ? navigator.getGamepads() : [];
      for (var i = 0; i < g.length; i++) if (g[i] && g[i].connected !== false) list.push(g[i]);
    } catch (e) {}
    return list;
  }

  var seen = {};          // pad index -> id, to announce each pad once
  var comboSince = 0;     // Select + Start held since (ms)
  var lastPad = null;     // most recently used pad (names in the remap screen)
  var ui = null;          // remap screen state while it is open

  function frame() {
    var list = pads(), want = {}, now = performance.now(), combo = false, any = false;
    for (var p = 0; p < list.length; p++) {
      var gp = list[p];
      if (seen[gp.index] !== gp.id) { seen[gp.index] = gp.id; announce(gp); }
      var held = actionsHeld(gp);
      for (var a in held) { any = true; want[SC[a]] = true; }
      if (activeTokens(gp).length) { any = true; lastPad = gp; }
      if (gp.mapping === 'standard' && tokenOn(gp, 'b8') && tokenOn(gp, 'b9')) combo = true;
      if (ui) uiFrame(gp, held);
    }
    if (any) document.documentElement.classList.add('gp-active');

    if (ui || document.hidden) releaseAll();
    else sync(want);

    if (combo && !ui) {
      if (!comboSince) comboSince = now;
      else if (now - comboSince > 1500) { comboSince = 0; openUi(); }
    } else if (!combo) comboSince = 0;

    requestAnimationFrame(frame);
  }

  // A touch means the player went back to the on-screen pad: show it again.
  document.addEventListener('touchstart', function () {
    document.documentElement.classList.remove('gp-active');
  }, { passive: true, capture: true });
  window.addEventListener('blur', releaseAll);
  document.addEventListener('visibilitychange', function () { if (document.hidden) releaseAll(); });

  window.addEventListener('gamepadconnected', function (e) { if (e.gamepad) announce(e.gamepad); });

  // --- Toast + button -----------------------------------------------------------------
  var announced = {};
  function announce(gp) {
    var b = document.getElementById('gpbtn');
    if (b) b.style.display = '';
    if (announced[gp.id]) return;
    announced[gp.id] = true;
    lastPad = lastPad || gp;
    var name = gp.id.replace(/\s*\(.*?\)\s*/g, ' ').trim() || 'Controller';
    toast('🎮 ' + name + ' connected' +
          (gp.mapping === 'standard' ? '' : ' (non-standard layout: check the mapping)') +
          '. Hold Select + Start or use the Controller button to remap.');
  }

  var toastTimer = 0;
  function toast(msg) {
    var t = document.getElementById('gptoast');
    if (!t) {
      t = document.createElement('div');
      t.id = 'gptoast';
      document.body.appendChild(t);
    }
    t.textContent = msg;
    t.style.display = 'block';
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { t.style.display = 'none'; }, 4500);
  }

  // --- Remap screen -------------------------------------------------------------------
  // ui = { profile, gp, rows: [elements], focus, capture: null | {action, add, base, since},
  //        prev: {action: held} for edge detection }
  function currentProfile() {
    var gp = lastPad || pads()[0];
    return { gp: gp || null, profile: gp ? profileOf(gp) : 'standard' };
  }

  function openUi() {
    if (ui) return;
    var cur = currentProfile();
    var box = document.createElement('div');
    box.id = 'gpcfg';
    box.innerHTML =
      '<div class="gp-panel" role="dialog" aria-label="Controller mapping">' +
      '<div class="gp-head"><b>Controller mapping</b><span class="gp-sub"></span></div>' +
      '<div class="gp-rows"></div>' +
      '<div class="gp-help">Click a row (or confirm on the pad) and press the new button. ' +
      '<b>+</b> adds a second button. Back closes.</div>' +
      '<div class="gp-foot"><button type="button" data-cmd="reset">Reset to defaults</button>' +
      '<button type="button" data-cmd="close">Close</button></div></div>';
    document.body.appendChild(box);
    // prev = every action "already held", so the buttons that opened the screen (Select +
    // Start = Z + X by default) act only after they are released.
    var prev = {};
    for (var k in DEFAULTS) prev[k] = true;
    ui = { box: box, gp: cur.gp, profile: cur.profile, focus: 0, capture: null, prev: prev, items: [] };
    box.querySelector('.gp-sub').textContent = cur.gp
      ? (cur.gp.id.replace(/\s*\(.*?\)\s*/g, ' ').trim() + (cur.profile === 'standard' ? ' · standard layout' : ' · custom layout'))
      : 'No controller detected yet: press any button on it.';
    box.addEventListener('click', onUiClick);
    box.addEventListener('touchstart', function (e) { e.stopPropagation(); }, { passive: true });
    window.addEventListener('keydown', onUiKey, true);
    renderUi();
  }

  function closeUi() {
    if (!ui) return;
    window.removeEventListener('keydown', onUiKey, true);
    ui.box.parentNode.removeChild(ui.box);
    ui = null;
  }

  function editableMap() {
    if (!maps[ui.profile]) maps[ui.profile] = clone(DEFAULTS);
    return mapFor(ui.profile);
  }

  function renderUi() {
    var m = mapFor(ui.profile), rows = ui.box.querySelector('.gp-rows'), html = '';
    for (var i = 0; i < ACTIONS.length; i++) {
      var a = ACTIONS[i][0], cap = ui.capture && ui.capture.action === a;
      var names = (m[a] || []).map(function (t) { return tokenName(t, ui.gp); }).join(', ') || '—';
      html += '<div class="gp-row" data-i="' + i + '">' +
              '<span class="gp-act">' + ACTIONS[i][1] + '</span>' +
              '<span class="gp-bind' + (cap ? ' cap' : '') + '">' +
              (cap ? 'Press a button… (Esc cancels)' : esc(names)) + '</span>' +
              '<button type="button" class="gp-add" data-add="' + i + '" title="Add another button">+</button></div>';
    }
    rows.innerHTML = html;
    ui.items = Array.prototype.slice.call(ui.box.querySelectorAll('.gp-row, .gp-foot button'));
    ui.items.forEach(function (el, k) { el.classList.toggle('focus', k === ui.focus); });
    var f = ui.items[ui.focus];
    if (f && f.scrollIntoView) f.scrollIntoView({ block: 'nearest' });
  }

  function esc(s) { return String(s).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); }

  function startCapture(i, add) {
    ui.focus = i;
    ui.capture = { action: ACTIONS[i][0], add: !!add, base: null, since: performance.now() };
    renderUi();
  }

  function activate(k, add) {
    var el = ui.items[k];
    if (!el) return;
    if (el.classList.contains('gp-row')) startCapture(+el.getAttribute('data-i'), add);
    else runCmd(el.getAttribute('data-cmd'));
  }

  function runCmd(cmd) {
    if (cmd === 'close') closeUi();
    else if (cmd === 'reset') { delete maps[ui.profile]; saveMaps(); ui.capture = null; renderUi(); }
  }

  function onUiClick(e) {
    var t = e.target;
    if (t.getAttribute('data-add') != null) { startCapture(+t.getAttribute('data-add'), true); return; }
    if (t.getAttribute('data-cmd')) { runCmd(t.getAttribute('data-cmd')); return; }
    while (t && t !== ui.box && !(t.classList && t.classList.contains('gp-row'))) t = t.parentNode;
    if (t && t !== ui.box) startCapture(+t.getAttribute('data-i'), false);
    else if (e.target === ui.box) closeUi();   // click on the dimmed backdrop
  }

  // While the screen is open the keyboard only drives it (the game gets nothing).
  function onUiKey(e) {
    e.stopImmediatePropagation();
    e.preventDefault();
    if (e.key === 'Escape') { if (ui.capture) { ui.capture = null; renderUi(); } else closeUi(); }
    else if (ui.capture) return;
    else if (e.key === 'ArrowDown') { ui.focus = Math.min(ui.items.length - 1, ui.focus + 1); renderUi(); }
    else if (e.key === 'ArrowUp') { ui.focus = Math.max(0, ui.focus - 1); renderUi(); }
    else if (e.key === 'Enter' || e.key === ' ') activate(ui.focus, false);
    else if (e.key === '+') activate(ui.focus, true);
  }

  function uiFrame(gp, held) {
    if (ui.capture) {
      // Bind the first input that was NOT already held when capture began (the button
      // used to start the capture is still down at that moment).
      var act = activeTokens(gp), c = ui.capture;
      if (!c.base) c.base = {};
      if (!c.base[gp.index]) { c.base[gp.index] = {}; act.forEach(function (t) { c.base[gp.index][t] = 1; }); return; }
      var base = c.base[gp.index], hit = null;
      for (var t in base) if (act.indexOf(t) < 0) delete base[t];
      for (var k = 0; k < act.length; k++) if (!base[act[k]]) { hit = act[k]; break; }
      if (hit) {
        if (profileOf(gp) !== ui.profile) { ui.profile = profileOf(gp); }
        ui.gp = gp;
        var m = editableMap(), list = c.add ? (m[c.action] || []).slice() : [];
        if (list.indexOf(hit) < 0) list.push(hit);
        // One button, one action: take it away from wherever else it was bound.
        for (var o in m) if (o !== c.action) m[o] = m[o].filter(function (x) { return x !== hit; });
        m[c.action] = list;
        saveMaps();
        ui.capture = null;
        ui.prev = {};
        for (var a in held) ui.prev[a] = true;          // the bound press must not also navigate
        ui.prev.C = ui.prev.X = ui.prev.Z = true;
        renderUi();
      } else if (performance.now() - c.since > 10000) { ui.capture = null; renderUi(); }
      return;
    }
    function edge(a) { return held[a] && !ui.prev[a]; }
    if (edge('down')) { ui.focus = Math.min(ui.items.length - 1, ui.focus + 1); renderUi(); }
    else if (edge('up')) { ui.focus = Math.max(0, ui.focus - 1); renderUi(); }
    else if (edge('C')) activate(ui.focus, false);
    else if (edge('Z')) activate(ui.focus, true);
    else if (edge('X') && !held.C) { ui.prev = held; closeUi(); return; }
    ui.prev = held;
  }

  window.openGamepadConfig = openUi;

  if (navigator.getGamepads) requestAnimationFrame(frame);
})();
