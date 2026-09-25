// WEB PORT: offline game pack (one zip in the Origin Private File System).
//
// "Download game" fetches build/gamepack-<id>.zip (made by gen-pack.py) into OPFS with
// js/gamepack-worker.js -- one resumable download instead of ~26k per-file requests. At
// boot, GamePack.mount() reads the zip's central directory, and drive.js's getLazyAsset /
// fetchGameAsset serve every game file from it (a local File.slice read, inflated with the
// native DecompressionStream when the entry is deflated), so the game runs with no network.
//
// An entry is only used when its md5 (stored as the central-directory comment) equals the
// md5 in the CURRENT mapping.js, so after a redeploy the unchanged files still come from the
// pack and only the changed ones hit the network until the player updates the pack.
(function () {
    var CD_SIG = 0x02014b50, LOCAL_SIG = 0x04034b50;
    var EOCD_SIG = 0x06054b50, EOCD64_SIG = 0x06064b50, EOCD64_LOC_SIG = 0x07064b50;
    var utf8 = new TextDecoder('utf-8');

    function flagKey() { return namespace + '__pack'; }
    function opfsPrefix() { return 'pack-' + String(namespace).replace(/[^\w-]/g, '_') + '-'; }

    async function readBytes(file, start, end) {
        return new DataView(await file.slice(start, end).arrayBuffer());
    }

    function u64(dv, off) { return dv.getUint32(off, true) + dv.getUint32(off + 4, true) * 4294967296; }

    // Central directory -> { lowercased path: {off, csize, method, md5} }
    async function parseCentralDirectory(file) {
        var tailLen = Math.min(file.size, 65535 + 22 + 20);
        var tailStart = file.size - tailLen;
        var tail = await readBytes(file, tailStart, file.size);
        var eocd = -1;
        for (var i = tailLen - 22; i >= 0; i--) {
            if (tail.getUint32(i, true) === EOCD_SIG) { eocd = i; break; }
        }
        if (eocd < 0) throw new Error('not a zip (no end of central directory)');

        var count = tail.getUint16(eocd + 10, true);
        var cdSize = tail.getUint32(eocd + 12, true);
        var cdOff = tail.getUint32(eocd + 16, true);
        if (count === 0xFFFF || cdSize === 0xFFFFFFFF || cdOff === 0xFFFFFFFF) {
            var loc = eocd - 20;
            if (loc < 0 || tail.getUint32(loc, true) !== EOCD64_LOC_SIG) throw new Error('zip64 locator missing');
            var e64Off = u64(tail, loc + 8);
            var e64 = await readBytes(file, e64Off, e64Off + 56);
            if (e64.getUint32(0, true) !== EOCD64_SIG) throw new Error('bad zip64 end of central directory');
            count = u64(e64, 32);
            cdSize = u64(e64, 40);
            cdOff = u64(e64, 48);
        }

        var cd = await readBytes(file, cdOff, cdOff + cdSize);
        var bytes = new Uint8Array(cd.buffer);
        var entries = Object.create(null);
        var p = 0;
        for (var n = 0; n < count; n++) {
            if (cd.getUint32(p, true) !== CD_SIG) throw new Error('corrupt central directory at entry ' + n);
            var method = cd.getUint16(p + 10, true);
            var csize = cd.getUint32(p + 20, true);
            var usize = cd.getUint32(p + 24, true);
            var nameLen = cd.getUint16(p + 28, true);
            var extraLen = cd.getUint16(p + 30, true);
            var commentLen = cd.getUint16(p + 32, true);
            var off = cd.getUint32(p + 42, true);
            var name = utf8.decode(bytes.subarray(p + 46, p + 46 + nameLen));

            // zip64 extra field (id 1): only the fields saturated above are present, in order.
            if (usize === 0xFFFFFFFF || csize === 0xFFFFFFFF || off === 0xFFFFFFFF) {
                var x = p + 46 + nameLen, xEnd = x + extraLen;
                while (x + 4 <= xEnd) {
                    var id = cd.getUint16(x, true), len = cd.getUint16(x + 2, true), q = x + 4;
                    if (id === 1) {
                        if (usize === 0xFFFFFFFF) { usize = u64(cd, q); q += 8; }
                        if (csize === 0xFFFFFFFF) { csize = u64(cd, q); q += 8; }
                        if (off === 0xFFFFFFFF) { off = u64(cd, q); q += 8; }
                        break;
                    }
                    x = q + len;
                }
            }

            var cStart = p + 46 + nameLen + extraLen;
            var md5 = utf8.decode(bytes.subarray(cStart, cStart + commentLen)).toLowerCase();
            if (name.charAt(name.length - 1) !== '/') {
                entries[name.toLowerCase()] = { off: off, csize: csize, method: method, md5: md5 };
            }
            p = cStart + commentLen;
        }
        return entries;
    }

    var GamePack = {
        file: null,       // File snapshot of the installed zip
        entries: null,    // parsed central directory
        info: null,       // { id, file, size, ts } of the installed pack
        _ready: null,

        supported: function () {
            return !!(navigator.storage && navigator.storage.getDirectory && window.Worker &&
                      typeof DecompressionStream === 'function');
        },

        // Open the installed pack (if any). Safe to call again to switch to a new pack.
        mount: function () {
            var self = this;
            var job = (async function () {
                if (!self.supported() || typeof localforage === 'undefined') return;
                var rec = await localforage.getItem(flagKey());
                if (!rec || !rec.file) return;
                var root = await navigator.storage.getDirectory();
                var file = await (await root.getFileHandle(rec.file)).getFile();
                if (file.size !== rec.size) throw new Error('pack size mismatch (' + file.size + ' != ' + rec.size + ')');
                var t0 = performance.now();
                var entries = await parseCentralDirectory(file);
                self.file = file; self.entries = entries; self.info = rec;
                console.log('[gamepack] mounted ' + rec.file + ': ' + Object.keys(entries).length +
                            ' files in ' + Math.round(performance.now() - t0) + 'ms');
            })().catch(function (e) { console.warn('[gamepack] not mounted:', e); });
            // Never let a hung OPFS/IndexedDB call stall asset loading for long.
            this._ready = Promise.race([job, new Promise(function (r) { setTimeout(r, 8000); })]);
            return this._ready;
        },

        whenReady: function () { return this._ready || Promise.resolve(); },

        // "gameasync/Path/File.png?h=<md5>" -> entry, if the pack has THIS version of it.
        lookup: function (url) {
            if (!this.entries || url.indexOf('gameasync/') !== 0) return null;
            var rest = url.slice('gameasync/'.length);
            var q = rest.indexOf('?h=');
            var path = q === -1 ? rest : rest.slice(0, q);
            var md5 = q === -1 ? '' : rest.slice(q + 3).toLowerCase();
            var e = this.entries[path.toLowerCase()];
            if (!e || (md5 && e.md5 && e.md5 !== md5)) return null;
            return e;
        },

        // Promise<ArrayBuffer|null>; null = not in the pack (caller falls back to the network).
        read: async function (url) {
            var e = this.lookup(url), file = this.file;
            if (!e) return null;
            try {
                var lh = await readBytes(file, e.off, e.off + 30);
                if (lh.getUint32(0, true) !== LOCAL_SIG) throw new Error('bad local header');
                var start = e.off + 30 + lh.getUint16(26, true) + lh.getUint16(28, true);
                var blob = file.slice(start, start + e.csize);
                if (e.method === 0) return await blob.arrayBuffer();
                if (e.method === 8) {
                    return await new Response(blob.stream().pipeThrough(new DecompressionStream('deflate-raw'))).arrayBuffer();
                }
                throw new Error('unsupported compression method ' + e.method);
            } catch (err) {
                console.warn('[gamepack] read failed for', url, err);
                return null;
            }
        },

        installed: function () {
            if (typeof localforage === 'undefined') return Promise.resolve(null);
            return localforage.getItem(flagKey()).catch(function () { return null; });
        },

        // gamepack.json of the deployed build, or null (no pack published / offline).
        fetchMeta: async function () {
            try {
                var r = await fetch('gamepack.json', { cache: 'no-store' });
                if (!r.ok) return null;
                var m = await r.json();
                return (m && m.id && m.file && m.size) ? m : null;
            } catch (e) { return null; }
        },

        // Download (or resume) `meta`'s pack into OPFS, then switch to it.
        // onProgress(gotBytes, totalBytes). Rejects with err.quota = true on a full disk.
        download: async function (meta, onProgress) {
            var root = await navigator.storage.getDirectory();
            var prefix = opfsPrefix();
            var target = prefix + meta.id + '.zip';
            var prev = await this.installed();

            // Drop abandoned partial downloads of older builds (keep the installed pack: the
            // running game may still be reading from it).
            for await (var name of root.keys()) {
                if (name.indexOf(prefix) === 0 && name !== target && !(prev && name === prev.file)) {
                    try { await root.removeEntry(name); } catch (e) {}
                }
            }

            await new Promise(function (resolve, reject) {
                var w = new Worker('js/gamepack-worker.js');
                w.onmessage = function (ev) {
                    var d = ev.data;
                    if (d.type === 'progress') { if (onProgress) onProgress(d.got, d.total); }
                    else if (d.type === 'done') { w.terminate(); resolve(); }
                    else if (d.type === 'error') {
                        w.terminate();
                        var err = new Error(d.message); err.quota = !!d.quota; reject(err);
                    }
                };
                w.onerror = function (ev) { w.terminate(); reject(new Error(ev.message || 'download worker failed')); };
                w.postMessage({ url: new URL(meta.file, location.href).href, size: meta.size, name: target });
            });

            await localforage.setItem(flagKey(), { id: meta.id, file: target, size: meta.size, ts: Date.now() });
            await this.mount();

            // The new pack is live: remove the old one.
            if (prev && prev.file && prev.file !== target) {
                try { await root.removeEntry(prev.file); } catch (e) {}
            }
        },
    };

    window.GamePack = GamePack;
})();
