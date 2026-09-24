// Canvas used for image generation
var generationCanvas = document.createElement('canvas')
window.fileAsyncCache = {};

window.getMappingKey = function(file) {
    return file.toLowerCase().replace(new RegExp("\\.[^/.]+$"), "")
}

window.loadFileAsync = function(fullPath, bitmap, callback) {
    // noop
    callback = callback || (() => {});

    // Get mapping key
    const mappingKey = getMappingKey(fullPath);
    const mappingValue = mapping[mappingKey];

    // Check if already loaded
    if (window.fileAsyncCache.hasOwnProperty(mappingKey)) return callback();

    // Show spinner
    if (!bitmap && window.setBusy) window.setBusy();

    // Check if this is a folder
    if (!mappingValue || mappingValue.endsWith("h=")) {
        console.error("Skipping loading", fullPath, mappingValue);
        return callback();
    }

    // Get target URL
    const iurl = "gameasync/" + mappingValue;

    // Get path and filename
    const path = "/game/" + mappingValue.substring(0, mappingValue.lastIndexOf("/"));
    const filename = mappingValue.substring(mappingValue.lastIndexOf("/") + 1).split("?")[0];

    // Main loading function
    const load = (cb1) => {
        getLazyAsset(iurl, filename, (data) => {
            // WEB PORT (fix): getLazyAsset gave up (missing/failed asset). Unblock the game
            // and continue WITHOUT the file instead of hanging. Don't mark it loaded, so a
            // later request can retry (the failure may have been transient). The FS dummy
            // stays; a cry SE reading it just fails to decode -> no sound, no freeze.
            if (!data) {
                if (!bitmap && window.setNotBusy) window.setNotBusy();
                callback();
                if (cb1) cb1();
                return;
            }
            FS.createPreloadedFile(path, filename, new Uint8Array(data), true, true, function() {
                window.fileAsyncCache[mappingKey] = 1;
                if (!bitmap && window.setNotBusy) window.setNotBusy();
                if (window.fileLoadedAsync) window.fileLoadedAsync(fullPath);
                callback();
                if (cb1) cb1();
            }, console.error, false, false, () => {
                try { FS.unlink(path + "/" + filename); } catch (err) {}
            });
        });
    }

    // Show progress if doing it synchronously only
    if (bitmap && bitmapSizeMapping[mappingKey]) {
        // Get image
        const sm = bitmapSizeMapping[mappingKey];
        generationCanvas.width = sm[0];
        generationCanvas.height = sm[1];

        // Draw
        var img = new Image;
        img.onload = function(){
            const ctx = generationCanvas.getContext('2d');
            ctx.drawImage(img, 0, 0, sm[0], sm[1]);

            // Create dummy from data uri
            FS.createPreloadedFile(path, filename, generationCanvas.toDataURL(), true, true, function() {
                // Return control to C++
                callback(); callback = () => {};

                // Lazy load and refresh
                load(() => {
                    const reloadBitmap = Module.cwrap('reloadBitmap', 'number', ['number'])
                    reloadBitmap(bitmap);
                });
            }, console.error, false, false, () => {
                try { FS.unlink(path + "/" + filename); } catch (err) {}
            });
        };

        img.src = sm[2];
    } else {
        if (bitmap) {
            console.warn('No sizemap for image', mappingKey);
        }
        load();
    }
}


window.saveFile = function(filename, localOnly) {
    // WEB PORT / CRITICAL FIX: FS.readFile below closes the file descriptor, and the
    // FS.close persist hook (installSavePersistHook in index.html) re-fires on that
    // close -> calls saveFile again -> FS.readFile -> close -> ... INFINITE RECURSION
    // -> "Maximum call stack size exceeded". That froze the boot (the save is read
    // during the restore / title "Continue" check) AND silently aborted every local
    // save (the overflow threw before localforage.setItem ran). Re-entrancy guard: the
    // nested call from the close hook is a no-op, so the outer call reads once and
    // persists normally.
    if (window.__inSaveFile) return;
    const fpath = '/game/' + filename;
    if (!FS.analyzePath(fpath).exists) {
        // WEB PORT: the game deleted this save -> drop the stored copy too, otherwise
        // loadFiles() would resurrect it on the next boot.
        localforage.removeItem(namespace + filename);
        localforage.getItem(namespace, function(err, res) {
            if (err || !res || !res.hasOwnProperty(filename)) return;
            delete res[filename];
            localforage.setItem(namespace, res);
        });
        return;
    }

    window.__inSaveFile = true;
    try {
        const buf = FS.readFile(fpath);
        localforage.setItem(namespace + filename, buf);

        localforage.getItem(namespace, function(err, res) {
            if (err || !res) res = {};
            res[filename] = { t: Number(FS.stat(fpath).mtime) };
            localforage.setItem(namespace, res);
        });

        if (!localOnly) {
            (window.saveCloudFile || (()=>{}))(filename, buf);
        }
    } finally {
        window.__inSaveFile = false;
    }
};

