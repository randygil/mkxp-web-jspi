# Deploying RGSS-Web

RGSS-Web is **100% client-side**: the browser downloads `mkxp.wasm`, the engine
glue, and the game assets, and runs everything locally. The server only ships
static files — there is **zero per-player server CPU**, and the number of
concurrent players is bounded only by your bandwidth/CDN, not by compute.

This document covers how to serve a build that already exists in
`mkxp-web/build/`. Building the engine (`rebuild-*.sh`) and packaging a game
(`import-game.sh`, `scripts_tool.rb`) are covered elsewhere; here we assume
`mkxp-web/build/` is populated.

---

## Serving requirements

Any static host works as long as it satisfies these:

1. **`.wasm` served as `Content-Type: application/wasm`.**
   This is what lets the browser use `WebAssembly.instantiateStreaming` (compile
   the module while it downloads). If the MIME type is wrong, startup is slower
   or fails.

2. **Brotli or gzip compression** for the large text/wasm assets.
   `mkxp.wasm` is ~4 MB uncompressed and drops to ~1.1 MB under Brotli q11.
   Prefer **pre-compressed** `.br`/`.gz` siblings so the server does no per-request
   compression work. Media (PNG/JPG/OGG/MP3/WAV) is already compressed and should
   **not** be recompressed.

3. **Cache-Control split into two tiers:**
   - **`immutable`, 1 year** for content-addressed / versioned assets: the wasm
     engine, `mkxp.js` (loaded with `?v=BUILD_VER`), and all game media under
     `gameasync/` (loaded with a `?h=<md5>` content hash). The URL changes when
     the bytes change, so these are safe to cache forever.
   - **`no-cache` (revalidate)** for the unversioned "shell" files that change on
     every redeploy: `index.html`, `sw.js`, `manifest.webmanifest`,
     `gameasync/mapping.js`, `gameasync/bitmap-map.js`, and `js/*`. These must be
     revalidated so a redeploy is picked up.

4. **HTTPS in production** (see below) — the Service Worker requires a secure
   context.

5. **Do NOT add COOP/COEP headers.**
   This build is **single-threaded** (no pthreads, no `SharedArrayBuffer`), so
   cross-origin isolation is **not** required. Adding `Cross-Origin-Opener-Policy`
   / `Cross-Origin-Embedder-Policy` gains nothing here and can break asset loads.

---

## HTTPS is mandatory in production

The Service Worker (`sw.js`) provides offline play and instant reloads, and
browsers only register a Service Worker in a **secure context**. In practice
that means the game must be served over **HTTPS** (or on `localhost` during
development). Two ways to get TLS:

- **Behind an existing reverse proxy** (Nginx/Apache/etc.): keep the container on
  plain HTTP at `:8080` and terminate TLS (and set HSTS) at the proxy. For
  Apache: `ProxyPass / http://127.0.0.1:8080/` + `ProxyPassReverse /`.
