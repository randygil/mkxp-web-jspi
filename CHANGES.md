# Changes from upstream mkxp-web

This fork (RGSS-Web / mkxp-web-jspi) modifies pulsejet/mkxp-web. Per GPL-2.0 §2(a),
the significant changes and the date they were made:

## 2026-09 — Pokemon Essentials v20/v21 (mkxp-z) games

- `extra/mruby-web.patch` (applied after `vm.c.patch`): hash index for the mruby symbol
  table (stock 2.1.2 degrades to a linear scan; ~15x faster frames with Essentials),
  `OP_ARYCAT` no longer aliases the splatted array (`f(*a, x)` mutated `a`), instance
  variables on Array/String subclasses.
- `extra/build_config.rb`, `CMakeLists.txt` — 64-bit `Integer` (`MRB_INT64`; 32-bit
  values >= 2**31 used to become Float), mruby method cache, `MKXP_RGSS_VERSION` build
  option (1 = XP, 2 = VX default; `src/config.cpp`), `MKXP_WEB_PROFILE` build
  (`--profiling-funcs`).
- `binding-mruby` — `Font#name=` implemented (was a no-op, so every game fell back to the
  bundled font), String/Array font names; `Bitmap.max_size`, `Bitmap#mega?`; natives
  `web_fetch_file`, `web_resolve_path`, `web_readdir`, `web_mkdir`, `web_text_input`,
  `web_text_gets`.
- `build/js` — fonts preloaded before boot, deleted saves removed from IndexedDB,
  `textinput.js` (typed text for `Input.gets`, on-screen keyboard on touch devices).
- `HTTPLite` — native `web_http` (`fetch` + `AbortController` timeout, awaited through JSPI,
  binary-safe bodies) behind real `HTTPLite.get` / `post` / `post_body` in the Essentials shim;
  `HTTPLite::JSON.stringify` now escapes strings properly.
- Save persistence (`build/index.html`, `js/drive.js`) — every file written under `/game`
  outside `Data/` is stored (not only closed `*.rxdata`), `rename` / `unlink` update IndexedDB,
  files in subdirectories are restored, and IndexedDB writes run in order (the save index's
  read-modify-write could drop entries on back-to-back saves).
- `tools/essentials/` — script packager, mkxp-z/Ruby 3 API shim and porting patches for
  Essentials games (see its README).
- Fixes: `extra/convert_audio.sh` wrote to a non-existent `CONV/` dir and deleted the
  originals; Dockerfile lacked `rsync`/`timidity`; `.gitattributes` keeps `*.sh` LF.

## 2026 — run script-heavy RGSS1 (XP) and RGSS2 (VX) games in the browser

**Event loop (the key change)**
- `src/graphics.cpp` — `FPSLimiter::delayTicks()` now calls `emscripten_sleep()` so a
  game's blocking RGSS render loops (`loop { Graphics.update }`) yield to the browser
  once per frame via ASYNCIFY/JSPI, unwinding the whole C+Ruby stack. This removes the
  need to rewrite a game's event loop into `main_update_loop` callbacks.
- `binding-mruby/binding-mruby.cpp` — removed `emscripten_set_main_loop()`; the game's
  own loop drives frames via the yield above.

**Toolchain**
- `CMakeLists.txt`, `extra/build_config.rb` — migrated to JSPI (`-s JSPI` / `ASYNCIFY=2`),
  wasm-native exceptions (`-fwasm-exceptions`) + wasm `setjmp`/`longjmp`
  (`-s SUPPORT_LONGJMP=wasm`); pinned emsdk 3.1.61; added `-flto` to the mruby build.

**mruby 2.1.2 compatibility (`deps/mruby/src/vm.c`, applied via `extra/vm.c.patch`)**
- Escaping-proc top-level env force-unshare in `mrb_top_run` — fixes "undefined method"
  from stored `Events.on* += proc{}` callbacks after later script loads / GC.
- `super` + `alias` `MRB_PROC_TARGET_CLASS` guard — fixes spurious "self has wrong type
  to call super" through deep alias chains.
- `super` garbage-mid guard — no-op instead of crashing when an alias-corrupted method id
  is not a valid symbol.
- Integer-division fixnum fix (original mkxp-web patch).

**Input / rendering**
- `src/input.cpp` — static keyboard bindings + `web_set_scancode` for browser keyboard input.
- `src/config.cpp`, `src/main.cpp` — request WebGL2 / GLES3; frame-skip and skip-storm fixes.
- `src/tilemap.cpp` — autotile perf: collapse the four 16×16 sub-pieces of "open field"
  autotile patterns (whose pieces sample a contiguous 32×32 atlas block, e.g. open
  water/grass) into a single 32×32 quad — pixel-identical but ¼ the vertices, so the tile
  VBO build and the animated tilemap vertex shader do ¼ the work on water/grass-heavy maps.
  Edge/corner patterns have non-contiguous pieces and keep the 4-piece path.

