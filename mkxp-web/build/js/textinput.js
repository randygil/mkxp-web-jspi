// Text entry for games that type text (RGSS/mkxp-z `Input.text_input = true` + `Input.gets`,
// e.g. the Pokémon Essentials naming screen).
//
// While text input is on, printable characters are buffered and handed to the engine on the
// next Input.gets (web_text_gets in binding-mruby/mrb-ext/kernel.cpp):
//  - physical keyboards: captured from keydown (event.key is the typed character, so the
//    keyboard layout and accents are respected). The event still reaches SDL, so Enter /
//    Backspace / arrows keep working as game keys.
//  - touch devices: a hidden <input> is focused so the on-screen keyboard opens; its text
//    arrives through `input` events (virtual keyboards send keydown "Unidentified").
(function () {
  var on = false, buf = '', box = null;

  function ensureBox() {
    if (box) return box;
    box = document.createElement('input');
    box.type = 'text';
    box.setAttribute('autocomplete', 'off');
    box.setAttribute('autocorrect', 'off');
    box.setAttribute('autocapitalize', 'off');
    box.setAttribute('spellcheck', 'false');
    box.setAttribute('aria-hidden', 'true');
    // Off-screen but focusable (display:none / visibility:hidden can't take focus).
    box.style.cssText = 'position:fixed;left:0;bottom:0;width:1px;height:1px;opacity:0;' +
                        'border:0;padding:0;font-size:16px;z-index:-1;';
    box.addEventListener('input', function () {
      if (on && box.value) buf += box.value;
      box.value = '';
    });
    document.body.appendChild(box);
    return box;
  }

  var coarse = window.matchMedia && window.matchMedia('(pointer: coarse)').matches;

  window.webTextInput = function (enable) {
    on = !!enable;
    window.webTextInputActive = on;
    buf = '';
    if (!coarse) return;               // desktop: keydown capture is enough
    var b = ensureBox();
    if (on) { b.value = ''; b.focus(); } else { b.blur(); }
  };

  window.webTextGets = function () {
    var s = buf;
    buf = '';
    return s;
  };

  // Capture phase so we see the key before SDL's handler.
  window.addEventListener('keydown', function (e) {
    if (!on || e.ctrlKey || e.metaKey || e.altKey) return;
    if (e.key && e.key.length === 1) {
      buf += e.key;
      // Stop the browser from also inserting it into a focused <input> (double entry).
      if (document.activeElement === box) e.preventDefault();
    }
  }, true);

  // Tapping the game while typing on a phone re-opens the keyboard if it was dismissed.
  document.addEventListener('pointerdown', function () {
    if (on && coarse && box && document.activeElement !== box) box.focus();
  }, true);
})();