- **Standalone HTTPS via Caddy** (automatic Let's Encrypt): see the Caddy section.

---

## Service Worker & offline caching

`sw.js` uses two Cache-Storage buckets:

- a **versioned shell cache** (`rgss-web-v*`) for the un-versioned shell
  (`index.html`, `sw.js`, `mapping.js`, `js/*`), served **network-first** — a redeploy is
  picked up as soon as the client is back online;
- a **stable asset cache** (`rgss-web-assets`) for the engine (`?v=`) and content-hashed
  media (`?h=`), served **cache-first**. It is **not** tied to the version cache, so it is
  never purged by a redeploy — a downloaded full-offline copy survives new deployments.

The harness also exposes two optional buttons (top-right of `index.html`):

- **Download game** — full offline play. When `gamepack.json` is deployed (built by
  `gen-pack.py`), it downloads the whole game as **one zip** (`gamepack-<id>.zip`) into the
  Origin Private File System with a worker (`js/gamepack-worker.js`), resuming interrupted
  downloads with HTTP `Range`; `js/gamepack.js` then serves every game file from that zip
  (no extraction, no per-file requests). The engine + page shell go into the stable cache.
  A new deploy shows **Update game**; until the player updates, only the files whose md5
  changed load from the network. Without `gamepack.json` it falls back to precaching every
  asset one by one into the stable cache.
- **Install app** — PWA install via `beforeinstallprompt` (Add-to-Home-Screen / standalone),
  backed by `manifest.webmanifest` + `icon-*.png`. Ship your own icons/manifest name per game.

**The game pack needs `Range` support** (Caddy, nginx, Apache and most CDNs have it) and
must not be re-compressed (zip is not in Caddy's `encode` types; don't add it). The deploy
image carries both `gameasync/` and the pack, so it is roughly twice the game size. On CDNs
with a per-file cache limit (e.g. Cloudflare free: 512 MB) the pack is served uncached from
the origin, which works but costs origin bandwidth.

**Redeploying is transparent:** bump `BUILD_VER` in `index.html` (engine) and the changed
assets' `?h=` hashes in `mapping.js` — clients fetch the new bytes, and the version-URL scheme
means a stale entry is never served for changed content. No server-side cache action is needed
beyond the `Cache-Control` headers above.

---

## Option A — Caddy container (recommended)

The `deploy/` directory ships a hardened, self-contained Caddy image. It is a
two-stage build (`deploy/Dockerfile`):

1. **Compress stage** (`alpine:3` + `brotli`/`gzip`): pre-compresses served text
   and wasm files larger than 1 KB into `.br` (Brotli q11) and `.gz` siblings.
   Media is intentionally skipped.
2. **Runtime stage** (`caddy:2-alpine`): copies `deploy/Caddyfile` and the
   compressed `/srv`, strips file capabilities from the Caddy binary (so it runs
   cleanly under `no-new-privileges` on the unprivileged port `:8080`), and runs
   as non-root UID `10001`. A `HEALTHCHECK` polls `/index.html`.

### What the Caddyfile does (`deploy/Caddyfile`)

- Serves the site on `:8080`, root `/srv`.
- `file_server { precompressed br zstd gzip }` — hands back the pre-generated
  `.br`/`.gz` with zero per-request CPU; `encode zstd gzip` is the dynamic
  fallback for anything not pre-compressed.
- Forces `Content-Type: application/wasm` on `*.wasm`.
- Cache-Control: `immutable` (1 year) for `*.wasm`, `/mkxp.js`, and `/gameasync/*`;
  `no-cache` for the shell files (`/`, `/index.html`, `/sw.js`,
  `/manifest.webmanifest`, `/gameasync/mapping.js`, `/gameasync/bitmap-map.js`,
  `/js/*`). The shell rule is listed after the immutable rule so it wins on
  overlapping paths.
- Security: `admin off`, `persist_config off`, `X-Content-Type-Options: nosniff`,
  `Referrer-Policy: no-referrer`, `Content-Security-Policy: frame-ancestors 'self'`,
  `Permissions-Policy: fullscreen=(self)`, and the `Server` banner removed.
- **No COOP/COEP** — intentionally omitted (single-threaded build).

### Build & run

Build from the **repo root** (the build context must include `mkxp-web/build/`):

```bash
# build (context = repo root)
docker build -f deploy/Dockerfile -t rgss-web .

# hardened run (image is already non-root)
docker run -d --name rgss-web \
  -p 8080:8080 \
  --read-only --tmpfs /tmp \
  -v rgss-web-caddy-data:/data -v rgss-web-caddy-config:/config \
  --cap-drop ALL --security-opt no-new-privileges \
  --restart unless-stopped \
  rgss-web
```

The `/data` and `/config` volumes are the only writable paths Caddy needs (the
root filesystem is read-only).

### Or with Compose (`deploy/docker-compose.yml`)

```bash
cd deploy && docker compose up -d --build
```

The compose file sets `context: ..` (repo root), the `read_only` root FS,
`tmpfs /tmp`, `caddy-data`/`caddy-config` volumes, `cap_drop: ALL`,
`no-new-privileges`, and the healthcheck.

The game is then at `http://<host>:8080/`. Put it behind your TLS reverse proxy
for production.

### Standalone HTTPS with Caddy

To let Caddy obtain and renew certificates itself instead of terminating TLS at a
proxy, edit `deploy/Caddyfile`: remove the `auto_https off` line and change the
site address from `:8080` to your domain (e.g. `play.example.com`). Then publish
ports 80 and 443 (`-p 80:80 -p 443:443`) and keep `/data` on a volume (it stores
the certificates).

---

## Option B — Apache (`deploy/apache.htaccess`)

If you serve the build directly from Apache (no container), drop
`deploy/apache.htaccess` into the web root next to `index.html`. Every block is
guarded by `<IfModule>`, so a missing module is skipped rather than fatal. It:

- Sets MIME types, including `application/wasm` for `.wasm` and
  `application/octet-stream` for `.dat`/`.rxdata`/`.rvdata`.
- Rewrites requests to a pre-compressed `name.ext.br` when the client sends
  `Accept-Encoding: br`, re-advertising the correct `Content-Type` + `br`
  encoding for `.wasm.br`/`.js.br`/`.json.br`.
- Falls back to dynamic `mod_brotli`/`mod_deflate` when no `.br` exists.
  **Note:** dynamically Brotli-compressing the ~4 MB wasm on every request is
  CPU-heavy — pre-generate `.br` for the large files.
- Caches media + `.wasm` + `mkxp.js` as `immutable` (1 year), and forces
  revalidation (`no-cache, must-revalidate`) on the shell files
  (`index.html`, `mapping.js`, `sw.js`, `drive.js`, `dpad.js`).

Pre-generate the compressed variants once after each rebuild, e.g.:

```bash
brotli -q 11 -kf mkxp.wasm mkxp.js gameasync/mapping.js js/*.js
```

> The Caddy container and `apache.htaccess` are two independent options. The
> `.htaccess` is for a **static Apache host without the container**; you do not
> need it when running the Caddy image (though you can still front the container
> with Apache purely as a TLS reverse proxy).

---

## Baked-in vs. mounted assets

By default the Caddy image is **self-contained**: the assets are copied into the
image at build time (`COPY --from=compress /srv /srv`), which also gets you the
pre-compressed `.br`/`.gz`. With a full game this image can be several hundred MB.

For a tiny image that reads assets from the host instead, remove the
`COPY … /srv` line from `deploy/Dockerfile` and volume-mount the build read-only
at run time:

```bash
docker run -d -p 8080:8080 -v "$PWD/mkxp-web/build:/srv:ro" rgss-web
```

In that case the build's Brotli pre-compression does not run — either generate
the `.br`/`.gz` yourself inside `mkxp-web/build/`, or accept Caddy's dynamic
gzip/zstd fallback.