**RPG Maker VX (RGSS2) support** — see [docs/RGSS2-VX.md](docs/RGSS2-VX.md)
- `binding-mruby/binding-mruby.cpp` — bind the version-appropriate renderer from `rgssVer`:
  `rgssVer >= 2` selects the new `WindowVX` + `TilemapVX` bindings, otherwise the RGSS1
  `Window` + `Tilemap`. Both are compiled in.
- `binding-mruby/windowvx-binding.cpp`, `tilemapvx-binding.cpp` — new mruby bindings for the
  RGSS2 `Window` / `Tilemap` (backed by the existing `src/windowvx.cpp` / `src/tilemapvx.cpp`
  engine classes); `binding-util` exposes the `flags` / `bitmaps` symbols the VX tilemap uses.
- `binding-mruby/viewportelement-binding.h` — bind the `viewport=` setter on
  Sprite / Window / Plane (VX menu and battle scenes reassign a drawable's viewport at
  runtime; upstream exposed only the getter).
- `src/config.cpp` — VX build defaults: `rgssVersion = 2`, 544×416, `Data/Scripts.rvdata`.
- `extra/rgss.rb` — the `RPG::` data-class shim exposes the VX-shaped fields Marshalled from
  `.rvdata` (weapon/armor combat params + feature flags, skill/item `icon_index` + skill
  messages, enemy `maxmp`/`def`/`spi`/`hit`/drops/conditions, animation `animation1_name…`,
  state fields), alongside the XP-shaped fields.
- `src/filesystem.cpp` — resolve NFC/NFD Unicode filename forms (VX RTP / Japanese asset names).
- `extra/js/drive.js` — accept both `.rxdata` and `.rvdata` map files.
- `CMakeLists.txt` — build the two new VX bindings; raise the wasm stack to 8 MB (deep
  RGSS/mruby recursion under JSPI overflows the 64 KB default); add a `MKXP_WEB_DEBUG` build
  toggle (`ASSERTIONS`/`SAFE_HEAP`/`STACK_OVERFLOW_CHECK` + `-g2`). `binding-mruby.cpp` and
  `src/eventthread.cpp` also emit boot script-load traces and script-error / message-box text
  to stderr for diagnosing new ports.

**Audio (frame-independent BGM)**
- `src/emscripten.cpp/.hpp`, `binding-mruby/audio-binding.cpp` — added `Audio.web_bgm_play/
  stop/fade`, which hand BGM to a JS Web Audio player (`build/js/webbgm.js`). mkxp's OpenAL
  renders on a main-thread `ScriptProcessorNode`, so BGM stutters/freezes whenever the main
  thread blocks (e.g. a synchronous Marshal save, a long map load); Web Audio plays on the
  browser's own audio thread and keeps going through those stalls. Intro→loop points are
  pluggable via `window.BGM_LOOP_TABLE`. SE/BGS/ME stay on mkxp's OpenAL (short / unnoticeable).
- `extra/rgss.rb` — Audio shim: tolerant play (swallows non-OGG decode errors), arity guard
  (forwards only name/volume/pitch when a game passes an extra `position` arg), and the
  BGM→Web-Audio routing with a native-OpenAL fallback when the `web_bgm_*` binding is absent.

**Browser harness & tooling**
- `build/index.html`, `extra/shell.html`, `build/js/*`, `build/sw.js` — unthrottled Web
  Worker timers, keyboard + on-screen touch input (D-pad/buttons dispatch real
  `KeyboardEvent.code`; canvas taps/clicks drive the engine pointer via `web_set_mouse` for
  clickable menus / tap-to-move), fullscreen toggle, and dropping the WebGL context on
  unload so a reload reclaims GPU memory promptly. Physical-keyboard input maps LETTER keys
  by the character produced (`event.key`) rather than physical position (`event.code`), so a
  binding to "A" works on AZERTY/QWERTZ/Dvorak (where the A-labeled key is not at the QWERTY-A
  position); non-letters keep the `event.code` map.
- `build/js/drive.js` — resilient on-demand asset loader: bounded retry on transient
  fetch failures then a graceful give-up (`callback(null)`) so a missing/failed asset can't
  hang the game; save-persist re-entrancy guard; cloud-restore-first (NAS) save loading.
- `build/sw.js`, `build/index.html` — Service Worker offline cache split into a versioned
  shell cache + a stable asset cache, plus an optional "download the whole game" button
  (bulk-precache for full offline play, resumable + delta updates) and a PWA install button
  (`beforeinstallprompt`); `manifest.webmanifest` + icons for Add-to-Home-Screen.
- `extra/rgss.rb` — generic mruby/RGSS compatibility shims (Win32API stub, Thread/Mutex
  no-ops, ENV/Dir stubs, streaming Zlib, ObjectSpace stubs, File byte helpers).
- `deploy/` — containerized static serving (Caddy: Brotli, correct wasm MIME, caching).
- `scripts_tool.rb`, `regen-mapping.sh`, `gen-bitmap-map.rb`, `gen-preload.rb`,
  `import-game.sh` — the "bring your own game" asset pipeline.