// WEB PORT: returns a Promise that resolves only AFTER every savefile has been
// written back into MEMFS. Boot is gated on this (see restoreSaves() run-dependency
// in index.html) so the title screen's safeExists?(Game.rxdata) can't run before the
// IndexedDB restore lands. Previously this was fire-and-forget in postRun and raced
// the save-check -> "Continue" often missing after a (hard) reload even though the
// save was in IndexedDB.
var loadFiles = function() {
    // WEB PORT: run the (possibly async) cloud restore FIRST and WAIT for it, so a server
    // save lands in MEMFS before the local restore below -- whose no-clobber guard
    // (if !exists) then keeps the cloud copy ("NAS first"). With no cloud hook this
    // resolves immediately and the restore is purely local, exactly as before.
    var cloud = null;
    try { cloud = window.loadCloudFiles ? window.loadCloudFiles() : null; } catch (e) { console.error(e); }
    return Promise.resolve(cloud).catch(function (e) { console.error(e); }).then(function () {
      return new Promise(function(resolve) {
        localforage.getItem(namespace, function(err, folder) {
            if (err || !folder) { return resolve(); }
            console.log('Locally stored savefiles:', folder);
            var keys = Object.keys(folder);
            if (keys.length === 0) { return resolve(); }
            var pending = keys.length;
            keys.forEach(function(key) {
                var meta = folder[key];
                localforage.getItem(namespace + key, function(err, res) {
                    try {
                        if (!err && res) {
                            var fpath = '/game/' + key;
                            // Don't clobber an already-present real file.
                            if (!FS.analyzePath(fpath).exists) {
                                FS.writeFile(fpath, res);
                                if (Number.isInteger(meta.t)) { FS.utime(fpath, meta.t, meta.t); }
                            }
                        }
                    } catch (e) { console.error(e); }
                    if (--pending === 0) { resolve(); }
                });
            });
        });
      });
    });
}

var createDummies = function() {
    // Base directory
    FS.mkdir('/game');

    // Create dummy objects
    for (var i = 0; i < mappingArray.length; i++) {
        // Get filename
        const file = mappingArray[i][1];
        const filename = '/game/' + file.split("?")[0];

        // Check if folder
        if (file.endsWith('h=')) {
            FS.mkdir(filename);
        } else {
            FS.writeFile(filename, '1');
        }
    }
};

window.setBusy = function() {
    document.getElementById('spinner').style.opacity = "0.5";
};

window.setNotBusy = function() {
    document.getElementById('spinner').style.opacity = "0";
};

window.onerror = function() {
    console.error("An error occured!")
};

function preloadList(jsonArray) {
    jsonArray.forEach((file) => {
        const mappingKey = getMappingKey(file);
        const mappingValue = mapping[mappingKey];
        if (!mappingValue || window.fileAsyncCache[mappingKey]) return;

        // Get path and filename
        const path = "/game/" + mappingValue.substring(0, mappingValue.lastIndexOf("/"));
        const filename = mappingValue.substring(mappingValue.lastIndexOf("/") + 1).split("?")[0];

        // Preload the asset
        getLazyAsset("gameasync/" + mappingValue, filename, (data) => {
            if (!data) return;

            FS.createPreloadedFile(path, filename, new Uint8Array(data), true, true, function() {
                window.fileAsyncCache[mappingKey] = 1;
            }, console.error, false, false, () => {
                try { FS.unlink(path + "/" + filename); } catch (err) {}
            });
        }, true);
    });
}

window.fileLoadedAsync = function(file) {
    document.title = wTitle;

    if (!(/.*Map.*rxdata/i.test(file))) return;

    // WEB PORT: preload/*.json files are an OPTIONAL per-map prefetch list
    // (generated offline by extra/dump.sh). When absent, the original code
    // fed the 404 HTML body to response.json(), spamming the console with
    // "Uncaught (in promise) SyntaxError" for every map load. Tolerate absence.
    if (window.__preloadUnavailable) return;
    fetch('preload/' + file + '.json')
        .then(function(response) {
            if (!response.ok) { window.__preloadUnavailable = true; return null; }
            return response.json();
        })
        .then(function(jsonResponse) {
            if (!jsonResponse) return;
            setTimeout(() => {
                preloadList(jsonResponse);
            }, 200);
        })
        .catch(function() {});
};

