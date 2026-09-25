# Bring Your Own Game

This guide walks through running **your** RPG Maker XP (RGSS1) or VX (RGSS2) game in the
browser with RGSS-Web. The engine ships with **no game and no RTP assets** — you supply your
own game files, and you are solely responsible for their licensing and rights (see `NOTICE`).

The steps below use XP (`.rxdata`) in their examples; the pipeline auto-detects VX
(`.rvdata`) too — the VX deltas (mainly the build config) are in
[RPG Maker VX (RGSS2) games](#rpg-maker-vx-rgss2-games) below and in [RGSS2-VX.md](RGSS2-VX.md).

## TL;DR

The engine WASM (`mkxp.wasm`) is **game-agnostic**. It reads the game's scripts —
`Data/Scripts.rxdata` (XP) or `Data/Scripts.rvdata` (VX) — plus its data and assets at
**runtime**, so adding a new game is a **re-packaging** task, not an engine rebuild. You only
rebuild the engine (`rebuild-*.sh`) when you change the C++ or mruby — or to switch the
pinned RGSS version between XP and VX ([RGSS2-VX.md](RGSS2-VX.md)) — never for a new game of
the same version.

The whole pipeline runs inside the build container via `import-game.sh`, with your game
mounted read-only at `/game`.

## The one-shot import

Build the builder image first (from the repo root `Dockerfile`), then run:

```bash
docker run --rm -it --platform linux/amd64 \
  -v "$PWD/mkxp-web:/src/mkxp-web" \
  -v "$PWD/import-game.sh:/import-game.sh" \
  -v "/path/to/YourRMXPGame:/game:ro" \
  mkxp-web-jspi /import-game.sh <namespace> ["Window Title"]
```

- `<namespace>` — the **IndexedDB save-key prefix** for this game. Keep it unique per game
  so saves from different games never collide. Defaults to `mygame`.
- `"Window Title"` — the browser tab title. Defaults to `RGSS-Web`.

`--platform linux/amd64` is required (emsdk is pinned to 3.1.61 for JSPI). On Apple Silicon
this runs emulated; the WASM output is identical.

## What each step produces

`import-game.sh` runs eight steps against `mkxp-web/build/gameasync/` (the "GA" dir):

1. **Reset + copy.** Wipes `build/gameasync/` and `build/preload/`, then `rsync`s your
   `Data/`, `Graphics/`, `Audio/` and `Game.ini` in, stripping Windows/editor cruft
   (`*.exe`, `*.dll`, `*.swf`, `*.lnk`, `*.ini.bak`, `Thumbs.db`, `.DS_Store`). Warns if
   there is no `Game.ini` — RGSS games need one (with `Scripts=Data/Scripts.rxdata`).
2. **Convert audio.** Runs `extra/convert_audio.sh` (see [Sharp edges](#sharp-edges)).
   Needs `ffmpeg`/`timidity` in the container; if missing, this step is skipped and MIDI/WMA
   will be **silent**.
3. **Extract scripts.** `scripts_tool.rb extract` unpacks `Data/Scripts.rxdata` into
   editable `.rb` files under `scripts_src/` (plus `index.json` preserving section order and
   names). This is your porting workspace.
4. **Install the compat shim.** Copies the generic mruby/RGSS `extra/rgss.rb` into the GA
   dir (Win32API stub, Thread/Mutex no-ops, ENV/Dir stubs, streaming Zlib, ObjectSpace
   stubs, File byte helpers).
5. **Generate `mapping.js`.** `regen-mapping.sh` indexes every file in the GA dir into the
   lowercase→`path?h=<md5>` map the loader uses, **including directory markers** (entries
   with an empty hash). See [the directory-marker requirement](#the-mappingjs-directory-marker-requirement).
6. **Generate `bitmap-map.js`.** `gen-bitmap-map.rb` reads image header dimensions
   (PNG/GIF/BMP, no decode) so `drive.js` can hand a correctly-sized placeholder bitmap to
   C++ instantly and stream real pixels in the background — avoiding the multi-second stall
   every image would otherwise cause on first touch.
7. **Generate per-map preloads.** `gen-preload.rb` Marshal-loads each `Data/Map*.rxdata`,
   collects referenced asset names, and writes `build/preload/Data/MapNNN.rxdata.json`
   prefetch lists (optional; reduces first-touch stalls).
8. **Build the offline game pack.** `gen-pack.py` zips every file in `mapping.js` into
   `build/gamepack-<id>.zip` (media stored, data deflated, each entry tagged with its md5)
   and writes `build/gamepack.json`. The **Download game** button fetches this single file
   into the browser's private file system for offline play (see `docs/DEPLOY.md`).
9. **Set namespace + title.** Rewrites `var namespace` and `var wTitle` in
   `build/index.html`.

After this, `build/gameasync/` is populated and `mkxp.wasm` is unchanged. Serve `build/`
(see `docs/DEPLOY.md`) and test in a browser.

## Sharp edges

### Audio
`extra/convert_audio.sh` converts, in place under `Audio/`:

- **MIDI (`.mid`) → OGG** via `timidity`, then re-encode.
- **`.ogg` and `.wav` → OGG** (libvorbis, `-qscale:a 0`).

The critical facts:

- **MIDI and WMA MUST be converted** — browsers cannot play them. WMA is not handled by the
  script; convert it yourself to OGG (or remove it) or it will be silent.
- **MP3 / WAV / OGG already play at runtime.** The re-encode pass just normalizes to OGG
  (smaller, well-supported); MP3 is left as-is and plays fine.
- **No Flash, no video.** `.swf` is stripped on copy; video playback is unsupported.

If `ffmpeg`/`timidity` are absent, audio conversion is skipped with a warning and any MIDI
stays silent.

**BGM plays on the browser's audio thread** (Web Audio, `build/js/webbgm.js`), so it does
not stutter when the main thread blocks (a synchronous save, a long map load). RGSS loops
the whole track by default; if your game uses intro→loop tracks, define
`window.BGM_LOOP_TABLE` before boot — keyed by the lowercased play path, value
`[startMs, endMs]` — e.g. in a small script you add to `build/` and load before
`js/webbgm.js`:

```js
window.BGM_LOOP_TABLE = { "audio/bgm/field": [4000, 45999] };
```

Tracks not listed loop over their full duration.

### Images
Supported formats: **PNG, JPEG, GIF, BMP**. The size-map fast path (step 6) reads
PNG/GIF/BMP headers only. Extremely large bitmaps can stress memory; the engine runs with
`ALLOW_MEMORY_GROWTH` and a 256 MB initial heap to absorb the churn.

If a screen loads/redraws *many* images very rapidly (e.g. a paperdoll UI cycling dozens of
files), the size-map fast path's double-load can race into a `PHYSFS ERROR` / FS error. Keep
those images off the fast path by listing their lowercased path prefixes in the
`SIZEMAP_EXCLUDE` env var (comma-separated) when running `gen-bitmap-map.rb`; excluded images
load fine on the slower single-load path.

### The `mapping.js` directory-marker requirement
`regen-mapping.sh` emits an entry for **every** path, and for directories it writes a
**folder marker** (a `path?h=` value with an **empty** md5). The loader's `drive.js`
`createDummies()` relies on these markers to `FS.mkdir` the directory tree before files land
in it. **If you regenerate `mapping.js` without the directory markers, `createDummies()`
fails** and the game will not load. Always use `regen-mapping.sh` (not a hand-rolled index).

### The engine WASM is not rebuilt per game
Adding or swapping a game only touches `build/gameasync/` and the generated maps. `mkxp.wasm`
is untouched. You only run `rebuild-*.sh` if you change the C++ or the mruby VM.

### Screen resolution
Default render resolution follows the build's RGSS version: XP **640×480**, VX **544×416**
(set in `src/config.cpp`). A game needing another internal resolution should call
`Graphics.resize_screen(w, h)` at boot.

## RPG Maker VX (RGSS2) games

The engine runs RGSS2 / RPG Maker VX games in addition to XP; full details are in
[RGSS2-VX.md](RGSS2-VX.md). The deltas from the XP flow above:

- **Build for VX.** The RGSS version is pinned in `mkxp-web/src/config.cpp` — set
  `rgssVersion = 2`, `defScreenW`/`defScreenH` to `544`/`416`, and
  `game.scripts = "Data/Scripts.rvdata"`, then rebuild the engine. (The repo already
  defaults to VX.)
- **Data files are `.rvdata`,** not `.rxdata` (Scripts, Maps, System, …). The full pipeline
  — `import-game.sh`'s script-extract, `gen-preload.rb`, `regen-mapping.sh`, and the asset
  copy — auto-detects both extensions, so a VX game imports exactly like an XP one. When you
  repack ported scripts, use the `.rvdata` path:
  `ruby scripts_tool.rb pack scripts_src build/gameasync/Data/Scripts.rvdata`.
- **Porting is the same** mruby work as XP ([PORTING-mruby.md](PORTING-mruby.md)), plus the
  VX `RPG::` data-class field gaps described in [RGSS2-VX.md](RGSS2-VX.md).

## The tiered reality (be honest with yourself)

This repo is a **toolkit + porting guide**, not drag-and-drop. Because the Ruby binding is
**mruby**, not CRuby/MRI, per-game porting effort varies sharply:

| Game type | What to expect |
| --- | --- |
| **Vanilla / lightly-scripted (XP or VX)** | Light mechanical porting + the asset processing above. Close to "just works" after import. (Not exhaustively tested across arbitrary games.) |
| **Pokémon Essentials-class (heavily scripted)** | **Substantial per-game mruby porting is still required**, even with the engine's `emscripten_sleep` event-loop yield, the mruby VM fixes, and the `rgss.rb` shims. See `docs/PORTING-mruby.md`. |
| **Plugin-heavy / custom-script** | Unknown per-game mruby walls. There is no pre-flight compatibility linter — you find out by running it. |

### Not supported
- **RPG Maker VX Ace (RGSS3)** — a different runtime (`.rvdata2`, Features-based data classes). Only XP (RGSS1) and VX (RGSS2) are supported.
- MRI/CRuby-only scripts (this is **mruby** only).
- Video playback and WMA audio.
- Native Win32API features (mouse hooks, INI, clipboard beyond the `rgss.rb` stub).
- Extremely large bitmaps.

## Performance: optional Essentials script patches

These are **optional** hot-path patches for Pokémon Essentials-based games (the class and
method names below are standard Essentials; exact script section numbers vary by version).
They are pure-Ruby edits to *your* extracted `scripts_src/` — no engine rebuild — and matter
in the browser far more than on desktop, because the Ruby VM is **mruby** (slower than MRI)
and the whole game loop runs on one thread that yields to the browser once per frame via
`emscripten_sleep`. Per-frame work that was invisible on desktop RGSS can dominate a frame
here.

> **Measuring first.** `Time.now` deltas are **unreliable** for CPU timing under JSPI — a
> wall-clock span across a frame includes the browser yield/render time, so a Ruby timer can
> report a figure larger than the frame's actual work. Profile with the engine's own
> `[fps] … [work] … ms` console line and bisect (disable one loop, measure the delta).

### 1. Cache animated panorama / fog bitmaps

Essentials' `AnimatedPlane` (in the `SpriteWindow` script) **disposes** its decoded
`AnimatedBitmap` on every `setPanorama` / `setFog` call. A map that *animates* its panorama
or fog by cycling through several images — e.g. a parallel-process event calling **Change
Map Settings** every few frames — therefore **re-decodes a full-screen PNG every cycle**.
Disposal also drops the bitmap's refcount to zero, evicting it from the `BitmapCache`, so the
next cycle decodes from disk again. On desktop this is negligible; in-browser it can cost
tens of ms per swap and visibly tank the frame rate.

Fix: keep a small **warm cache** of decoded bitmaps keyed by `path+hue`, reuse instead of
disposing on swap, and free them only when the plane itself is disposed (a real map change)
or via LRU beyond a cap. Leave `setBitmap`, `update` and `clearBitmaps` untouched — only the
panorama/fog paths get warmed.

```ruby
class AnimatedPlane < LargePlane
  def initialize(viewport)
    super(viewport)
    @bitmap  = nil
    @warm    = {}     # "path|hue" => AnimatedBitmap (insertion order = LRU)
    @warmMax = 8
  end

  def dispose
    @warm.each_value { |ab| ab.dispose if ab && !ab.disposed? }
    @warm.clear
    @bitmap.dispose if @bitmap && !@bitmap.disposed?
    @bitmap = nil
    self.bitmap = nil if !self.disposed?
    super
  end

  def setPanorama(file, hue = 0)
    return _detach if file.nil?
    _assignWarm("Graphics/Panoramas/" + file, hue)
  end

  def setFog(file, hue = 0)
    return _detach if file.nil?
    _assignWarm("Graphics/Fogs/" + file, hue)
  end

  def _detach                       # park the plane without disposing the bitmap
    @bitmap = nil
    self.bitmap = nil if !self.disposed?
  end

  def _assignWarm(fullpath, hue)    # decode once per distinct [path,hue], then reuse
    _detach
    key = "#{fullpath}|#{hue}"
    w = @warm[key]
    w = nil if w && w.disposed?
    w = AnimatedBitmap.new(fullpath, hue) unless w
    @warm.delete(key); @warm[key] = w
    @bitmap = w
    while @warm.size > @warmMax
      k = @warm.keys.first
      ab = @warm.delete(k)
      ab.dispose if ab && !ab.disposed? && !ab.equal?(@bitmap)
    end
  end
end
```

This helps **any** map that cycles or swaps its panorama/fog, engine-wide. Note it caches the
*decode*, not the plane's per-frame tile-blit — a scrolling plane still re-tiles as the map
moves (that is stock `LargePlane` behaviour).

### 2. Cull reflection sprites like character sprites

`Spriteset_Map#update` already skips updating **character** sprites that are off-screen (an
`in_range?`-style visibility test). But it updates **every reflection sprite unconditionally**
each frame — a terrain scan plus a mirror-sprite rebuild — even for events far off-screen. On
large maps (towns/cities) with many events this is pure waste, since an off-screen character's
reflection is off-screen too.

Fix: apply the same on-screen test the character loop uses to the reflection loop. Always
update the player's reflection; skip out-of-range event reflections. Reuse whatever range
check that Essentials version's character loop calls (shown here as `in_range?`).

```ruby
for sprite in @reflectedSprites
  sprite.visible = true
  sprite.visible = (@map == $game_map) if sprite.event == $game_player
  ev = sprite.event
  if ev.is_a?(Game_Event)
    sprite.update if ev.trigger == 3 || ev.trigger == 4 || in_range?(ev)
  else
    sprite.update   # player reflection: always
  end
end
```

The range check's margin (Essentials uses several tiles beyond the screen) means a frozen
reflection resumes updating well before it could scroll into view, so there is no visible
pop-in. Neutral on small maps where everything is on-screen.

After applying either patch, **repack** (next section) so the browser loads the new scripts.

## Repack after porting

If you edited `scripts_src/*.rb` to port the game to mruby, repack them back into
`Scripts.rxdata`:

```bash
ruby scripts_tool.rb pack scripts_src build/gameasync/Data/Scripts.rxdata
```

Then make the loader refetch the new scripts — **either** re-run `regen-mapping.sh` (which
recomputes the `?h=` md5) **or** manually bump the `Scripts.rxdata ?h=` hash in
`build/gameasync/mapping.js`. If you skip this, the browser/Service Worker may serve the old
cached `Scripts.rxdata` and your changes won't take effect.

Then rebuild the offline pack so **Download game** ships the new files:

```bash
python3 gen-pack.py
```

(A stale pack is still safe: the loader only uses pack entries whose md5 matches the current
`mapping.js`, and fetches the rest from the network.)

> The Service Worker (offline + fast reloads) requires a secure context, so production must
> be HTTPS. See `docs/DEPLOY.md` for serving requirements (`.wasm` must be served as
> `Content-Type: application/wasm`; this build is single-threaded, so **do not** add
> COOP/COEP headers).
