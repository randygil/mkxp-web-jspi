// WEB PORT: downloads the offline game pack into OPFS (see js/gamepack.js).
// Runs in a dedicated worker because FileSystemSyncAccessHandle (worker-only) writes the
// file IN PLACE: whatever reached disk survives a closed tab / lost connection, and the
// next run resumes from the current file size with an HTTP Range request.
// message in:  { url, size, name }
// messages out: { type: 'progress', got, total } | { type: 'done' } | { type: 'error', message, quota }
self.onmessage = async function (e) {
    var d = e.data, h = null;
    try {
        var root = await navigator.storage.getDirectory();
        var fh = await root.getFileHandle(d.name, { create: true });
        h = await fh.createSyncAccessHandle();
        var got = h.getSize();
        if (got > d.size) { h.truncate(0); got = 0; }

        if (got < d.size) {
            // ALWAYS a Range request, even from byte 0: proxies (e.g. Traefik's compress
            // middleware) gzip a plain 200 on the fly -- burning CPU on an already-compressed
            // zip and dropping Content-Length -- but pass 206 responses through untouched.
            // cache: 'no-store' so the browser's HTTP cache doesn't keep a second copy.
            var resp = await fetch(d.url, { headers: { Range: 'bytes=' + got + '-' }, cache: 'no-store' });
            if (resp.status === 200) {
                if (got) { h.truncate(0); got = 0; }        // server ignored Range: start over
            } else if (resp.status === 206) {
                var m = /bytes (\d+)-/.exec(resp.headers.get('Content-Range') || '');
                if (!m || Number(m[1]) !== got) {
                    h.truncate(0);
                    throw new Error('server returned an unexpected range, retry to start over');
                }
            } else {
                throw new Error('HTTP ' + resp.status + ' fetching the game pack');
            }

            var reader = resp.body.getReader();
            var lastFlush = got, lastPost = 0;
            self.postMessage({ type: 'progress', got: got, total: d.size });
            for (;;) {
                var r = await reader.read();
                if (r.done) break;
                if (got + r.value.byteLength > d.size) throw new Error('game pack is larger than expected (redeployed?)');
                got += h.write(r.value, { at: got });
                if (got - lastFlush >= 32 * 1048576) { h.flush(); lastFlush = got; }
                var now = Date.now();
                if (now - lastPost > 200) { lastPost = now; self.postMessage({ type: 'progress', got: got, total: d.size }); }
            }
            h.flush();
        }

        if (got !== d.size) throw new Error('download incomplete (' + got + ' of ' + d.size + ' bytes), retry to resume');
        self.postMessage({ type: 'progress', got: got, total: d.size });
        h.close(); h = null;
        self.postMessage({ type: 'done' });
    } catch (err) {
        var msg = String((err && err.message) || err);
        self.postMessage({ type: 'error', message: msg,
                           quota: !!err && (err.name === 'QuotaExceededError' || /quota/i.test(msg)) });
    } finally {
        if (h) { try { h.flush(); h.close(); } catch (e2) {} }
    }
};
