// Virtual on-screen touch controls (mobile D-pad + action buttons).
//
// WEB PORT: the single-threaded web build has ONE input path -- a window
// 'keydown'/'keyup' listener (in index.html) that reads `event.code`, maps it to an
// SDL scancode and pushes it straight into the engine via web_set_scancode(). The old
// version of this file dispatched legacy `keyCode`-only events to the canvas, which
// carry no `event.code`, so they never reached that bridge and the touch UI did
// nothing. We now emit real KeyboardEvents carrying `code` on `window`, i.e. exactly
// what a physical key press produces.
//
// index.html keeps calling bindKey(elementId, keyCode) and is_touch_device(); both
// are preserved here so no inline-script changes are needed.

(function () {
  // Legacy keyCode (what index.html passes) -> KeyboardEvent.code (what the bridge reads)
  var KEYCODE_TO_CODE = {
    37: 'ArrowLeft', 38: 'ArrowUp', 39: 'ArrowRight', 40: 'ArrowDown',
    13: 'Enter', 32: 'Space', 27: 'Escape', 16: 'ShiftLeft', 116: 'F5',
    65: 'KeyA', 66: 'KeyB', 67: 'KeyC', 68: 'KeyD', 81: 'KeyQ', 83: 'KeyS', 87: 'KeyW', 88: 'KeyX', 89: 'KeyY', 90: 'KeyZ'
  };

  var BIND = {};          // elementId -> KeyboardEvent.code
  var held = {};          // touch.identifier -> elementId currently pressed
  var handlersReady = false;
  var synthesizing = false;   // true while WE dispatch a key (so it isn't read as real keyboard use)

  function fireKey(code, down) {
    if (!code) return;
    synthesizing = true;
    window.dispatchEvent(new KeyboardEvent(down ? 'keydown' : 'keyup', {
      code: code, key: code, bubbles: true, cancelable: true
    }));
    synthesizing = false;
  }

  // --- Optional virtual pad (opt-in) -------------------------------------------
  // The on-screen pad (D-pad + action buttons + menu button) is HIDDEN by default.
  // On touch devices a small toggle button (#padtoggle, top-left) is shown; tapping it
  // shows/hides the pad. The choice is remembered across sessions (localStorage). Desktop
  // / keyboard players never see the toggle or the pad. Game-area taps still drive the
  // engine pointer (menus, dialogue, tap-to-move) whether or not the pad is shown.
  var controlsVisible = null;
  function setControlsVisible(v) {
    v = !!v;
    if (controlsVisible === v) return;
    controlsVisible = v;
    ['dpad', 'apad', 'menubtn'].forEach(function (id) {
      var e = document.getElementById(id);
      if (e) e.style.display = v ? 'block' : 'none';
    });
    var tg = document.getElementById('padtoggle');
    if (tg) tg.classList.toggle('pad-on', v);
    try { localStorage.setItem('padVisible', v ? '1' : '0'); } catch (e) {}
  }

  function setActive(elementId, on) {
    var el = elementId && document.getElementById(elementId);
    if (el) el.classList.toggle('dpad-active', !!on);
  }

  // Which bound control (if any) is under a point. Walks up so a touch landing on a
  // child/label still resolves to the button.
  function controlAt(x, y) {
    var el = document.elementFromPoint(x, y);
    while (el && !BIND[el.id]) el = el.parentElement;
    return el ? el.id : null;
  }

  // Press/hold a control for a given touch id; releasing whatever that touch held before.
  function press(elementId, tid) {
    if (held[tid] === elementId) return;
    if (held[tid]) { fireKey(BIND[held[tid]], false); setActive(held[tid], false); }
    if (elementId) {
      held[tid] = elementId;
      fireKey(BIND[elementId], true);
      setActive(elementId, true);
    } else {
      delete held[tid];
    }
  }

  function release(tid) {
    if (held[tid]) { fireKey(BIND[held[tid]], false); setActive(held[tid], false); }
    delete held[tid];
  }

  // --- Game-area touches -> engine mouse (clickable menus; later tap-to-move).
  // Dispatching a MouseEvent on the canvas is what actually reaches Ruby's
  // Input.mouse_x/y + Input.press?(MOUSELEFT) on this build (verified). One pointer.
  var mouseTid = null;
  var mouseDownBtn = false;   // real desktop mouse button held
  // Feed the engine pointer via the web_set_mouse export. Unlike a dispatched
  // MouseEvent (which only reaches Ruby in the top-level map loop), this writes
  // EventThread::mouseState directly, so Input.mouse_x/y + press?(MOUSELEFT) update in
  // nested menu loops too. Map client(CSS) px -> canvas buffer px (canvas.width/height);
  // mkxp then scales the buffer coords down to the game screen.
  function fireMouse(type, cx, cy, buttons) {
    var c = document.querySelector('canvas');
    if (!c || !(window.Module && Module.ccall)) return;
    var r = c.getBoundingClientRect();
    if (!r.width || !r.height) return;
    var bx = Math.round(c.width  * (cx - r.left) / r.width);
    var by = Math.round(c.height * (cy - r.top)  / r.height);
    try { Module.ccall('web_set_mouse', null, ['number', 'number', 'number'], [bx, by, buttons ? 1 : 0]); } catch (e) {}
  }

  // Global cancel gesture: a right-click (desktop) or a two-finger tap (mobile) acts like
  // the B/Escape key everywhere in the game -- including screens with no on-screen Cancel
  // button (trainer card, summary, ...). Sent through the SAME keyboard bridge the physical
  // Escape key uses (event.code 'Escape' -> SDL scancode -> web_set_scancode), so it reaches
  // Ruby's Input.trigger?(Input::B) in every loop. A brief hold guarantees a frame samples it.
  function fireCancel() {
    fireKey('Escape', true);
    setTimeout(function () { fireKey('Escape', false); }, 140);
  }

  // A touch on an overlay UI control (fullscreen button, save/download/install buttons, pad
  // toggle, menu button) must NOT be hijacked as a game-area pointer: doing so preventDefault'd
  // the button's synthetic click (so it never fired) AND sent a stray tap into the game. Detect
  // those and let the tap flow to the DOM so the control's own handler runs.
  function isUiElement(x, y) {
    var el = document.elementFromPoint(x, y);
    while (el && el !== document.body && el !== document.documentElement) {
      var tag = el.tagName;
      if (tag === 'BUTTON' || tag === 'A' || tag === 'INPUT' || tag === 'SELECT' || tag === 'TEXTAREA') return true;
      if (el.id === 'fullscreen' || el.id === 'padtoggle' || el.id === 'menubtn') return true;
      if (el.classList && el.classList.contains('vpad')) return true;   // gamepad body / gaps
      el = el.parentElement;
    }
    return false;
  }

  function onStart(e) {
    // Two-finger tap on the game area = cancel (B). Ignore when a control is under a finger
    // (the D-pad + A-button combo is also two touches, and must NOT cancel).
    if (e.touches && e.touches.length === 2) {
      var onCtl = false;
      for (var j = 0; j < e.touches.length; j++) {
        if (controlAt(e.touches[j].clientX, e.touches[j].clientY)) { onCtl = true; break; }
      }
      if (!onCtl) {
        e.preventDefault();
        if (mouseTid !== null) { fireMouse('mouseup', e.touches[0].clientX, e.touches[0].clientY, 0); mouseTid = null; }
        fireCancel();
        return;
      }
    }
    for (var i = 0; i < e.changedTouches.length; i++) {
      var t = e.changedTouches[i];
      var id = controlAt(t.clientX, t.clientY);
      if (id) {
        e.preventDefault();
        press(id, t.identifier);
      } else if (mouseTid === null && !isUiElement(t.clientX, t.clientY)) {  // game area -> pointer
        mouseTid = t.identifier;
        e.preventDefault();
        fireMouse('mousemove', t.clientX, t.clientY, 1);
        fireMouse('mousedown', t.clientX, t.clientY, 1);
      }
    }
  }

  function onMove(e) {
    var acted = false;
    for (var i = 0; i < e.changedTouches.length; i++) {
      var t = e.changedTouches[i];
      if (t.identifier in held) {
        acted = true;
        press(controlAt(t.clientX, t.clientY), t.identifier);   // null -> release (slid off)
      } else if (t.identifier === mouseTid) {
        acted = true;
        fireMouse('mousemove', t.clientX, t.clientY, 1);
      }
    }
    if (acted) e.preventDefault();
  }

  function onEnd(e) {
    for (var i = 0; i < e.changedTouches.length; i++) {
      var t = e.changedTouches[i];
      if (t.identifier in held) {
        e.preventDefault();
        release(t.identifier);
      } else if (t.identifier === mouseTid) {
        e.preventDefault();
        fireMouse('mouseup', t.clientX, t.clientY, 0);
        mouseTid = null;
      }
    }
  }

  function ensureHandlers() {
    if (handlersReady) return;
    handlersReady = true;
    // Document-level so a single set of listeners covers every bound control and
    // handles multi-touch (walk + press A) and sliding across the D-pad. Touches that
    // are NOT on a control are left untouched (no preventDefault), so the game canvas
    // still receives them.
    document.addEventListener('touchstart', onStart, { passive: false });
    document.addEventListener('touchmove', onMove, { passive: false });
    document.addEventListener('touchend', onEnd, { passive: false });
    document.addEventListener('touchcancel', onEnd, { passive: false });
    // Real mouse on the game canvas -> engine pointer, so menus are clickable with a
    // mouse (desktop) via the same web_set_mouse path that touch uses. The D-pad /
    // action buttons stay touch-only (desktop players use the keyboard for those).
    var cv = document.querySelector('canvas');
    if (cv) {
      cv.addEventListener('mousedown', function (e) { if (e.button !== 0) return; mouseDownBtn = true; fireMouse('mousedown', e.clientX, e.clientY, 1); });
      window.addEventListener('mousemove', function (e) { if (mouseDownBtn) fireMouse('mousemove', e.clientX, e.clientY, 1); });
      window.addEventListener('mouseup', function (e) { if (mouseDownBtn && e.button === 0) { mouseDownBtn = false; fireMouse('mouseup', e.clientX, e.clientY, 0); } });
      // Right-click anywhere on the game = cancel (B). Suppress the browser context menu.
      cv.addEventListener('contextmenu', function (e) { e.preventDefault(); fireCancel(); });
    }
    wirePadToggle();
  }

  // The opt-in toggle: shown only on touch devices, flips the pad on/off. Its own
  // touchstart calls stopPropagation() so the document-level onStart never treats the tap
  // as a game-area pointer; preventDefault suppresses the emulated click. A short debounce
  // guards against a touch + synthesized click firing the toggle twice.
  var lastToggle = 0;
  function wirePadToggle() {
    var tg = document.getElementById('padtoggle');
    if (!tg) return;
    if (window.is_touch_device && is_touch_device()) tg.style.display = 'block';
    function toggle(e) {
      if (e) { e.preventDefault(); e.stopPropagation(); }
      var now = (window.performance && performance.now) ? performance.now() : (+new Date());
      if (now - lastToggle < 350) return;
      lastToggle = now;
      setControlsVisible(!controlsVisible);
    }
    tg.addEventListener('touchstart', toggle, { passive: false });
    tg.addEventListener('click', toggle);
    // Restore the saved preference (default: hidden). Only honoured on touch devices;
    // desktop/keyboard always stays hidden (no toggle shown).
    var pref = false;
    try { pref = localStorage.getItem('padVisible') === '1'; } catch (e) {}
    setControlsVisible((window.is_touch_device && is_touch_device()) ? pref : false);
  }

  // index.html contract: bindKey('d-up', 38) etc.
  window.bindKey = function (elementId, keyCode) {
    var code = KEYCODE_TO_CODE[keyCode];
    if (code) BIND[elementId] = code;
    ensureHandlers();
  };

  // index.html contract. "Touch device" = the PRIMARY pointer is a finger (phones,
  // tablets). maxTouchPoints alone is also true on touch-screen laptops / some desktop
  // Chrome builds, which showed the pad to mouse+keyboard players. Matches the CSS
  // `@media (pointer: coarse)` rule that actually displays the pad.
  window.is_touch_device = function () {
    if (window.matchMedia) return window.matchMedia('(pointer: coarse)').matches;
    return (navigator.maxTouchPoints || 0) > 0 || ('ontouchstart' in window);
  };

  // Fit the canvas: fill height in landscape, width in portrait.
  var resize = function () {
    var el = document.getElementById('canvas');
    if (!el) return;
    if (window.innerHeight > window.innerWidth) {
      el.style.height = 'unset';
      el.style.width = '100%';
    } else {
      el.style.width = 'unset';
      el.style.height = '100%';
    }
  };
  window.resize = resize;
  window.addEventListener('resize', resize);
  window.addEventListener('load', resize);
})();