var activeStreams = [];
function getLazyAsset(url, filename, callback, noretry, attempt) {
    // WEB PORT (fix): previously a fetch that did NOT return HTTP 200-399 -- a 404, or a
    // status-0 / network-error / aborted response (e.g. a transient failure through the
    // service worker) -- never called the callback (onreadystatechange only handled the
    // success range), and the 10s watchdog just re-issued the SAME request forever
    // (on-demand loads pass no `noretry`). That froze the whole game: the JSPI file-load
    // never resolved and the spinner stuck on "<file> - start". THIS was the cry-audio
    // hang. Now: handle every terminal outcome, retry a bounded number of times, then GIVE
    // UP with callback(null) so the caller can continue without the asset (a missing/failed
    // cry SE is non-fatal).
    attempt = attempt || 1;
    const MAX_ATTEMPTS = noretry ? 1 : 3;
    const xhr = new XMLHttpRequest();
    xhr.responseType = "arraybuffer";
    const pdiv = document.getElementById("progress");
    let abortTimer = 0;
    let settled = false;

    const clearStream = () => {
        const i = activeStreams.indexOf(filename);
        if (i !== -1) activeStreams.splice(i, 1);
        if (activeStreams.length === 0) pdiv.style.opacity = '0';
    };

    const succeed = (data) => {
        if (settled) return; settled = true;
        clearTimeout(abortTimer);
        pdiv.innerHTML = `${filename} - done`;
        clearStream();
        callback(data);
    };

    const fail = (why) => {
        if (settled) return; settled = true;
        clearTimeout(abortTimer);
        try { xhr.abort(); } catch (e) {}
        clearStream();
        if (attempt < MAX_ATTEMPTS) {
            getLazyAsset(url, filename, callback, noretry, attempt + 1);
        } else {
            console.warn("getLazyAsset: giving up on", url, "(" + why + ") after", attempt, "attempt(s)");
            pdiv.innerHTML = `${filename} - skip`;
            if (activeStreams.length === 0) pdiv.style.opacity = '0';
            callback(null);
        }
    };

    xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE) return;
        if (xhr.status >= 200 && xhr.status < 400) succeed(xhr.response);
        else fail("status " + xhr.status);
    };
    xhr.onerror = function() { fail("network error"); };
    xhr.onprogress = function (event) {
        if (settled) return;
        const loaded = Math.round(event.loaded / 1024);
        const total = Math.round(event.total / 1024);
        pdiv.innerHTML = `${filename} - ${loaded}KB / ${total}KB`;
        clearTimeout(abortTimer);
        abortTimer = setTimeout(() => fail("stalled"), 10000);
    };

    try {
        xhr.open('GET', url);
        xhr.send();
    } catch (e) { fail("open/send threw"); return; }

    pdiv.innerHTML = `${filename} - start`;
    pdiv.style.opacity = '0.5';
    if (activeStreams.indexOf(filename) === -1) activeStreams.push(filename);

    abortTimer = setTimeout(() => fail("start timeout"), 10000);
}

// WEB PORT: the engine enumerates Fonts/*.ttf|otf ONCE at startup (to learn each font's
// family name), but createDummies left them as 1-byte placeholders -> every custom font
// failed to open and all text fell back to the bundled Liberation Sans. Fetch the real
// font files into MEMFS before main() runs (preRun + run dependency, after createDummies).
window.preloadFonts = function() {
    var fonts = mappingArray.filter(function(m) {
        return /^fonts\//.test(m[0]) && /\.(ttf|otf)\?/i.test(m[1]);
    });
    if (!fonts.length) return;
    var add = Module.addRunDependency, rem = Module.removeRunDependency;
    if (add) add('preload-fonts');
    Promise.all(fonts.map(function(m) {
        return fetch('gameasync/' + m[1])
            .then(function(r) { if (!r.ok) throw new Error(r.status + ' ' + m[1]); return r.arrayBuffer(); })
            .then(function(buf) {
                FS.writeFile('/game/' + m[1].split('?')[0], new Uint8Array(buf));
                window.fileAsyncCache[m[0]] = 1;
            })
            .catch(function(e) { console.error('font preload failed', e); });
    })).then(function() { if (rem) rem('preload-fonts'); });
};
