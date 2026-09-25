// Frame-independent BGM player (Web Audio).
//
// mkxp plays audio through Emscripten's OpenAL, which drives a *main-thread*
// ScriptProcessorNode. So BGM stutters/freezes whenever the main thread blocks (e.g. a
// synchronous Marshal save, a long map load). Web Audio (AudioBufferSourceNode + GainNode)
// renders on the browser's own audio thread, so once a track is playing it keeps going
// through main-thread stalls. The engine calls these hooks from Ruby via
// Audio.web_bgm_play / web_bgm_stop / web_bgm_fade (see src/emscripten.cpp,
// binding-mruby/audio-binding.cpp, and the Audio shim in extra/rgss.rb). SE/BGS/ME stay on
// mkxp's OpenAL (short / less noticeable).
//
// LOOP POINTS: RGSS loops the whole track by default. If your game has intro->loop tracks,
// define window.BGM_LOOP_TABLE before this script runs (e.g. in a small script your game
// ships), keyed by the lowercased play path, value [startMs, endMs]:
//     window.BGM_LOOP_TABLE = { "audio/bgm/field": [4000, 45999], ... };
// Tracks not listed loop over their full duration.
(function () {
  var LOOP_TABLE = window.BGM_LOOP_TABLE || {};

  var ctx = null;
  function audioCtx() {
    if (ctx) return ctx;
    // Reuse mkxp's OpenAL AudioContext when present (already resumed on a user gesture),
    // else create our own.
    try {
      if (window.AL && window.AL.currentCtx && window.AL.currentCtx.audioCtx) {
        ctx = window.AL.currentCtx.audioCtx;
        return ctx;
      }
    } catch (e) {}
    try { ctx = new (window.AudioContext || window.webkitAudioContext)(); } catch (e) { ctx = null; }
    return ctx;
  }
  function resumeCtx() {
    var c = audioCtx();
    if (c && c.state === 'suspended') { try { c.resume(); } catch (e) {} }
  }
  ['keydown', 'pointerdown', 'touchstart', 'mousedown'].forEach(function (ev) {
    window.addEventListener(ev, resumeCtx, { passive: true });
  });

  var bufCache = {};       // url -> decoded AudioBuffer
  var cacheOrder = [];     // LRU of urls
  var CACHE_MAX = 4;       // ~4 decoded tracks at once (bounded; each a few tens of MB)
  var curUrl = null, curSource = null, curGain = null;
  var gen = 0;             // bumped to cancel stale async decodes / stops

  function resolveUrl(path) {
    try {
      var key = window.getMappingKey ? window.getMappingKey(path)
                                     : path.toLowerCase().replace(/\.[^/.]+$/, '');
      var val = window.mapping ? window.mapping[key] : null;
      if (!val || val.slice(-2) === 'h=') return null;
      return 'gameasync/' + val;
    } catch (e) { return null; }
  }

  function stopCurrent() {
    if (curSource) {
      try { curSource.onended = null; curSource.stop(); } catch (e) {}
      try { curSource.disconnect(); } catch (e) {}
    }
    if (curGain) { try { curGain.disconnect(); } catch (e) {} }
    curSource = null; curGain = null; curUrl = null;
  }

  function cachePut(url, buf) {
    bufCache[url] = buf;
    cacheOrder.push(url);
    while (cacheOrder.length > CACHE_MAX) {
      var old = cacheOrder.shift();
      if (old !== curUrl && old !== url) delete bufCache[old];
    }
  }

  function startBuffer(url, buffer, volume, pitch, loop) {
    var c = audioCtx(); if (!c) return;
    stopCurrent();
    var src = c.createBufferSource();
    src.buffer = buffer;
    src.playbackRate.value = ((pitch > 0 ? pitch : 100) / 100.0);
    src.loop = true;
    if (loop && loop.length === 2 && loop[1] > loop[0]) {
      src.loopStart = loop[0] / 1000.0;
      src.loopEnd = Math.min(loop[1] / 1000.0, buffer.duration);
    }
    var gain = c.createGain();
    gain.gain.value = Math.max(0, Math.min(1, volume / 100.0));
    src.connect(gain); gain.connect(c.destination);
    try { src.start(0); } catch (e) {}
    curSource = src; curGain = gain; curUrl = url;
  }

  window.webBgmPlay = function (path, volume, pitch) {
    volume = (volume == null) ? 100 : volume;
    pitch = (pitch == null) ? 100 : pitch;
    var url = resolveUrl(path);
    if (!url) return;
    resumeCtx();
    // Same track already playing -> just update volume, don't restart (avoids hiccups
    // when the game re-issues bgm_play for the current track, e.g. re-entering a map).
    if (url === curUrl && curGain) {
      try { curGain.gain.value = Math.max(0, Math.min(1, volume / 100.0)); } catch (e) {}
      return;
    }
    var loop = LOOP_TABLE[String(path).toLowerCase()] || null;
    var myGen = ++gen;
    if (bufCache[url]) { startBuffer(url, bufCache[url], volume, pitch, loop); return; }
    (window.fetchGameAsset ? window.fetchGameAsset(url)
                           : fetch(url).then(function (r) { return r.arrayBuffer(); })).then(function (ab) {
      var c = audioCtx(); if (!c) return;
      var done = function (buffer) {
        if (myGen !== gen || !buffer) return;      // a newer play/stop superseded this
        cachePut(url, buffer);
        startBuffer(url, buffer, volume, pitch, loop);
      };
      try {
        var p = c.decodeAudioData(ab, done, function () {});
        if (p && p.then) p.then(done, function () {});
      } catch (e) {}
    }).catch(function () {});
  };

  window.webBgmStop = function () { gen++; stopCurrent(); };

  window.webBgmFade = function (ms) {
    gen++;
    var c = audioCtx();
    if (curGain && c) {
      var now = c.currentTime, dur = Math.max(0, (ms || 0) / 1000.0);
      try {
        curGain.gain.cancelScheduledValues(now);
        curGain.gain.setValueAtTime(curGain.gain.value, now);
        curGain.gain.linearRampToValueAtTime(0, now + dur);
      } catch (e) {}
      var src = curSource;
      curSource = null; curGain = null; curUrl = null;
      setTimeout(function () {
        if (src) { try { src.stop(); } catch (e) {} try { src.disconnect(); } catch (e) {} }
      }, (ms || 0) + 60);
    } else {
      stopCurrent();
    }
  };
})();
