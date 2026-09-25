/*
** sw.js — Service Worker for the mkxp-web-jspi engine (WEB PORT addition).
**
** Goal: after the first visit, make reloads near-instant and enable offline play by
** caching the WASM engine + the on-demand game assets in the Cache Storage API.
**
** Strategy:
**  - IMMUTABLE content (versioned/hashed URLs: `?v=` engine, `?h=` assets, and anything
**    under gameasync/{Graphics,Audio,Data,Fonts,Movies}) -> CACHE-FIRST, into a STABLE cache
**    (ASSET_CACHE). Safe because the URL changes whenever the content changes (new build
**    version / new asset hash), so a stale entry is never served for changed content.
**  - Everything else (index.html, mapping.js, the small js/*.js, sw.js itself) -> NETWORK-
**    FIRST, into the versioned cache, falling back to cache when offline. This picks up
**    redeploys immediately while still working offline.
**  - Savefiles are in IndexedDB (localforage), never fetched, so they're untouched here.
**
** Bump CACHE_VERSION on a redeploy to purge the un-versioned shell cache (hashed/versioned
** URLs already self-refresh). ASSET_CACHE is intentionally NOT tied to CACHE_VERSION so a
** redeploy never purges a full offline copy the user downloaded (see the download button in
** index.html); immutable URLs are safe to keep forever.
*/
const CACHE_VERSION = 'rgss-web-v1';
const ASSET_CACHE = 'rgss-web-assets';
const NET_TIMEOUT_MS = 4000;   // network-first: fall back to cache after this long
const NET_DEAD_MS = 30000;     // ...then serve cache first for this long (see fetch handler)
var netDeadUntil = 0;

// Small shell files worth precaching so a 2nd visit boots instantly even before the game
// requests them. The big wasm + assets are cached at runtime on first use (cache-first).
const PRECACHE = [
  'js/localforage.min.js',
  'js/drive.js',
  'js/gamepack.js',
  'js/dpad.js',
  'js/gamepad.js',
  'gameasync/mapping.js',
  'gameasync/bitmap-map.js',
];

function isImmutable(url) {
  if (url.search.indexOf('v=') !== -1 || url.search.indexOf('h=') !== -1) return true;
  if (/\/gameasync\/(Graphics|Audio|Data|Fonts|Movies)\//i.test(url.pathname)) return true;
  if (/\/mkxp\.wasm$/.test(url.pathname)) return true;
  return false;
}

self.addEventListener('install', function (e) {
  e.waitUntil(
    caches.open(CACHE_VERSION)
      .then(function (c) { return c.addAll(PRECACHE).catch(function () {}); })
      .then(function () { return self.skipWaiting(); })
  );
});

self.addEventListener('activate', function (e) {
  e.waitUntil(
    caches.keys()
      .then(function (keys) {
        // Keep both the versioned shell cache AND the stable asset cache.
        return Promise.all(keys.filter(function (k) { return k !== CACHE_VERSION && k !== ASSET_CACHE; })
                               .map(function (k) { return caches.delete(k); }));
      })
      .then(function () { return self.clients.claim(); })
  );
});

self.addEventListener('fetch', function (e) {
  var req = e.request;
  if (req.method !== 'GET') return;
  var url;
  try { url = new URL(req.url); } catch (err) { return; }
  if (url.origin !== self.location.origin) return; // let cross-origin pass through
  // The offline game pack (hundreds of MB, fetched with Range requests by
  // js/gamepack-worker.js into OPFS) must never be copied into Cache Storage.
  if (/\/gamepack-[^/]*\.zip$/.test(url.pathname)) return;

  if (isImmutable(url)) {
    // CACHE-FIRST: serve from the STABLE asset cache; on miss, fetch and store there.
    e.respondWith(
      caches.open(ASSET_CACHE).then(function (cache) {
        return cache.match(req).then(function (hit) {
          if (hit) return hit;
          return fetch(req).then(function (resp) {
            if (resp && resp.status === 200) {
              try { cache.put(req, resp.clone()); } catch (err) {}
            }
            return resp;
          }).catch(function () {
            // A failed fetch on a cache-miss immutable asset must NOT reject respondWith
            // (that makes the request error with status 0, and the on-demand loader would
            // retry forever -> game hang). Return a terminal response: a cached copy from
            // ANY cache if present, else a 503 so the loader can skip/continue gracefully.
            return caches.match(req).then(function (hit2) {
              return hit2 || new Response('', { status: 503, statusText: 'SW fetch failed' });
            });
          });
        });
      })
    );
  } else {
    // NETWORK-FIRST: fresh when online (picks up redeploys), cache fallback when offline.
    // A network that hangs instead of failing (captive portal, Wi-Fi without internet, bad
    // signal) would stall the boot for the whole TCP timeout, so after NET_TIMEOUT_MS a
    // cached copy is served if there is one; otherwise we keep waiting for the network.
    // After such a timeout the network is presumed dead for NET_DEAD_MS: cached copies are
    // then served at once (the fetch still runs, refreshing the cache and clearing the flag
    // as soon as the network answers), so the boot doesn't pay the timeout once per file.
    e.respondWith(new Promise(function (resolve) {
      var settled = false;
      var finish = function (resp) { if (!settled && resp) { settled = true; resolve(resp); } };
      var wait = Date.now() < netDeadUntil ? 0 : NET_TIMEOUT_MS;
      var timer = setTimeout(function () {
        caches.match(req).then(function (hit) {
          if (hit && !settled) netDeadUntil = Date.now() + NET_DEAD_MS;
          finish(hit);
        });
      }, wait);
      fetch(req).then(function (resp) {
        clearTimeout(timer);
        netDeadUntil = 0;
        if (resp && resp.status === 200) {
          var copy = resp.clone();
          caches.open(CACHE_VERSION).then(function (cache) { try { cache.put(req, copy); } catch (err) {} });
        }
        finish(resp);
      }).catch(function () {
        clearTimeout(timer);
        // Offline: check EVERY cache (the versioned shell cache AND the stable ASSET_CACHE,
        // which the offline-download button fills with the shell + navigation document).
        caches.match(req).then(function (hit) {
          if (hit) return hit;
          if (req.mode === 'navigate') return caches.match('index.html');
          return undefined;
        }).then(function (hit) { finish(hit || Response.error()); });
      });
    }));
  }
});
