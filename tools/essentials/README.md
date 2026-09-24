# Pokemon Essentials (v20/v21) on mkxp-web

Tooling to run Pokemon Essentials games that target **mkxp-z** (Ruby 3.x) on this
**mruby 2.1.2** engine. Tested end to end with *Pokemon Anil 4.x* (Essentials v21.1, 372 plugin
scripts): title, intro, naming, overworld, trainer battles, multi-slot save/load, at 60 FPS.

No game files are included; you need your own copy of the game.

## Build

1. Build the engine for **RPG Maker XP** (Essentials is an XP project):

   ```sh
   docker run --rm -e MKXP_RGSS_VERSION=1 -v "$PWD:/src" mkxp-web-jspi /src/rebuild-engine.sh
   ```

   `MKXP_RGSS_VERSION=1` selects RGSS1 (640x480, `Data/Scripts.rxdata`, frame rate driven by
   `Graphics.frame_rate`). The default (unset) stays VX.

2. Import the game as usual (`import-game.sh`), which also extracts `scripts_src/`.
   Keep the audio unconverted (Essentials plays OGG/WAV directly); if it was converted, run
   `pack.sh audio` to restore it.

3. Package the scripts:

   ```sh
   docker run --rm -v "$PWD:/src" -v "/path/to/Game:/game:ro" \
     -e GAME_TITLE="My Game" -e USER_LANGUAGE=es_ES \
     mkxp-web-jspi /src/tools/essentials/pack.sh
   ```

4. In `mkxp-web/build/index.html` set `namespace` / `wTitle`, and bump `BUILD_VER` after every
   engine rebuild (the Service Worker otherwise keeps serving the old `mkxp.wasm`).

## What `pack.sh` does

- **`build_scripts.rb`** builds `Data/Scripts.rxdata` from `scripts_src/` plus every plugin in
  `Data/PluginScripts.rxdata`, inlined before `Main`. mruby's `eval` has no `Binding`, so
  `PluginManager.runPlugins` can't load them at runtime; it is patched to a no-op.
  - Every `defined?(...)` is rewritten: mruby 2.1.2 has no `defined?` keyword. This covers
    constants, `A::B`, `@ivar`, `$gvar`, methods, `recv.meth`, `yield`, `super`, and
    `eval("defined?(X#{y})")`.
- **`patches.rb`** holds the source fixes, applied by section/file name.
  - Generic ones: bare `module_function` → `extend self`; `$!` → an explicit `rescue => var`;
    UTF-8 BOMs; `module FileTest` → `class FileTest`; `class X < X`.
  - A few plugin-specific ones: squiggly heredoc, `**nil`, a 64 KB+ string literal, and 64-bit
    trainer IDs saved as `Float`.
- **`essentials_shim.rb`** is appended to `rgss.rb` and provides the mkxp-z / Ruby 3 API mruby
  lacks:
  - `System`, `Input.triggerex?` & co.
  - text entry (`Input.text_input` / `Input.gets`, including the phone's on-screen keyboard);
  - `HTTPLite` (`get` / `post` / `post_body`, same results as mkxp-z) on the browser's `fetch`
    through the `web_http` native, plus `HTTPLite::JSON` (`parse` / `stringify`). The server must
    allow CORS; failures and timeouts (`HTTPLite.timeout`, 30 s by default) raise `MKXPError`.
    Connectivity probes to hosts without CORS (google.com, 1.1.1.1...) fail at once, so
    `network_available?` returns false without any request;
  - a real `Dir` on the browser FS;
  - case-insensitive `File`/`FileTest` lookups (the browser FS is case-sensitive, Windows isn't);
  - `File.basename(path, ext)`, `const_get("A::B")`;
  - `Encoding`, `Struct` `keyword_init:`, and the missing Integer/Array/Hash/String methods.

## Engine changes this relies on

These are part of the engine, not these tools.

- **`extra/mruby-web.patch`**, applied after `vm.c.patch` by the build scripts:
  - A hash index for mruby's symbol table. Stock 2.1.2 degrades to a linear scan: ~90 % of
    CPU time with Essentials, 38 ms → 2.5 ms of Ruby per frame.
  - The `f(*a, x)` fix: the splat used to alias `a`.
  - Instance variables on Array/String subclasses.
- **`extra/build_config.rb` + `CMakeLists.txt`**: 64-bit `Integer` (`MRB_INT64`) and the method
  cache.
- **Bindings**:
  - `Font#name=` (it was a no-op) and the `Font.new` / `default_name=` arrays;
  - `Bitmap.max_size`, `Bitmap#mega?`;
  - `web_fetch_file`, `web_resolve_path`, `web_readdir`, `web_mkdir`, `web_text_input`,
    `web_text_gets`, `web_http`.
- **`build/js`**: fonts are preloaded before boot (`preloadFonts`), deleted saves are also
  removed from IndexedDB, and `textinput.js`. Every file the game writes outside `Data/` (not
  only `*.rxdata`, subdirectories too) is stored in IndexedDB, and `File.rename` moves the stored copy.

## Debugging helpers (Node + puppeteer-core, uses the system Chrome)

```sh
cd tools/essentials && npm install
node run.mjs 60 shot.png Enter Enter          # boot, press keys, screenshot
PROFILE=/tmp/prof node drive.mjs              # long-lived session driven over HTTP :8130
node prof.mjs "Partida 1.rxdata"              # load a save and take a CPU profile
```

`URL` (default `http://127.0.0.1:8124/`) and `CHROME` (path to the Chrome binary) can be set
through the environment. For named wasm frames in profiles, build the engine with
`-e MKXP_WEB_PROFILE=1` (`--profiling-funcs`, release speed).

Scripts that fail to load show up in the console as `=== SCRIPT LOAD ERROR in '<section>' ===`.
Runtime errors are also written by Essentials to `errorlog.txt` in the browser FS
(`FS.readFile('/game/errorlog.txt')`).
